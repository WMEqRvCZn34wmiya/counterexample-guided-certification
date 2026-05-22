module FormalVerificationRandomForests

using DataFrames
using DecisionTree
using DelimitedFiles
using Printf
using Random
using StatsBase

using Ipopt
using JuMP
using Juniper

using MLJ, MLJXGBoostInterface
import MLJ: @load
using XGBoost

using SoleData: feature, metacond, test_operator, threshold, value
using SoleLogics
using SoleModels
using ModalDecisionLists

const SL = SoleLogics
const SD = SoleData
const SM = SoleModels

export Result

"""
This holds the results of each experiment.
See also [`make_experiment_table`](@ref).
"""
const Result = NamedTuple{
    (
        :numtrees,
        :maxdepth,
        :batchsize,
        :lcomplexity,
        :rcomplexity,
        :tottime,
        :convtime,
        :numcycles,
        :metricpre,
        :metricpost,
    ),
    Tuple{Int,Int,Int,Int,Int,Float64,Float64,Int,Float64,Float64},
}

export make_experiment_table

include("table_builder.jl")

export aggregate_leafs
export make_constraint
export constraint_bounds_and_eps
export make_boundary_constraint
export istrivally_unsat
export make_optimizer
export verify
export adjustement_of_counterexample
export perturb
export f1_score

include("utils.jl")

export forest_to_lra, tree_to_lra, forest_decisionlist_to_lra
export decisionlist_to_lra, xgboost_to_lra

include("lra_conversions/forests.jl")
include("lra_conversions/decisionlists.jl")
include("lra_conversions/xgboosts.jl")

export to_smtlib2, parse_z3_model

include("smt_conversion_regression.jl")

export to_smtlib2_classification, parse_z3_model_classification

include("smt_conversion_classification.jl")

export to_smtlib2_classification_xgboost, parse_z3_model_classification_xgboost

include("smt_conversion_classification_xgboost.jl")

export DatasetConfig
export path, delimiter, skipstart, target_col, feature_cols, mappings, dropvalue
export datasetname
export load_dataset

export fishbream_config, fishperch_config
export realestate_config
export vehicle_config
export energyheat_config, energycool_config
export REGRESSION_DATASETS

export iris_config
export seeds_config
export glass_config
export ecoli_config
export breastcancer_config
export ads_config
export monks_1_config
export soybean_small_config

export cryotherapy_config
export cryotherapy_config_small
export divorce_config
export divorce_config_small
export hayes_roth_config
export hayes_roth_config_small

export concrete_config_small
export dailydemand_config_small
export forestfires_config_small
export yacht_config_small

include("load_dataset.jl")

export experiment

include("experiment_regression.jl")

export experiment_classification

include("experiment_classification.jl")

end
