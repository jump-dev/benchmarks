# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

using JuMP
import HiGHS

function main()
    category_data = [
        1800.0 2200.0
        91.0 Inf
        0.0 65.0
        0.0 1779.0
    ]
    cost = [2.49, 2.89, 1.50, 1.89, 2.09, 1.99, 2.49, 0.89, 1.59]
    food_data = [
        410 24 26 730
        420 32 10 1190
        560 20 32 1800
        380 4 19 270
        320 12 10 930
        320 15 12 820
        320 31 12 1230
        100 8 2.5 125
        330 8 10 180
    ]
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    @variable(
        model,
        nutrition[i = 1:size(category_data, 1)],
        lower_bound = category_data[i, 1],
        upper_bound = category_data[i, 2],
    )
    @variable(model, buy[1:size(food_data, 1)] >= 0)
    @objective(model, Min, cost' * buy)
    @constraint(model, food_data' * buy .== nutrition)
    optimize!(model)
    @assert termination_status(model) == OPTIMAL
    @constraint(model, buy[end] + buy[end-1] <= 6.0)
    optimize!(model)
    @assert termination_status(model) == INFEASIBLE
    return
end

main()
