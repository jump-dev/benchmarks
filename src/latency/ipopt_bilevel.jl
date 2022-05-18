# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

using JuMP
import Ipopt

function f(x...)
    model = Model(Ipopt.Optimizer)
    set_silent(model)
    @variable(model, y[1:2])
    @NLobjective(
        model,
        Max,
        y[1] * x[1] + y[2] * x[2] - x[1] * y[1]^4 - 2 * x[2] * y[2]^4,
    )
    @constraint(model, (y[1] - 10)^2 + (y[2] - 10)^2 <= 25)
    optimize!(model)
    return objective_value(model)
end

function ∇f(g, x...)
    model = Model(Ipopt.Optimizer)
    set_silent(model)
    @variable(model, y[1:2])
    @NLobjective(
        model,
        Max,
        y[1] * x[1] + y[2] * x[2] - x[1] * y[1]^4 - 2 * x[2] * y[2]^4,
    )
    @constraint(model, (y[1] - 10)^2 + (y[2] - 10)^2 <= 25)
    optimize!(model)
    g[1] = value(y[1]) - value(y[1])^4
    g[2] = value(y[2]) - 2 * value(y[2])^4
    return
end

"""
    main()

Solves the bilevel optimization problem:
```
min  z + x_1^2 + x_2^2
s.t.
     z >= max  y_1 * x_1 + y_2 * x_2 - x_1 * y_1^4 - 2 * x_2 * y_2^4
          s.t. (y_1 - 10)^2 + (y_2 - 10)^2 <= 25
```
"""
function main()
    model = Model(Ipopt.Optimizer)
    set_optimizer_attribute(model, "hessian_approximation", "limited-memory")
    set_optimizer_attribute(model, "tol", 1e-5)
    @variable(model, x[1:2] >= 0)
    register(model, :f, 2, f, ∇f)
    @NLobjective(model, Min, f(x[1], x[2]) + x[1]^2 + x[2]^2)
    optimize!(model)
    @assert termination_status(model) == LOCALLY_SOLVED
    @assert isapprox(objective_value(model), -3.1; atol = 0.1)
    return
end

main()
