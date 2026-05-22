using DelimitedFiles

# Configuration struct for any dataset
"""
Configuration structure for any dataset.

# Getters
```julia
    datasetname(dc::DatasetConfig) = dc.name
    # just a renaming as above
    name(dc::DatasetConfig) = datasetname(dc)

    # relative path to dataset
    path(dc::DatasetConfig) = dc.path

    # CSV delimiter
    delimiter(dc::DatasetConfig) = dc.delimiter

    # rows to skip
    skipstart(dc::DatasetConfig) = dc.skipstart

    # column index of label
    target_col(dc::DatasetConfig) = dc.target_col

    # columns to use as features
    feature_cols(dc::DatasetConfig) = dc.feature_cols

    # optional mappings for categorical columns
    mappings(dc::DatasetConfig) = dc.mappings

    # if a row contains this, drop out the row
    dropvalue(dc::DatasetConfig) = dc.dropvalue

    # specify which columns must be treated as integer numbers
    integerfeatures(dc::DatasetConfig) = dc.integerfeatures

    # the type of the dataset (0 classification, 1 regression, 2 experimental regression)
    dataset_type(dc::DatasetConfig) = dc.dataset_type
```
"""
mutable struct DatasetConfig
    name::String
    path::String                        # relative path to dataset
    delimiter::Char                     # CSV delimiter
    skipstart::Int                      # rows to skip
    target_col::Int                     # column index of label
    feature_cols::Union{UnitRange{Int},Iterators.Flatten}  # columns to use as features
    mappings::Dict{Int,Dict{String,Int}}    # optional mappings for categorical columns
    transformers::Dict{Int,<:Function}      # optional transformers for any column
    dropvalue::Union{String,Nothing}    # if a row contains this, drop out the row
    integerfeatures::Vector{Int}        # specify which features have an integer domain

    # 0 for classification, 1 for real regression, 2 for integer regression
    dataset_type::Int              # the regression has to be an integer number

    function DatasetConfig(
        name::String,
        path::String,
        delimiter::Char;
        skipstart::Int=1,
        target_col::Int=-1,
        feature_cols::Union{UnitRange{Int},Iterators.Flatten}=1:1,
        mappings::Dict{Int64,Dict{String,Int}}=Dict{Int64,Dict{String,Int}}(),
        transformers::Dict{Int64,<:Function}=Dict{Int64,Function}(),
        dropvalue::Union{String,Nothing}=nothing,
        integerfeatures::Vector{Int}=Int[],
        dataset_type::Int=0,
    )
        new(
            name,
            path,
            delimiter,
            skipstart,
            target_col,
            feature_cols,
            mappings,
            transformers,
            dropvalue,
            integerfeatures,
            dataset_type,
        )
    end
end

datasetname(dc::DatasetConfig) = dc.name
name(dc::DatasetConfig) = datasetname(dc) # just a renaming for datasetname
path(dc::DatasetConfig) = dc.path
delimiter(dc::DatasetConfig) = dc.delimiter
skipstart(dc::DatasetConfig) = dc.skipstart
target_col(dc::DatasetConfig) = dc.target_col
feature_cols(dc::DatasetConfig) = dc.feature_cols
mappings(dc::DatasetConfig) = dc.mappings
dropvalue(dc::DatasetConfig) = dc.dropvalue
integerfeatures(dc::DatasetConfig) = dc.integerfeatures
dataset_type(dc::DatasetConfig) = dc.dataset_type

"""
Loader for a dataset

# Examples
```julia
julia> fishbream_config = DatasetConfig(
    "fishbream",
    "fishbream.csv",
    ',',
    skipstart = 1,
    target_col = 2,
    feature_cols = 3:7,
    dataset_type = 1
)

julia> X, y = load_dataset(fishbream_config)
```
"""
function load_dataset(
    config::DatasetConfig; root_path::String=joinpath(@__DIR__, "dataset")
)
    dataset_path = joinpath(root_path, path(config))
    data = DelimitedFiles.readdlm(
        dataset_path, delimiter(config); skipstart=skipstart(config)
    )

    # filter out missing values
    if !isnothing(dropvalue)
        data = data[[!any(row .== "?") for row in eachrow(data)], :]
    end

    # mappings for categorical columns
    for (col, mapping) in config.mappings
        for i in 1:size(data)[1]
            data[i, col] = mapping[string(data[i, col])]
        end
    end

    # transformation for scientific notation
    for (col, transformer) in config.transformers
        for i in 1:size(data)[1]
            data[i, col] = transformer(data[i, col])
        end
    end

    _feature_cols = if config.feature_cols isa Iterators.Flatten
        collect(config.feature_cols)
    else
        config.feature_cols
    end

    features = float.(data[:, _feature_cols])

    if dataset_type(config) == 0
        labels = string.(data[:, config.target_col])
    else
        labels = float.(data[:, config.target_col])
    end

    return features, labels
end

"""
Deepcopy `dc` but changing the `dataset_type` field.
"""
function copy_with_type(dc::DatasetConfig, t::Int)
    _dc = deepcopy(dc)
    _dc.dataset_type = t;
    return _dc
end

# ------------------------ Dataset Configurations ------------------------

fishbream_config = DatasetConfig(
    "fishbream",
    "fishbream.csv",
    ',';
    skipstart=1,
    target_col=2,
    feature_cols=3:7,
    dataset_type=1,
)

fishperch_config = DatasetConfig(
    "fishperch",
    "fishperch.csv",
    ',';
    skipstart=1,
    target_col=2,
    feature_cols=3:7,
    dataset_type=1,
)

realestate_config = DatasetConfig(
    "realestate",
    "realestate.csv",
    ',';
    skipstart=1,
    target_col=8,
    feature_cols=2:7,
    dataset_type=1,
)

vehicle_config = DatasetConfig(
    "vehicle",
    "vehicle.csv",
    ',';
    skipstart=1,
    target_col=3,
    feature_cols=Iterators.flatten((2:2, 4:5)),
    dataset_type=1,
)

energyheat_config = DatasetConfig(
    "energyheat",
    "energy.csv",
    ',';
    skipstart=1,
    target_col=9,
    feature_cols=1:8,
    dataset_type=1,
)

energycool_config = DatasetConfig(
    "energycool",
    "energy.csv",
    ',';
    skipstart=1,
    target_col=9,
    feature_cols=1:8,
    dataset_type=1,
)

ads_config = DatasetConfig(
    "Advertising",
    "Advertising.csv",
    ',';
    skipstart=1,
    target_col=4,
    feature_cols=1:3,
    dataset_type=1,
)

##############################################################################################

iris_config = DatasetConfig(
    "iris",
    "iris.csv",
    ',';
    skipstart=1,
    target_col=5,
    feature_cols=1:4,
    dataset_type=0,
    mappings=Dict(
        5 => Dict(
            "Iris-setosa" => 1,
            "Iris-versicolor" => 2,
            "Iris-virginica" => 3,
        ),
    ),
)

seeds_config = DatasetConfig(
    "seeds",
    "seeds.csv",
    ',';
    skipstart=0,
    target_col=8,
    feature_cols=1:7,
    dataset_type=0,
)

# To construct the data, seven geometric parameters of wheat kernels were measured:
# 1. area A,
# 2. perimeter P,
# 3. compactness C = 4*pi*A/P^2,
# 4. length of kernel,
# 5. width of kernel,
# 6. asymmetry coefficient
# 7. length of kernel groove.
glass_config = DatasetConfig(
    "glass",
    "glass.csv",
    ',';
    skipstart=0,
    target_col=11,
    feature_cols=2:10,
    dataset_type=0,
)

ecoli_config = DatasetConfig(
    "ecoli",
    "ecoli.csv",
    ',';
    skipstart=0,
    target_col=9,
    feature_cols=2:8,
    dataset_type=0,
    mappings=Dict(
        9 => Dict(
            " cp" => 1,
            " im" => 2,
            "imS" => 3,
            "imL" => 4,
            "imU" => 5,
            " om" => 6,
            "omL" => 7,
            " pp" => 8,
        ),
    ),
)

breastcancer_config = DatasetConfig(
    "breastcancer",
    "breastcancer.csv",
    ',';
    skipstart=0,
    target_col=2,
    feature_cols=3:32,
    dataset_type=0,
    mappings=Dict(2 => Dict("M" => 1, "B" => 2)),
)

##############################################################################################

cryotherapy_config = DatasetConfig(
    "cryotherapy",
    "cryotherapy.csv",
    ',';
    skipstart=1,
    target_col=7,
    feature_cols=1:6,
    dataset_type=0,
)

cryotherapy_config_small = DatasetConfig(
    "cryotherapy_small",
    "cryotherapy_small.csv",
    ',';
    skipstart=1,
    target_col=7,
    feature_cols=1:6,
    dataset_type=0,
)

divorce_config = DatasetConfig(
    "divorce",
    "divorce.csv",
    ',';
    skipstart=1,
    target_col=55,
    feature_cols=1:54,
    dataset_type=0,
)

divorce_config_small = DatasetConfig(
    "divorce_small",
    "divorce_small.csv",
    ',';
    skipstart=1,
    target_col=55,
    feature_cols=1:54,
    dataset_type=0,
)

hayes_roth_config = DatasetConfig(
    "hayes_roth",
    "hayes_roth.csv",
    ',';
    skipstart=1,
    target_col=6,
    feature_cols=1:5,
    dataset_type=0,
)

hayes_roth_config_small = DatasetConfig(
    "hayes_roth_small",
    "hayes_roth_small.csv",
    ',';
    skipstart=1,
    target_col=6,
    feature_cols=1:5,
    dataset_type=0,
)

monks_1_config = DatasetConfig(
    "monks_1",
    "monks_1.csv",
    ',';
    skipstart=1,
    target_col=7,
    feature_cols=1:6,
    dataset_type=0,
)

soybean_small_config = DatasetConfig(
    "soybean_small",
    "soybean_small.csv",
    ',';
    skipstart=1,
    target_col=36,
    feature_cols=1:35,
    dataset_type=0,
    mappings=Dict(36 => Dict("D1" => 1, "D2" => 2, "D3" => 4, "D4" => 4)),
)

##############################################################################################

concrete_config_small = DatasetConfig(
    "concrete",
    "concrete_small.csv",
    ',';
    skipstart=1,
    target_col=9,
    feature_cols=1:8,
    dataset_type=1,
)


dailydemand_config_small = DatasetConfig(
    "dailydemand",
    "dailydemand_small.csv",
    ';';
    skipstart=1,
    target_col=11,
    feature_cols=3:10,
    dataset_type=1,
)

forestfires_config_small = DatasetConfig(
    "forestfires",
    "forestfires_small.csv",
    ',';
    skipstart=1,
    target_col=11,
    feature_cols=5:10,
    dataset_type=1,
)

yacht_config_small = DatasetConfig(
    "yacht",
    "yacht_small.csv",
    ',';
    skipstart=0,
    target_col=7,
    feature_cols=2:6,
    dataset_type=1,
)


##############################################################################################


REGRESSION_DATASETS = [
    fishbream_config,
    fishperch_config,
    realestate_config,
    vehicle_config,
    energyheat_config,
    energycool_config,
]

CLASSIFICATION_DATASETS = [
    iris_config, seeds_config, glass_config, ecoli_config, breastcancer_config,
    cryotherapy_config, divorce_config, hayes_roth_config, monks_1_config,
    soybean_small_config
]
