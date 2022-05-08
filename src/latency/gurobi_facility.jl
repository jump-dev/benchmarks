# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

using JuMP
import Gurobi

function main(N::Int)
    model = Model(Gurobi.Optimizer)
    G, F = N, N
    set_time_limit_sec(model, 0.0)
    set_optimizer_attribute(model, "Presolve", 0)
    @variables(model, begin
        0 <= y[1:F, 1:2] <= 1
        s[0:G, 0:G, 1:F] >= 0
        z[0:G, 0:G, 1:F], Bin
        r[0:G, 0:G, 1:F, 1:2]
        d
    end)
    @objective(model, Min, d)
    @constraint(model, [i in 0:G, j in 0:G], sum(z[i, j, f] for f in 1:F) == 1)
    M = 2 * sqrt(2)
    for i in 0:G, j in 0:G, f in 1:F
        @constraints(
            model,
            begin
                s[i, j, f] == d + M * (1 - z[i, j, f])
                r[i, j, f, 1] == i / G - y[f, 1]
                r[i, j, f, 2] == j / G - y[f, 2]
                sum(r[i, j, f, k]^2 for k in 1:2) <= s[i, j, f]^2
            end
        )
    end
    optimize!(model)
    return
end

main(parse(Int, ARGS[1]))
