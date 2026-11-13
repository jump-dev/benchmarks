#!/bin/bash

# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

# Run the benchmarks using the package versions that were registered before a
# given date (or dates).
#
# Usage:
#
#     scripts/run_historical.sh yyyy-mm-dd [yyyy-mm-dd ...]
#
# To keep the user's regular Julia depot untouched, this script uses a
# separate depot (default: ~/.julia-benchmarks), containing a git clone of the
# General registry. For each date, the registry is checked out at the last
# commit before that date, Manifest.toml is deleted, and the project is
# re-resolved so that every package is at the newest version available at the
# time. Pkg does not update a registry with a detached HEAD, so it stays at
# that commit for the duration of the run.
#
# Environment variables:
#
#   JULIA_CMD        Julia binary to use. Defaults to the juliaup 1.10 install.
#                    The same binary is used by the latency benchmarks.
#   BENCHMARK_DEPOT  Depot directory. Defaults to ~/.julia-benchmarks.
#
# Output for each date is written to data/<yyyy-mm-dd>-00-00, and a log to
# logs/<yyyy-mm-dd>-00-00.log. If data/<yyyy-mm-dd>-00-00 already exists, the
# existing directory is moved to data_replaced/ rather than deleted.
#
# A failure for one date does not stop the remaining dates from running.

set -u

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 yyyy-mm-dd [yyyy-mm-dd ...]"
    exit 1
fi

REPO=$(cd "$(dirname "$0")/.." && pwd)
DEPOT="${BENCHMARK_DEPOT:-$HOME/.julia-benchmarks}"
REGISTRY="$DEPOT/registries/General"
JULIA_110="$HOME/.julia/juliaup/julia-1.10.12+0.aarch64.apple.darwin14/Julia-1.10.app/Contents/Resources/julia/bin/julia"

export JULIA_CMD="${JULIA_CMD:-$JULIA_110}"
export JULIA_DEPOT_PATH="$DEPOT"
export JULIA_NUM_THREADS=1

mkdir -p "$REPO/logs" "$DEPOT/registries"

if [ ! -d "$REGISTRY/.git" ]; then
    echo "Cloning General registry into $REGISTRY"
    git clone https://github.com/JuliaRegistries/General.git "$REGISTRY"
fi

# Bring the registry up to date once, at the start. Network failures are not
# fatal: we just use whatever history is already there.
(cd "$REGISTRY" && git checkout --quiet master && git pull --quiet --ff-only) \
    || echo "WARNING: could not update the General registry; using local copy"

run_historical () {
    local date="$1"
    local run_name="${date}-00-00"
    local log="$REPO/logs/${run_name}.log"
    local sha
    sha=$(cd "$REGISTRY" && git rev-list -n 1 --first-parent --before="${date} 00:00" master)
    if [ -z "$sha" ]; then
        echo "ERROR: no registry commit before $date"
        return 1
    fi
    (cd "$REGISTRY" && git checkout --quiet "$sha") || return 1
    if [ -d "$REPO/data/$run_name" ]; then
        mkdir -p "$REPO/data_replaced"
        local backup="$REPO/data_replaced/${run_name}-replaced-$(date +%Y%m%d%H%M%S)"
        echo "data/$run_name already exists; moving it to $backup"
        mv "$REPO/data/$run_name" "$backup"
    fi
    {
        echo "Registry commit: $sha"
        echo "Julia: $JULIA_CMD"
        echo "Depot: $DEPOT"
        rm -f "$REPO/Manifest.toml"
        # A build failure (for example, an old Gurobi.jl that cannot find a
        # local Gurobi install) should not prevent the other benchmarks from
        # running, so errors in these steps are logged but not fatal.
        "$JULIA_CMD" --project="$REPO" -e '
            import Pkg
            try
                Pkg.instantiate()
            catch err
                @error "Pkg.instantiate() failed" err
            end
            try
                Pkg.precompile()
            catch err
                @error "Pkg.precompile() failed" err
            end
            Pkg.status()' \
            && "$JULIA_CMD" --project="$REPO" "$REPO/scripts/benchmarks.jl" --historical "$date" \
            && "$JULIA_CMD" --project="$REPO" "$REPO/scripts/benchmarks.jl" --publish
    } > "$log" 2>&1
    local status=$?
    (cd "$REGISTRY" && git checkout --quiet master)
    return $status
}

for date in "$@"; do
    if [[ ! "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "Invalid date '$date': expected yyyy-mm-dd"
        continue
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S')  START  $date"
    if run_historical "$date"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S')  OK     $date"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S')  FAILED $date (see logs/${date}-00-00.log)"
    fi
done
