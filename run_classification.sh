#!/usr/bin/bash

NAMES=(
    iris
    breastcancer
    ecoli
    glass
    seeds
    cryotherapy
    divorce
    hayes_roth
    soybean_small
)

MODELS=(
    xgboost
    # decision_forest
    # list_forest
)

for name in "${NAMES[@]}"; do
    for model in "${MODELS[@]}"; do
        SESSION="exp_${name}_${model}"

        echo "Starting tmux session: $SESSION"

        # Create tmux session in detached mode
        tmux new-session -d -s "$SESSION"

        # Start Julia with project and run experiment;
        # C-m means "enter" in tmux
        tmux send-keys -t "$SESSION" \
            "julia --project=. experiments/run_experiment.jl ${name} ${model}" C-m
    done
done

echo "All experiments started."
echo "Attach with: tmux attach -t exp_<name>"
