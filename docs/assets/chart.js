/* Copyright (c) 2022: jump-dev/benchmarks contributors
 *
 * Use of this source code is governed by an MIT-style license that can be found
 * in the LICENSE.md file or at https://opensource.org/licenses/MIT.
 *
 * SVG chart scaffolding used by app.js: elements, axes, paths, the crosshair
 * with its tooltip, hover wiring, legends, the line chart over runs and the
 * sparkline in tables. Loaded before app.js; uses h() from app.js at render
 * time.
 */
"use strict";

const SVG_NS = "http://www.w3.org/2000/svg";
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function svgEl(tag, attrs, text) {
  const e = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs || {})) if (v != null) e.setAttribute(k, v);
  if (text != null) e.textContent = text;
  return e;
}

// Tick step for an axis spanning `span`: 1, 2 or 5 times a power of ten,
// giving about four steps.
function niceStep(span) {
  const raw = span / 4, pow = 10 ** Math.floor(Math.log10(raw)), frac = raw / pow;
  return pow * (frac <= 1 ? 1 : frac <= 2 ? 2 : frac <= 5 ? 5 : 10);
}

// A y axis fitted to the data rather than anchored at zero, as {lo, hi, step}:
// one tick of head room on each side (but never below zero), so a flat series
// is not drawn on the frame. Nulls are ignored.
function fittedAxis(values) {
  const present = values.filter((v) => v != null && Number.isFinite(v));
  const dlo = present.length ? Math.min(...present) : 0, dhi = present.length ? Math.max(...present) : 1;
  const step = niceStep(Math.max(dhi - dlo, Math.abs(dhi) * 0.02, 1e-9));
  const lo = Math.max(0, Math.floor(dlo / step) * step - (dlo === Math.floor(dlo / step) * step ? step : 0));
  const hi = Math.ceil(dhi / step) * step + (dhi === Math.ceil(dhi / step) * step ? step : 0);
  return { lo, hi, step };
}

// Horizontal grid lines from lo to hi by step, labelled at the left margin.
function yGrid(lo, hi, step, y, P, W, label) {
  const g = svgEl("g", { class: "axis" });
  for (let k = 0; lo + k * step <= hi + 1e-9 * step; k++) {
    const v = lo + k * step;
    g.append(svgEl("line", { x1: P.l, x2: W - P.r, y1: y(v), y2: y(v) }));
    g.append(svgEl("text", { x: P.l - 6, y: y(v) + 4, "text-anchor": "end" }, label(v)));
  }
  return g;
}

// Rotated y-axis title in the left margin, centred on the plot area.
function yAxisTitle(text, P, H) {
  const mid = P.t + (H - P.t - P.b) / 2;
  return svgEl("text", { class: "axis-title", x: 14, y: mid, "text-anchor": "middle", transform: `rotate(-90 14 ${mid})` }, text);
}

// "M x y L x y ..." through the values with x(i), y(v); the line breaks at a null.
function linePath(values, x, y) {
  let d = "", pen = false;
  values.forEach((v, i) => {
    if (v == null || !Number.isFinite(v)) { pen = false; return; }
    d += (pen ? " L" : "M") + x(i).toFixed(1) + " " + y(v).toFixed(1);
    pen = true;
  });
  return d;
}

// Position of a mouse event in the viewBox units of an svg.
function svgPoint(svg, e, W, H) {
  const box = svg.getBoundingClientRect();
  return { x: (e.clientX - box.left) / box.width * W, y: (e.clientY - box.top) / box.height * H };
}

// Tooltip next to the pointer, on the side with more room.
function placeTip(tip, wrap, clientX, clientY) {
  const box = wrap.getBoundingClientRect();
  const left = clientX - box.left;
  tip.style.display = "block";
  tip.style.left = `${left > box.width / 2 ? left - 12 - 220 : left + 12}px`;
  tip.style.top = `${Math.max(0, clientY - box.top - 20)}px`;
}

// Vertical hairline from y1 to y2 with one dot per colour, hidden until
// show(x, ys) is called; a null in ys hides that dot.
function crosshair(svg, y1, y2, colors, r = 4) {
  const g = svgEl("g", { class: "crosshair", style: "display:none" });
  const hair = svgEl("line", { y1, y2 });
  g.append(hair);
  const dots = colors.map((c) => { const d = svgEl("circle", { r, class: "pt", fill: c }); g.append(d); return d; });
  svg.append(g);
  return {
    show(x, ys) {
      g.style.display = "";
      hair.setAttribute("x1", x); hair.setAttribute("x2", x);
      dots.forEach((d, j) => {
        d.style.display = ys[j] == null ? "none" : "";
        d.setAttribute("cx", x);
        if (ys[j] != null) d.setAttribute("cy", ys[j]);
      });
    },
    hide() { g.style.display = "none"; },
  };
}

// Transparent, focusable rectangle over the plot area that receives the
// pointer and keyboard events. Appended last so it sits on top.
function hitRect(svg, x, y, width, height, pointer = false) {
  const r = svgEl("rect", { x, y, width, height, fill: "transparent", tabindex: 0, style: pointer ? "cursor:pointer" : null });
  svg.append(r);
  return r;
}

// Wire a hit target: move(e) on mouse move, focus() when tabbed to, hide() on
// leave and blur, and if open(e) returns a hash, a click (or Enter, with no
// event) navigates there.
function hoverEvents(hit, { move, focus, hide, open }) {
  hit.addEventListener("mousemove", move);
  hit.addEventListener("focus", focus);
  hit.addEventListener("mouseleave", hide);
  hit.addEventListener("blur", hide);
  if (open) {
    hit.addEventListener("click", (e) => { const to = open(e); if (to) location.hash = to; });
    hit.addEventListener("keydown", (e) => { if (e.key === "Enter") { const to = open(null); if (to) location.hash = to; } });
  }
}

// One swatch per series.
function legend(series) {
  return h("div", { class: "legend" }, series.map((s) =>
    h("span", null, h("span", { class: "swatch", style: `background: ${s.color}` }), s.label)));
}

// "Nov 2026" from an ISO date.
function fmtMonth(iso) { const d = (iso || "").slice(0, 10); return d ? `${MONTHS[Number(d.slice(5, 7)) - 1]} ${d.slice(0, 4)}` : ""; }

// Lines over the runs, one point per run at equal spacing (runs are mostly
// monthly, and a few days apart otherwise, so a time axis would stack them).
//   runs:   [{id, date, ...}] oldest first
//   series: [{label, color, value(run) -> number | null}]
//   opts:   {fmt(v), yTitle, open(run) -> hash, head(run) -> node, unit}
// Several series get a legend. The tooltip carries every series at the
// hovered run and its change from the first run with a value. The y axis is
// fitted to the data rather than anchored at zero: the point of the chart is
// the change between runs, which a zero baseline would flatten.
const LC_W = 640, LC_H = 240, LC_P = { l: 64, r: 30, t: 14, b: 30 };
function lineChart(runs, series, opts) {
  const n = runs.length;
  const values = series.map((s) => runs.map((r) => { const v = s.value(r); return v == null || !Number.isFinite(v) ? null : v; }));
  const wrap = h("div", { class: "chart-wrap" });
  const svg = svgEl("svg", { viewBox: `0 0 ${LC_W} ${LC_H}`, role: "img" });
  const plotW = LC_W - LC_P.l - LC_P.r, plotH = LC_H - LC_P.t - LC_P.b;
  const all = values.flat().filter((v) => v != null);
  if (!all.length) {
    svg.append(svgEl("text", { class: "empty", x: LC_W / 2, y: LC_H / 2, "text-anchor": "middle" }, "No data in this range"));
    wrap.append(svg);
    return wrap;
  }
  const { lo: yMin, hi: yMax, step } = fittedAxis(all);
  const band = plotW / Math.max(n, 1);
  const x = (i) => LC_P.l + i * band + band / 2;
  const y = (v) => LC_P.t + plotH - ((v - yMin) / (yMax - yMin)) * plotH;
  const tickFmt = opts.tickFmt || opts.fmt;
  svg.append(yGrid(yMin, yMax, step, y, LC_P, LC_W, tickFmt));
  // Date labels on every k-th run so they do not collide; the newest is
  // always labelled.
  const every = Math.max(1, Math.ceil(n / Math.floor(plotW / 72)));
  const xt = svgEl("g", { class: "axis" });
  runs.forEach((r, i) => {
    if ((n - 1 - i) % every) return;
    xt.append(svgEl("text", { x: x(i), y: LC_H - 10, "text-anchor": "middle" }, fmtMonth(r.date)));
  });
  svg.append(xt);
  if (opts.yTitle) svg.append(yAxisTitle(opts.yTitle, LC_P, LC_H));
  svg.append(svgEl("line", { x1: LC_P.l, x2: LC_W - LC_P.r, y1: y(yMin), y2: y(yMin), class: "baseline" }));
  series.forEach((s, j) => {
    svg.append(svgEl("path", { d: linePath(values[j], x, y), class: "line", stroke: s.color }));
    values[j].forEach((v, i) => { if (v != null) svg.append(svgEl("circle", { class: "pt", cx: x(i), cy: y(v), r: 3, fill: s.color })); });
  });
  // Crosshair, tooltip, click-through to the run.
  const tip = h("div", { class: "tooltip" });
  const cross = crosshair(svg, LC_P.t, y(yMin), series.map((s) => s.color), 5);
  const hit = hitRect(svg, LC_P.l, LC_P.t, plotW, plotH, !!opts.open);
  const firstValue = (j) => values[j].find((v) => v != null);
  let current = n - 1;
  const showAt = (i, clientX, clientY) => {
    current = i;
    cross.show(x(i), values.map((vs) => (vs[i] == null ? null : y(vs[i]))));
    placeTip(tip, wrap, clientX, clientY);
    const r = runs[i];
    tip.replaceChildren(h("div", null,
      h("div", { class: "tip-head" }, opts.head ? opts.head(r) : h("b", null, r.id)),
      series.map((s, j) => {
        const v = values[j][i], f = firstValue(j);
        return h("div", { class: "tip-row" },
          h("span", { class: "key", style: `background: ${s.color}` }),
          h("b", null, v == null ? "–" : opts.fmt(v)), " ",
          h("span", { class: "muted" }, series.length === 1 ? opts.unit || "" : s.label), " ",
          v != null && f != null && f > 0 && values[j].indexOf(f) !== i ? deltaEl(v / f) : null);
      }),
      i > 0 ? h("div", { class: "muted small" }, "change since the first run shown") : null));
  };
  const nearest = (e) => Math.max(0, Math.min(n - 1, Math.round((svgPoint(svg, e, LC_W, LC_H).x - LC_P.l - band / 2) / band)));
  hoverEvents(hit, {
    move: (e) => showAt(nearest(e), e.clientX, e.clientY),
    focus: () => { const b = hit.getBoundingClientRect(); showAt(n - 1, b.right - 40, b.top); },
    hide: () => { tip.style.display = "none"; cross.hide(); },
    open: opts.open ? (e) => opts.open(runs[e ? nearest(e) : current]) : null,
  });
  wrap.append(svg, tip);
  if (series.length > 1) wrap.append(legend(series));
  return wrap;
}

// A small line of the values (nulls break it) with a dot on the last one, for
// a table cell. The y range is fitted to the values.
function sparkline(values, w = 120, hgt = 24) {
  const svg = svgEl("svg", { class: "spark", viewBox: `0 0 ${w} ${hgt}`, "aria-hidden": "true" });
  const present = values.filter((v) => v != null && Number.isFinite(v));
  if (present.length < 2) return svg;
  const lo = Math.min(...present), hi = Math.max(...present);
  const n = values.length;
  const x = (i) => 3 + (w - 6) * (n > 1 ? i / (n - 1) : 0);
  const y = (v) => hi === lo ? hgt / 2 : hgt - 3 - (hgt - 6) * (v - lo) / (hi - lo);
  svg.append(svgEl("path", { d: linePath(values, x, y) }));
  let last = n - 1;
  while (last >= 0 && (values[last] == null || !Number.isFinite(values[last]))) last--;
  if (last >= 0) svg.append(svgEl("circle", { cx: x(last), cy: y(values[last]), r: 2 }));
  return svg;
}
