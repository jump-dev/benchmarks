# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

include(joinpath(dirname(@__DIR__), "src", "Benchmarks.jl"))
import .Benchmarks
import Dates

if get(ARGS, 1, "") == "--run"
    date = Dates.format(Dates.now(), "yyyy-mm-dd-HH-MM")
    Benchmarks.run(date)
elseif get(ARGS, 1, "") == "--tune"
    Benchmarks.tune()
elseif get(ARGS, 1, "") == "--publish"
    Benchmarks.publish()
end
