exp_datasets = [vehicle_config]

# :regression or :ads;
# this is a Val because `experiment` will dispatch of this
exp_type = Val(:regression)

# which learning schema do you want to leverage?
# (decision_forest should not be available for regression)
exp_models = [:decision_forest, :xgboost]

# this will contain all the specialized hyperparameterisations for each 
# exp_models type (see below)
exp_hparam = Dict()

# Configuration for decision forests ###########################################

# number of trees in the model
exp_hparam[:decision_forest] = [8, 16, 32]
# exp_numtrees = [8, 16, 32]

# maximum depth of each tree;
# this can be ignored by everyone else
exp_maxdepth = [3]

# Configuration for decision lists #############################################
exp_hparam[:list_forest] = [8, 16, 32]

# Configuration for XGBoost ####################################################
exp_hparam[:xgboost] = [32, 24, 16]

# Configuration related to contraints ##########################################
# number of features in the left part of the constraint
exp_lcomplexities = [3, 2, 1]

# same as above, for the right part;
exp_rcomplexities = [1]

# specific left constraints from which to choose
exp_lconstraints = [
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(1), >=, 2005.1)),
        Atom(ScalarCondition(VariableValue(1), <=, 2005.9)),
    ),
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(1), >=, 2005.1)),
        Atom(ScalarCondition(VariableValue(1), <=, 2005.9)),
        Atom(ScalarCondition(VariableValue(2), >=, 16.3)),
        Atom(ScalarCondition(VariableValue(2), <=, 18.3)),
    ),
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(1), >=, 2005.1)),
        Atom(ScalarCondition(VariableValue(1), <=, 2005.9)),
        Atom(ScalarCondition(VariableValue(2), >=, 16.3)),
        Atom(ScalarCondition(VariableValue(2), <=, 18.3)),
        Atom(ScalarCondition(VariableValue(3), >=, 7100.0)),
        Atom(ScalarCondition(VariableValue(3), <=, 7900.0)),
    ),
]

# specific right constraints from which to choose
exp_rconstraints = [
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(0, "Or"), >=, 3.03)),
        Atom(ScalarCondition(VariableValue(0, "Or"), <=, 3.08)),
    ),
]

exp_batchsize = [1]

# number of times each experiment is repeated
exp_repetitions = 10

exp_seed = 1605
Random.seed!(exp_seed)
