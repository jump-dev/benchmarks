# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

using JuMP
import DelimitedFiles
import Ipopt

function main(filename, method)
    regularizing_value = 1.0
    file_samples_histo = joinpath(@__DIR__, "data", filename)
    samples_histo = DelimitedFiles.readdlm(file_samples_histo, ',', Float64)
    (num_conf, num_row) = size(samples_histo)
    num_spins = num_row - 1
    reconstruction = Array{Float64}(undef, num_spins, num_spins)
    num_samples = sum(samples_histo[:, 1])
    lambda = regularizing_value * sqrt(log((num_spins^2) / 0.05) / num_samples)
    RISEobjective(h) = exp(-h)
    RPLEobjective(h) = log(1 + exp(-2h))
    for current_spin in 1:num_spins
        println("Reconstructing the parameters adjacent to node ", current_spin)
        nodal_stat = [
            samples_histo[k, 1+current_spin] *
            (i == current_spin ? 1 : samples_histo[k, 1+i]) for
            k in 1:num_conf, i in 1:num_spins
        ]
        m = Model(Ipopt.Optimizer)
        set_optimizer_attribute(m, "tol", 1e-12)
        if endswith(method, "rise")
            JuMP.register(m, :IIPobjective, 1, RISEobjective; autodiff = true)
        else
            JuMP.register(m, :IIPobjective, 1, RPLEobjective; autodiff = true)
        end
        @variable(m, x[1:num_spins])
        @variable(m, z[1:num_spins])
        if startswith(method, "log")
            @NLobjective(
                m,
                Min,
                log(
                    sum(
                        (samples_histo[k, 1] / num_samples) * IIPobjective(
                            sum(x[i] * nodal_stat[k, i] for i in 1:num_spins),
                        ) for k in 1:num_conf
                    ),
                ) + lambda * sum(z[j] for j = 1:num_spins if current_spin != j)
            )
        else
            @NLobjective(
                m,
                Min,
                sum(
                    (samples_histo[k, 1] / num_samples) * IIPobjective(
                        sum(x[i] * nodal_stat[k, i] for i in 1:num_spins),
                    ) for k in 1:num_conf
                ) + lambda * sum(z[j] for j = 1:num_spins if current_spin != j)
            )
        end
        for j in 1:num_spins
            @constraint(m, z[j] >= x[j])
            @constraint(m, z[j] >= -x[j])
        end
        optimize!(m)
        spin_values = [value(x[i]) for i in 1:num_spins]
        println(current_spin, " = ", spin_values)
        for i in 1:num_spins
            reconstruction[current_spin, i] = spin_values[i]
        end
        nodal_stat = 0
        m = 0
        GC.gc()
        break
    end
    return
end

main("09_spins.csv", ARGS[1])
