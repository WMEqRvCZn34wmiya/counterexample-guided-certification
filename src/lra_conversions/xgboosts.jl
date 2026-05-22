###############################################################################
##### XGBoost #################################################################
###############################################################################

# Regression
# (we know, DecisionXGBoost{Float32} is a very very very very very very very 
# very bad name for indicating a XGBoostRegression translated to solemodels)
function xgboost_to_lra(
    smodel::DecisionXGBoost{Float32};
    base_score::Float64=0.5,
    pure_lra::Bool=false,
)
    _smodels = SoleModels.models(smodel)
    l = length(_smodels)

    goal = join(["o$i" for i in 1:l], " ")

    conjuncts = [
        boosted_to_lra(tree; id=id) for
        (id, tree) in enumerate(SoleModels.models(smodel))
    ]

    return if pure_lra
        CONJUNCTION(conjuncts...)
    else
        # CONJUNCTION(conjuncts..., Atom("(= Or (/ (+ $goal) $l))"))
        # base_score = smodel.info.base_score   # TODO IDK IN OUR MODEL 
        #  CONJUNCTION(conjuncts..., Atom("(= Or (+ $goal))")) 
         CONJUNCTION(conjuncts..., Atom("(= Or (+ $goal $base_score))")) 
        #  CONJUNCTION(conjuncts..., Atom("(bs = $base_score) ∧ (= Or (+ $goal bs) ∧  )")) 
    end
end

function boosted_to_lra(tree::Branch{T}; id::Int=1) where {T<:Real}
    return CONJUNCTION(
        IMPLICATION(antecedent(tree), tree_to_lra(posconsequent(tree); id=id)),
        IMPLICATION(
            ∇(antecedent(tree)), tree_to_lra(negconsequent(tree); id=id)
        ),
    )
end
function boosted_to_lra(leaf::LeafModel{T}; id::Int=1) where {T<:Real}
    return Atom(ScalarCondition(VariableValue(id, "o$(id)"), ==, outcome(leaf)))
end

################################################################################
# Classification
# Differently from the case of regression, here weights are linked to a 
# specific classification within a specific tree;
# we can't just enumerate alle the weights while we are building the output 
# (e.g., 1,2,3,...12 weights), but instead we have to do:
# weight1 for classification A of first tree
# weight2 for classification B of first tree etc.
function xgboost_to_lra(
    smodel::DecisionXGBoost{T}; pure_lra::Bool=false
) where {T}
    _smodels = SoleModels.models(smodel)
    n_trees = length(_smodels)

    classes = unique(smodel.info.supporting_labels)
    n_classes = length(unique(smodel.info.supporting_labels))

    # _nweights_per_tree = [length(tree.info.leaf_value) for tree in _smodels]
    weights = smodel.info.leaf_value

    # 1st parenthesis (within the article)
    trees = []

    # DONE: fix the indexing for the weights
    # e.g.: there is no w_2_7 when encoding the second tree of the example
    # (see test/temp_xgboost_classification.jl)
    # TODO: the translation from lra to smtlib2 might be affected by this too
    my_w = 0
    for (id, tree) in enumerate(_smodels)
        if (id != 1)
            old_w = my_w + 1
        else
            old_w = 1
        end
        my_w = length(smodel.models[id].info.leaf_value) + old_w - 1

        tree = boosted_to_lra_classification(
            tree;
            id=id,
            classes=classes,
            weights,
            # if I am dealing with the second tree, with 9 weights, 
            # coming from a tree with 2 weights, I don't want to do 
            # w_2_3, w_2_4, etc.
            # but I want to do w_2_1, w_2_2, etc. instead;
            # so I have to delete a factor 2 from every j (the second index)
            range_adjustment=old_w - 1,
            left=old_w,
            right=my_w,
        )
        push!(trees, tree)
    end

    # trees = [boosted_to_lra_classification(tree; id=id, classes=classes) for (id, tree) in smodel |> SoleModels.models |> enumerate]

    # 2nd parenthesis
    class_masks = mask_class(n_trees, n_classes)

    # 3rd parenthesis
    onehot_binding = onehot_to_class_binding(n_trees, n_classes)

    # 4th parenthesis
    # when creating all the c_j, you need to consider these weights
    counting_binding = count_classes_weighted(n_trees, n_classes)

    # 5th parenthesis
    _geq_than_all_classes = geq_than_all_classes(n_classes)

    # 6th parenthesis
    _eq_to_at_least_one_class = eq_to_at_least_one_class(n_classes)

    # 7th parenthesis
    _mask_between_majorities = mask_between_majorities(n_classes)

    # 8th parenthesis
    _mask_implies_output = mask_implies_output(n_classes)

    # 9th parenthesis
    _notmask_implies_nooutput = notmask_implies_nooutput(n_classes)

    # 10th parenthesis
    _or_at_least_one_class = fix_class_for_or(n_classes)

    return if pure_lra
        CONJUNCTION(trees...)
    else
        # this should be called Oc, but Or is kept for avoiding changing the parser
        CONJUNCTION(
            trees...,
            class_masks,
            onehot_binding,
            counting_binding,
            _geq_than_all_classes,
            _eq_to_at_least_one_class,
            _mask_between_majorities...,
            _mask_implies_output,
            _notmask_implies_nooutput,
            _or_at_least_one_class,
        )
    end
end

function boosted_to_lra_classification(
    tree::Branch{T}; id::Int=1, classes, weights, range_adjustment, left, right
) where {T}
    postree = posconsequent(tree)
    negrtree = negconsequent(tree)

    if postree isa ConstantModel
        r1 = left + 1
    else
        lv_poscon = posconsequent(tree).info.leaf_value
        r1 = left + length(lv_poscon)
    end

    if negrtree isa ConstantModel
        r2 = r1
    else
        lv_negtcon = negconsequent(tree).info.leaf_value
        r2 = r1 + length(lv_negtcon)
    end

    return CONJUNCTION(
        IMPLICATION(
            antecedent(tree),
            boosted_to_lra_classification(
                posconsequent(tree);
                id,
                classes,
                weights,
                range_adjustment=range_adjustment,
                left,
                right=r1 - 1,
            ),
        ),
        IMPLICATION(
            NEGATION(antecedent(tree)),
            boosted_to_lra_classification(
                negconsequent(tree);
                id,
                classes,
                range_adjustment=range_adjustment,
                weights=weights,
                left=r1,
                right=r2,
            ),
        ),
    )
end

function boosted_to_lra_classification(
    leaf::LeafModel{T};
    id::Int=1,
    classes,
    weights,
    range_adjustment,
    left,
    right,
) where {T}
    # use this if you want a continuative numbering of weights within trees;
    # e.g., w1_1, w1_2, w2_1, w2_2, w2_3, etc.
    # j = left - range_adjustment

    # use this if you want j to be associated with labels
    j = findfirst(x -> x == outcome(leaf), classes)

    return CONJUNCTION(
        Atom(ScalarCondition(VariableValue(id, "o$(id)"), ==, outcome(leaf))),
        Atom(
            ScalarCondition(
                VariableValue(id, "w$(id)_$(j)"), ==, "$(weights[left])"
            ),
        ),
    )
end

###############################################################################
###### Stuff for classification ###############################################
###############################################################################

# fourth parentesis for the case of xgboost
function count_classes_weighted(n_trees, n_classes)
    answer = []

    for j in 1:n_classes
        _inner_string = ""

        for i in 1:n_trees
            _inner_string = _inner_string * "(* o$(i)_$(j) w$(i)_$(j)) + " # TODO!! ALLERT THIS IS AN ERROR IF WE WONT AUTO GENERATE TE CONTROPART
        end

        _inner_string = _inner_string[1:(end - 2)]

        push!(
            answer,
            Atom(ScalarCondition(VariableValue(0, "c$(j)"), ==, _inner_string)),
        )
    end

    return CONJUNCTION(answer...)
end

# # make the second parenthesis in the output class formula for the classification case
# function mask_class(n_trees, n_classes)
#     return CONJUNCTION([
#         CONJUNCTION([
#             DISJUNCTION(
#                 # this encodes y_i^j
#                 ScalarCondition(VariableValue(0, "o$(i)_$(j)"), ==, "0") |> Atom,
#                 ScalarCondition(VariableValue(0, "o$(i)_$(j)"), ==, "1") |> Atom
#             )
#             for j in 1:n_classes
#         ]...)
#         for i in 1:n_trees
#     ]...)
# end
#
# # make the third parenthesis for the classification case
# function onehot_to_class_binding(n_trees, n_classes)
#     answer = []
#
#     for i in 1:n_trees
#         for j in 1:n_classes
#             a = IMPLICATION(
#                 ScalarCondition(VariableValue(0, "o$(i)_$(j)"), ==, "1") |> Atom,
#                 ScalarCondition(VariableValue(0, "o$(i)"), ==, "$(j)") |> Atom)
#             b = IMPLICATION(
#                 ScalarCondition(VariableValue(0, "o$(i)"), ==, "$(j)") |> Atom,
#                 ScalarCondition(VariableValue(0, "o$(i)_$(j)"), ==, "1") |> Atom)
#
#             push!(answer, CONJUNCTION(a, b))
#         end
#     end
#
#     return CONJUNCTION(answer...)
# end
# # make the fifth parenthesis
# function geq_than_all_classes(n_classes)
#     return CONJUNCTION([
#         Atom("z >= c_$(j)")
#         for j in 1:n_classes
#     ]...)
# end
#
# # make the sixth parenthesis
# function eq_to_at_least_one_class(n_classes)
#     return DISJUNCTION([
#         Atom("z == c_$(j)")
#         for j in 1:n_classes
#     ]...)
# end
#
# # make the seventh parenthesis
# function mask_between_majorities(n_classes)
#     return [
#         CONJUNCTION(
#             IMPLICATION(Atom("e$(j)"), Atom("c$(j) == z")),
#             IMPLICATION(Atom("c$(j) == z"), Atom("e$(j)"))
#         )
#         for j in 1:n_classes
#     ]
# end
#
# # make the 8th parenthesis
# function mask_implies_output(n_classes)
#     return CONJUNCTION([
#         IMPLICATION(Atom("e$(j)"), Atom("Or >= $(j)"))
#         for j in 1:n_classes
#     ]...)
# end
#
# # make the ninth parenthesis
# function notmask_implies_nooutput(n_classes)
#     return CONJUNCTION([
#         IMPLICATION(NEGATION(Atom("e$(j)")), NEGATION(Atom("(Or == $(j))")))
#         for j in 1:n_classes
#     ]...)
# end
#
# # make the tenth parenthesis
# function fix_class_for_or(n_classes)
#     return DISJUNCTION([
#         Atom("Or == $(j)")
#         for j in 1:n_classes
#     ]...)
# end
#
#
#
