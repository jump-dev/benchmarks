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
