"""
    experimentmodel, dataset, constraints; my_smt=:z3, opt_solver=:gurobi)

Implements the pipeline for formal verification and certificate the decision forest models.
This function iteratively verifies constraints and repairs violations until convergence.

The function performs verification and repair through the following iterative steps:
1. Converts the decision forest model into Linear Real Arithmetic (LRA) format.
2. Uses an SMT solver to find counterfactual explanations violating constraints.
3. If a counterfactual is found, repairs by adding it to the dataset and retraining.
The process continues until no further counterexamples can be found.
"""
function experiment(
    # could be provided by the called; not a big deal, loading time is ~0.02s for "abalone"
    X,
    y,
    config,
    ::Val{:regression};
    smt2filename::String="$(smt2filename)",

    # model type selector;
    # this can be, :decision_forest, :list_forest, :xgboost
    model_type::Symbol=:decision_forest,

    # stuff related to decision forests
    n_subfeatures::Int=-1,
    n_trees::Int=1,
    partial_sampling::Float64=1.0,
    forest_max_depth::Int=-1,
    pure_lra::Bool=false,

    # stuff related to lists 
    n_lists::Int=1,

    # stuff related to xgboost
    n_rounds::Int=1,
    lconstraint_complexity::Int=1,
    default_lconstraints::Vector{SyntaxBranch}=SyntaxBranch[],
    rconstraint_complexity::Int=1,
    default_rconstraints::Vector{SyntaxBranch}=SyntaxBranch[],
    quantiles_coeff::Vector{Float64}=[0.2, 0.8],
    batch_size::Int=1,
    variablename::String="Or",
    M::Int=100000,
    TIMEOUT::Float64=3000.0, # timeout after which the experiment is declared as divergent
    silent::Bool=false,
    # e.g., to forward `root_path` in `load_dataset`
    kwargs...,
)
    convergence_time, numcycles = 0.0, 0

    # we want to keep track of the first model that is trained,
    # since we will compare the performance of this with the last (certified) one
    first_model_trained = nothing
    first_adhoc_model_trained = nothing
    last_adhoc_model_trained = nothing

    # pick the correct left and right constraint
    lconstraint = default_lconstraints[lconstraint_complexity]
    rconstraint = default_rconstraints[rconstraint_complexity]
    rconstraint_lbound, rconstraint_rbound, EPS = constraint_bounds_and_eps(
        rconstraint
    )

    @info EPS
    @info lconstraint
    @info rconstraint

    # this will be useful later; see the Counterexample Repair section
    rconstraint_dnf = dnf(rconstraint)

    !silent && printstyled("Boundary constraint generation...\n"; color=:green)
    boundary_constraints = make_boundary_constraint(X)

    # this is the final constraint
    constraint = IMPLICATION(lconstraint, rconstraint)

    if istrivally_unsat(
        config, lconstraint, rconstraint, boundary_constraints, smt2filename
    )
        return nothing
    end

    while true
        !silent && printstyled("Creating (or cleaning) optimizators...")
        jump_model = make_optimizer()

        !silent && printstyled(
            "Forest training & SoleModel conversion...\n"; color=:green
        )

        # train depending on the type requested by the experiments runner
        model = nothing

        # this is filled in the case of xgboost and serves for the final output:
        # y_final = _base_score + sum(o_1, o_2, o_3...)
        _base_score = nothing

        if model_type == :decision_forest
            model = build_forest(y, X, -1, n_trees, 1.0, forest_max_depth, 5, 2)
        elseif model_type == :list_forest
            println("Error! Not supported yet")
            exit(5)
        elseif model_type == :xgboost
            # this part is copy-pasted from the XGBoost examples of SoleXplorer
            df = DataFrame(X, ["V$(i)" for i in 1:size(X)[2]])
            df.y = y
            model = XGBoostRegressor(;
                num_round=n_rounds, max_depth=6, tree_method="exact"
            )
            m = machine(model, df[:, 1:(end - 1)], df.y)
            MLJ.fit!(m)

            _base_score = mean(y)

            trees = XGBoost.trees(m.fitresult[1])
            # this is only needed in classification
            # classlabels = String.(levels(df.y))
            println("trees type: $(typeof(trees))")
            model = solemodel(trees, Matrix(X), y)
        else
            println("Error! Invalid model_type provided!")
            exit(3)
        end

        smodel = solemodel(model)

        if isnothing(first_model_trained)
            first_model_trained = deepcopy(model)

            if model_type == :xgboost
                first_adhoc_model_trained = MLJ.fitted_params(m)[1][1] # .booster
            end
        end

        !silent &&
            printstyled("Converting the model to LRA format...\n"; color=:green)

        lra = nothing
        if model_type == :decision_forest
            lra = forest_to_lra(smodel; pure_lra=pure_lra)
        elseif model_type == :list_forest
            # TODO: actually, ensembles of decision lists are not supported yet,
            # in fact, this case should crash before with an error code 5
            lra = forest_decisionlist_to_lra(smodel; pure_lra=pure_lra)
        elseif model_type == :xgboost
            # println("Typeof smodel, before calling lra:")
            # println(typeof(smodel))
            lra = xgboost_to_lra(
                smodel; pure_lra=pure_lra, base_score=_base_score
            )
        else
            println("Error! Invalid model_type provided!")
            exit(4)
        end

        lra_to_evaluate = CONJUNCTION(
            lra, NEGATION(constraint), boundary_constraints...
        )

        !silent && printstyled(
            "To smt2 output file ($(smt2filename))...\n"; color=:green
        )
        to_smtlib2(
            lra_to_evaluate;
            output_file=smt2filename,
            force_input=["Or"],
            integerfeatures=integerfeatures(config),
            typeof_output=dataset_type(config),
        )

        # os is the value of the "big O" (e.g., Or in the case of regression)
        vs, os, O = nothing, nothing, nothing

        !silent && printstyled("Formal verification...\n"; color=:green)
        stats = @timed begin
            # call z3... is the smt2 file unsatisfiable? If it is not the case, go on
            _verify_res = verify(smt2filename)
            if _verify_res == false
                if model_type == :xgboost
                    last_adhoc_model_trained = MLJ.fitted_params(m)[1][1] # .booster
                end

                return (
                    model,
                    # deepcopy all the MLJ machines for avoiding SEGFAULTs
                    last_adhoc_model_trained,
                    convergence_time,
                    numcycles,
                    IMPLICATION(lconstraint, rconstraint),
                    first_model_trained,
                    first_adhoc_model_trained
                )
            else
                vs, os = _verify_res # counterexample
            end

            O = nothing
            try
                O = adjustement_of_counterexample(
                    config, jump_model, os, rconstraint_dnf, M
                )
            catch
                # ERROR: LoadError: BoundsError: attempt to access 0-element Vector{String} at index [0]
                return nothing
            end

            if isnothing(O)
                return nothing
            end
        end

        O = snap_to_nearest_interval(O, rconstraint_dnf, EPS)

        # finally, add a new (and eventually perturbed) instance to the dataset
        new_x = [
            parse(Float64, replace(strip(last(split(v, "="))), " " => "")) for
            v in vs
        ]

        for _ in 1:batch_size
            _p = perturb(new_x, lconstraint)
            X = vcat(X, batch_size == 1 ? new_x' : _p')
            y = vcat(y, O)

            println(smodel)
            # println("X: $(new_x')")
            # println("y: $(O)")

            # open("prova_modelli.txt", "a") do f
            # println(f, smodel)
            # end
            # open("prova_dati.txt", "a") do f
            #     println(f, new_x')
            #     println(f, O)
            # end
        end

        @info "Repeat cycle and add the $(length(y))-th instance to the dataset"
        convergence_time += (stats.time - stats.compile_time) * batch_size
        numcycles += 1 * batch_size

        # divergence condition
        if convergence_time > TIMEOUT
            return (
                model,
                # deepcopy all the MLJ machines for avoiding SEGFAULTs
                last_adhoc_model_trained,
                convergence_time,
                -1,
                IMPLICATION(lconstraint, rconstraint),
                first_model_trained,
                first_adhoc_model_trained
            )
        end
    end
end
