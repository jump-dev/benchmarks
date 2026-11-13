/* Copyright (c) 2022: jump-dev/benchmarks contributors
 *
 * Use of this source code is governed by an MIT-style license that can be found
 * in the LICENSE.md file or at https://opensource.org/licenses/MIT.
 *
 * JuMP benchmark browser. Plain JS, no dependencies; chart.js holds the SVG
 * scaffolding. Pages are routed on the URL hash:
 *
 *   #/                       dashboard: indices over time and the largest changes
 *   #/runs                   every run with its package versions
 *   #/run/<id>?vs=<id>       one run against a baseline (default: the previous run)
 *   #/benchmarks             every benchmark with its latest value and trend
 *   #/benchmark/<name>       one benchmark: each metric over time
 *
 * Pages that show a range of runs take ?from=<id>&to=<id>&group=micro|latency.
 *
 * Data (written by `scripts/benchmarks.jl --publish`):
 *   data/index.json          {generated, runs: [{id, date, julia, n_benchmarks, packages}]}
 *   data/benchmarks.json     {name: {group, source, runs: [id], <metric>: [value]}}
 *   data/runs/<id>.json      {id, date, julia, versioninfo, packages, results}
 */
"use strict";

const REPO_URL = "https://github.com/jump-dev/benchmarks";

// Every metric is "lower is better". Times are nanoseconds from
// BenchmarkTools; memory is bytes.
const METRICS = [
  { key: "time_min", label: "Minimum time", fmt: fmtTime, tick: fmtTimeTick,
    desc: "The fastest sample. The most reliable measure of the code itself, since it is least affected by whatever else the machine was doing." },
  { key: "time_median", label: "Median time", fmt: fmtTime, tick: fmtTimeTick,
    desc: "The median sample, including the time spent in garbage collection." },
  { key: "gc_min", label: "Minimum GC time", fmt: fmtTime, tick: fmtTimeTick,
    desc: "The time spent in the garbage collector in the fastest sample. Often zero." },
  { key: "gc_median", label: "Median GC time", fmt: fmtTime, tick: fmtTimeTick,
    desc: "The median time spent in the garbage collector across the samples." },
  { key: "allocs", label: "Allocations", fmt: fmtCount, tick: fmtCountTick,
    desc: "The number of heap allocations. Unlike times, this is deterministic, so a change is a real change in the code." },
  { key: "memory", label: "Memory allocated", fmt: fmtBytes, tick: fmtBytes,
    desc: "The total bytes allocated. Deterministic, like the number of allocations." },
];
const metricByKey = (k) => METRICS.find((m) => m.key === k) || METRICS[0];

const GROUPS = [["", "All"], ["micro", "Micro-benchmarks"], ["latency", "Latency examples"]];
const GROUP_LABEL = { micro: "micro", latency: "latency" };

// A relative change smaller than this is shown as noise.
const FLAT = 0.05;

// ---------------------------------------------------------------- utilities

function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  if (attrs) {
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null) continue;
      if (k === "class") el.className = v;
      else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
      else el.setAttribute(k, v);
    }
  }
  for (const c of children.flat(Infinity)) {
    if (c == null || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}

// Three significant figures, no trailing zeros, with thousands separators.
function sig(x, digits = 3) {
  if (x === 0) return "0";
  const mag = Math.floor(Math.log10(Math.abs(x)));
  const decimals = Math.max(0, digits - 1 - mag);
  return x.toLocaleString(undefined, { maximumFractionDigits: decimals, minimumFractionDigits: 0 });
}
function fmtTime(ns) {
  if (ns == null || !Number.isFinite(ns)) return "–";
  if (ns < 1e3) return sig(ns) + " ns";
  if (ns < 1e6) return sig(ns / 1e3) + " μs";
  if (ns < 1e9) return sig(ns / 1e6) + " ms";
  return sig(ns / 1e9) + " s";
}
// Axis ticks on a fitted axis differ by small steps, so they need more
// figures than the three of fmtTime.
function fmtTimeTick(ns) {
  const unit = ns < 1e3 ? [1, "ns"] : ns < 1e6 ? [1e3, "μs"] : ns < 1e9 ? [1e6, "ms"] : [1e9, "s"];
  return (ns / unit[0]).toLocaleString(undefined, { maximumFractionDigits: 4 }) + " " + unit[1];
}
function fmtBytes(b) {
  if (b == null || !Number.isFinite(b)) return "–";
  if (b < 1024) return sig(b) + " B";
  if (b < 1024 ** 2) return sig(b / 1024) + " KiB";
  if (b < 1024 ** 3) return sig(b / 1024 ** 2) + " MiB";
  return sig(b / 1024 ** 3) + " GiB";
}
function fmtCount(x) { return x == null || !Number.isFinite(x) ? "–" : x.toLocaleString(undefined, { maximumFractionDigits: 0 }); }
function fmtCountTick(x) { return x >= 1e6 ? sig(x / 1e6) + "M" : x >= 1e3 ? sig(x / 1e3) + "k" : fmtCount(x); }
function fmtPct(x) { return x == null ? "–" : x.toFixed(1) + "%"; }
// "2026-11-01 00:00" from "2026-11-01T00:00".
function fmtDate(iso) { return (iso || "").replace("T", " "); }
function fmtDay(iso) { return (iso || "").slice(0, 10); }

// The relative change from a to b as a ratio b / a, or null.
function ratio(a, b) { return a != null && b != null && a > 0 && Number.isFinite(b) ? b / a : null; }
// "+12.3%" / "−4.5%" of a ratio, coloured when it is more than FLAT either
// way. Every metric is lower-is-better, so a rise is "worse".
function deltaEl(r, title) {
  if (r == null || !Number.isFinite(r)) return h("span", { class: "delta flat" }, "–");
  const pct = 100 * (r - 1);
  const cls = Math.abs(pct) < 100 * FLAT ? "flat" : pct > 0 ? "worse" : "better";
  const text = `${pct >= 0 ? "+" : "−"}${Math.abs(pct) >= 1000 ? Math.abs(pct).toLocaleString(undefined, { maximumFractionDigits: 0 }) : Math.abs(pct).toFixed(1)}%`;
  return h("span", { class: `delta ${cls}`, title: title || null }, text);
}
function deltaText(r) {
  if (r == null || !Number.isFinite(r)) return "";
  const pct = 100 * (r - 1);
  return `${pct >= 0 ? "+" : "−"}${Math.abs(pct).toFixed(1)}%`;
}

// Pkg.status() writes a package tracking a git branch as
// "v1.28.0 `https://github.com/jump-dev/JuMP.jl.git#master`"; the short form
// is "v1.28.0#master", with the full text in the tooltip of pkgEl.
function shortVersion(v) {
  if (!v) return "–";
  const m = v.match(/^(\S+)\s+`([^`]*)`$/);
  if (!m) return v;
  const rev = m[2].includes("#") ? m[2].slice(m[2].lastIndexOf("#")) : "";
  return `${m[1]}${rev || " (dev)"}`;
}
function pkgEl(v) { return h("span", { class: "mono", title: v && v !== shortVersion(v) ? v : null }, shortVersion(v)); }

function groupChip(group) { return h("span", { class: `chip group-${group}` }, GROUP_LABEL[group] || group); }
function benchLink(name) { return h("a", { href: `#/benchmark/${encodeURIComponent(name)}`, class: "mono" }, name); }
function runLink(run, text) { return h("a", { href: `#/run/${run.id}`, class: "mono" }, text || run.id); }
function sourceLink(b) {
  if (!b.source) return null;
  return h("a", { href: `${REPO_URL}/blob/master/${b.source}`, target: "_blank", rel: "noopener" }, b.source);
}

// ---------------------------------------------------------------- data

const cache = { data: null, runs: new Map() };

async function fetchJson(url, missing) {
  const r = await fetch(url, { cache: "no-cache" });
  if (r.ok) return r.json();
  if (missing !== undefined) return missing;
  throw new Error(`${url} not found (HTTP ${r.status}): run scripts/benchmarks.jl --publish first`);
}

// index.json and benchmarks.json, loaded once and joined:
//   runs        [{id, date, julia, packages, n_benchmarks, i}] oldest first
//   runById     Map id -> run
//   benchmarks  [{name, group, source, runIds, values: Map runId -> {metric: value}}]
//   benchByName Map name -> benchmark
function getData() {
  if (!cache.data) {
    cache.data = Promise.all([fetchJson("data/index.json"), fetchJson("data/benchmarks.json")]).then(([index, raw]) => {
      const runs = index.runs.slice().sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
      runs.forEach((r, i) => { r.i = i; });
      const runById = new Map(runs.map((r) => [r.id, r]));
      const benchmarks = Object.entries(raw).map(([name, b]) => {
        const values = new Map();
        b.runs.forEach((id, j) => {
          const v = {};
          for (const m of METRICS) { const x = b[m.key][j]; v[m.key] = x == null || !Number.isFinite(x) ? null : x; }
          values.set(id, v);
        });
        return { name, group: b.group, source: b.source, runIds: b.runs, values };
      }).sort((a, b) => a.name.localeCompare(b.name));
      return { index, runs, runById, benchmarks, benchByName: new Map(benchmarks.map((b) => [b.name, b])) };
    });
  }
  return cache.data;
}

// One run's own file: versioninfo and the full package list.
function getRun(id) {
  if (!cache.runs.has(id)) cache.runs.set(id, fetchJson(`data/runs/${id}.json`, null));
  return cache.runs.get(id);
}

// The value of a metric for a benchmark in a run, or null.
function val(b, runId, key) { const v = b.values.get(runId); return v ? v[key] : null; }

// The benchmarks of a group ("" for all).
function inGroup(benchmarks, group) { return group ? benchmarks.filter((b) => b.group === group) : benchmarks; }

// The runs from query.from to query.to inclusive (defaults: all), oldest
// first, with the ids actually used.
function rangeRuns(data, query) {
  const { runs } = data;
  let from = runs.findIndex((r) => r.id === query.from), to = runs.findIndex((r) => r.id === query.to);
  if (from < 0) from = 0;
  if (to < 0) to = runs.length - 1;
  if (from > to) [from, to] = [to, from];
  return { runs: runs.slice(from, to + 1), from: runs[from].id, to: runs[to].id };
}

// Geometric mean of the ratios v(b) / v0(b) over the benchmarks with positive
// values in both, as {ratio, n}. Used for "run B vs run A" summaries.
function geomeanRatio(benchmarks, runA, runB, key) {
  let sum = 0, n = 0;
  for (const b of benchmarks) {
    const a = val(b, runA.id, key), c = val(b, runB.id, key);
    if (a != null && c != null && a > 0 && c > 0) { sum += Math.log(c / a); n++; }
  }
  return { ratio: n ? Math.exp(sum / n) : null, n };
}

// An index over the runs: 100 at the first run, then the geometric mean of
// each benchmark's value relative to its value in the first run. Only the
// benchmarks with a positive value in every run count, so the index follows a
// fixed set of benchmarks and is not moved by benchmarks being added or
// removed. Returns {points: [value | null], used: [benchmark]}.
function indexSeries(benchmarks, runs, key) {
  if (!runs.length) return { points: [], used: [] };
  const used = benchmarks.filter((b) => runs.every((r) => { const v = val(b, r.id, key); return v != null && v > 0; }));
  const first = runs[0];
  const points = runs.map((r) => used.length
    ? 100 * Math.exp(used.reduce((s, b) => s + Math.log(val(b, r.id, key) / val(b, first.id, key)), 0) / used.length)
    : null);
  return { points, used };
}

// The previous run that has results, for the default baseline of a run.
function previousRun(data, run) { return run.i > 0 ? data.runs[run.i - 1] : null; }

// ---------------------------------------------------------------- router

function parseHash() {
  const hash = location.hash.replace(/^#/, "") || "/";
  const [path, qs] = hash.split("?");
  const query = Object.fromEntries(new URLSearchParams(qs || ""));
  return { path: path.split("/").filter(Boolean).map(decodeURIComponent), query };
}
function hashFor(path, query) {
  const qs = new URLSearchParams(Object.entries(query || {}).filter(([, v]) => v != null && v !== "")).toString();
  return "#/" + path.map(encodeURIComponent).join("/") + (qs ? "?" + qs : "");
}
function setQuery(path, query) { location.hash = hashFor(path, query); }

async function render() {
  const app = document.getElementById("app");
  const { path, query } = parseHash();
  try {
    let view;
    if (path.length === 0) view = await dashboardView(query);
    else if (path[0] === "runs") view = await runsView(query);
    else if (path[0] === "run" && path[1]) view = await runView(path[1], query);
    else if (path[0] === "benchmarks") view = await benchmarksView(query);
    else if (path[0] === "benchmark" && path[1]) view = await benchmarkView(path[1], query);
    else view = h("p", { class: "err" }, "Unknown page");
    app.replaceChildren(view);
    const top = { run: "runs", benchmark: "benchmarks" }[path[0]] ?? (path[0] || "");
    for (const a of document.querySelectorAll(".topbar nav a[href^='#/']")) {
      a.classList.toggle("active", a.getAttribute("href").slice(2).split(/[/?]/)[0] === top);
    }
    window.scrollTo(0, 0);
  } catch (e) {
    app.replaceChildren(h("p", { class: "err" }, String(e.message || e)));
    console.error(e);
  }
}
window.addEventListener("hashchange", render);
window.addEventListener("DOMContentLoaded", render);

// ---------------------------------------------------------------- generic pieces

// columns: [{key, label, num, render(row), sort(row), title, wrap}]
function makeTable(columns, rows, opts = {}) {
  let sortKey = opts.sortKey || columns[0].key;
  let asc = opts.asc != null ? opts.asc : true;
  const wrap = h("div", { class: "table-wrap" });
  function draw() {
    const col = columns.find((c) => c.key === sortKey) || columns[0];
    const keyOf = col.sort || ((r) => r[col.key]);
    const sorted = rows.slice().sort((a, b) => {
      const x = keyOf(a), y = keyOf(b);
      const xn = x == null || x === "" || Number.isNaN(x) ? 1 : 0, yn = y == null || y === "" || Number.isNaN(y) ? 1 : 0;
      if (xn !== yn) return xn - yn; // nulls last
      if (x < y) return asc ? -1 : 1;
      if (x > y) return asc ? 1 : -1;
      return 0;
    });
    const thead = h("tr", null, columns.map((c) =>
      h("th", {
        class: `sortable ${c.num ? "num" : ""} ${c.key === sortKey ? "sorted" : ""} ${c.key === sortKey && asc ? "asc" : ""}`,
        onclick: () => { if (sortKey === c.key) asc = !asc; else { sortKey = c.key; asc = !c.num; } draw(); },
        title: c.title || null,
      }, c.label)));
    const tbody = sorted.map((r) => h("tr", { class: opts.rowClass ? opts.rowClass(r) : null }, columns.map((c) =>
      h("td", { class: c.num ? "num" : c.wrap ? "wrap" : null }, c.render ? c.render(r) : r[c.key]))));
    wrap.replaceChildren(h("table", null, h("thead", null, thead), h("tbody", null, tbody)));
  }
  draw();
  return wrap;
}

function select(options, value, onchange, attrs = {}) {
  return h("select", { onchange: (e) => onchange(e.target.value), ...attrs },
    options.map(([v, label]) => h("option", { value: v, selected: v === value ? "" : null }, label)));
}

function tile(label, value, sub) {
  return h("div", { class: "tile" }, h("div", { class: "label" }, label), h("div", { class: "value" }, value == null ? "–" : value), sub ? h("div", { class: "sub" }, sub) : null);
}

// "2026-11-01 · JuMP v1.32.1" for menus.
function runLabel(run) { return `${fmtDate(run.date)} · JuMP ${shortVersion(run.packages.JuMP)}`; }

// The From / To / Group controls shared by the pages that show a range.
function rangeControls(data, query, path, range, extra = []) {
  const update = (patch) => setQuery(path, { ...query, ...patch });
  const runOpts = data.runs.map((r) => [r.id, runLabel(r)]);
  return h("div", { class: "controls" },
    h("label", null, "Group", select(GROUPS, query.group || "", (v) => update({ group: v }))),
    h("label", null, "From run", select(runOpts, range.from, (v) => update({ from: v }))),
    h("label", null, "To run", select(runOpts, range.to, (v) => update({ to: v }))),
    ...extra,
  );
}

// A row of the tooltip header: the run id, date and JuMP version.
function runHead(run) {
  return h("div", null, h("b", { class: "mono" }, run.id), h("div", { class: "muted" }, `JuMP ${shortVersion(run.packages.JuMP)} · Julia ${run.julia || "?"}`));
}

// A plot section: title with the change from first to last run, description, chart.
function plotSection(title, delta, description, chart) {
  return h("section", { class: "plot" },
    h("h3", null, title, delta != null ? h("span", { class: "delta-wrap" }, " ", deltaEl(delta, "change from the first to the last run shown")) : null),
    description ? h("p", { class: "muted small" }, description) : null,
    chart);
}

// ---------------------------------------------------------------- dashboard

async function dashboardView(query) {
  const data = await getData();
  const range = rangeRuns(data, query);
  const benchmarks = inGroup(data.benchmarks, query.group);
  const runs = range.runs;
  const first = runs[0], last = runs[runs.length - 1];
  const latest = data.runs[data.runs.length - 1];
  const time = geomeanRatio(benchmarks, first, last, "time_min");
  const memory = geomeanRatio(benchmarks, first, last, "memory");
  const allocs = geomeanRatio(benchmarks, first, last, "allocs");
  // Latency examples time a whole script, so their garbage-collection and
  // allocation figures are those of the `run` call and mean nothing.
  const latency = query.group === "latency";

  // One index chart per family of metrics, each series indexed to 100 at
  // the first run of the range.
  const indexChart = (keys, colors) => {
    const built = keys.map((k, j) => ({ metric: metricByKey(k), color: colors[j], ...indexSeries(benchmarks, runs, k) }));
    const series = built.map((s) => ({ label: `${s.metric.label} (${s.used.length})`, color: s.color, value: (r) => s.points[runs.indexOf(r)] }));
    return lineChart(runs, series, { fmt: (v) => v.toFixed(1), tickFmt: (v) => v.toFixed(0), yTitle: "Index (first run = 100)", head: runHead, open: (r) => `#/run/${r.id}` });
  };
  const indexDelta = (key) => { const s = indexSeries(benchmarks, runs, key); const p = s.points.filter((v) => v != null); return p.length > 1 ? p[p.length - 1] / p[0] : null; };

  // The largest changes between the first and the last run of the range.
  const changes = benchmarks.map((b) => ({ b, r: ratio(val(b, first.id, "time_min"), val(b, last.id, "time_min")), a: val(b, first.id, "time_min"), z: val(b, last.id, "time_min") }))
    .filter((x) => x.r != null);
  const regressions = changes.filter((x) => x.r > 1 + FLAT).sort((x, y) => y.r - x.r).slice(0, 10);
  const improvements = changes.filter((x) => x.r < 1 - FLAT).sort((x, y) => x.r - y.r).slice(0, 10);
  const changeCols = [
    { key: "name", label: "Benchmark", render: (x) => [benchLink(x.b.name), groupChip(x.b.group)], sort: (x) => x.b.name },
    { key: "a", label: fmtDay(first.date), num: true, render: (x) => fmtTime(x.a), title: `minimum time in ${first.id}` },
    { key: "z", label: fmtDay(last.date), num: true, render: (x) => fmtTime(x.z), title: `minimum time in ${last.id}` },
    { key: "r", label: "Change", num: true, render: (x) => deltaEl(x.r) },
  ];

  return h("div", null,
    h("h1", null, "JuMP performance benchmarks"),
    h("p", { class: "muted" },
      `This site tracks the performance of the `, h("a", { href: "https://github.com/jump-dev", target: "_blank", rel: "noopener" }, "JuMP-dev"), ` ecosystem over time. `,
      `Each run installs the newest versions of JuMP and its dependencies that were registered on the run's date, usually the first of the month, and measures a fixed set of benchmarks on the same machine: `,
      `micro-benchmarks of single features (run time, garbage collection and allocations with BenchmarkTools) and latency examples, which are whole scripts run from the command line and so include compilation time. `,
      `Lower is better everywhere. Click a run or a benchmark to drill in.`),
    h("div", { class: "tiles" },
      tile("Runs", data.runs.length, `${fmtDay(data.runs[0].date)} to ${fmtDay(latest.date)}`),
      tile("Benchmarks", latest.n_benchmarks, `${data.benchmarks.filter((b) => b.group === "micro").length} micro · ${data.benchmarks.filter((b) => b.group === "latency").length} latency`),
      tile("Latest run", runLink(latest, fmtDay(latest.date)), `JuMP ${shortVersion(latest.packages.JuMP)} · Julia ${latest.julia || "?"}`),
      tile("Run time, first to last", deltaEl(time.ratio), `geometric mean over ${time.n} benchmarks`),
      latency ? null : tile("Memory, first to last", deltaEl(memory.ratio), `geometric mean over ${memory.n} benchmarks`),
      latency ? null : tile("Allocations, first to last", deltaEl(allocs.ratio), `geometric mean over ${allocs.n} benchmarks`),
    ),
    rangeControls(data, query, [], range),
    h("h2", null, "Trends"),
    h("p", { class: "muted" },
      `Each line is an index: 100 at the first run shown, then the geometric mean of every benchmark's value relative to that first run. `,
      `Only the benchmarks measured in every run of the range count (the number in brackets), so the index follows a fixed set and is not moved by benchmarks being added. `,
      `Garbage-collection times are often zero, so fewer benchmarks count towards those lines. Hover for the values at a run; click a point to open the run.`),
    h("div", { class: latency ? "plots" : "plots three" },
      plotSection("Run time", indexDelta("time_min"), "Minimum and median time of each benchmark.",
        indexChart(["time_min", "time_median"], ["var(--series-1)", "var(--series-2)"])),
      latency ? null : plotSection("Garbage collection", indexDelta("gc_min"), "Time spent in the garbage collector, minimum and median.",
        indexChart(["gc_min", "gc_median"], ["var(--series-1)", "var(--series-2)"])),
      latency ? null : plotSection("Memory", indexDelta("memory"), "Bytes allocated and the number of allocations.",
        indexChart(["memory", "allocs"], ["var(--series-1)", "var(--series-2)"])),
    ),
    h("h2", null, "Largest changes in minimum time, ", h("span", { class: "mono" }, first.id), " to ", h("span", { class: "mono" }, last.id)),
    h("p", { class: "muted" }, `The benchmarks whose minimum time moved by more than ${100 * FLAT}% between the first and the last run of the range. Timing noise of a few percent is normal; the ones at the top of each list are worth a look.`),
    h("div", { class: "cols" },
      h("div", null, h("h3", null, `Slower (${regressions.length})`), regressions.length ? makeTable(changeCols, regressions, { sortKey: "r", asc: false }) : h("p", { class: "muted" }, "None.")),
      h("div", null, h("h3", null, `Faster (${improvements.length})`), improvements.length ? makeTable(changeCols, improvements, { sortKey: "r", asc: true }) : h("p", { class: "muted" }, "None.")),
    ),
    h("p", { class: "muted small" }, h("a", { href: hashFor(["benchmarks"], query) }, "Every benchmark"), " · ", h("a", { href: "#/runs" }, "Every run")),
  );
}

// ---------------------------------------------------------------- runs

async function runsView(query) {
  const data = await getData();
  const benchmarks = inGroup(data.benchmarks, query.group);
  const rows = data.runs.map((run) => {
    const prev = previousRun(data, run);
    return {
      run, prev,
      time: prev ? geomeanRatio(benchmarks, prev, run, "time_min") : { ratio: null, n: 0 },
      memory: prev ? geomeanRatio(benchmarks, prev, run, "memory") : { ratio: null, n: 0 },
      allocs: prev ? geomeanRatio(benchmarks, prev, run, "allocs") : { ratio: null, n: 0 },
    };
  });
  const pkg = (name) => ({ key: name, label: name === "MathOptInterface" ? "MOI" : name, title: name, render: (x) => pkgEl(x.run.packages[name]), sort: (x) => x.run.packages[name] || null });
  const cols = [
    { key: "id", label: "Run", render: (x) => runLink(x.run), sort: (x) => x.run.id },
    { key: "julia", label: "Julia", render: (x) => h("span", { class: "mono" }, x.run.julia || "–"), sort: (x) => x.run.julia },
    pkg("JuMP"), pkg("MathOptInterface"), pkg("Ipopt"), pkg("HiGHS"), pkg("Gurobi"), pkg("PowerModels"),
    { key: "n", label: "Benchmarks", num: true, render: (x) => fmtCount(x.run.n_benchmarks), sort: (x) => x.run.n_benchmarks },
    { key: "time", label: "Time vs previous", num: true, title: "geometric mean change in minimum time over the benchmarks common to this run and the previous one", render: (x) => deltaEl(x.time.ratio, `over ${x.time.n} benchmarks`), sort: (x) => x.time.ratio },
    { key: "memory", label: "Memory vs previous", num: true, title: "geometric mean change in memory allocated", render: (x) => deltaEl(x.memory.ratio, `over ${x.memory.n} benchmarks`), sort: (x) => x.memory.ratio },
    { key: "allocs", label: "Allocations vs previous", num: true, title: "geometric mean change in the number of allocations", render: (x) => deltaEl(x.allocs.ratio, `over ${x.allocs.n} benchmarks`), sort: (x) => x.allocs.ratio },
  ];
  return h("div", null,
    h("h1", null, "Runs ", h("span", { class: "chip" }, data.runs.length)),
    h("p", { class: "muted" },
      `Each run is named by its date. A run on the first of a month at 00:00 used the package versions registered before that date; a run at any other time is a one-off on the versions available then. `,
      `The last three columns compare each run with the one before it as a geometric mean over the benchmarks common to both, so a large value points at the run where something changed. Click a run for its package versions and results.`),
    h("div", { class: "controls" },
      h("label", null, "Group", select(GROUPS, query.group || "", (v) => setQuery(["runs"], { ...query, group: v }))),
      h("span", { class: "note" }, "The group applies to the comparison columns.")),
    makeTable(cols, rows, { sortKey: "id", asc: false }),
  );
}

// ---------------------------------------------------------------- one run

async function runView(id, query) {
  const data = await getData();
  const run = data.runById.get(id);
  if (!run) throw new Error(`unknown run ${id}`);
  const baseline = (query.vs && data.runById.get(query.vs)) || previousRun(data, run);
  const [full, base] = await Promise.all([getRun(id), baseline ? getRun(baseline.id) : null]);
  if (!full) throw new Error(`data/runs/${id}.json not found`);
  const group = query.group || "";
  const q = (query.q || "").toLowerCase();
  const benchmarks = inGroup(data.benchmarks, group).filter((b) => b.values.has(id) || (baseline && b.values.has(baseline.id)));
  const rows = benchmarks.filter((b) => !q || b.name.toLowerCase().includes(q));
  const prev = previousRun(data, run), next = run.i + 1 < data.runs.length ? data.runs[run.i + 1] : null;
  const update = (patch) => setQuery(["run", id], { ...query, ...patch });

  // Packages whose version differs from the baseline.
  const pkgRows = [];
  if (base) {
    const names = new Set([...Object.keys(full.packages), ...Object.keys(base.packages)]);
    for (const name of [...names].sort((a, b) => a.localeCompare(b))) {
      const a = base.packages[name], b = full.packages[name];
      if (a !== b) pkgRows.push({ name, a, b, kind: a == null ? "added" : b == null ? "removed" : "changed" });
    }
  }
  const pkgCols = [
    { key: "name", label: "Package", render: (x) => h("span", { class: "mono" }, x.name) },
    { key: "a", label: baseline ? baseline.id : "baseline", render: (x) => x.a ? pkgEl(x.a) : h("span", { class: "muted" }, "not installed"), sort: (x) => x.a || "" },
    { key: "b", label: id, render: (x) => x.b ? pkgEl(x.b) : h("span", { class: "muted" }, "not installed"), sort: (x) => x.b || "" },
  ];

  const vs = (key) => baseline ? geomeanRatio(inGroup(data.benchmarks, group), baseline, run, key) : { ratio: null, n: 0 };
  const time = vs("time_min"), memory = vs("memory"), allocs = vs("allocs");
  const cell = (key, fmt) => ({
    key, label: metricByKey(key).label, num: true, render: (b) => fmt(val(b, id, key)), sort: (b) => val(b, id, key),
  });
  const delta = (key) => ({
    key: key + "_d", label: "vs baseline", num: true, title: `change in ${metricByKey(key).label.toLowerCase()} from the baseline run`,
    render: (b) => deltaEl(ratio(baseline ? val(b, baseline.id, key) : null, val(b, id, key))),
    sort: (b) => ratio(baseline ? val(b, baseline.id, key) : null, val(b, id, key)),
  });
  const cols = [
    { key: "name", label: "Benchmark", render: (b) => [benchLink(b.name), groupChip(b.group)], sort: (b) => b.name },
    cell("time_min", fmtTime), delta("time_min"),
    cell("time_median", fmtTime), delta("time_median"),
    cell("gc_min", fmtTime),
    cell("allocs", fmtCount), delta("allocs"),
    cell("memory", fmtBytes), delta("memory"),
  ];
  const keyPkgs = Object.entries(run.packages).sort(([a], [b]) => a.localeCompare(b));

  return h("div", null,
    h("h1", null, "Run ", h("span", { class: "mono" }, id)),
    h("p", { class: "muted" },
      prev ? [runLink(prev, "← " + prev.id), " · "] : null,
      h("a", { href: "#/runs" }, "all runs"),
      next ? [" · ", runLink(next, next.id + " →")] : null),
    h("dl", { class: "kv" },
      h("dt", null, "Date"), h("dd", null, fmtDate(run.date)),
      h("dt", null, "Julia"), h("dd", { class: "mono" }, run.julia || "–"),
      h("dt", null, "Packages"), h("dd", null, h("span", { class: "mono" }, keyPkgs.map(([k, v]) => `${k} ${shortVersion(v)}`).join(" · ")), ` and ${Math.max(0, Object.keys(full.packages).length - keyPkgs.length)} more, below`),
      h("dt", null, "Benchmarks"), h("dd", null, `${run.n_benchmarks} measured`),
    ),
    h("details", null, h("summary", null, "versioninfo()"), h("pre", { class: "log" }, full.versioninfo || "not recorded")),
    h("div", { class: "controls" },
      h("label", null, "Baseline run", select(data.runs.filter((r) => r.id !== id).map((r) => [r.id, runLabel(r)]), baseline ? baseline.id : "", (v) => update({ vs: v }), { class: "wide" })),
      h("label", null, "Group", select(GROUPS, group, (v) => update({ group: v }))),
      h("label", null, "Search", h("input", { type: "search", value: query.q || "", placeholder: "benchmark name", onchange: (e) => update({ q: e.target.value }) })),
      baseline ? h("span", { class: "note" }, "Changes are this run relative to the baseline: ", runLink(baseline), ".") : null,
    ),
    h("div", { class: "tiles" },
      tile("Run time vs baseline", deltaEl(time.ratio), `geometric mean over ${time.n} benchmarks`),
      tile("Memory vs baseline", deltaEl(memory.ratio), `geometric mean over ${memory.n} benchmarks`),
      tile("Allocations vs baseline", deltaEl(allocs.ratio), `geometric mean over ${allocs.n} benchmarks`),
      tile("Packages changed", baseline ? pkgRows.length : "–", baseline ? `of ${Object.keys(full.packages).length} in the Manifest` : "no baseline"),
    ),
    h("h2", null, "Package changes ", baseline ? h("span", { class: "chip" }, pkgRows.length) : null),
    h("p", { class: "muted" }, "The packages whose version differs between the baseline and this run. When a benchmark moves, the cause is usually in this list."),
    baseline ? (pkgRows.length ? makeTable(pkgCols, pkgRows, { sortKey: "name" }) : h("p", { class: "muted" }, "No package changed.")) : h("p", { class: "muted" }, "Choose a baseline run above."),
    h("h2", null, "Results ", h("span", { class: "chip" }, `${rows.length} of ${benchmarks.length}`)),
    h("p", { class: "muted" }, "Every benchmark measured in this run. Times are the minimum and median of the samples BenchmarkTools took; click a column heading to sort, for example by the change in minimum time."),
    makeTable(cols, rows, { sortKey: "name" }),
  );
}

// ---------------------------------------------------------------- benchmarks

async function benchmarksView(query) {
  const data = await getData();
  const range = rangeRuns(data, query);
  const runs = range.runs;
  const first = runs[0], last = runs[runs.length - 1];
  const metric = metricByKey(query.metric || "time_min");
  const q = (query.q || "").toLowerCase();
  const rows = inGroup(data.benchmarks, query.group).filter((b) => !q || b.name.toLowerCase().includes(q)).map((b) => {
    // The latest run in the range with a value, and the one before it.
    const present = runs.filter((r) => val(b, r.id, metric.key) != null);
    const latest = present[present.length - 1], before = present[present.length - 2];
    return {
      b, latest, n: present.length,
      value: latest ? val(b, latest.id, metric.key) : null,
      prev: latest && before ? ratio(val(b, before.id, metric.key), val(b, latest.id, metric.key)) : null,
      span: ratio(val(b, first.id, metric.key), val(b, last.id, metric.key)),
      series: runs.map((r) => val(b, r.id, metric.key)),
    };
  });
  const cols = [
    { key: "name", label: "Benchmark", render: (x) => [benchLink(x.b.name), groupChip(x.b.group)], sort: (x) => x.b.name },
    { key: "n", label: "Runs", num: true, title: "runs in the range with a value", sort: (x) => x.n },
    { key: "value", label: `Latest ${metric.label.toLowerCase()}`, num: true, render: (x) => metric.fmt(x.value), sort: (x) => x.value },
    { key: "latest", label: "In run", render: (x) => x.latest ? runLink(x.latest) : "–", sort: (x) => x.latest ? x.latest.id : null },
    { key: "prev", label: "vs previous run", num: true, render: (x) => deltaEl(x.prev), sort: (x) => x.prev },
    { key: "span", label: `${fmtDay(first.date)} to ${fmtDay(last.date)}`, num: true, title: "change from the first to the last run of the range", render: (x) => deltaEl(x.span), sort: (x) => x.span },
    { key: "trend", label: "Trend", render: (x) => sparkline(x.series), sort: (x) => x.span },
  ];
  const update = (patch) => setQuery(["benchmarks"], { ...query, ...patch });
  return h("div", null,
    h("h1", null, "Benchmarks ", h("span", { class: "chip" }, rows.length)),
    h("p", { class: "muted" },
      `Every benchmark, with its latest value of the chosen metric, the change from the run before, the change across the whole range, and a sparkline of the range. `,
      `Click a benchmark for plots of every metric over time.`),
    rangeControls(data, query, ["benchmarks"], range, [
      h("label", null, "Metric", select(METRICS.map((m) => [m.key, m.label]), metric.key, (v) => update({ metric: v }))),
      h("label", null, "Search", h("input", { type: "search", value: query.q || "", placeholder: "benchmark name", onchange: (e) => update({ q: e.target.value }) })),
    ]),
    makeTable(cols, rows, { sortKey: "name" }),
  );
}

// ---------------------------------------------------------------- one benchmark

async function benchmarkView(name, query) {
  const data = await getData();
  const b = data.benchByName.get(name);
  if (!b) throw new Error(`unknown benchmark ${name}`);
  const range = rangeRuns(data, query);
  const runs = range.runs;
  const present = runs.filter((r) => b.values.has(r.id));
  const allPresent = data.runs.filter((r) => b.values.has(r.id));
  const update = (patch) => setQuery(["benchmark", name], { ...query, ...patch });
  const open = (r) => `#/run/${r.id}`;
  const plot = (m) => {
    const vs = present.map((r) => val(b, r.id, m.key)).filter((v) => v != null && v > 0);
    const delta = vs.length > 1 ? vs[vs.length - 1] / vs[0] : null;
    return plotSection(m.label, delta, m.desc,
      lineChart(runs, [{ label: m.label, color: "var(--series-1)", value: (r) => val(b, r.id, m.key) }],
        { fmt: m.fmt, tickFmt: m.tick, head: runHead, open }));
  };
  // History, newest first, each metric with its change from the run before.
  const hist = present.map((r, i) => ({ run: r, prev: i > 0 ? present[i - 1] : null })).reverse();
  const histCols = [
    { key: "run", label: "Run", render: (x) => runLink(x.run), sort: (x) => x.run.id },
    { key: "jump", label: "JuMP", render: (x) => pkgEl(x.run.packages.JuMP), sort: (x) => x.run.packages.JuMP },
    { key: "moi", label: "MOI", render: (x) => pkgEl(x.run.packages.MathOptInterface), sort: (x) => x.run.packages.MathOptInterface },
    ...METRICS.flatMap((m) => {
      const cols = [{ key: m.key, label: m.label, num: true, render: (x) => m.fmt(val(b, x.run.id, m.key)), sort: (x) => val(b, x.run.id, m.key) }];
      if (["time_min", "allocs", "memory"].includes(m.key)) {
        cols.push({ key: m.key + "_d", label: "vs previous", num: true, title: `change in ${m.label.toLowerCase()} from the run before`,
          render: (x) => deltaEl(ratio(x.prev ? val(b, x.prev.id, m.key) : null, val(b, x.run.id, m.key))),
          sort: (x) => ratio(x.prev ? val(b, x.prev.id, m.key) : null, val(b, x.run.id, m.key)) });
      }
      return cols;
    }),
  ];
  const sameGroup = data.benchmarks.filter((x) => x.group === b.group);
  return h("div", null,
    h("h1", null, h("span", { class: "mono" }, name), groupChip(b.group)),
    h("p", { class: "muted" },
      b.group === "latency"
        ? `A latency example: the wall time of running a whole script from the command line, including compilation. `
        : `A micro-benchmark: a small, self-contained feature measured with BenchmarkTools. `,
      b.source ? ["Defined in ", sourceLink(b), ". "] : null,
      `Measured in ${allPresent.length} runs, from ${fmtDay(allPresent[0].date)} to ${fmtDay(allPresent[allPresent.length - 1].date)}.`),
    h("div", { class: "controls" },
      h("label", null, "Benchmark", select(sameGroup.map((x) => [x.name, x.name]), name, (v) => setQuery(["benchmark", v], query), { class: "wide mono" })),
      h("label", null, "From run", select(data.runs.map((r) => [r.id, runLabel(r)]), range.from, (v) => update({ from: v }))),
      h("label", null, "To run", select(data.runs.map((r) => [r.id, runLabel(r)]), range.to, (v) => update({ to: v }))),
    ),
    h("h2", null, "Metrics over time"),
    h("p", { class: "muted" }, "One plot per metric. The change next to each title is from the first to the last run shown. The y axes are fitted to the data and do not start at zero. Hover for the value at a run; click a point to open the run and see which packages changed."),
    h("div", { class: "plots" }, METRICS.map(plot)),
    h("h2", null, "History ", h("span", { class: "chip" }, present.length)),
    makeTable(histCols, hist, { sortKey: "run", asc: false }),
  );
}
