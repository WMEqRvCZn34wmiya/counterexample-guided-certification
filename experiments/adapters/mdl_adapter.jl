# This file contains specific dispatches that are defined in 
# ModalDecisionLists, at test/rdl_benchmark/test_functions.jl
#
# These should be made available to everyone, with a proper export;
# since it is not a problem of this project, we prefer to just freeze the logic
# here below.

function __apply_post(m, preds)
    if haskey(info(m), :apply_postprocess)
        apply_postprocess_f = info(m, :apply_postprocess)
        preds = apply_postprocess_f.(preds)
    end
    preds
end

function apply_dl(
    m::DecisionList,
    i::AbstractInterpretation;
    check_args::Tuple=(),
    check_kwargs::NamedTuple=(;),
    kwargs...,
)
    for rule in rulebase(m)
        if checkantecedent(rule, i, check_args...; check_kwargs...)
            return consequent(rule)
        end
    end
    defaultconsequent(m)
end

function apply_dl(
    m::DecisionList{O},
    d::AbstractInterpretationSet;
    check_args::Tuple=(),
    check_kwargs::NamedTuple=(;),
    kwargs...,
) where {O}
    nsamp = ninstances(d)
    preds = Vector{O}(undef, nsamp)
    uncovered_idxs = 1:nsamp

    for rule in rulebase(m)
        length(uncovered_idxs) == 0 && break

        uncovered_d = slicedataset(d, uncovered_idxs; return_view=true)

        idxs_sat = findall(
            checkantecedent(rule, uncovered_d, check_args...; check_kwargs...)
        )
        idxs_sat = uncovered_idxs[idxs_sat]
        uncovered_idxs = setdiff(uncovered_idxs, idxs_sat)

        foreach((i)->(preds[i] = outcome(consequent(rule))), idxs_sat)
    end

    length(uncovered_idxs) != 0 &&
        foreach((i)->(preds[i] = outcome(defaultconsequent(m))), uncovered_idxs)

    return preds
end

function apply_ensemble(
    m::DecisionEnsemble,
    X::PropositionalLogiset;
    suppress_parity_warning=false,
    kwargs...,
)
    submodels = models(m)

    total_preds = []

    for subm in submodels
        if hasproperty(subm, :info) && haskey(info(subm), :featurenames)
            feature_names = info(subm)[:featurenames]

            # TODO: this is unsafe as 'PropositionalLogiset' does not necessarily allow slicing in this manner.
            # However, until PropositionalLogiset is reworked this must suffice
            X_model = X[:, feature_names]
            preds = if isa(subm, DecisionList)
                apply_dl(
                    subm,
                    X_model;
                    suppress_parity_warning=suppress_parity_warning,
                    kwargs...,
                )
            else
                apply(subm, X_model)
            end
        else
            preds = if isa(subm, DecisionList)
                apply_dl(
                    subm,
                    X;
                    suppress_parity_warning=suppress_parity_warning,
                    kwargs...,
                )
            else
                apply(subm, X)
            end
        end

        push!(total_preds, preds)
    end

    preds = hcat(total_preds...)
    preds = __apply_post(m, preds)
    preds = [
        weighted_aggregation(m)(preds[i, :]; suppress_parity_warning) for
        i in 1:size(preds, 1)
    ]
    return preds
end
