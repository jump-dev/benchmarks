# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

module TestBenchmarks

include(joinpath(dirname(@__DIR__), "src", "Benchmarks.jl"))

import .Benchmarks
import Test

function runtests()
    for name in names(@__MODULE__; all = true)
        if startswith("$name", "test_")
            Test.@testset "$name" begin
                getfield(@__MODULE__, name)()
            end
        end
    end
    return
end

function test_microbenchmarks()
    for name in names(Benchmarks; all = true)
        if startswith("$name", "benchmark_")
            Test.@test getfield(Benchmarks, name)() === nothing
        end
    end
    return
end

function test_latency()
    for (file, arg) in [
        "gurobi_facility.jl" => 2,
        "gurobi_lqcp.jl" => 2,
        "ipopt_jump_2788.jl" => 20,
        "ipopt_clnlbeam.jl" => 1,
        "power_models_opf_acp.jl" => "pglib_opf_case5_pjm",
    ]
        ret = Benchmarks._run_latency(file, arg)
        Test.@test ret.exitcode == 0
    end
    return
end

end  # module

TestBenchmarks.runtests()
