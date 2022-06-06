#!/bin/bash

# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

cd ~/Code/benchmarks

# Update the repository
git pull

# Update the repository activity
~/julia --project=. scripts/repositories.jl --update

# Save and re-upload
git add .
git commit -m "Repositories: automatic update"
git push
