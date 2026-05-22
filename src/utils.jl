"""
    extract_output_values(model::DecisionEnsemble)

Return all the output numeric values of `model`, such as
1.8811384444910775 and 0.6622551215154123" for, respectively, the atoms
"[o1] == 1.8811384444910775" and "[o2] == 0.6622551215154123".
"""
function extract_output_values(model::DecisionEnsemble)
    clean_matches = filter(
        x -> !isnothing(x),
        map(
            x -> begin
                x = match(r"\[o(\d+)\] == ([\d.e\-+]+)", x)
                isnothing(x) ? nothing : x.match
            end,
            syntaxstring(model),
        ),
    )

    # isolate the "1.8811384444910775" part, and parse it
    ois = strip.(last.(split.(clean_matches, "==")))
    map!(x -> Convert(Float64, x), oi)

    return ois
end

"""
This method is deprecated.

    function make_constraint(
        data::Array{R, N};
        _length::Int = 5,
        sigma_modifier::Float64 = 1.0,
        phi::Union{Nothing,SoleLogics.SyntaxBranch} = nothing,
        connectives::Vector{C} = C[CONJUNCTION, DISJUNCTION],
        bowtie::Vector{F} = F[<=, >=]
    ) where {C<:SoleLogics.Connective, F<:Function, N<:Number}

Return a constraint that can be used to certify a machine learning model trained on the
dataset `(data, y)`.

# Arguments
- `data::Matrix{N}`: the data, which only contains numerical values;
- `y::Vector{N}`: the (numerical) labels.

# Keyword Arguments
- `_length::Int = 5`: length of the generated constraint, which can be seen as the number of
    `connectives` appearing, minus one;
- `sigma_modifier::Float64 = 1.0`: given a specific column `i` of `data`, this factor
    regulates which values can be sampled to create a new sentence within the final
    constraint; by default, only the values of `data[i]` that belong to `[μ-S, μ+S]` are
    considered, where `μ` is the mean of `data[i]` and `S` is the standard deviation `σ` of
    `data[i]`, multiplied by this argument;
- `phi::Union{Nothing,SoleLogics.SyntaxBranch} = nothing`: if this argument is set, then
    it is merged with the constraint generated;
- `connectives::Vector{C} = C[CONJUNCTION, DISJUNCTION]`: collection of
    admissible `SoleLogics.Connectives` to randomly pick from;
- `bowtie::Vector{F} = F[<=, >=]`: admissible relations to randomly pick from;
- `variablename::Union{Nothing, String} = nothing`: overload the default name of the
    output `Atom`s.

# Examples
```julia
julia> # make a synthetic dataset
julia> n = 500
julia> data = rand(n, 5)
julia> y = 3*data[:, 1] .^ 2 .+ 2*sin.(5*data[:, 2]) .+ data[:, 3] .+ 0.5*randn(n)

julia> make_constraint(Xoshiro(42), data, y)
```
"""
function make_constraint(
    data::Array{R,N};
    _length::Int=5,
    phi::Union{Nothing,SoleLogics.SyntaxTree}=nothing, # SoleLogics.Atom,SoleLogics.SyntaxBranch
    connectives::Vector{C}=SoleLogics.Connective[CONJUNCTION, DISJUNCTION],
    weights::Vector{Float64}=[0.3, 0.7],
    quantiles_coeff::Vector{Float64}=[0.2, 0.8],
    variablename::Union{Nothing,String,Vector{String}}=nothing,
    integer_domain::Bool=false,
    already_used_cols::Vector{Int}=Int[],
) where {C<:SoleLogics.Connective,R<:Real,N}

    # utility for uniform picking a random value in a collection
    _choose = x -> x[rand(1:length(x))]

    # default column value
    col = 1

    # in the degenerate case of a column vector, this is just a renaming
    distribution = deepcopy(data)

    # compute the distribution of its value
    if ndims(data) == 2
        # pick a random column (e.g., the first);
        # it must be a new value
        col = _choose([i for i in 1:last(size(data))])
        while col in already_used_cols
            col = _choose([i for i in 1:last(size(data))])
        end

        push!(already_used_cols, col)

        distribution = data[:, col]
    end

    ## pick two consecutive values for a certain feature
    ## sort!(unique!(distribution))
    ## pos = rand(1:(length(distribution)-1))
    ## lbound, rbound = distribution[pos:(pos+1)]

    sort!(distribution)
    lbound = StatsBase.quantile(distribution, quantiles_coeff[1])
    rbound = StatsBase.quantile(distribution, quantiles_coeff[2])

    # in the case of integer domain, we snap the boundaries to the left and right
    if integer_domain
        lbound, rbound = floor(lbound), ceil(rbound)
    end

    if isnothing(variablename)
        new_atom = CONJUNCTION(
            Atom(ScalarCondition(VariableValue(col), >, lbound)),
            Atom(ScalarCondition(VariableValue(col), <, rbound)),
        )
    elseif variablename isa String
        new_atom = CONJUNCTION(
            Atom(
                ScalarCondition(
                    VariableValue(col, "$(variablename)"), >=, lbound
                ),
            ),
            Atom(
                ScalarCondition(
                    VariableValue(col, "$(variablename)"), <=, rbound
                ),
            ),
        )
    else
        throw(
            ArgumentError(
                "The provided variablename is neither nothing, nor a String " *
                "(value is $variablename)",
            ),
        )
    end

    # prepare phi, if necessary
    if isnothing(phi)
        phi = new_atom
    else
        _operator = StatsBase.sample(connectives, StatsBase.Weights(weights))
        phi = _operator(phi, new_atom)
    end

    # base case
    if _length == 1
        return phi
    else
        return make_constraint(
            data;
            _length=_length - 1,
            phi=phi,
            connectives,
            weights=weights,
            variablename,
            integer_domain=integer_domain,
            already_used_cols=already_used_cols,
        )
    end
end

"""
Return the left and right bounds of the given constraint of an experiment.
Also, as the third parameter, return an EPS factor.

For example, return 15.8, 16.0 from the SyntaxBranch Or > 15.8 ∧ Or < 16.0.

For what regards EPS, suppose * is the value returned from the optimizer,
and A and B are the delimiters of the given interval constraint;
here, we want to do the following: * A ..x.. B -> snap * to A, then move it to x.
The same from right to left.
"""
function constraint_bounds_and_eps(constraint::SyntaxBranch)
    constraint_lbound = SoleData.threshold(atoms(constraint)[1].value)
    constraint_rbound = SoleData.threshold(atoms(constraint)[2].value)
    if constraint_lbound > constraint_rbound
        constraint_lbound, constraint_rbound = constraint_rbound,
        constraint_lbound
    end

    EPS = 0.5 * (constraint_rbound - constraint_lbound)

    return constraint_lbound, constraint_rbound, EPS
end

"""
Retrieve all the min & max boundaries from each feature in X, and assemble them in the shape
of a SyntaxBranch (a constraint).
"""
function make_boundary_constraint(X)
    boundary_constraints = []

    for i in 1:size(X)[2]
        _min, _max = minimum(X[:, i]), maximum(X[:, i])
        _min_atom = Atom(ScalarCondition(VariableValue(i), >=, _min))
        _max_atom = Atom(ScalarCondition(VariableValue(i), <=, _max))
        push!(boundary_constraints, CONJUNCTION(_min_atom, _max_atom))
    end

    return boundary_constraints
end

"""
Given three constraints `left`, `right` and `boundaries`, check whether one of the following
is trivially unsat:
- `lconstraint`;
- `lconstraint => rconstraint`;
- `(⋀(boundary_constraints)) ∧ lconstraint ∧ ¬rconstraint`.
"""
function istrivally_unsat(
    config, lconstraint, rconstraint, boundary_constraints, smt2filename
)
    for (c, case) in [
        (lconstraint, :left),
        (IMPLICATION(lconstraint, rconstraint), :implication),
        (
            CONJUNCTION(boundary_constraints..., lconstraint, ¬(rconstraint)),
            :complete,
        ),
    ]
        if case == :implication
            to_smtlib2(
                c;
                output_file=smt2filename,
                force_input=["Or"],
                integerfeatures=integerfeatures(config),
                typeof_output=dataset_type(config),
            )
        else
            to_smtlib2(
                c;
                output_file=smt2filename,
                force_input=["Or"],
                integerfeatures=integerfeatures(config),
                typeof_output=dataset_type(config),
            )
        end

        _command = `z3 -smt2 $(smt2filename)`

        try
            _buffer = IOBuffer()
            _ = run(Base.pipeline(_command; stdout=_buffer))
            # we don't care about the result, but just the fact that Z3 triggered an UNSAT error
            _ = String(take!(_buffer))
        catch e
            if e.procs[1].exitcode == 1
                printstyled("The given constraint is UNSAT!\n"; color=:yellow)
                printstyled("Constraint [type $(case)]\n"; color=:red)
                printstyled("$(syntaxstring(c))\n"; color=:red)

                return true
            end
        end
    end

    return false
end

"""
We combine ipopt (which handles the quadratic constraint s^2 we will minimize) with the
searching of assignments to discrete variables (thanks to Juniper).
"""
function make_optimizer()
    ipopt = optimizer_with_attributes(
        Ipopt.Optimizer, "print_level" => 0, "sb" => "yes"
    )
    juniper = optimizer_with_attributes(
        Juniper.Optimizer, "nl_solver" => ipopt, "log_levels" => []
    )
    return JuMP.Model(juniper)
end

"""
Consider the given smt2file handle; call z3 and return the given model, if possible.
Otherwise, return false.
"""
function verify(smt2filename::String)
    _command = `z3 -smt2 $(smt2filename)`
    z3result = nothing

    try
        _buffer = IOBuffer()
        process = run(Base.pipeline(_command; stdout=_buffer))

        wait(process)

        z3result = String(take!(_buffer))

        # return all the vs (the assignment to each feature) and the os
        return parse_z3_model(z3result)
    catch e

        # open("verify.debug", "w") do f
        #     println(f, z3result)
        # end

        if e.procs[1].exitcode == 1
            @info "The negation of the constraint is UNSAT; " *
                "thus, the entire formula is SAT and the model is certified."

            return false
        end
    end
end

"""
Leverage JuMP to adjust the value of a model (the counterexample) returned by Z3;
see [`verify`](@ref).
"""
function adjustement_of_counterexample(
    config, jump_model, os, rconstraint_dnf, M
)
    # extract only the interesting part of os, where os results from the sat solver
    output_value_to_be_fixed = parse(Float64, strip(last(split(os[end], "="))))

    if dataset_type(config) != 1
        @variable(jump_model, o, Int)
    else
        @variable(jump_model, o)
    end

    fix(o, output_value_to_be_fixed; force=true)

    # this is the value that has to be choose by the optimizer
    @variable(jump_model, s)

    # we need to introduce the binary variables for implementing disjunctions
    @variable(jump_model, z[1:length(rconstraint_dnf)], Bin)

    # for each conjunction in the rconstraint_dnf,
    # consider each individual piece and pair it with a binary disjunctive variable

    for (i, conjunction) in enumerate(rconstraint_dnf)
        for letter in conjunction
            _condition = test_operator(metacond(SoleData.value(atom(letter))))
            _threshold = threshold(SoleData.value(atom(letter)))

            if _condition == (<=)
                @constraint(jump_model, o + s <= _threshold + M * (1 - z[i]))
            elseif _condition == (>=)
                @constraint(jump_model, o + s >= _threshold - M * (1 - z[i]))
            else
                printstyled("ERROR: $(_condition) is not allowed."; color=:red)
                return -1
            end
        end
    end

    # at least one clause must hold
    @constraint(jump_model, sum(z) >= 1)

    # this costant number be filled from the initial pipeline constraints
    @objective(jump_model, Min, s^2)

    optimize!(jump_model)

    # we adjust the previous output value with the new minimal
    # slack which respects the given constraint

    s_value = JuMP.value(s)
    if s_value === NaN
        printstyled("ERROR: the resulting s is NaN."; color=:red)
        return nothing
    end

    return output_value_to_be_fixed + s_value
end

"""
Check if we slightly need to fix the output of JuMP, due to numerical errors.
"""
function snap_to_nearest_interval(O, rconstraint_dnf, EPS)
    # this is the "best" constraint, that is, the one with one of the 2 bounds closer to O
    best_distance = 1 << 30
    best_left_bound = nothing
    best_right_bound = nothing

    for (_, conjunction) in enumerate(rconstraint_dnf)
        leq, geq = atoms(conjunction)

        left_bound = threshold(SoleData.value(leq))
        right_bound = threshold(SoleData.value(geq))

        # O is closer to the interval we are just considering
        if abs(left_bound - O) < best_distance ||
            abs(right_bound - O) < best_distance
            best_left_bound = left_bound
            best_right_bound = right_bound
        end
    end

    # we can finally adjust O
    if O < best_left_bound
        return O + EPS
    else
        return O - EPS
    end
end

"""
Return a perturbed version of the `target` variable.
The returned target is still complaint to `lconstraint`.
"""
function perturb(
    target,
    lconstraint::SyntaxBranch;
    perturbation::Float64=0.2,

    # kill the process after this number of runs, to avoid infinite recursions
    kill_limit=100,

    # each time a new trial of perturbation is tried (maybe because the proposed one is
    # not complaint with the left constraint) retry but lower the perturbation power by this
    # factor
    degradation::Float64=0.99,
)
    if kill_limit == 0
        return target
    end

    noise = 1 .+ perturbation .* (2 .* rand(length(target)) .- 1)
    perturbed_target = target .* noise

    if !check(lconstraint, scalarlogiset([perturbed_target]), 1)
        return perturb(
            target,
            lconstraint;
            perturbation=perturbation * degradation,
            kill_limit=kill_limit - 1,
        )
    end

    return perturbed_target
end

"""
Compute the f1 score between `y_pred` and `y_true`.
The possible classes are obtained from `y_true`, and the f1 score is obtained by averaging
the f1 score of each class.
"""
function f1_score(y_pred, y_true)
    @assert length(y_true) == length(y_pred) "Ground truth and predicted labels should " *
        "have the same length, but $(length(y_true)) ≠ $(length(y_pred))."

    if length(y_pred) == 0
        return NaN
    end

    classes = unique(vcat(y_true, y_pred))

    # multi class scenario
    tp = Dict(c => 0 for c in classes)
    fp = Dict(c => 0 for c in classes)
    fn = Dict(c => 0 for c in classes)

    for (yt, yp) in zip(y_true, y_pred)
        if yp == yt
            tp[yt] += 1
        else
            fp[yp] = get(fp, yp, 0) + 1
            fn[yt] = get(fn, yt, 0) + 1
        end
    end

    # we consider the mean of each f1 score
    f1s = Float64[]
    for c in classes
        precision = (tp[c] + fp[c] == 0) ? 0.0 : tp[c] / (tp[c] + fp[c])
        recall = (tp[c] + fn[c] == 0) ? 0.0 : tp[c] / (tp[c] + fn[c])
        f1 = if (precision + recall == 0)
            0.0
        else
            2 * precision * recall / (precision + recall)
        end
        push!(f1s, f1)
    end

    return mean(f1s)
end
