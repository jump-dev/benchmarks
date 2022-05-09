#  Copyright 2017, Iain Dunning, Joey Huchette, Miles Lubin, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.

###
### Matrix benchmarks
###

function _matrix_affine_product(n::Int)
    model = Model()
    a = rand(n, n)
    @variable(model, x[1:n, 1:n])
    @expression(model, a * x)
    return
end

function _matrix_quadratic_product(n::Int)
    model = Model()
    a = rand(n, n)
    @variable(model, x[1:n, 1:n])
    @expression(model, a * x * a)
    return
end

let
    for s in (:affine, :quadratic), N in [10, 50]
        f = getfield(@__MODULE__, Symbol("_matrix_$(s)_product"))
        new_name = Symbol("benchmark_matrix_$(s)_product_$(lpad(N, 3, '0'))")
        @eval $(new_name)() = $f($N)
    end
end

###
### Vector benchmarks
###

function _vector_sum(n::Int)
    model = Model()
    c = rand(n)
    @variable(model, z[1:n])
    @constraint(model, sum(c[i] * z[i] for i in 1:n) <= 1)
    return
end

function _vector_dot(n::Int)
    model = Model()
    c = rand(n)
    @variable(model, z[1:n])
    @constraint(model, LinearAlgebra.dot(c, z) <= 1)
    return
end

function _matrix_sum(n::Int)
    model = Model()
    a = rand(n, n)
    @variable(model, x[1:n, 1:n])
    @constraint(model, sum(a[i, j] * x[i, j] for i in 1:n, j in 1:n) <= 1)
    return
end

function _matrix_dot(n::Int)
    model = Model()
    a = rand(n, n)
    @variable(model, x[1:n, 1:n])
    @constraint(model, LinearAlgebra.dot(a, x) <= 1)
    return
end

function _array_sum(n::Int)
    model = Model()
    b = rand(n, n, n)
    @variable(model, y[1:n, 1:n, 1:n])
    @constraint(
        model,
        sum(b[i, j, k] * y[i, j, k] for i in 1:n, j in 1:n, k in 1:n) <= 1,
    )
    return
end

function _array_dot(n::Int)
    model = Model()
    b = rand(n, n, n)
    @variable(model, y[1:n, 1:n, 1:n])
    @constraint(model, LinearAlgebra.dot(b, y) <= 1)
    return
end

let
    for s in (:vector, :matrix, :array), N in [10, 50]
        f = getfield(@__MODULE__, Symbol("_$(s)_sum"))
        new_name = Symbol("benchmark_$(s)_sum_$(lpad(N, 3, '0'))")
        @eval $(new_name)() = $f($N)
    end
end

###
### Macro
###

function _macro_linear(N::Int)
    m = Model()
    @variable(m, x[1:10N, 1:5N])
    @variable(m, y[1:N, 1:N, 1:N])
    for z in 1:10
        @constraint(
            m,
            9 * y[1, 1, 1] - 5 * y[N, N, N] -
            2 * sum(z * x[j, i*N] for j in ((z-1)*N+1):z*N, i in 3:4) +
            sum(i * (9 * x[i, j] + 3 * x[j, i]) for i in N:2N, j in N:2N) +
            x[1, 1] +
            x[10N, 5N] +
            x[2N, 1] +
            1 * y[1, 1, N] +
            2 * y[1, N, 1] +
            3 * y[N, 1, 1] +
            y[N, N, N] - 2 * y[N, N, N] + 3 * y[N, N, N] <=
            sum(
                sum(
                    sum(
                        N * i * j * k * y[i, j, k] + x[i, j] for
                        k = 1:N if i != j && j != k
                    ) for j in 1:N
                ) for i in 1:N
            ) + sum(
                sum(x[i, j] for j = 1:5N if j % i == 3) for
                i = 1:10N if i <= N * z
            )
        )
    end
    return
end

function _macro_quad(N::Int)
    m = Model()
    @variable(m, x[1:10N, 1:5N])
    @variable(m, y[1:N, 1:N, 1:N])
    for z in 1:10
        @constraint(
            m,
            9 * y[1, 1, 1] - 5 * y[N, N, N] -
            2 * sum(z * x[j, i*N] for j in ((z-1)*N+1):z*N, i in 3:4) +
            sum(i * (9 * x[i, j] + 3 * x[j, i]) for i in N:2N, j in N:2N) +
            x[1, 1] +
            x[10N, 5N] * x[2N, 1] +
            1 * y[1, 1, N] * 2 * y[1, N, 1] +
            3 * y[N, 1, 1] +
            y[N, N, N] - 2 * y[N, N, N] * 3 * y[N, N, N] <=
            sum(
                sum(
                    sum(
                        N * i * j * k * y[i, j, k] * x[i, j] for
                        k = 1:N if i != j && j != k
                    ) for j in 1:N
                ) for i in 1:N
            ) + sum(
                sum(x[i, j] for j = 1:5N if j % i == 3) for
                i = 1:10N if i <= N * z
            )
        )
    end
    return
end

let
    for s in (:linear, :quad), N in [10, 50]
        f = getfield(@__MODULE__, Symbol("_macro_$(s)"))
        new_name = Symbol("benchmark_macro_$(s)_$(lpad(N, 3, '0'))")
        @eval $(new_name)() = $f($N)
    end
end

###
### Printing
###

function benchmark_print_AffExpr()
    m = Model()
    N = 100
    @variable(m, x[1:N])
    c = @constraint(m, sum(i * x[i] for i in 1:N) >= N)
    sprint(print, c)
    return
end

function benchmark_print_model()
    m = Model()
    N = 100
    @variable(m, x[1:N])
    @constraint(m, sum(i * x[i] for i in 1:N) >= N)
    sprint(print, m)
    return
end

function benchmark_print_model_10000()
    m = Model()
    N = 10_000
    @variable(m, x[1:N])
    @constraint(m, sum(i * x[i] for i in 1:N) >= N)
    sprint(print, m)
    return
end

function benchmark_print_small_model()
    m = Model()
    N = 10
    @variable(m, x1[1:N])
    @variable(m, x2[1:N, f = 1:N])
    @variable(m, x3[1:N, f = 1:2:N])
    @variable(m, x4[[:a, :b, :c]])
    @variable(m, x5[[:a, :b, :c], [:d, "e", 4]])
    @constraint(
        m,
        sum(i * x1[i] for i in 1:N) +
        sum(i * f * x2[i, f] for i in 1:N, f in 1:N) +
        sum(i * f * x3[i, f] for i in 1:N, f in 1:2:N) +
        sum(x4) >= N
    )
    sprint(print, m)
    return
end

###
### Axis constraints
###

function _sum_iterate(con_refs)
    x = 0.0
    for con_ref in con_refs
        x += dual(con_ref)
    end
    return x
end

function _sum_index(con_refs)
    x = 0.0
    for i in eachindex(con_refs)
        x += dual(con_refs[i])
    end
    return x
end

function _dense_axis_constraints(key = :index)
    n = 1_000
    model = Model()
    mock = MOI.Utilities.MockOptimizer(
        MOI.Utilities.Model{Float64}(),
        eval_variable_constraint_dual = false,
    )
    MOI.Utilities.set_mock_optimize!(
        mock,
        mock -> MOI.Utilities.mock_optimize!(
            mock,
            zeros(n),
            (MOI.VariableIndex, MOI.EqualTo{Float64}) => ones(n - 1),
        ),
    )
    MOI.Utilities.reset_optimizer(model, mock)
    @variable(model, x[1:n])
    set = MOI.EqualTo(0.0)
    con_refs = @constraint(model, [i = 2:n], x[i] in set)
    optimize!(model)
    if key == :index
        _sum_index(con_refs)
    else
        _sum_iterate(con_refs)
    end
    return
end

function _sparse_axis_constraints(key = :index)
    n = 1_000
    model = Model()
    mock = MOI.Utilities.MockOptimizer(
        MOI.Utilities.Model{Float64}(),
        eval_variable_constraint_dual = false,
    )
    MOI.Utilities.set_mock_optimize!(
        mock,
        mock -> MOI.Utilities.mock_optimize!(
            mock,
            zeros(n),
            (MOI.VariableIndex, MOI.EqualTo{Float64}) => ones(div(n, 2)),
        ),
    )
    MOI.Utilities.reset_optimizer(model, mock)
    @variable(model, x[1:n])
    set = MOI.EqualTo(0.0)
    con_refs = @constraint(model, [i = 1:n; iseven(i)], x[i] in set)
    optimize!(model)
    if key == :index
        _sum_index(con_refs)
    else
        _sum_iterate(con_refs)
    end
    return
end

let
    for container in (:dense, :sparse), sum_type in (:iterate, :index)
        f = getfield(@__MODULE__, Symbol("_$(container)_axis_constraints"))
        new_name = Symbol("benchmark_$(container)_axis_constraints_$(sum_type)")
        @eval $(new_name)() = $f($(sum_type))
    end
end

###
### Model constructors
###

"""
    benchmark_p_median(
        num_facilities = 100,
        num_customers = 100,
        num_locations = 5_000,
    )

Implements the "p-median" facility location problem. We try to locate N
facilities such that we minimize the distance any given customer has to travel
to reach their closest facility. In this simple instance we will operate
in a 1D world with L possible locations for facilities, and customers being
located at random locations along the number line from 1 to D.
We use anonymous variables to remove the cost of name generation from the
benchmark.
"""
function benchmark_p_median(
    num_facilities = 100,
    num_customers = 100,
    num_locations = 5_000,
)
    Random.seed!(10)
    customer_locations = [rand(1:num_locations) for _ in 1:num_customers]
    model = Model()
    has_facility = @variable(model, [1:num_locations], Bin)
    is_closest = @variable(model, [1:num_locations, 1:num_customers], Bin)
    @objective(
        model,
        Min,
        sum(
            abs(customer_locations[customer] - location) *
            is_closest[location, customer] for customer in 1:num_customers,
            location in 1:num_locations
        )
    )
    for customer in 1:num_customers
        # `location` can't be closest for `customer` if there is no facility.
        @constraint(
            model,
            [location in 1:num_locations],
            is_closest[location, customer] <= has_facility[location]
        )
        # One facility must be the closest for `customer`.
        @constraint(
            model,
            sum(
                is_closest[location, customer] for location in 1:num_locations
            ) == 1
        )
    end
    # Must place all facilities.
    @constraint(model, sum(has_facility) == num_facilities)
    return
end
