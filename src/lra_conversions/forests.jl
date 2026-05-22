###############################################################################
##### Decision Forests ########################################################
###############################################################################

###### Regression

"""
    forest_to_lra(smodel::DecisionEnsemble{F}; pure_lra::Bool=true) where {F<:Real}
    forest_to_lra(smodel::DecisionEnsemble{S}; pure_lra::Bool=true) where {S<:AbstractString}

Translate a `SoleModels.DecisionEnsemble` into its LRA form.


!!! notes
    If `pure_lra` is set to `false`, then a new "big o" atom is appended at the end of the
    encoding, depending on the fact that the `DecisionEnsemble` is a forest of regression or
    classification trees.

    The role of this new variable is to align the values of every output "o1, o2...".
    In other words, it describes how the final decision is taken by the forest.

See also [`tree_to_lra`](@ref).
"""
function forest_to_lra(
    smodel::DecisionEnsemble{F}; pure_lra::Bool=true
) where {F<:Real}
    l = length(SoleModels.models(smodel))
    goal = join(["o$i" for i in 1:l], " ")

    conjuncts = [
        tree_to_lra(tree; id=id) for
        (id, tree) in enumerate(SoleModels.models(smodel))
    ]

    return if pure_lra
        CONJUNCTION(conjuncts...)
    else
        CONJUNCTION(conjuncts..., Atom("(= Or (/ (+ $goal) $l))"))
    end
end

"""
    tree_to_lra(Branch{F}; id::Int=1) where {F<:AbstractFloat}
    tree_to_lra(leaf::LeafModel{F}; id::Int=1) where {F<:AbstractFloat}

Translate a single tree (a certain `SoleModels.Branch`) into its LRA form.
"""
function tree_to_lra(tree::Branch{T}; id::Int=1) where {T}
    CONJUNCTION(
        IMPLICATION(antecedent(tree), tree_to_lra(posconsequent(tree); id=id)),
        IMPLICATION(
            ∇(antecedent(tree)), tree_to_lra(negconsequent(tree); id=id)
        ),
    )
end
function tree_to_lra(leaf::LeafModel{T}; id::Int=1) where {T}
    return Atom(ScalarCondition(VariableValue(id, "o$(id)"), ==, outcome(leaf)))
end

"""
    ∇(a::Atom{ScalarCondition})

Reverse the condition within an `Atom{ScalarCondition}`, instead of applying ¬ (`NEGATION`)
`Connective`.
"""
function ∇(a::Atom{ASC}) where {ASC<:SoleData.AbstractScalarCondition}
    _operator = test_operator(metacond(value(a)))
    _id = i_variable(feature(metacond(value(a))))
    _threshold = threshold(value(a))

    return Atom(
        ScalarCondition(
            VariableValue(_id),
            SoleData.inverse_test_operator(_operator),
            _threshold,
        ),
    )
end

###### Classification

"""
This dispatch of `forest_to_lra` is specific for the classification case.
It builds all the 10 parenthesis designed in the article.
"""
function forest_to_lra(
    smodel::DecisionEnsemble{S}; pure_lra::Bool=true
) where {S<:AbstractString}
    n_trees = length(SoleModels.models(smodel))
    n_classes = length(unique(smodel.info.supporting_labels))

    # 1st parenthesis (within the article)
    trees = [
        tree_to_lra(tree; id=id) for
        (id, tree) in enumerate(SoleModels.models(smodel))
    ]

    # 2nd parenthesis
    class_masks = mask_class(n_trees, n_classes)

    # 3rd parenthesis
    onehot_binding = onehot_to_class_binding(n_trees, n_classes)

    # 4th parenthesis
    # when creating all the c_j, you need to consider these weights
    counting_binding = count_classes(n_trees, n_classes)

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

# make the second parenthesis in the output class formula for the classification case
function mask_class(n_trees, n_classes)
    return CONJUNCTION(
        [
            CONJUNCTION(
                [
                    DISJUNCTION(
                        # this encodes y_i^j
                        Atom(
                            ScalarCondition(
                                VariableValue(0, "o$(i)_$(j)"), ==, "0"
                            ),
                        ),
                        Atom(
                            ScalarCondition(
                                VariableValue(0, "o$(i)_$(j)"), ==, "1"
                            ),
                        ),
                    ) for j in 1:n_classes
                ]...,
            ) for i in 1:n_trees
        ]...,
    )
end

# make the third parenthesis for the classification case
function onehot_to_class_binding(n_trees, n_classes)
    answer = []

    for i in 1:n_trees
        for j in 1:n_classes
            a = IMPLICATION(
                Atom(ScalarCondition(VariableValue(0, "o$(i)_$(j)"), ==, "1")),
                Atom(ScalarCondition(VariableValue(0, "o$(i)"), ==, "$(j)")),
            )
            b = IMPLICATION(
                Atom(ScalarCondition(VariableValue(0, "o$(i)"), ==, "$(j)")),
                Atom(ScalarCondition(VariableValue(0, "o$(i)_$(j)"), ==, "1")),
            )

            push!(answer, CONJUNCTION(a, b))
        end
    end

    return CONJUNCTION(answer...)
end

# make the fourth parenthesis
function count_classes(n_trees, n_classes)
    answer = []

    for j in 1:n_classes
        _inner_string = ""

        for i in 1:n_trees
            _inner_string = _inner_string * "o$(i)_$(j) + "
        end

        _inner_string = _inner_string[1:(end - 2)]

        push!(
            answer,
            Atom(ScalarCondition(VariableValue(0, "c$(j)"), ==, _inner_string)),
        )
    end

    return CONJUNCTION(answer...)
end

# make the fifth parenthesis
function geq_than_all_classes(n_classes)
    return CONJUNCTION([Atom("z >= c_$(j)") for j in 1:n_classes]...)
end

# make the sixth parenthesis
function eq_to_at_least_one_class(n_classes)
    return DISJUNCTION([Atom("z == c_$(j)") for j in 1:n_classes]...)
end

# make the seventh parenthesis
function mask_between_majorities(n_classes)
    return [
        CONJUNCTION(
            IMPLICATION(Atom("e$(j)"), Atom("c$(j) == z")),
            IMPLICATION(Atom("c$(j) == z"), Atom("e$(j)")),
        ) for j in 1:n_classes
    ]
end

# make the 8th parenthesis
function mask_implies_output(n_classes)
    return CONJUNCTION(
        [IMPLICATION(Atom("e$(j)"), Atom("Or >= $(j)")) for j in 1:n_classes]...
    )
end

# make the ninth parenthesis
function notmask_implies_nooutput(n_classes)
    return CONJUNCTION(
        [
            IMPLICATION(
                NEGATION(Atom("e$(j)")), NEGATION(Atom("(Or == $(j))"))
            ) for j in 1:n_classes
        ]...,
    )
end

# make the tenth parenthesis
function fix_class_for_or(n_classes)
    return DISJUNCTION([Atom("Or == $(j)") for j in 1:n_classes]...)
end
