using FormalVerificationRandomForests

using DataFrames
using DecisionTree
using JuMP
using Ipopt
using Random
using StatsBase
using Statistics: cor

using SoleBase

using SoleLogics

using SoleModels
using SoleModels: weighted_aggregation

# needed by mdl_adapter.jl, that is, the adpapter for ModalDecisionLists
using SoleData
using SoleData: AbstractInterpretationSet, AbstractInterpretation

include("adapters/sm_adapter.jl")
include("adapters/mdl_adapter.jl")
include("utils.jl")

OUTPUT_PATH = joinpath(pwd(), "results")
SMT2_TEMP_PATH = joinpath(OUTPUT_PATH, "smt2dump")
DATA_PATH = joinpath(pwd(), "dataset")
CONFIG_PATH = joinpath(pwd(), "experiments", "configurations")

if length(ARGS) < 2
    println("Missing name argument!")
    println(
        "Execute using: julia --project=. test/run_experiment <name> <modeltype>",
    )

    println(
        "The available names are: ads, breastcancer, ecoli, fishbream, " *
        "fishperch, glass, iris, realestate, seeds, vehicle.",
    )
    println(
        "The available model type are: decision_forest, list_forest, xgboost"
    )
    exit(1)
end

# data name inserted by the user
data_name = ARGS[1]
model_type = Symbol(ARGS[2])

# you can use these 2 following optional flags for overwriting the default 
# options
#
# a certain hyperparameter value, to be associated with your model
hyperparameter = nothing
# the LC you see in each experiment, that is, the length of the left constraint
lconstraintlength = nothing

try
    global hyperparameter = [parse(Int64, ARGS[3])]
    global lconstraintlength = [parse(Int64, ARGS[4])]
catch
    println("No hyperparamter and lconstraintlength parameters were overloaded")
end

# the name of the selected configuration should provide the following
# exp_algorithm, exp_datasets, exp_hparam, exp_maxdepth, exp_lcomplexities 
# exp_rcomplexities,  exp_lconstraints, exp_rconstraints, exp_batchsize 
# exp_repetitions, exp_seed
#
# See any example in experiments/configurations for an explanation
_data_names = [
    "iris",
    "breastcancer",
    "ecoli",
    "glass",
    "seeds",
    "fishbream",
    "fishperch",
    "realestate",
    "energycool",
    "vehicle",
    "ads",
    "monks_1",
    "soybean_small",
    "cryotherapy",
    "cryotherapy_small",
    "hayes_roth",
    "hayes_roth_small",
    "divorce",
    "divorce_small",

    "concrete_small",
    "dailydemand_small",
    "forestfires_small",
    "yacht_small"
]

_model_types = [:decision_forest, :list_forest, :xgboost]

# just to check the proper name input from the user
_name_flag = false

# inject the configuration corresponding to a certain data_name;
# note that the configuration is a whole julia file, instead of a json or toml;
# this is due to old decisions related to this project, but it is not that bad!
for _data_name in _data_names
    if data_name == _data_name
        include(joinpath(CONFIG_PATH, "configuration_$(data_name).jl"))
        global _name_flag = true
        break
    end
end

# if these were overloaded, let's confirm this
if hyperparameter != nothing && lconstraintlength != nothing
    exp_hparam[model_type] = hyperparameter
    exp_lcomplexities = lconstraintlength
end

if !_name_flag
    println("Error! The name provided is not supported yet.")
    exit(2)
end

if !(model_type in _model_types)
    println("Error! The model type provided is not supported yet.")
end

Random.seed!(exp_seed)

my_PRE = nothing
my_POST = nothing
my_X_train = nothing
my_X_test = nothing
my_y_train = nothing
my_y_test = nothing

for (datasetconfig, lcomplexity, rcomplexity, batchsize, maxdepth) in
    Iterators.product(
    exp_datasets,
    exp_lcomplexities,
    exp_rcomplexities,
    exp_batchsize,

    # only decision forests must iterate this... but! 
    # this is one and only one value, thus no code is repeated 
    # (if we are running, say, decision lists, this can be ignored)
    exp_maxdepth,
)
    # println("Current parameterization: ")
    # println("Left complexity: $(lcomplexity)")
    # println("Right complexity: $(rcomplexity)")
    # println("Model type: $(model_type)")

    # we need to iterate each specific hyperparameter associated to the current 
    # model type;
    # this is dynamic (hyperparamters semantics is different for each model) 
    # and it is convenient to set here, outside the Iterators.product
    for hparam in exp_hparam[model_type]
        _datasetname = datasetname(datasetconfig)

        i = 1
        while i <= exp_repetitions

            # data shuffling
            X, y = load_dataset(datasetconfig; root_path=DATA_PATH)
            nrows = size(X, 1)

            perm = randperm(nrows)
            X_perm = X[perm, :]
            y_perm = y[perm]

            ratio = 0.8
            ntrain = floor(Int, ratio * nrows)

            X_train, X_test = X_perm[1:ntrain, :], X_perm[(ntrain + 1):end, :]
            y_train, y_test = y_perm[1:ntrain], y_perm[(ntrain + 1):end]

            experiment_response = nothing

            _exec_stats = @timed begin
                experiment_response = FormalVerificationRandomForests.experiment(
                    # the exp_type is whether :regression or :classification
                    X_train,
                    y_train,
                    datasetconfig,
                    exp_type;
                    smt2filename=joinpath(
                        SMT2_TEMP_PATH, "$(_datasetname)_$(model_type).smt2"
                    ),
                    model_type=model_type,

                    # parameters for decision forests
                    forest_max_depth=maxdepth,
                    n_trees=hparam,

                    # parameters for lists
                    n_lists=hparam,

                    # parameters for XGBoost                     
                    n_rounds=hparam,
                    lconstraint_complexity=lcomplexity,
                    rconstraint_complexity=rcomplexity,
                    default_lconstraints=exp_lconstraints,
                    default_rconstraints=exp_rconstraints,
                    quantiles_coeff=[0.2, 0.8],
                    batch_size=batchsize,
                    variablename="Or",
                    silent=true,
                    root_path=DATA_PATH,
                )
            end

            # if something went wrong (e.g., the constraint generated in the pipeline is UNSAT),
            # just repeat the iteration
            if isnothing(experiment_response)
                continue
                # else, just unpack the interesting results and push them into the final collection
            else
                # the difference between the certified model and machine is that 
                # one belongs to the Sole domain, while the other is MLJ
                certified_model,
                certified_adhoc, _convtime, _numcycles, _constraint,
                first_model, first_adhoc = experiment_response

                PRE = first_model
                POST = certified_model

                global my_PRE = PRE
                global my_POST = POST
                global my_X_train = X_train
                global my_X_test = X_test
                global my_y_train = y_train
                global my_y_test = y_test

                println("A model of type $(typeof(my_PRE)) returned")
                flush(stdout)

                # println("Exp type: $(exp_type)")
                # println("Model type: $(model_type)")
                # println("Solemodel: $(typeof(certified_model))")
                # println("Certified: $(typeof(certified_machine))")

                if exp_type == Val(:regression) && model_type == :xgboost
                    println("A")

                    # put the MLJ's models here
                    pre_score, post_score = compare_models(
                        # XGBoost booster
                        first_adhoc,
                        certified_adhoc,
                        X_test,
                        y_test,
                        model_type,
                        exp_type,
                    )
                else
                    println("B")

                    # put the Sole' models here
                    pre_score, post_score = compare_models(
                        first_model,
                        certified_model,
                        X_test,
                        y_test,
                        model_type,
                        exp_type,
                    )
                end

                println("First cor: $(pre_score); Cert cor: $(post_score)")

                _result = Result((
                    hparam,
                    maxdepth,
                    batchsize,
                    lcomplexity,
                    rcomplexity,
                    _exec_stats.time - _exec_stats.compile_time,
                    _convtime,
                    _numcycles,
                    pre_score,
                    post_score,
                ))

                #
                writeresult(
                    joinpath(
                        OUTPUT_PATH,
                        "$(_datasetname)_TY_$(model_type)_LC_$(lcomplexity)_RC_$(rcomplexity)_HP_$(hparam)_MD_$(maxdepth)_BS_$(batchsize).txt",
                    ),
                    _result;
                    othercontent=_constraint,
                )

                i += 1
            end
        end
    end
end
