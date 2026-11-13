# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

module Benchmarks

using JuMP
import Ipopt

import BenchmarkTools
import Dates
import InteractiveUtils
import JSON
import LinearAlgebra
import Pkg
import Random
import Statistics

const DATA_DIR = joinpath(dirname(@__DIR__), "data")

for file in readdir(joinpath(@__DIR__, "micro"))
    if endswith(file, ".jl")
        include(joinpath(@__DIR__, "micro", file))
    end
end

const LATENCY_EXAMPLES = [
    # gurobi_facility
    "gurobi_facility.jl" => 25,
    "gurobi_facility.jl" => 50,
    "gurobi_facility.jl" => 75,
    "gurobi_facility.jl" => 100,
    # gurobi_lqcp
    "gurobi_lqcp.jl" => 500,
    "gurobi_lqcp.jl" => 1000,
    "gurobi_lqcp.jl" => 1500,
    "gurobi_lqcp.jl" => 2000,
    # highs_diet
    "highs_diet.jl" => nothing,
    # ipopt_jump_2788
    "ipopt_jump_2788.jl" => 200,
    "ipopt_jump_2788.jl" => 400,
    "ipopt_jump_2788.jl" => 800,
    # ipopt_clnlbeam
    "ipopt_clnlbeam.jl" => 5,
    "ipopt_clnlbeam.jl" => 50,
    "ipopt_clnlbeam.jl" => 500,
    # power_models
    "power_models_opf_acp.jl" => "pglib_opf_case5_pjm",
    "power_models_opf_acr.jl" => "pglib_opf_case5_pjm",
    # inverse ising
    "inverse_ising_expr.jl" => "rise",
    "inverse_ising_expr.jl" => "logrise",
    "inverse_ising_expr.jl" => "rple",
    "inverse_ising_register.jl" => "rise",
    "inverse_ising_register.jl" => "logrise",
    "inverse_ising_register.jl" => "rple",
]

function _run_latency(filename, arg)
    julia_cmd = get(ENV, "JULIA_CMD", joinpath(ENV["HOME"], "julia"))
    project = dirname(@__DIR__)
    file = joinpath(@__DIR__, "latency", filename)
    if arg === nothing
        return Base.run(`$julia_cmd --project=$project $file`)
    end
    return Base.run(`$julia_cmd --project=$project $file $arg`)
end

function _benchmark_suite()
    suite = BenchmarkTools.BenchmarkGroup()
    for name in names(@__MODULE__; all = true)
        if startswith("$name", "benchmark_")
            f = getfield(@__MODULE__, name)
            suite[string(name)] = BenchmarkTools.@benchmarkable $f()
        end
    end
    for (file, arg) in LATENCY_EXAMPLES
        suite["$file $arg"] =
            BenchmarkTools.@benchmarkable _run_latency($file, $arg)
    end
    return suite
end

###
### run
###

function run(run_name)
    directory = joinpath(DATA_DIR, run_name)
    mkdir(directory)
    _write_pkg_data(directory)
    _run_benchmarks(directory)
    return
end

function _generate_report(t::BenchmarkTools.Trial)
    return Dict(
        "memory" => t.memory,
        "allocs" => t.allocs,
        "time_min" => minimum(t.times),
        "time_median" => Statistics.median(t.times),
        "gc_min" => minimum(t.gctimes),
        "gc_median" => Statistics.median(t.gctimes),
    )
end

function _generate_report(results::BenchmarkTools.BenchmarkGroup)
    return Dict(name => _generate_report(trial) for (name, trial) in results)
end

function _write_pkg_data(directory)
    open(joinpath(directory, "versioninfo"), "w") do io
        return InteractiveUtils.versioninfo(io)
    end
    open(joinpath(directory, "Manifest"), "w") do io
        return Pkg.status(; mode = Pkg.PKGMODE_MANIFEST, io = io)
    end
    return
end

function _run_benchmarks(directory)
    suite = _benchmark_suite()
    param_filename = joinpath(DATA_DIR, "benchmark_params.json")
    params = BenchmarkTools.load(param_filename)[1]
    BenchmarkTools.loadparams!(suite, params, :evals, :samples)
    # Run each benchmark separately so that one failure (for example, a
    # benchmark that uses an API that did not exist in a historical version of
    # JuMP) does not prevent the other results from being recorded.
    results = BenchmarkTools.BenchmarkGroup()
    for name in sort!(collect(keys(suite)))
        @info "Running benchmark: $name"
        try
            results[name] = BenchmarkTools.run(suite[name])
        catch err
            @warn "Benchmark failed: $name" err
        end
    end
    # We could use BenchmarkTools.save(filename, results), but this generates
    # quite large files. Create a smaller report for simplicity.
    report = _generate_report(results)
    open(joinpath(directory, "results.json"), "w") do io
        return write(io, JSON.json(report))
    end
    return
end

###
### tune
###

function tune()
    suite = _benchmark_suite()
    BenchmarkTools.tune!(suite)
    BenchmarkTools.save(
        joinpath(DATA_DIR, "benchmark_params.json"),
        BenchmarkTools.params(suite),
    )
    return
end

###
### publish
###
###
### The site in docs/ is static and reads three kinds of file, all written by
### publish() from the raw results in data/:
###
###   docs/data/index.json            every run with its date, Julia version,
###                                   key package versions and benchmark count
###   docs/data/runs/<run>.json       one run: versioninfo, every package
###                                   version in its Manifest, and its results
###   docs/data/benchmarks.json       one entry per benchmark with the values
###                                   of each metric across the runs
###

const DOCS_DATA_DIR = joinpath(dirname(@__DIR__), "docs", "data")

# The packages whose versions are listed in index.json, and so on the Runs
# page. The rest are in each run's own file.
const KEY_PACKAGES = [
    "JuMP",
    "MathOptInterface",
    "Ipopt",
    "HiGHS",
    "Gurobi",
    "PowerModels",
    "BenchmarkTools",
]

# The `Manifest` file of a run is the output of `Pkg.status(; mode =
# PKGMODE_MANIFEST)`, one package per line:
#     [6e4b80f9] BenchmarkTools v1.8.0
# possibly preceded by a status marker (⌃, ⌅, …) and followed by a git source:
#     [4076af6c] JuMP v1.25.0 `https://github.com/jump-dev/JuMP.jl.git#master`
function _parse_manifest(filename)
    packages = Dict{String,String}()
    isfile(filename) || return packages
    for line in eachline(filename)
        m = match(r"\[([0-9a-f]{8})\]\s+(\S+)\s+(.*)$", line)
        m === nothing && continue
        packages[m[2]] = String(strip(m[3]))
    end
    return packages
end

function _julia_version(filename)
    isfile(filename) || return ""
    for line in eachline(filename)
        m = match(r"^Julia Version (\S+)", line)
        m === nothing || return String(m[1])
    end
    return ""
end

# Where a benchmark is defined, relative to the repository root, for the link on
# its page. Micro-benchmarks are functions in src/micro; latency benchmarks are
# the scripts in src/latency, named "<file> <argument>".
function _benchmark_source(name)
    if startswith(name, "benchmark_")
        dir = joinpath(dirname(@__DIR__), "src", "micro")
        files = filter(f -> endswith(f, ".jl"), readdir(dir))
        sources = Dict(f => read(joinpath(dir, f), String) for f in files)
        for file in files
            if occursin("function $name(", sources[file])
                return "micro", "src/micro/$file"
            end
        end
        # Some benchmarks are generated with @eval from a name like
        # "benchmark_matrix_$(s)_product_$(N)", so look for the file that
        # contains the longest prefix of the name.
        for n in length(name):-1:(length("benchmark_") + 4)
            for file in files
                if occursin(name[1:n], sources[file])
                    return "micro", "src/micro/$file"
                end
            end
        end
        return "micro", "src/micro"
    end
    file = first(split(name, ' '))
    return "latency", "src/latency/$file"
end

# A run directory is "yyyy-mm-dd-HH-MM".
_run_date(run) = replace(run, r"^(\d{4}-\d{2}-\d{2})-(\d{2})-(\d{2})$" => s"\1T\2:\3")

function _read_runs()
    runs = Any[]
    for run in sort!(readdir(DATA_DIR))
        root = joinpath(DATA_DIR, run)
        isdir(root) || continue
        filename = joinpath(root, "results.json")
        if !isfile(filename)
            @warn("Skipping $run: no results.json (failed run?)")
            continue
        end
        push!(
            runs,
            Dict{String,Any}(
                "id" => run,
                "date" => _run_date(run),
                "julia" => _julia_version(joinpath(root, "versioninfo")),
                "versioninfo" =>
                    isfile(joinpath(root, "versioninfo")) ?
                    read(joinpath(root, "versioninfo"), String) : "",
                "packages" => _parse_manifest(joinpath(root, "Manifest")),
                "results" => JSON.parsefile(filename),
            ),
        )
    end
    return runs
end

const METRIC_KEYS =
    ("memory", "allocs", "gc_min", "gc_median", "time_min", "time_median")

function _write_json(filename, data)
    mkpath(dirname(filename))
    open(filename, "w") do io
        return write(io, JSON.json(data))
    end
    return
end

function publish()
    runs = _read_runs()
    # docs/data/runs/<run>.json, removing the files of runs that no longer
    # exist in data/.
    rm(joinpath(DOCS_DATA_DIR, "runs"); force = true, recursive = true)
    for run in runs
        _write_json(joinpath(DOCS_DATA_DIR, "runs", "$(run["id"]).json"), run)
    end
    # docs/data/index.json
    index = Dict{String,Any}(
        "generated" => Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SSZ"),
        "runs" => [
            Dict{String,Any}(
                "id" => run["id"],
                "date" => run["date"],
                "julia" => run["julia"],
                "n_benchmarks" => length(run["results"]),
                "packages" => Dict(
                    k => run["packages"][k] for
                    k in KEY_PACKAGES if haskey(run["packages"], k)
                ),
            ) for run in runs
        ],
    )
    _write_json(joinpath(DOCS_DATA_DIR, "index.json"), index)
    # docs/data/benchmarks.json
    benchmarks = Dict{String,Any}()
    for run in runs, (name, result) in run["results"]
        if !haskey(benchmarks, name)
            group, source = _benchmark_source(name)
            benchmarks[name] = Dict{String,Any}(
                "group" => group,
                "source" => source,
                "runs" => String[],
                (k => Any[] for k in METRIC_KEYS)...,
            )
        end
        b = benchmarks[name]
        push!(b["runs"], run["id"])
        for k in METRIC_KEYS
            push!(b[k], get(result, k, nothing))
        end
    end
    _write_json(joinpath(DOCS_DATA_DIR, "benchmarks.json"), benchmarks)
    return
end

end  # module
