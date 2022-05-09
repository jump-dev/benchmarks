#!/bin/bash

# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

# Before running, you first need to convert the General registry to a Git
# repository, instead of reading from the .tar.gz.

run_historical () {
    cd ~/.julia/registries/General
    git checkout master
    git pull
    git_sha=$(git rev-list -n 1 --first-parent --before="${1} 00:00" master)
    git checkout $git_sha
    cd ~/Code/benchmarks
    ~/julia --project=. -e 'import Pkg; Pkg.update()'
    ~/julia --project=. scripts/benchmarks.jl --historical ${1}
    cd ~/.julia/registries/General
    git checkout master
}

run_historical "${1}"
