exp_datasets = [cryotherapy_config]

# :regression or :classification;
# this is a Val because `experiment` will dispatch of this
exp_type = Val(:classification)

# which learning schema do you want to leverage?
# (decision_forest should not be available for regression)
exp_models = [:list_forest]

# this will contain all the specialized hyperparameterisations for each 
# exp_models type (see below)
exp_hparam = Dict()

# Configuration for decision forests ###########################################

# number of trees in the model
exp_hparam[:decision_forest] = [8, 16, 32]
# exp_numtrees = [8, 16, 32]

# maximum depth of each tree;
# this can be ignored by everyone else
exp_maxdepth = [5]

# Configuration for decision lists #############################################
exp_hparam[:list_forest] = [8, 16, 32]

# Configuration for XGBoost ####################################################
exp_hparam[:xgboost] = [8, 16, 32]

# Configuration related to contraints ##########################################
# number of features in the left part of the constraint
exp_lcomplexities = [3, 2, 1]

# same as above, for the right part;
exp_rcomplexities = [1]

# specific left constraints from which to choose
exp_lconstraints = [
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(2), >=, 32)),
        Atom(ScalarCondition(VariableValue(2), <=, 36)),
    ),
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(2), >=, 32)),
        Atom(ScalarCondition(VariableValue(2), <=, 36)),
        Atom(ScalarCondition(VariableValue(3), >=, 9)),
        Atom(ScalarCondition(VariableValue(3), <=, 12)),
    ),
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(2), >=, 32)),
        Atom(ScalarCondition(VariableValue(2), <=, 36)),
        Atom(ScalarCondition(VariableValue(3), >=, 9)),
        Atom(ScalarCondition(VariableValue(3), <=, 12)),
        Atom(ScalarCondition(VariableValue(4), >=, 5)),
        Atom(ScalarCondition(VariableValue(4), <=, 5)),
    ),
]

# specific right constraints from which to choose
exp_rconstraints = [
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(0, "Or"), >=, 1)),
        Atom(ScalarCondition(VariableValue(0, "Or"), <=, 1)),
    ),
]

exp_batchsize = [1]

# number of times each experiment is repeated
exp_repetitions = 10

exp_seed = 1605
