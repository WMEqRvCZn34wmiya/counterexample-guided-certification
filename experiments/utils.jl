# Utilities related to experiments;
# maybe it makes sense to merge these with src/utils

using MLJ, MLJXGBoostInterface
using XGBoost
import SoleModels: choose_preds, DecisionXGBoost, Label, CLabel

"""
Dump (with `println`) the content of `result` into the file provided;
if the latter does not exists, create it.
"""
function writeresult(
    filepath::String, result::Result; othercontent::Any=nothing
)
    if !isfile(filepath)
        touch(filepath)
    end

    open(filepath, "a") do f
        println(f, result)

        if !isnothing(othercontent)
            println(f, othercontent)
        end
    end
end

function apply_metric(a, b, ::Val{:regression})
    return cor(a, b)
end

function apply_metric(a, b, ::Val{:classification})
    return f1_score(a, b)
end

"""
Wrapper to many entrypoints to models learning.
The available arguments you can dispatch on are: `:decision_forest`, 
`:list_forest`, `:xgboost`.
"""
function apply_model(model, xs, ::Val{:decision_forest})
    return apply_forest(model, xs)
end

function apply_model(model, xs, ::Val{:list_forest})
    # see mdl_experimental_imports.jl
    # this is strange, but apply_ensemble does not accept matrixes nor frames
    df = DataFrame(xs, ["V$(i)" for i in 1:size(xs)[2]])
    return apply_ensemble(model, PropositionalLogiset(df))
end

import SoleModels: iscomplete
function SoleModels.iscomplete(m::DecisionXGBoost{Float32})
    return true
end

# Beware... in this particular case, the model should be an XGBoost.Booster
function apply_model(booster, xs, ::Val{:xgboost})
    dmat = XGBoost.DMatrix(Matrix{Float32}(xs))
    return XGBoost.predict(booster, dmat)

    # df = DataFrame(xs, :auto)
    # return MLJ.predict(model, df)
end

# function apply_model(model, xs, ::Val{:xgboost})
#
#     println("Model type: $(typeof(model))")
#     println("xs type: $(typeof(xs))")
#     # return MLJ.predict(model, xs)
#
#     df = DataFrame(Float32.(xs), ["V$(i)" for i in 1:size(xs, 2)])
#     return MLJ.predict(model, df)
#
#     # xs32 = Matrix{Float32}(xs)
#     # return MLJ.predict(model, xs32)
#
#     # return apply(
#     #     model,
#     #     SoleData.scalarlogiset(
#     #         # maybe: ["V$(i)" for i in 1:size(xs)[2]]) 
#     #         DataFrame(xs, :auto);
#     #         allow_propositional=true,
#     #     ),
#     # )
#     #
#     # df = DataFrame(xs, ["V$(i)" for i in 1:size(xs)[2]])
#     # return apply(model, PropositionalLogiset(df))
# end

"""
Compare the two models given, a generic one and a certified one;
these should be of the same type but, actually, you could think about scenarios
where you want to do a comparison between different model types.

Compare means to reproduce the same call to [`apply_metric`](@ref), on `X_test`
and `y_test`, with the two models.

`type` is a singleton Val(:regression) or Val(:classification), regulating
the dispatch on the inner `apply_metric` used for the comparison.

In the case of regression, `apply_metric` is the Pearson correlation; 
otherwise, it is the F1 score.

Note that the prediction of each model is obtained by calling 
[`apply_model`](@ref).
"""
function compare_models(
    first_model,
    certified_model,
    X_test,
    y_test,

    # yeah, the former is a Symbol and the other one is already a singleton...
    # this makes sense for how the rest of the code works:
    # the model_type is something iterated and manipulated during an experiment,
    # whilst the experiment_type is never touched from the configuration specs
    model_type::Symbol,
    experiment_type::Val,
)
    y_pred = apply_model(first_model, X_test, Val(model_type))
    pre_score = apply_metric(y_test, y_pred, experiment_type)

    y_pred = apply_model(certified_model, X_test, Val(model_type))
    post_score = apply_metric(y_test, y_pred, experiment_type)

    return pre_score, post_score
end
