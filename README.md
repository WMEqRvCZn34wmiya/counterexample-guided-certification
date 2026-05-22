# FormalVerificationRandomForests

# Requirements

- [Z3 theorem prover](https://github.com/Z3Prover/z3?tab=readme-ov-file); remember to add the path of the executable to your system's PATH variable, so that this package can properly call it (as a double check, in any OS, the command `z3 --version` should run properly).
- [Julia programming language](https://julialang.org/downloads/).

Run `juliaup add 1.11` to install the specific version of Julia we used to execute the experiments.

# Usage

Open a terminal in this folder, and open a new Julia session by running: 
```julia 
julia +1.11
```

You could even set the version `1.11` to be the default one by running `juliaup default 1.11` and, then, simply `julia`.

Now, activate the reproducibility environment by pressing `]`.
You should see a `pkg>` tag appearing, and you need to execute the following command for activating the project's environment:

```julia
activate .
```

To install all the necessary dependencies, run:
```
instantiate
```

At this point, consider one of the datasets in the `dataset` folder, whose "name" is the part before the `.csv` extension.

You can run the experiments related to that specific dataset by executing:

```julia
include("test/experiment_<name>.jl")
```

All the results are written in the `results` folder. In particular, each filename follows this naming convention:

``` name_LC_x_RC_x_HP_x_MD_x_BS_x.txt ```

In particular:

- `name` is the name of the dataset;
- `TY_x` is the name of the trained models;
- `LC_x` is the number of features in the left part of the constraint;
- `RC_x` is the number of features in the right part of the constraint;
- `HP_x` is a certain hyperparameter: the number of trees for tree forests, the number of lists in the case of decision list esembles, or number of rounds in XGBoost
- `MD_x` is the maximum depth of each tree;
- `BS_x` is the number of instances that are inserted in the dataset, after each call to the optimizer.

All experiments can be run with a launcher, in order to parallelize the computation with parameterization by spawning many `tmux` terminals; 
See `run_classification.sh` and `run_regression.sh` for a coarse strategy, just running many datasets in parallel.
See `run_granular.sh` for a granular strategy, spawning every possible parameterization for each specified dataset.

You can generate the table of the article by running the following in the REPL:
```julia
println( 
    make_experiment_table(
        ["divorce_small"],  # put here the dataset <name> you are testing
        ["list_forest"],    # method to inspect; can be decision_tree, list_forest or xgboost
        [3,2,1],            # antecedent complexity
        [8, 16, 32];        # hyperparameters (number of trees in decision forests, number of lists in list forests, number of rounds in xgboost) 
        FOLDER_PATH = joinpath(@__DIR__, "results"),    # keep this if running from the root of the project 
        shape = "@_TY_@_LC_@_RC_1_HP_@_MD_5_BS_1.txt"   # pattern for parsing results; MD is a deprecated parameter, and sometimes has to be tweaked between 3, 5 and 8 just for retrocompatibility
    )
)
```

# Datasets

You can inspect all the datasets involved by browsing the `dataset` folder.

In particular, you can also download them at the following links.

[Kaggle link for the Fish Market dataset]((https://www.kaggle.com/datasets/vipullrathod/fish-market)); we splitted the original dataset, distinguishing `bream` and `perch` classes, to respectively obtain `fishbream` and `fishperch`.

[Kaggle link for the Real Estate dataset](https://www.kaggle.com/datasets/quantbruce/real-estate-price-prediction).

[Kaggle link for the Advertising dataset](https://www.kaggle.com/datasets/ashydv/advertising-dataset).

[Kaggle link for the Vehicle dataset](https://www.kaggle.com/datasets/nehalbirla/vehicle-dataset-from-cardekho).


[UCI archive link for the Iris dataset](https://archive.ics.uci.edu/dataset/53/iris).

[UCI archive link for the Seeds dataset](https://archive.ics.uci.edu/dataset/236/seeds).

[UCI archive link for the Ecoli](https://archive.ics.uci.edu/dataset/39/ecoli).

[UCI archive link for the Breast Cancer Wisconsin](https://archive.ics.uci.edu/dataset/17/breast+cancer+wisconsin+diagnostic).

[UCI archive link for the Glass Identification dataset](https://archive.ics.uci.edu/dataset/42/glass+identification).

[UCI archive link for the Cryotherapy dataset](https://archive.ics.uci.edu/dataset/429/cryotherapy+dataset)

[UCI archive link for the Divorce dataset](https://archive.ics.uci.edu/dataset/539/divorce+predictors+data+set)

[UCI archive link for the Hayes Roth dataset](https://archive.ics.uci.edu/dataset/44/hayes+roth)

[UCI archive link for the Soybean dataset](https://archive.ics.uci.edu/dataset/91/soybean+small)

[UCI archive link for the Concrete Compressive Strenth dataset](https://archive.ics.uci.edu/dataset/165/concrete+compressive+strength)

[UCI archive link for the Daily Demand Forecasting Orders dataset](https://archive.ics.uci.edu/dataset/409/daily+demand+forecasting+orders)

[UCI archive link for the Forest Fires dataset](https://archive.ics.uci.edu/dataset/162/forest+fires)

[UCI archive link for the Yacht Hydrodynamics dataset](https://archive.ics.uci.edu/dataset/243/yacht+hydrodynamics)


# Other Notes

You can find the specific constraints we defined for each experiment, at the top of its corresponding file (in the `test` folder).

To know which method we defined, open the `FormalVerificationRandomForests.jl` file in the `src` directory.

To know more about one specific method, run:

```julia
? <methodname>
```
