###############################################################################
##### Decision Lists ##########################################################
###############################################################################

function forest_decisionlist_to_lra(
    dls::DecisionEnsemble{F,DecisionList{F}}; pure_lra::Bool=true
) where {F}
    l = length(SoleModels.models(dls))
    goal = join(["o$i" for i in 1:l], " ")

    conjuncts = []

    for (id, dl) in enumerate(SoleModels.models(dls))
        rl = rulebase(dl)
        antecedents = antecedent.(rl)
        consequents = Atom.([c.outcome for c in consequent.(rl)])
        number_rules = length(antecedents)
        #@show antecedents
        neg_antecedents = NEGATION.(antecedents)
        #@show neg_antecedents
        default_consequents = Atom(
            ScalarCondition(
                VariableValue(1, "o$(id)"), ==, dl.defaultconsequent.outcome
            ),
        )
        finalcon = decisionlist_to_lra(
            antecedents,
            neg_antecedents,
            consequents,
            default_consequents,
            id,
            number_rules,
        )
        push!(conjuncts, finalcon) # MAYBE ERROR HERE FOR SPLAT OF conjunct
    end

    return if pure_lra
        CONJUNCTION(conjuncts...)
    else
        # TODO: regression or classification depending on F
        CONJUNCTION(conjuncts..., Atom("(= Or (/ (+ $goal) $l))"))
    end
end

"""
    decisionlist_to_lra...

Translate a single decisionlist into its LRA form.
"""
function decisionlist_to_lra(
    antecedents,
    neg_antecedents,
    consequents,
    default_consequent,
    id::Int=1,
    N::Int=1,
) where {T}
    function _outvar_with_atom_value(consequent, id)
        return Atom(ScalarCondition(VariableValue(1, "o$(id)"), ==, consequent))
    end

    conjs = []

    push!(
        conjs,
        IMPLICATION(
            antecedents[1],
            # _outvar_with_atom_value(consequents[1], id)
            Atom(
                ScalarCondition(
                    VariableValue(1, "o$(id)"), ==, SL.value(consequents[1])
                ),
            ),
            # consequents[1]
        ),
    )

    for i in 2:N
        conj = begin
            IMPLICATION(
                CONJUNCTION(
                    CONJUNCTION(neg_antecedents[1:(i - 1)]...),
                    antecedents[i],
                ),
                # _outvar_with_atom_value(consequents[i], id)
                Atom(
                    ScalarCondition(
                        VariableValue(1, "o$(id)"),
                        ==,
                        SL.value(consequents[i]),
                    ),
                ),
                # consequents[i]
            )
        end
        push!(conjs, conj)
    end

    final_lra = CONJUNCTION(
        CONJUNCTION(conjs...),
        IMPLICATION(CONJUNCTION(neg_antecedents...), default_consequent),
    )
    return final_lra
end
