#!/bin/bash

# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

# Update the repository
git pull

# Run the new benchmarks
~/julia --project=. -e 'import Pkg; Pkg.update()'
~/julia --project=. scripts/benchmarks.jl --run
~/julia --project=. scripts/benchmarks.jl --publish

# Save and re-upload
git add .
git commit -m "Automatic update"
git push
