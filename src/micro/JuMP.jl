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

"""
    benchmark_value_nonlinear_expression()

This benchmark deals with a large number of nested subexpressisons, some of
which are un-used.

Relevant JuMP issues and PRs:
 * https://github.com/jump-dev/JuMP.jl/issues/746
 * https://github.com/jump-dev/JuMP.jl/pull/2515
"""
function benchmark_value_nonlinear_expression()
    n = 500
    model = Model(Ipopt.Optimizer)
    γ, ρ, r, μR, ζ = 2, 0.05, 0.041, 0.051, 1.5
    σR = sqrt((ζ / γ + 1) / 2 * (μR - r)^2 / (ρ - r))
    amin, amax = -0.3, 1e4
    x = map(x -> x + 5 * x^10, range(0, stop = 1, length = n))
    a = (amax - amin) / (maximum(x) - minimum(x)) * x .+ amin
    z, λ = 3.0 * [0.01, 0.03], [0.5, 0.5]
    @variable(
        model,
        V[i = 1:n, j = 1:2],
        start = (z[j] + r * a[i])^(1 - γ) / (1 - γ) / ρ
    )
    @NLexpression(model, Vpb1[j = 1:2], (z[j] + a[1] * r)^(-γ))
    @NLexpression(
        model,
        Vpbo[i = 2:n, j = 1:2],
        (V[i, j] - V[i-1, j]) / (a[i] - a[i-1])
    )
    @NLexpression(
        model,
        Vpb[i = 1:n, j = 1:2],
        (i == 1) * Vpb1[j] + (i > 1) * Vpbo[max(i, 2), j]
    )
    @NLexpression(
        model,
        Vpfo[i = 1:(n-1), j = 1:2],
        (V[i+1, j] - V[i, j]) / (a[i+1] - a[i])
    )
    @NLexpression(
        model,
        Vpfn[j = 1:2],
        (z[j] + a[n] * r + (μR - r)^2 / (γ * σR^2) * a[n])^(-γ)
    )
    @NLexpression(
        model,
        Vpf[i = 1:n, j = 1:2],
        (i == n) * Vpfn[j] + (i < n) * Vpfo[min(i, n - 1), j]
    )
    @NLexpression(
        model,
        Vp[i = 1:n, j = 1:2, s = 1:2],
        (s == 1) * Vpb[i, j] + (s == 2) * Vpf[i, j]
    )
    @NLexpression(model, Vpp1[j = 1:2], 0.0)
    @NLexpression(model, Vppn[j = 1:2], -γ * Vp[n, j, 1] / a[n])
    @NLexpression(
        model,
        Vppo[i = 2:(n-1), j = 1:2],
        (
            (a[i] - a[i-1]) * V[i+1, j] + (a[i+1] - a[i]) * V[i-1, j] -
            (a[i+1] - a[i-1]) * V[i, j]
        ) / (0.5 * (a[i+1] - a[i-1]) * (a[i+1] - a[i]) * (a[i] - a[i-1]))
    )
    @NLexpression(
        model,
        Vpp[i = 1:n, j = 1:2],
        (i == 1) * Vpp1[j] +
        (i == n) * Vppn[j] +
        (i > 1) * (i < n) * Vppo[min(max(i, 2), n - 1), j]
    )
    @NLexpression(
        model,
        c[i = 1:n, j = 1:2, s = 1:2],
        abs(Vp[i, j, s])^(-1 / γ)
    )
    @NLexpression(model, k1[j = 1:2, s = 1:2], 0.0)
    @NLexpression(
        model,
        ko[i = 2:n, j = 1:2, s = 1:2],
        (-Vp[i, j, s] / Vpp[i, j]) * (μR - r) / σR^2
    )
    @NLexpression(
        model,
        kk[i = 1:n, j = 1:2, s = 1:2],
        (i == 1) * k1[j, s] + (i > 1) * ko[max(i, 2), j, s]
    )
    @NLexpression(
        model,
        k[i = 1:n, j = 1:2, s = 1:2],
        (kk[i, j, s] <= (a[i] - a[1])) * (kk[i, j, s] >= 0) * kk[i, j, s] +
        (kk[i, j, s] >= (a[i] - a[1])) * (a[i] - a[1])
    )
    @NLexpression(
        model,
        savings[i = 1:n, j = 1:2, s = 1:2],
        (z[j] + r * a[i] + (μR - r) * k[i, j, s] - c[i, j, s])
    )
    @NLexpression(
        model,
        UVp[i = 1:n, j = 1:2],
        (savings[i, j, 1] <= 0) * Vp[i, j, 1] +
        (savings[i, j, 1] > 0) * (savings[i, j, 2] >= 0) * Vp[i, j, 2]
    )
    @NLexpression(
        model,
        Uk[i = 1:n, j = 1:2],
        (savings[i, j, 1] <= 0) * k[i, j, 1] +
        (savings[i, j, 1] > 0) * (savings[i, j, 2] >= 0) * k[i, j, 2] +
        (savings[i, j, 1] > 0) *
        (savings[i, j, 2] < 0) *
        (k[i, j, 1] + k[i, j, 2]) / 2
    )
    @NLexpression(
        model,
        Uc[i = 1:n, j = 1:2],
        (savings[i, j, 1] <= 0) * c[i, j, 1] +
        (savings[i, j, 1] > 0) * (savings[i, j, 2] >= 0) * c[i, j, 2] +
        (savings[i, j, 1] > 0) *
        (savings[i, j, 2] < 0) *
        (z[j] + r * a[i] + (μR - r) * Uk[i, j])
    )
    @NLexpression(
        model,
        HJB[i = 1:n, j = 1:2],
        Uc[i, j]^(1 - γ) / (1 - γ) +
        UVp[i, j] * (z[j] + r * a[i] + (μR - r) * Uk[i, j] - Uc[i, j]) +
        Vpp[i, j] * 0.5 * Uk[i, j]^2 * σR^2 +
        λ[j] * (V[i, (j==1)*2+(j==2)*1] - V[i, j])
    )
    @NLconstraint(model, [i = 1:n, j = 1:2], ρ * V[i, j] == HJB[i, j])
    optimize!(model)
    value.(c)
    return
end

function benchmark_nlexpr_micro_sum()
    model = Model()
    @variable(model, x)
    @objective(model, Min, sum(x^i for i in 1:10_000))
    return
end

function benchmark_nlexpr_micro_prod()
    model = Model()
    @variable(model, x)
    @objective(model, Min, prod(x^i for i in 1:10_000))
    return
end

function benchmark_nlexpr_micro_many_constraints()
    model = Model()
    @variable(model, x[1:10_000])
    @constraint(model, [i = 1:10_000], sin(x[i]) <= cos(i))
    return
end

function benchmark_nlexpr_micro_value_expr_many_small()
    model = Model()
    @variable(model, x)
    @expression(model, expr[i = 1:10_000], x^i)
    value.(x -> 2.0, expr)
    return
end

function benchmark_nlexpr_micro_value_expr_few_large()
    model = Model()
    @variable(model, x)
    @expression(model, expr, sum(x^i for i in 1:10_000))
    value(x -> 2.0, expr)
    return
end

function benchmark_nlexpr_model_mle()
    Random.seed!(1234)
    n = 1_000
    data = randn(n)
    model = Model(Ipopt.Optimizer)
    set_silent(model)
    @variable(model, μ, start = 0.0)
    @variable(model, σ >= 0.0, start = 1.0)
    @objective(
        model,
        Max,
        n / 2 * log(1 / (2 * π * σ^2)) -
        sum((data[i] - μ)^2 for i in 1:n) / (2 * σ^2)
    )
    optimize!(model)
    return
end

function benchmark_nlexpr_model_clnlbeam()
    N = 1000
    h = 1 / N
    alpha = 350
    model = Model(Ipopt.Optimizer)
    set_silent(model)
    @variables(model, begin
        -1 <= t[1:(N+1)] <= 1
        -0.05 <= x[1:(N+1)] <= 0.05
        u[1:(N+1)]
    end)
    @objective(
        model,
        Min,
        sum(
            0.5 * h * (u[i+1]^2 + u[i]^2) +
            0.5 * alpha * h * (cos(t[i+1]) + cos(t[i])) for i in 1:N
        ),
    )
    @constraint(
        model,
        [i = 1:N],
        x[i+1] - x[i] - 0.5 * h * (sin(t[i+1]) + sin(t[i])) == 0,
    )
    @constraint(
        model,
        [i = 1:N],
        t[i+1] - t[i] - 0.5 * h * u[i+1] - 0.5 * h * u[i] == 0,
    )
    optimize!(model)
    return
end

function benchmark_nlexpr_model_rosenbrock()
    model = Model(Ipopt.Optimizer)
    set_silent(model)
    @variable(model, x)
    @variable(model, y)
    @objective(model, Min, (1 - x)^2 + 100 * (y - x^2)^2)
    optimize!(model)
    return
end

function benchmark_nlexpr_model_jump_2788()
    N = 400
    Random.seed!(1234)
    k = N
    n = 12
    p = rand(400:700, k, 1)
    c1 = rand(100:200, k, n)
    c2 = 0.9 .* c1
    b = rand(150:250, k, 1)
    model = Model(Ipopt.Optimizer)
    set_silent(model)
    @variable(model, 0 <= x[i = 1:n] <= 1)
    @variable(model, 0 <= var1 <= 1)
    @variable(model, 0 <= var2 <= 1)
    @variable(model, 0 <= var3 <= 1)
    @objective(model, Max, var1 - var2 + var3)
    @expression(model, expr, sum(x[i] * p[i] for i in 1:n))
    @expression(model, expr_c1[j = 1:k], sum(x[i] * c1[j, i] for i in 1:n))
    @expression(model, expr_c2[j = 1:k], sum(x[i] * c2[j, i] for i in 1:n))
    @constraint(model, expr == sum(b[j] / (1 + var1)^j for j in 1:k))
    @constraint(model, expr == sum(expr_c1[j] / (1 + var2)^j for j in 1:k),)
    @constraint(model, expr == sum(expr_c2[j] / (1 + var3)^j for j in 1:k),)
    @constraint(model, [j = 1:k], expr_c1[j] >= b[j])
    optimize!(model)
    return
end

function benchmark_nlexpr_model_nested_problems()
    function solve_lower_level(x...)
        model = Model(Ipopt.Optimizer)
        set_silent(model)
        @variable(model, y[1:2])
        @objective(
            model,
            Max,
            x[1]^2 * y[1] + x[2]^2 * y[2] - x[1] * y[1]^4 - 2 * x[2] * y[2]^4,
        )
        @constraint(model, (y[1] - 10)^2 + (y[2] - 10)^2 <= 25)
        optimize!(model)
        @assert termination_status(model) == LOCALLY_SOLVED
        return objective_value(model), value.(y)
    end
    function V(x...)
        f, _ = solve_lower_level(x...)
        return f
    end
    function ∇V(g::AbstractVector, x...)
        _, y = solve_lower_level(x...)
        g[1] = 2 * x[1] * y[1] - y[1]^4
        g[2] = 2 * x[2] * y[2] - 2 * y[2]^4
        return
    end
    function ∇²V(H::AbstractMatrix, x...)
        _, y = solve_lower_level(x...)
        H[1, 1] = 2 * y[1]
        H[2, 2] = 2 * y[2]
        return
    end
    model = Model(Ipopt.Optimizer)
    set_silent(model)
    @variable(model, x[1:2] >= 0)
    @operator(model, f_V, 2, V, ∇V, ∇²V)
    @objective(model, Min, x[1]^2 + x[2]^2 + f_V(x[1], x[2]))
    optimize!(model)
    solution_summary(model)
    return
end

function benchmark_nlexpr_model_votroto()
    Q = -0.8:0.4:0.8
    model = Model(Ipopt.Optimizer)
    set_silent(model)
    @variable(model, -2 <= p[1:5] <= 2)
    @variable(model, -1 <= w <= 3)
    @variable(model, -1 <= q <= 3)
    @objective(model, Min, w)
    f(p, q) = (1 / sqrt(2π)) * exp(-((p - q)^2) / 2)
    total(p, q) = sum(_p * f(i, q) for (i, _p) in enumerate(p))
    l1(p, q) = 1 - total(p, q) + 0.5 * total(p, 0.5)
    l2(p, q) = total(p, q) - 1
    lhs(p, q, _q) = l1(p, q) - l1(p, _q)
    @constraint(model, [_q in Q], w * lhs(p, q, _q) + (1 - w) * l2(p, q) <= 0)
    optimize!(model)
    return
end

function benchmark_nlexpr_model_large_expressions()
    N = 50_000
    model = Model(Ipopt.Optimizer)
    set_silent(model)
    set_attribute(model, "max_iter", 1)
    @variable(model, y[1:N], start = 1)
    @variable(model, z[1:N])
    @objective(model, Max, sum(2z[i]^2 + sin(1 / y[i]) for i in 1:N))
    @constraint(
        model,
        [i = 1:N],
        ifelse(z[i] <= y[i]^3, log(y[i] / i), z[i] / cos(y[i])) <= 42,
    )
    @constraint(model, sum(z[i]^i + log(y[i]) for i in 1:N) == 0)
    optimize!(model)
    return
end

function benchmark_nlexpr_model_large_expressions_2()
    N = 100
    model = Model(Ipopt.Optimizer)
    set_silent(model)
    set_attribute(model, "max_iter", 1)
    @variable(model, y[1:N], start = 1)
    @variable(model, z[1:N])
    @objective(model, Max, sum(2z[i]^2 + sin(1 / y[i]) for i in 1:N))
    @constraint(
        model,
        prod(
            ifelse(z[i] <= y[i]^3, log(y[i] / i), z[i] / cos(y[i])) for i in 1:N
        ) <= 42
    )
    @constraint(model, sum(z[i]^i + log(y[i]) for i in 1:N) == 0)
    optimize!(model)
    return
end
