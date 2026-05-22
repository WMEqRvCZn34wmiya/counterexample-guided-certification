exp_datasets = [iris_config]

# :regression or :classification;
# this is a Val because `experiment` will dispatch of this
exp_type = Val(:classification)

# which learning schema do you want to leverage?
# (decision_forest should not be available for regression)
exp_models = [:xgboost, :list_forest]

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
exp_hparam[:xgboost] = [4] # 8, 16, 32]

# Configuration related to contraints ##########################################
# number of features in the left part of the constraint
exp_lcomplexities = [3, 2, 1]

# same as above, for the right part;
exp_rcomplexities = [1]

# specific left constraints from which to choose
exp_lconstraints = [
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(4), >=, 0.65)), # this was >= 0.8 and <= 0.8
        Atom(ScalarCondition(VariableValue(4), <=, 0.95)),
    ),
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(4), >=, 0.65)),
        Atom(ScalarCondition(VariableValue(4), <=, 0.95)),
        Atom(ScalarCondition(VariableValue(3), >=, 6.72)),
        Atom(ScalarCondition(VariableValue(3), <=, 6.88)),
    ),
    CONJUNCTION(
        # Atom(ScalarCondition(VariableValue(4), >=, 990.65)),
        # Atom(ScalarCondition(VariableValue(4), <=, 990.95)),
        # Atom(ScalarCondition(VariableValue(3), >=, 996.72)),
        # Atom(ScalarCondition(VariableValue(3), <=, 996.88)),
        # Atom(ScalarCondition(VariableValue(2), >=, 992.05)),
        # Atom(ScalarCondition(VariableValue(2), <=, 992.15)),
        #
        # Old (and good) contraints
        Atom(ScalarCondition(VariableValue(4), >=, 0.65)),
        Atom(ScalarCondition(VariableValue(4), <=, 0.95)),
        Atom(ScalarCondition(VariableValue(3), >=, 6.72)),
        Atom(ScalarCondition(VariableValue(3), <=, 6.88)),
        Atom(ScalarCondition(VariableValue(2), >=, 2.05)),
        Atom(ScalarCondition(VariableValue(2), <=, 2.15)),
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
