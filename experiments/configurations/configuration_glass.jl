exp_datasets = [glass_config]

# :regression or :classification;
# this is a Val because `experiment` will dispatch of this
exp_type = Val(:classification)

# which learning schema do you want to leverage?
# (decision_forest should not be available for regression)
exp_models = [:xgboost]

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
        # if the weight percentace of Na oxide is low
        Atom(ScalarCondition(VariableValue(2), >=, 10.78)),
        Atom(ScalarCondition(VariableValue(2), <=, 10.99)),
    ),
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(2), >=, 10.78)),
        Atom(ScalarCondition(VariableValue(2), <=, 10.99)),
        # if the weight percentage of Mg oxide is high
        Atom(ScalarCondition(VariableValue(3), >=, 4.00)),
        Atom(ScalarCondition(VariableValue(3), <=, 4.45)),
    ),
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(2), >=, 10.78)),
        Atom(ScalarCondition(VariableValue(2), <=, 10.99)),
        Atom(ScalarCondition(VariableValue(3), >=, 4.00)),
        Atom(ScalarCondition(VariableValue(3), <=, 4.45)),
        # and the weight percentage of Al oxide is low
        Atom(ScalarCondition(VariableValue(4), >=, 0.35)),
        Atom(ScalarCondition(VariableValue(4), <=, 0.45)),
    ),
]

# specific right constraints from which to choose
exp_rconstraints = [
    # then the glass is headlamps glass
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(0, "Or"), >=, 7)),
        Atom(ScalarCondition(VariableValue(0, "Or"), <=, 7)),
    ),
]

exp_batchsize = [1]

# number of times each experiment is repeated
exp_repetitions = 10

exp_seed = 1605
