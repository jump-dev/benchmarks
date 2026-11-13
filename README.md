# JuMP benchmarks

This repository contains benchmarks for JuMP-dev.

Visualizations are available at [jump.dev/benchmarks](https://jump.dev/benchmarks).

## Adding new benchmarks

This repository is open for contributions! There are two types of benchmarks we
track:

 * `/src/latency` contains end-to-end scripts. We run these from the command
   line, so they include compilation latency. Add new benchmarks here that
   matter to end-users.
 * `/src/micro` contains a collection of micro-benchmarks, organized by package.
   Each benchmark is a function beginning with `benchmark_`, and tests a small,
   self-contained feature of the package.

## Running the benchmark script

Run the benchmarks using `scripts/benchmarks.jl`:
```
julia --project=. scripts/benchmarks.jl --tune
julia --project=. scripts/benchmarks.jl --run
julia --project=. scripts/benchmarks.jl --publish
```

To run the benchmarks using the package versions that were available at a
historical date (for example, the first of each month), use
`scripts/run_historical.sh`. It uses a separate Julia depot in
`~/.julia-benchmarks` with a git clone of the General registry so that it does
not interfere with your normal Julia installation:
```
scripts/run_historical.sh 2026-11-01 2026-10-01
```

## The website

The site at [jump.dev/benchmarks](https://jump.dev/benchmarks) is static and is
served by GitHub Pages from `docs/`. It has four kinds of page:

 * **Dashboard**: an index of run time, garbage collection and memory over a
   range of runs, and the benchmarks that changed most across the range.
 * **Runs**: every run with its Julia and package versions and how it compares
   with the run before. Click a run to see every package whose version changed
   since a baseline run, and each benchmark's result against that baseline.
 * **Benchmarks**: every benchmark with its latest value, recent changes and a
   sparkline. Click a benchmark for a plot of each metric over time; click a
   point in a plot to open the run.

The pages are plain JavaScript in `docs/assets/` with no dependencies. They
read the files that `scripts/benchmarks.jl --publish` writes from the raw
results in `data/`:

| File | Contents |
|---|---|
| `docs/data/index.json` | Every run with its date, Julia version, key package versions and benchmark count. |
| `docs/data/runs/<run>.json` | One run: `versioninfo()`, every package version in its Manifest, and its results. |
| `docs/data/benchmarks.json` | One entry per benchmark with the values of each metric across the runs. |

To preview the site locally, serve `docs/` over HTTP (the pages fetch JSON, so
opening `index.html` from the file system does not work):
```
python3 -m http.server --directory docs 8000
```

## Hardware

These benchmarks run on a 2020 Apple Mac Mini (M1) with 16GB of memory:
```
Julia Version 1.10.12
Platform Info:
  OS: macOS (arm64-apple-darwin25.5.0)
  CPU: 8 × Apple M1
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-15.0.7 (ORCJIT, apple-m1)
Threads: 1 default, 0 interactive, 1 GC (on 4 virtual cores)
```
Performance on other machines may differ. However, we're mostly interested in
long-term trends. The exact `versioninfo()` of every run is shown on its page.
