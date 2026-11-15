// Copyright (c) 2022: jump-dev/benchmarks contributors
//
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE.md file or at https://opensource.org/licenses/MIT.

// The repository activity page, docs/repositories/index.html. The charts are
// drawn with Plotly, themed from the colours in style.css.
//
// Data (written by `scripts/repositories.jl --update`):
//   summary.json                    {element id: number}
//   download_stats.json             {package: {dates, requests}}
//   contributor_prs_over_time.json  {dates, counts: [[all, new], ...]}
//   data.json                       {package: [{is_pr, date, type, user}]},
//                                   with type "opened" or "closed"

"use strict";

// The series shown when the page loads. The others are in the legend.
const VISIBLE_DOWNLOADS = new Set(["JuMP.jl", "HiGHS.jl"]);
const VISIBLE_PACKAGES = new Set(["JuMP.jl", "MathOptInterface.jl"]);
const VISIBLE_USERS = new Set(["odow", "mlubin", "blegat"]);

// The window, in days, of the moving average of downloads.
const DOWNLOAD_WINDOW = 28;

// The initial y-axis range of the downloads chart.
const DOWNLOAD_RANGE = [0, 100_000];

// Colours after the four series colours of style.css, for the charts with
// many series. They are mid-tones, so they read on both surfaces.
const EXTRA_COLORS = ["#9558b2", "#cb3c33", "#1a9aa8", "#8c564b"];

// ---------------------------------------------------------------- utilities

async function loadJSON(file) {
  const response = await fetch(file);
  if (!response.ok) throw new Error(`could not load ${file}: ${response.status}`);
  return response.json();
}

// Dates are YYYY-MM-DD strings, handled in UTC throughout.
function isoDate(d) {
  return d.toISOString().slice(0, 10);
}

function nextDay(date) {
  const d = new Date(date + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + 1);
  return isoDate(d);
}

const TODAY = isoDate(new Date());

// A step series with a value on every day, so that the stacked charts line up.
class DailySeries {
  constructor() {
    this.x = [];
    this.y = [];
  }
  // Set the value from `date` onwards, carrying the previous value forward
  // over any gap.
  set(date, value) {
    const n = this.x.length;
    if (n > 0 && this.x[n - 1] === date) {
      this.y[n - 1] = value;
      return;
    }
    if (n > 0) {
      for (let d = nextDay(this.x[n - 1]); d < date; d = nextDay(d)) {
        this.x.push(d);
        this.y.push(this.y[n - 1]);
      }
    }
    this.x.push(date);
    this.y.push(value);
  }
}

function legendOnly(trace, visible) {
  if (!visible.has(trace.name)) trace.visible = "legendonly";
  return trace;
}

// Keys ordered by a numeric score, largest first, so the legend and the
// colours start with the busiest packages and users.
function byDescending(keys, score) {
  return [...keys].sort((a, b) => score(b) - score(a) || a.localeCompare(b));
}

// ---------------------------------------------------------------- series

// The number of issues (or pull requests) of `events` that are open on each
// day or, if `cumulative`, that have been opened by each day.
function countOpened(name, events, isPR, cumulative) {
  const series = new DailySeries();
  let n = 0;
  for (const e of events) {
    if (e.is_pr !== isPR) continue;
    if (e.type === "opened") n++;
    else if (!cumulative) n--;
    else continue;
    series.set(e.date.slice(0, 10), n);
  }
  series.set(TODAY, n);
  return { name, x: series.x, y: series.y, stackgroup: "one", line: { width: 1 } };
}

// The number of unique users that have opened an issue (or pull request) in
// `events` by each day.
function countUsers(name, events, isPR) {
  const series = new DailySeries();
  const users = new Set();
  for (const e of events) {
    if (e.is_pr !== isPR || e.type !== "opened" || users.has(e.user)) continue;
    users.add(e.user);
    series.set(e.date.slice(0, 10), users.size);
  }
  series.set(TODAY, users.size);
  return { name, x: series.x, y: series.y, line: { width: 2 } };
}

// {package: events} to {user: events}, in date order.
function eventsByUser(data) {
  const out = {};
  for (const events of Object.values(data)) {
    for (const e of events) (out[e.user] ??= []).push(e);
  }
  for (const events of Object.values(out)) {
    events.sort((a, b) => a.date.localeCompare(b.date));
  }
  return out;
}

// The mean daily downloads over the trailing window, scaled to a month.
function rollingAverage(dates, requests) {
  const ms = (d) => Date.parse(d + "T00:00:00Z");
  const window = DOWNLOAD_WINDOW * 86400e3;
  const result = [];
  let start = 0;
  let sum = 0;
  for (let i = 0; i < requests.length; i++) {
    sum += requests[i];
    while (ms(dates[start]) < ms(dates[i]) - window) sum -= requests[start++];
    result.push((30.42 * sum) / (i - start + 1));
  }
  return result;
}

// ---------------------------------------------------------------- theme

function cssVar(name) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

// The Plotly layout of every chart, from the colours of the current theme.
function themeLayout() {
  const axis = {
    gridcolor: cssVar("--grid"),
    linecolor: cssVar("--baseline"),
    zerolinecolor: cssVar("--baseline"),
    tickfont: { color: cssVar("--text-2") },
    automargin: true,
  };
  return {
    paper_bgcolor: "rgba(0,0,0,0)",
    plot_bgcolor: "rgba(0,0,0,0)",
    font: { family: getComputedStyle(document.body).fontFamily, size: 12, color: cssVar("--text-2") },
    colorway: [1, 2, 3, 4].map((i) => cssVar(`--series-${i}`)).concat(EXTRA_COLORS),
    margin: { l: 8, r: 8, t: 8, b: 8 },
    hovermode: "x unified",
    hoverlabel: {
      bgcolor: cssVar("--surface"),
      bordercolor: cssVar("--border"),
      font: { color: cssVar("--text") },
    },
    // Plotly reverses the legend of stacked charts. Keep the order of the
    // traces, busiest first, on every chart.
    legend: { font: { color: cssVar("--text-2") }, itemdoubleclick: "toggleothers", traceorder: "normal" },
    xaxis: { ...axis, type: "date" },
    yaxis: { ...axis, rangemode: "tozero" },
  };
}

const charts = [];

function merged(layout) {
  const theme = themeLayout();
  return {
    ...theme,
    ...layout,
    legend: { ...theme.legend, ...layout.legend },
    xaxis: { ...theme.xaxis, ...layout.xaxis },
    yaxis: { ...theme.yaxis, ...layout.yaxis },
  };
}

function plot(id, traces, layout = {}) {
  const div = document.getElementById(id);
  charts.push({ div, layout });
  return Plotly.newPlot(div, traces, merged(layout), {
    responsive: true,
    displaylogo: false,
    modeBarButtonsToRemove: ["select2d", "lasso2d"],
  });
}

// Redraw with the new colours when the colour scheme changes, keeping the
// series that the reader has shown or hidden and the current zoom.
window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
  for (const { div, layout } of charts) {
    const next = merged(layout);
    next.xaxis.range = div.layout.xaxis.range;
    next.yaxis.range = div.layout.yaxis.range;
    Plotly.react(div, div.data, next);
  }
});

// ---------------------------------------------------------------- charts

function yTitle(text) {
  return { yaxis: { title: { text } } };
}

async function summary() {
  const data = await loadJSON("summary.json");
  for (const [id, value] of Object.entries(data)) {
    const el = document.getElementById(id);
    if (el) el.textContent = Number(value).toLocaleString("en-US");
  }
}

async function downloads() {
  const data = await loadJSON("download_stats.json");
  const total = {};
  for (const [name, d] of Object.entries(data)) total[name] = d.requests.reduce((a, b) => a + b, 0);
  const traces = byDescending(Object.keys(data), (k) => total[k]).map((name) =>
    legendOnly(
      { name, x: data[name].dates, y: rollingAverage(data[name].dates, data[name].requests), line: { width: 2 } },
      VISIBLE_DOWNLOADS,
    ),
  );
  await plot("chart_download_statistics", traces, {
    yaxis: { title: { text: "Downloads per month" }, range: DOWNLOAD_RANGE },
  });
}

async function prActivity() {
  const data = await loadJSON("contributor_prs_over_time.json");
  const traces = [
    { name: "New contributors", type: "bar", x: data.dates, y: data.counts.map((c) => c[1]) },
    { name: "Existing contributors", type: "bar", x: data.dates, y: data.counts.map((c) => c[0] - c[1]) },
  ];
  await plot("chart_pr_activity", traces, {
    ...yTitle("Pull requests opened"),
    barmode: "stack",
    bargap: 0.15,
    legend: { orientation: "h", x: 0, y: 1.08 },
  });
}

async function activity() {
  const data = await loadJSON("data.json");
  const users = eventsByUser(data);
  const packages = byDescending(Object.keys(data), (k) => data[k].length);
  const people = byDescending(Object.keys(users), (k) => users[k].length);
  const perPackage = [
    ["chart_count_open_issues", "Open issues", (k) => countOpened(k, data[k], false, false)],
    ["chart_count_open_pull_requests", "Open pull requests", (k) => countOpened(k, data[k], true, false)],
    ["chart_cumulative_count_open_issues", "Issues opened", (k) => countOpened(k, data[k], false, true)],
    ["chart_cumulative_count_open_pull_requests", "Pull requests opened", (k) => countOpened(k, data[k], true, true)],
    ["chart_count_users_open_issues", "Users", (k) => countUsers(k, data[k], false)],
    ["chart_count_users_open_pull_requests", "Users", (k) => countUsers(k, data[k], true)],
  ];
  for (const [id, title, series] of perPackage) {
    await plot(id, packages.map((k) => legendOnly(series(k), VISIBLE_PACKAGES)), yTitle(title));
  }
  const perUser = [
    ["chart_unique_users_open_issues", "Issues opened", false],
    ["chart_unique_users_open_pull_requests", "Pull requests opened", true],
  ];
  for (const [id, title, isPR] of perUser) {
    const traces = people.map((k) => legendOnly(countOpened(k, users[k], isPR, true), VISIBLE_USERS));
    await plot(id, traces, yTitle(title));
  }
}

for (const load of [summary, downloads, prActivity, activity]) {
  load().catch((err) => console.error(err));
}
