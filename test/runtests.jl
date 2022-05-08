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

function test_latency_gurobi_facility()
    ret = Benchmarks._run_latency("gurobi_facility.jl", 2)
    Test.@test ret.exitcode == 0
    return
end

function test_latency_ipopt_jump_2788()
    ret = Benchmarks._run_latency("ipopt_jump_2788.jl", 20)
    Test.@test ret.exitcode == 0
    return
end

end  # module

TestBenchmarks.runtests()
