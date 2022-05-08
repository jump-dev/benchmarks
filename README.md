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

## Dashboard improvements

The visualizations at [jump.dev/benchmarks](https://jump.dev/benchmarks) are
preliminary. If you're interested in front-end web development and have
suggestions for how we could improve things, please get in touch.

## Hardware

These benchmarks run on a 2022 Apple Mac Mini with 16GB of memory:
```
Julia Version 1.7.2
Commit bf53498635 (2022-02-06 15:21 UTC)
Platform Info:
  OS: macOS (x86_64-apple-darwin19.5.0)
  CPU: Apple M1
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-12.0.1 (ORCJIT, westmere)
```
Performance on other machines may differ. However, we're mostly interested in
long-term trends.
