# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

module Benchmarks

using JuMP
import Ipopt

import BenchmarkTools
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
    results = BenchmarkTools.run(suite)
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

function _rebuild_data_json()
    data = Dict{String,Any}()
    for (root, _, _) in walkdir(DATA_DIR)
        if root == DATA_DIR
            continue
        end
        date = String(last(split(root, '/')))
        data[date] = JSON.parsefile(joinpath(root, "results.json"))
    end
    dates = sort(collect(keys(data)))
    output = Dict{String,Any}()
    for date in dates
        for (benchmark, result) in data[date]
            if !haskey(output, benchmark)
                output[benchmark] = Dict{String,Any}(
                    "dates" => String[],
                    "memory" => Int[],
                    "allocs" => Int[],
                    "gc_min" => Float64[],
                    "gc_median" => Float64[],
                    "time_min" => Float64[],
                    "time_median" => Float64[],
                )
            end
            y = output[benchmark]
            push!(y["dates"], date)
            for (key, value) in result
                push!(y[key], value)
            end
        end
    end
    open(joinpath(dirname(@__DIR__), "docs", "data.json"), "w") do io
        return write(io, JSON.json(output))
    end
    return dates, output
end

function _normalized_data(dates, data)
    output = Dict{String,Any}("dates" => dates)
    dates_to_index = Dict(d => i for (i, d) in enumerate(dates))
    # For now, only compute summary of the times
    fields =
        ("time_min", "time_median", "memory", "allocs", "gc_min", "gc_median")
    for key in fields
        output[key] = _normalized_data(dates_to_index, data, key)
    end
    open(joinpath(dirname(@__DIR__), "docs", "summary_data.json"), "w") do io
        return write(io, JSON.json(output))
    end
    return output
end

function _normalized_data(dates_to_index, data, key)
    outputs = [Float64[] for _ in 1:length(dates_to_index)]
    for (_, result) in data
        if any(iszero, result[key])
            continue  # skip normalizing for tests with 0 allocations, etc.
        end
        scale_factor = 100 / result[key][1]
        for (i, date) in enumerate(result["dates"])
            index = dates_to_index[date]
            new_value = scale_factor * result[key][i]
            push!(outputs[index], new_value)
        end
    end
    return [Statistics.mean(o) for o in outputs]
end

function publish()
    dates, data = _rebuild_data_json()
    _normalized_data(dates, data)
    return
end

end  # module
