# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

###
### Initial package setup
###

import Pkg

function pkg_spec(arg)
    pkg, branch = split(arg, '#')
    return Pkg.PackageSpec(; name = pkg, rev = branch)
end

if get(ARGS, 1, "") == "--checkout"
    packages = ["JuMP", "Ipopt", "Gurobi"]
    if length(ARGS) == 1
        # Check out latest published versions of each package
        Pkg.free(packages)
    elseif ARGS[2] == "master"
        # Checkout latest commit of each package
        Pkg.add([pkg_spec("$p#master") for p in packages])
    else
        Pkg.add(pkg_spec.(ARGS[2:end]))
    end
    Pkg.update()
end

###
### Run stuff
###

include(joinpath(dirname(@__DIR__), "src", "Benchmarks.jl"))

import .Benchmarks
import Dates

has_arg(arg) = any(isequal(arg), ARGS)
if get(ARGS, 1, "") == "--historical"
    Benchmarks.run("$(ARGS[2])-00-00")
else
    if has_arg("--tune")
        Benchmarks.tune()
    end
    if has_arg("--run")
        Benchmarks.run(Dates.format(Dates.now(), "yyyy-mm-dd-HH-MM"))
    end
    if has_arg("--publish")
        Benchmarks.publish()
    end
end
