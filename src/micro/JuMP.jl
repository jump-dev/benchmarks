# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

function benchmark_jump_creating_model()
    model = Model()
    return
end

function benchmark_jump_creating_variable_array()
    model = Model()
    @variable(model, 0 <= x[i = 1:1_000] <= i, start = i)
    return
end

function benchmark_jump_creating_variable_dense_axis_array()
    model = Model()
    S = 1:1_000
    @variable(model, 0 <= x[i = S] <= i, start = i)
    return
end

function benchmark_jump_creating_variable_sparse_axis_array()
    model = Model()
    S = 1:1_000
    @variable(model, 0 <= x[i = S; isodd(i)] <= i, start = i)
    return
end

function benchmark_jump_creating_small_constraints()
    I, T = 100, 1_000
    model = Model()
    @variable(model, 0 <= x[1:I, 1:T] <= 100)
    @constraint(model, [i in 1:I, t in 2:T], x[i, t] - x[i, t-1] <= 10)
    @constraint(model, [i in 1:I, t in 2:T], x[i, t] - x[i, t-1] >= -10)
    @objective(model, Min, sum(x))
    return
end

