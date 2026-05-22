#!/usr/bin/bash

NAMES=(
    ### classification
    iris
    breastcancer
    ecoli
    glass
    seeds

    # cryotherapy
    cryotherapy_small

    # divorce
    divorce_small

    # hayes_roth
    hayes_roth_small

    # monks_1
    soybean_small

    ### regression
    fishbream
    fishperch
    realestate
    energycool
    vehicle
    ads

    concrete_small
    dailydemand_small 
    forestfires_small
    # residential_small
    yacht_small

)

# this does not handle the list_forest type yet
MODELS=(
    list_forest
    # xgboost
    # decision_forest
)

HPS=(8 16 32)
LCS=(3 2 1)

for name in "${NAMES[@]}"; do
for model in "${MODELS[@]}"; do
for HP in "${HPS[@]}"; do
for LC in "${LCS[@]}"; do
    SESSION="exp_${name}_${model}_HP_${HP}_LC_${LC}"

    echo "Starting tmux session: $SESSION"

    # Create tmux session in detached mode
    tmux new-session -d -s "$SESSION"

    # Start Julia with project and run experiment;
    # C-m means "enter" in tmux
    tmux send-keys -t "$SESSION" \
        "julia --project=. experiments/run_experiment.jl ${name} ${model} ${HP} ${LC}" C-m
done
done
done
done

echo "Everything started!"
