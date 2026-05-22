"""
Return the LaTeX's table encoding of the experiments' results.
The provided args are injected in the `shape` metastring, as below.

# Examples
```julia
julia> make_experiment_table(
    ["fishbream"], 
    ["xgboost", "list_forest", "decision_forest"], 
    [1,2,3], 
    [8,16,32];
    FOLDER_PATH = joinpath(@__DIR__, "results"),
    shape = "@_TY_@_LC_@_RC_1_NT_@_MD_3_BS_1.txt"
)
```

# Operative example for CIMK2026
Use something similar to the following

```julia
a = make_experiment_table(["cryotherapy_small"], ["list_forest"], [3,2,1], [8,16,32]; FOLDER_PATH = joinpath(@__DIR__, "results"), shape = "@_TY_@_LC_@_RC_1_HP_@_MD_5_BS_1.txt")
println(a)
```

Note how important is to use println to remove double backslashes;
after having done this, you want to quickly remove all the noise, simulating all the other rows in the article.

Note that the formula above will return a dump of all the three rows combining [3,2,1] (length of antecedent of the contraint) and [8,16,32];
you probably want to launch three commands separatedly ([3,2,1], [8], then [3,2,1] with [16] and so on).
It is easier to read in that way.
"""
function make_experiment_table(
    args...;
    FOLDER_PATH::String=joinpath(@__DIR__, "results"),
    shape::String="@_@_@_@.txt",
    target::String="@",
)
    # fill_template2("@a@b.txt", [1,2,3], [4,5]) returns the following stream of strings:
    # "1a4b.txt", "1a5b.txt", "2a4b.txt", "2a5b.txt", "3a4b.txt", "3a5b.txt"
    function get_filestream(shape, args...; target::String="@")
        files = String[]

        for combo in Iterators.product(reverse(args)...)
            new_file = shape
            combo = reverse(string.(collect(combo)))

            for c in combo
                new_file = replace(new_file, target => c; count=1)
            end
            push!(files, new_file)
        end

        return files
    end

    # retrieve the average number of numcycles wrapped within the given file;
    # (numtrees = 8, maxdepth = 5, batchsize = 1, lcomplexity = 5, rcomplexity = 3, convtime = 21.0, numcycles = 231, lconstraintmode = :fulland)
    function average_cycles(filepath::String)
        _nsamples = 0

        _sumcycles = 0
        _cycles_collection = []

        _sumdelta = 0.0
        _delta_collection = []

        _sumtime = 0.0
        _times_collection = []

        open(filepath, "r") do f
            for line in readlines(f)
                try
                    parsed_tuple = eval(Meta.parse(line))
                    result = Result(parsed_tuple)

                    # if we are reading a file containing a -1
                    if result.numcycles == -1
                        continue
                    end

                    _numcycles = result.numcycles
                    _sumcycles += _numcycles
                    push!(_cycles_collection, _numcycles)

                    _currentdelta = result.metricpost - result.metricpre
                    _sumdelta += _currentdelta
                    push!(_delta_collection, _sumdelta)

                    _currenttottime = result.tottime
                    _sumtime += _currenttottime
                    push!(_times_collection, _currenttottime)

                    _nsamples += 1
                catch
                    # avoid parsing comments and other logs
                    continue
                end
            end
        end

        try
            _avg_sumcycles = Int(div(_sumcycles, _nsamples))
            _avg_delta = round(_sumdelta / _nsamples; digits=1)

            if _avg_delta == -0.0
                _avg_delta = 0.0
            end

            _avg_sumtime = Int(div(_sumtime, _nsamples))

            _std_sumcycles = abs(
                round(StatsBase.std(_cycles_collection); digits=1)
            )
            _std_delta = abs(round(StatsBase.std(_delta_collection); digits=1))
            _std_sumtime = abs(
                round(StatsBase.std(_times_collection); digits=1)
            )

            return "" *
                   '$' *
                   "{" *
                   string(_avg_sumcycles) *
                   "}{\\pm" *
                   string(_std_sumcycles) *
                   "}" *
                   '$' *
                   " & " *
                   '$' *
                   "{" *
                   string(_avg_delta) *
                   "}{\\pm" *
                   string(_std_delta) *
                   "}" *
                   '$' *
                   " & " *
                   '$' *
                   "{" *
                   string(_avg_sumtime) *
                   "}{\\pm" *
                   string(_std_sumtime) *
                   "}" *
                   '$'
        catch
            return "" *
                   '$' *
                   "{-}{-}" *
                   '$' *
                   " & " *
                   '$' *
                   "{-}{-}" *
                   '$' *
                   " & " *
                   '$' *
                   "{-}{-}" *
                   '$'
        end
    end

    # string encoding the LaTeX's table content
    table = ""

    filestream = get_filestream(shape, args...; target=target)
    filestream_length = length(filestream)
    cursor = 1 # iterator for the file we are currently processing

    # `id` decides whether we need to go newline in the table (e.g., it identifies a row)
    for id in args[1]
        table =
            table * " & {\\em $id (" * '$' * "$(args[4][1])" * '$' * " trees)} "

        currentfile = filestream[cursor]
        while !isnothing(findfirst(id, currentfile))
            experiment_filepath = joinpath(FOLDER_PATH, currentfile)

            table = table * " & $(average_cycles(experiment_filepath)) "

            cursor += 1
            if cursor > filestream_length
                break
            end
            currentfile = filestream[cursor]
        end

        # we need to consider a new row
        table *= " \\\\ \n \\cline{2-11} \n"
    end

    return table
end
