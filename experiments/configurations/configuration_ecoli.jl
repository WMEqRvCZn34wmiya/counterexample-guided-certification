exp_datasets = [ecoli_config]

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
        # aggregate score about amino acid content of outer membrane
        # and periplasmic proteins very low
        Atom(ScalarCondition(VariableValue(5), >=, 0.08)),
        Atom(ScalarCondition(VariableValue(5), <=, 0.15)),
    ),
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(5), >=, 0.08)),
        Atom(ScalarCondition(VariableValue(5), <=, 0.15)),
        # high score of the ALOM membrane spanning region prediction program
        Atom(ScalarCondition(VariableValue(6), >=, 0.95)),
        Atom(ScalarCondition(VariableValue(6), <=, 0.98)),
    ),
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(5), >=, 0.08)),
        Atom(ScalarCondition(VariableValue(5), <=, 0.15)),
        Atom(ScalarCondition(VariableValue(6), >=, 0.95)),
        Atom(ScalarCondition(VariableValue(6), <=, 0.98)),
        # score of ALOM program after excluding putative cleavable signal
        # regions from the sequence.
        Atom(ScalarCondition(VariableValue(7), >=, 0.632)),
        Atom(ScalarCondition(VariableValue(7), <=, 0.639)),
    ),
]

# specific right constraints from which to choose
exp_rconstraints = [
    # then the protein is located in the outer membrane ("om" class)
    CONJUNCTION(
        Atom(ScalarCondition(VariableValue(0, "Or"), >=, 6)),
        Atom(ScalarCondition(VariableValue(0, "Or"), <=, 6)),
    ),
]

exp_batchsize = [1]

# number of times each experiment is repeated
exp_repetitions = 10

exp_seed = 1605
