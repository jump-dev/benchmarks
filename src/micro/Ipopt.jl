# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

function benchmark_ipopt_fractional_power()
    model = Model(Ipopt.Optimizer)
    set_silent(model)
    @variable(model, x <= 0)
    @variable(model, y >= 0)
    @variable(model, z >= 0)
    @objective(model, Max, -2 * x + y + z)
    @NLconstraint(model, z <= -sign(x) * (abs(x)^0.3) * y^0.7)
    @NLconstraint(model, x <= z^0.7 * y^0.3)
    @NLconstraint(model, x^2 + y^2 <= z + 1)
    optimize!(model)
    @assert termination_status(model) == LOCALLY_SOLVED
    @assert isapprox(objective_value(model), 4.0, atol = 0.1)
    return
end
