# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

import Ipopt
import JuMP
import PowerModels

function main(case::String)
    data = PowerModels.parse_file(joinpath(@__DIR__, "data", case * ".m"))
    solver = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6)
    result = PowerModels.run_opf(data, PowerModels.ACRPowerModel, solver)
    println()
    println(result["termination_status"])
    println(result["primal_status"])
    println(result["solve_time"])
    return
end

main(ARGS[1])
