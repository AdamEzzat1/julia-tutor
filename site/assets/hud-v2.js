// HUD background, draft 2 ("Analysis"): a Jarvis-style display that locks onto,
// scans and annotates the things this site teaches: a Kepler orbit, the Lorenz
// system, Newton's method, a convergence-order fit, Euler's stability disk, a
// sparse stencil, a symdiff expression tree, multiple dispatch, BKT mastery.
//
// House rules, same as the tutor's: every number shown is either computed here,
// live, from the stated equation, or copied from a recorded file in the repo (the
// file is named next to it). Nothing is random; the sequence is fixed.
//
// Legibility: the HUD is knocked back to KNOCK_KEEP of its strength behind every
// block of text, figure and table on screen (re-measured on scroll and resize),
// and each scan is placed where it overlaps the least content.
// Pure client-side canvas, so it runs on GitHub Pages. Colours are the site's
// tokens (web/src/styles.css) and follow Quarto's light/dark toggle.
(() => {
  "use strict";
  if (window.__jtHud) return;
  window.__jtHud = true;

  // ---- settings --------------------------------------------------------------
  const FPS = 30;
  const KNOCK_KEEP = 0.22; // share of the HUD left visible behind text/figures
  const CONTENT = "main h1, main h2, main h3, main h4, main h5, main p, main li, main pre, main table, " +
    "main figure, main img, main svg, main blockquote, main dl, main .callout, main button, main input, " +
    "main select, main textarea, .quarto-title-block, .page-intro, .nav-footer, " +
    // Quarto's sidebars and table of contents live outside <main>
    "#TOC li, #TOC h2, #quarto-sidebar li, #quarto-sidebar .sidebar-title, #quarto-margin-sidebar li, " +
    "#quarto-margin-sidebar h2, .sidebar .quarto-alternate-formats, .sidebar .toc-actions";
  // Course sizes: units per course, from site/data/courses.json (web/src/hud.test.ts checks this).
  const COURSES = [["CORE", 20, "ready"], ["SCIENCE", 9, "ready"], ["SCICOMP", 13, "ready"], ["SCIML", 6, "in-progress"], ["QUANTUM", 13, "in-progress"]];
  // Recorded values, shown with the file they come from.
  const TICKER = [
    "julia 1.10.13 · JULIA_VERSION",
    "alloc dp54_step! = 0 · odeint/measure_baseline.toml",
    "alloc solve_adaptive = 18 · odeint/measure_baseline.toml",
    "conv_order 5.18 · odeint/case/report_fixtures.toml",
    "tol_slope 1.03 · odeint/case/report_fixtures.toml",
    "JET 0.9.14 · symdiff/measure_baseline.toml",
    "rewrite_innermost::Any · symdiff/measure_baseline.toml",
    "JT001 vector-any-literal · src/rules",
    "JT002 abstract-field-type · src/rules",
    "JT003 mutates-without-bang · src/rules",
    "JT005 one-to-length-loop · src/rules",
    "JT006 float-literal-equality · src/rules",
    "JT007 nonconst-global-read · src/rules",
  ];

  // ---- canvas --------------------------------------------------------------
  const canvas = document.createElement("canvas");
  canvas.className = "jt-hud";
  canvas.setAttribute("aria-hidden", "true");
  document.body.prepend(canvas);
  const ctx = canvas.getContext("2d");
  const hexLayer = document.createElement("canvas");
  const hctx = hexLayer.getContext("2d");

  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  const params = new URLSearchParams(location.search);
  const frozen = params.has("hudt") ? parseFloat(params.get("hudt")) || 0 : null; // test hook: a still frame at t
  let W = 0, H = 0, dpr = 1, raf = 0, last = 0, scale = 1;
  const t0 = performance.now();
  let pal = {};

  function hexToRgb(s, fb) {
    const m = /^#?([0-9a-f]{6})$/i.exec((s || "").trim());
    if (!m) return fb;
    const n = parseInt(m[1], 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  function readPalette() {
    const cs = getComputedStyle(document.body);
    const dark = document.body.classList.contains("quarto-dark");
    const tok = (n, d, l) => hexToRgb(cs.getPropertyValue(n), dark ? d : l);
    pal = {
      dark,
      P: tok("--jt-purple", [192, 138, 224], [138, 79, 174]),
      B: tok("--jt-blue", [138, 162, 245], [54, 87, 200]),
      G: tok("--jt-green", [108, 195, 91], [47, 125, 34]),
      A: tok("--jt-amber", [224, 169, 74], [154, 101, 18]),
      R: tok("--jt-red", [236, 116, 104], [184, 53, 45]),
      M: tok("--jt-muted", [157, 149, 171], [119, 111, 130]),
      k: dark ? 1 : 0.7,
    };
    drawHexLayer();
  }
  const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${Math.max(0, Math.min(1, a * pal.k * scale))})`;
  const MONO = '"JetBrains Mono", ui-monospace, monospace';
  function font(px, weight = 500) {
    ctx.font = `${weight} ${px}px ${MONO}`;
    if ("letterSpacing" in ctx) ctx.letterSpacing = px <= 10 ? "0.08em" : "0.12em";
  }

  // Deterministic sequence (no Math.random anywhere).
  function lcg(seed) { let s = seed >>> 0; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); }

  // ---- content rects: where the HUD must stay quiet --------------------------
  let rects = [], rectsDirty = true, lastRectScan = 0, rectsVersion = 0;
  const PANELS = "main div, main section, main article, main aside, main a, main details";
  function solid(cs) {
    const m = cs.backgroundColor.match(/[\d.]+/g);
    return (m && (m.length < 4 || +m[3] > 0.3)) || cs.backgroundImage !== "none" || parseFloat(cs.borderTopWidth) > 0;
  }
  function scanRects(now) {
    rects = [];
    const add = (b) => {
      if (b.width < 2 || b.height < 2 || b.bottom < 0 || b.top > H || b.right < 0 || b.left > W) return false;
      rects.push([b.left - 10, b.top - 6, b.width + 20, b.height + 12]);
      return true;
    };
    for (const el of document.querySelectorAll(CONTENT)) { add(el.getBoundingClientRect()); if (rects.length > 500) break; }
    // cards and panels: opaque boxes would hide a scan placed behind them
    for (const el of document.querySelectorAll(PANELS)) {
      const b = el.getBoundingClientRect();
      if (b.width < 60 || b.height < 30 || b.bottom < 0 || b.top > H) continue;
      if (solid(getComputedStyle(el))) add(b);
      if (rects.length > 800) break;
    }
    rectsDirty = false; lastRectScan = now; rectsVersion++;
  }
  function overlap(x, y, w, h) {
    let a = 0;
    for (const [rx, ry, rw, rh] of rects) {
      const ox = Math.min(x + w, rx + rw) - Math.max(x, rx), oy = Math.min(y + h, ry + rh) - Math.max(y, ry);
      if (ox > 0 && oy > 0) a += ox * oy;
    }
    return a;
  }
  function knockout() {
    if (!rects.length) return;
    const p = new Path2D();
    for (const [x, y, w, h] of rects) p.rect(x, y, w, h); // one path = union, so overlaps are not knocked twice
    ctx.save();
    ctx.globalCompositeOperation = "destination-out";
    ctx.filter = "blur(6px)"; // soft edge, so the dimming reads as depth, not boxes
    ctx.fillStyle = `rgba(0,0,0,${1 - KNOCK_KEEP})`;
    ctx.fill(p);
    ctx.restore();
  }

  // ---- layout ---------------------------------------------------------------
  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = window.innerWidth; H = window.innerHeight;
    for (const c of [canvas, hexLayer]) { c.width = Math.round(W * dpr); c.height = Math.round(H * dpr); }
    canvas.style.width = W + "px"; canvas.style.height = H + "px";
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    hctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    scale = W < 760 ? 0.7 : 1;
    rectsDirty = true;
    if (pal.P) drawHexLayer();
  }

  // Hex micro-texture, pre-rendered once per size/theme.
  const HEX = 22;
  function hexCenter(i, j) { return [i * HEX * 1.5, j * HEX * Math.sqrt(3) + (i % 2 ? HEX * Math.sqrt(3) / 2 : 0)]; }
  function hexPath(c, cx, cy, r) {
    c.beginPath();
    for (let k = 0; k < 6; k++) { const a = (Math.PI / 3) * k; c[k ? "lineTo" : "moveTo"](cx + r * Math.cos(a), cy + r * Math.sin(a)); }
    c.closePath();
  }
  function drawHexLayer() {
    hctx.clearRect(0, 0, W, H);
    hctx.strokeStyle = rgba(pal.B, pal.dark ? 0.05 : 0.06); hctx.lineWidth = 1;
    for (let i = 0; i * HEX * 1.5 < W + HEX; i++)
      for (let j = 0; j * HEX * 1.73 < H + HEX; j++) { const [x, y] = hexCenter(i, j); hexPath(hctx, x, y, HEX - 2); hctx.stroke(); }
  }
  function hexSparks(t) {
    // a fixed sequence of cells light up and fade (about one every 0.7 s)
    const cols = Math.ceil(W / (HEX * 1.5)), rows = Math.ceil(H / (HEX * 1.73));
    const n = Math.floor(t / 0.7);
    for (let k = Math.max(0, n - 3); k <= n; k++) {
      const r = lcg(k * 7919 + 13);
      const i = Math.floor(r() * cols), j = Math.floor(r() * rows);
      const age = t - k * 0.7, a = Math.max(0, 1 - age / 2.1);
      if (a <= 0) continue;
      const [x, y] = hexCenter(i, j);
      hexPath(ctx, x, y, HEX - 2);
      ctx.fillStyle = rgba(k % 3 ? pal.B : pal.P, 0.07 * a); ctx.fill();
      ctx.strokeStyle = rgba(k % 3 ? pal.B : pal.P, 0.35 * a); ctx.lineWidth = 1; ctx.stroke();
    }
  }

  // ---- small drawing helpers --------------------------------------------------
  const ease = (x) => 1 - Math.pow(1 - Math.max(0, Math.min(1, x)), 3);
  const easeBack = (x) => { x = Math.max(0, Math.min(1, x)); const c = 1.70158; return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2); };
  const clamp01 = (x) => Math.max(0, Math.min(1, x));
  function line(x0, y0, x1, y1) { ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke(); }
  function poly(pts, n, close) {
    if (n < 2) return;
    ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < n; i++) ctx.lineTo(pts[i][0], pts[i][1]);
    if (close) ctx.closePath();
    ctx.stroke();
  }
  function glow(c, on) {
    if (on && pal.dark) { ctx.shadowColor = rgba(c, 0.8); ctx.shadowBlur = 8; } else { ctx.shadowBlur = 0; }
  }
  function fit(pts, box, pad = 0.08) {
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (const [x, y] of pts) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
    const s = Math.min(box.w * (1 - 2 * pad) / (x1 - x0 || 1), box.h * (1 - 2 * pad) / (y1 - y0 || 1));
    const ox = box.x + box.w / 2 - s * (x0 + x1) / 2, oy = box.y + box.h / 2 + s * (y0 + y1) / 2;
    return ([x, y]) => [ox + s * x, oy - s * y];
  }
  function typed(text, p) { return text.slice(0, Math.ceil(text.length * clamp01(p))); }
  const fmt = (x, d = 4) => (Math.abs(x) < 1e-3 && x !== 0 ? x.toExponential(1) : x.toFixed(d)).replace("-", "−");

  // Lock-on brackets: snap in from large, blink twice.
  function brackets(b, p, c) {
    const s = 1 + 0.35 * (1 - easeBack(p)), cx = b.x + b.w / 2, cy = b.y + b.h / 2;
    const w = b.w * s, h = b.h * s, L = Math.min(22, b.w * 0.12);
    const blink = p < 1 ? 1 : 1;
    ctx.strokeStyle = rgba(c, 0.7 * blink * clamp01(p * 3)); ctx.lineWidth = 1.5;
    for (const [sx, sy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
      const x = cx + sx * w / 2, y = cy + sy * h / 2;
      ctx.beginPath(); ctx.moveTo(x - sx * L, y); ctx.lineTo(x, y); ctx.lineTo(x, y - sy * L); ctx.stroke();
    }
  }
  let labelsUsed = [];
  // Leader-line callout: dot on the subject, diagonal, shelf, typed label.
  function callout(ax, ay, side, dy, text, p, c, box) {
    if (p <= 0) return;
    font(10.5, 500);
    const tw = ctx.measureText(text).width + 8;
    // pick the side where the label covers the least content (off-screen counts as covered);
    // if both sides are crowded, keep the dot and leave the label out
    const cover = (sd) => {
      const lx0 = sd > 0 ? box.x + box.w + 14 : box.x - 14 - tw, ly0 = ay + dy - 14;
      const off = Math.max(0, -lx0) + Math.max(0, lx0 + tw - W);
      return (overlap(lx0, ly0, tw, 16) + off * 16) / (tw * 16);
    };
    const cs = cover(side), co = cover(-side);
    if (co < cs) side = -side;
    const crowded = Math.min(cs, co) > 0.12;
    const ex = side > 0 ? box.x + box.w + 14 : box.x - 14;
    let ey = ay + dy;
    // stack labels that would collide with an earlier one in this scan
    const lx = side > 0 ? ex : ex - tw;
    for (let tries = 0; tries < 12 && labelsUsed.some(([x, y, w, h]) => lx < x + w && lx + tw > x && ey - 14 < y + h && ey > y); tries++) ey += 15;
    labelsUsed.push([lx, ey - 14, tw, 14]);
    const kx = ax + side * Math.min(Math.abs(ex - ax) * 0.5, 30);
    const q = ease(p / 0.45);
    ctx.fillStyle = rgba(c, 0.9); ctx.beginPath(); ctx.arc(ax, ay, 2.2, 0, 7); ctx.fill();
    ctx.strokeStyle = rgba(c, 0.55); ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(ax, ay);
    const mx = ax + (kx - ax) * Math.min(1, q * 2), my = ay + (ey - ay) * Math.min(1, q * 2);
    ctx.lineTo(mx, my);
    if (q > 0.5) ctx.lineTo(kx + (ex - kx) * ((q - 0.5) * 2), ey);
    ctx.stroke();
    if (p > 0.45 && !crowded) {
      font(10.5, 500); ctx.textBaseline = "bottom"; ctx.textAlign = side > 0 ? "left" : "right";
      ctx.fillStyle = rgba(c, 0.92);
      ctx.fillText(typed(text, (p - 0.45) / 0.55), ex + side * 4, ey - 2);
    }
  }

  // ---- specimens: real maths, computed once ---------------------------------
  function rk4(f, y, h) {
    const k1 = f(y), k2 = f(y.map((v, i) => v + h / 2 * k1[i])), k3 = f(y.map((v, i) => v + h / 2 * k2[i])), k4 = f(y.map((v, i) => v + h * k3[i]));
    return y.map((v, i) => v + h / 6 * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i]));
  }

  const SPECIMENS = [];

  // 1. Kepler orbit, e = 0.5, a = 1 (case-odeint). Velocity Verlet with a step that
  //    shrinks near perihelion; dots mark steps.
  SPECIMENS.push((() => {
    const e = 0.5; let x = 1 - e, y = 0, vx = 0, vy = Math.sqrt((1 + e) / (1 - e)), t = 0;
    const acc = (x, y) => { const r3 = Math.pow(x * x + y * y, 1.5); return [-x / r3, -y / r3]; };
    const E0 = 0.5 * (vx * vx + vy * vy) - 1 / Math.hypot(x, y);
    const pts = [[x, y]]; let [ax, ay] = acc(x, y);
    while (t < 2 * Math.PI) {
      const h = 0.045 * Math.pow(Math.hypot(x, y), 1.5);
      vx += h / 2 * ax; vy += h / 2 * ay; x += h * vx; y += h * vy;
      [ax, ay] = acc(x, y); vx += h / 2 * ax; vy += h / 2 * ay; t += h; pts.push([x, y]);
    }
    const E1 = 0.5 * (vx * vx + vy * vy) - 1 / Math.hypot(x, y);
    return {
      name: "KEPLER ORBIT", src: "case-odeint · e = 0.5, a = 1", c: "B",
      draw(b, p, cur) {
        const m = fit(pts.concat([[0, 0]]), b), q = pts.map(m), n = Math.floor(q.length * p);
        ctx.strokeStyle = rgba(pal.B, 0.75); ctx.lineWidth = 1.4; glow(pal.B, true); poly(q, n); glow(pal.B, false);
        ctx.fillStyle = rgba(pal.B, 0.55);
        for (let i = 0; i < n; i += 2) { ctx.beginPath(); ctx.arc(q[i][0], q[i][1], 1.3, 0, 7); ctx.fill(); }
        const [sx, sy] = m([0, 0]); ctx.fillStyle = rgba(pal.A, 0.8); ctx.beginPath(); ctx.arc(sx, sy, 3.5, 0, 7); ctx.fill();
        const peri = q[0], apo = m([-1.5, 0]);
        return [
          [peri[0], peri[1], 1, -22, `perihelion r = 0.5 · steps bunch up`, "B"],
          [apo[0], apo[1], -1, -22, `aphelion r = 1.5`, "B"],
          [sx, sy, 1, 34, `E = ${fmt(E0, 4)} · drift ${fmt(Math.abs(E1 - E0) / Math.abs(E0), 1)}`, "G"],
          [sx, sy, -1, 34, `${pts.length - 1} verlet_step! calls`, "P"],
        ];
      },
    };
  })());

  // 2. Lorenz system (unit 24: lorenz!), RK4 here; slowly rotating projection.
  SPECIMENS.push((() => {
    const s = 10, r = 28, bb = 8 / 3, f = ([x, y, z]) => [s * (y - x), x * (r - z) - y, x * y - bb * z];
    let u = [1, 0, 0]; for (let i = 0; i < 400; i++) u = rk4(f, u, 0.01);
    const pts = []; for (let i = 0; i < 2600; i++) { u = rk4(f, u, 0.01); pts.push(u); }
    return {
      name: "LORENZ ATTRACTOR", src: "unit 24 · lorenz!(du, u, p, t)", c: "P",
      draw(b, p, cur, t) {
        const a = t * 0.12, ca = Math.cos(a), sa = Math.sin(a);
        const proj = pts.map(([x, y, z]) => [x * ca - y * sa, z]);
        const m = fit(proj, b), q = proj.map(m), n = Math.floor(q.length * p);
        ctx.strokeStyle = rgba(pal.P, 0.6); ctx.lineWidth = 0.9; glow(pal.P, true); poly(q, n); glow(pal.P, false);
        const h = q[Math.max(0, n - 1)]; ctx.fillStyle = rgba(pal.P, 0.95); ctx.beginPath(); ctx.arc(h[0], h[1], 2.5, 0, 7); ctx.fill();
        const top = q.reduce((a, v) => (v[1] < a[1] ? v : a), q[0]);
        return [
          [top[0], top[1], 1, -12, "σ = 10  ρ = 28  β = 8/3", "P"],
          [h[0], h[1], -1, 28, "course: Tsit5() · here: RK4, Δt = 0.01", "B"],
          [q[0][0], q[0][1], 1, 40, "chaotic: nearby starts diverge", "A"],
        ];
      },
    };
  })());

  // 3. Newton's method on f(x) = x² − 2 from x₀ = 1 (units 23, 25).
  SPECIMENS.push((() => {
    const it = [1]; for (let i = 0; i < 4; i++) { const x = it[i]; it.push(x - (x * x - 2) / (2 * x)); }
    const curve = []; for (let x = 0.6; x <= 2.2; x += 0.02) curve.push([x, x * x - 2]);
    return {
      name: "NEWTON ITERATION", src: "units 23, 25 · f(x) = x² − 2", c: "G",
      draw(b, p) {
        const m = fit(curve.concat([[0.6, -1.8], [2.2, 3]]), b);
        ctx.strokeStyle = rgba(pal.M, 0.45); ctx.lineWidth = 1; line(...m([0.6, 0]), ...m([2.2, 0]));
        ctx.strokeStyle = rgba(pal.B, 0.75); ctx.lineWidth = 1.4; glow(pal.B, true); poly(curve.map(m), Math.floor(curve.length * clamp01(p * 2))); glow(pal.B, false);
        const steps = Math.floor(clamp01((p - 0.4) / 0.6) * 4.999);
        ctx.strokeStyle = rgba(pal.G, 0.7); ctx.lineWidth = 1;
        for (let i = 0; i < steps; i++) {
          const x = it[i], y = x * x - 2;
          ctx.setLineDash([3, 3]); line(...m([x, 0]), ...m([x, y])); ctx.setLineDash([]);
          line(...m([x, y]), ...m([it[i + 1], 0]));
        }
        const k = Math.max(0, steps - 1), [px, py] = m([it[Math.min(steps, 4)], 0]);
        const out = [[px, py, 1, 26, `x${"₀₁₂₃₄"[Math.min(steps, 4)]} = ${it[Math.min(steps, 4)].toFixed(12)}`, "G"]];
        if (steps >= 3) out.push([...m([it[3], 0]), -1, -30, `|x₃ − √2| = ${Math.abs(it[3] - Math.SQRT2).toExponential(1)}`, "A"]);
        if (steps >= 4) out.push([...m([2, 2]), 1, 0, "quadratic: correct digits double", "B"]);
        return out;
      },
    };
  })());

  // 4. Convergence order: RK4 on y' = y over [0, 1], error vs h, least-squares slope.
  SPECIMENS.push((() => {
    const pts = [];
    for (let k = 2; k <= 7; k++) {
      const n = 1 << k, h = 1 / n; let y = [1];
      for (let i = 0; i < n; i++) y = rk4(([v]) => [v], y, h);
      pts.push([Math.log10(h), Math.log10(Math.abs(y[0] - Math.E))]);
    }
    const mx = pts.reduce((a, p) => a + p[0], 0) / pts.length, my = pts.reduce((a, p) => a + p[1], 0) / pts.length;
    const slope = pts.reduce((a, p) => a + (p[0] - mx) * (p[1] - my), 0) / pts.reduce((a, p) => a + (p[0] - mx) ** 2, 0);
    return {
      name: "CONVERGENCE ORDER", src: "unit 31 · log₁₀ error vs log₁₀ h", c: "B",
      draw(b, p) {
        const m = fit(pts, b, 0.14), q = pts.map(m);
        ctx.strokeStyle = rgba(pal.M, 0.4); ctx.lineWidth = 1;
        line(b.x + b.w * 0.08, b.y + b.h * 0.92, b.x + b.w * 0.92, b.y + b.h * 0.92); line(b.x + b.w * 0.08, b.y + b.h * 0.08, b.x + b.w * 0.08, b.y + b.h * 0.92);
        const n = Math.floor(q.length * clamp01(p * 1.6));
        ctx.fillStyle = rgba(pal.B, 0.9);
        for (let i = 0; i < n; i++) { ctx.beginPath(); ctx.arc(q[i][0], q[i][1], 3, 0, 7); ctx.fill(); }
        if (p > 0.6) {
          const a = m([pts[0][0], my + slope * (pts[0][0] - mx)]), z = m([pts[5][0], my + slope * (pts[5][0] - mx)]);
          const u = ease((p - 0.6) / 0.4);
          ctx.strokeStyle = rgba(pal.P, 0.8); ctx.lineWidth = 1.4; glow(pal.P, true); line(a[0], a[1], a[0] + (z[0] - a[0]) * u, a[1] + (z[1] - a[1]) * u); glow(pal.P, false);
        }
        return [
          [q[2][0], q[2][1], -1, -16, `fitted order p = ${slope.toFixed(2)} (RK4, live)`, "P"],
          [q[5][0], q[5][1], 1, -10, `h = 1/128 · err ${Math.pow(10, pts[5][1]).toExponential(1)}`, "B"],
          [q[0][0], q[0][1], 1, 22, "recorded dp54: conv_order 5.18", "G"],
        ];
      },
    };
  })());

  // 5. Forward Euler stability: |1 + hλ| ≤ 1 (unit 35, euler-overshoot).
  SPECIMENS.push((() => {
    const seq = [1]; for (let i = 0; i < 4; i++) seq.push(seq[i] * (1 - 2.5));
    return {
      name: "STABILITY REGION", src: "unit 35 · forward Euler, y' = λy", c: "R",
      draw(b, p) {
        const m = fit([[-3.2, -1.5], [0.6, 1.5]], b);
        const [cx, cy] = m([-1, 0]), [ex] = m([0, 0]), R = ex - cx;
        ctx.strokeStyle = rgba(pal.M, 0.4); ctx.lineWidth = 1; line(...m([-3.2, 0]), ...m([0.6, 0])); line(...m([0, -1.5]), ...m([0, 1.5]));
        ctx.strokeStyle = rgba(pal.G, 0.75); ctx.lineWidth = 1.4; glow(pal.G, true);
        ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2 * clamp01(p * 1.5)); ctx.stroke(); glow(pal.G, false);
        ctx.fillStyle = rgba(pal.G, 0.08); ctx.beginPath(); ctx.arc(cx, cy, R * clamp01(p * 1.5), 0, 7); ctx.fill();
        const good = m([-0.5, 0]), bad = m([-2.5, 0]);
        if (p > 0.5) {
          ctx.fillStyle = rgba(pal.G, 0.95); ctx.beginPath(); ctx.arc(good[0], good[1], 3.5, 0, 7); ctx.fill();
          ctx.fillStyle = rgba(pal.R, 0.95); ctx.beginPath(); ctx.arc(bad[0], bad[1], 3.5, 0, 7); ctx.fill();
        }
        return [
          [good[0], good[1], 1, -26, "hλ = −0.5 · inside: decays", "G"],
          [bad[0], bad[1], -1, -26, "hλ = −2.5 · outside: overshoots", "R"],
          [bad[0], bad[1], -1, 26, `yₙ: ${seq.map((v) => fmt(v, v % 1 ? 3 : 0)).join(", ")}`, "A"],
        ];
      },
    };
  })());

  // 6. Sparse pattern: 2-D Poisson, 5-point stencil, n = 8 (unit 33).
  SPECIMENS.push((() => {
    const n = 8, N = n * n, nz = [];
    for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) {
      const r = i * n + j; nz.push([r, r]);
      if (j > 0) nz.push([r, r - 1]); if (j < n - 1) nz.push([r, r + 1]);
      if (i > 0) nz.push([r, r - n]); if (i < n - 1) nz.push([r, r + n]);
    }
    return {
      name: "SPARSE PATTERN", src: "unit 33 · 2-D Poisson, 5-point stencil", c: "P",
      draw(b, p) {
        const S = Math.min(b.w, b.h) * 0.86, x0 = b.x + (b.w - S) / 2, y0 = b.y + (b.h - S) / 2, c = S / N;
        ctx.strokeStyle = rgba(pal.M, 0.35); ctx.lineWidth = 1; ctx.strokeRect(x0, y0, S, S);
        const k = Math.floor(nz.length * p);
        for (let i = 0; i < k; i++) {
          const [r, col] = nz[i];
          ctx.fillStyle = rgba(r === col ? pal.P : pal.B, r === col ? 0.95 : 0.7);
          ctx.fillRect(x0 + col * c, y0 + r * c, Math.max(1.5, c * 0.9), Math.max(1.5, c * 0.9));
        }
        const scanY = y0 + S * clamp01(p);
        ctx.strokeStyle = rgba(pal.B, 0.5 * (1 - clamp01((p - 0.95) * 20))); line(x0 - 6, scanY, x0 + S + 6, scanY);
        return [
          [x0 + S * 0.5, y0 + S * 0.5, 1, -40, `${N}×${N} · nnz = ${nz.length} (${(100 * nz.length / N / N).toFixed(1)}% filled)`, "P"],
          [x0 + c * (n + 0.5), y0 + c * 0.5, -1, -8, "bands at ±1 and ±n", "B"],
          [x0 + S * 0.9, y0 + S * 0.9, 1, 20, "kron(I, T) + kron(T, I)", "G"],
        ];
      },
    };
  })());

  // 7. symdiff: d/dx [sin(x) · x²], deriv recursing over the expression tree.
  SPECIMENS.push((() => {
    // node: [label, x, y, parent, rule]
    const N = [["Mul", 0, 0, -1, "deriv(::Mul): product rule"], ["Fn{sin}", -1, 1, 0, "dfn(::typeof(sin), u) = cos(u)"],
      ["Pow", 1, 1, 0, "deriv(::Pow): n·xⁿ⁻¹"], ["x", -1, 2, 1, ""], ["x", 0.6, 2, 2, ""], ["2", 1.4, 2, 2, ""]];
    const order = [3, 1, 4, 5, 2, 0]; // post-order: children before parents, as deriv recurses
    return {
      name: "SYMBOLIC DERIVATIVE", src: "project symdiff · d/dx [sin(x) · x²]", c: "G",
      draw(b, p) {
        const m = fit([[-1.6, 0.3], [1.9, -2.3]], b), pos = N.map(([, x, y]) => m([x, -y]));
        ctx.strokeStyle = rgba(pal.M, 0.5); ctx.lineWidth = 1;
        N.forEach(([, , , par], i) => { if (par >= 0 && p > 0.05) line(...pos[par], ...pos[i]); });
        const done = Math.floor(clamp01((p - 0.15) / 0.85) * order.length + 0.001);
        font(10, 600); ctx.textAlign = "center"; ctx.textBaseline = "middle";
        N.forEach(([lab], i) => {
          const ok = order.indexOf(i) < done, c = ok ? pal.G : pal.B;
          ctx.fillStyle = rgba(pal.dark ? [20, 18, 26] : [246, 242, 234], 0.9);
          ctx.strokeStyle = rgba(c, 0.85); ctx.lineWidth = 1.2; glow(c, ok);
          ctx.beginPath(); ctx.roundRect(pos[i][0] - 30, pos[i][1] - 10, 60, 20, 4); ctx.fill(); ctx.stroke(); glow(c, false);
          ctx.fillStyle = rgba(c, 0.95); ctx.fillText(lab, pos[i][0], pos[i][1]);
        });
        const cur = order[Math.min(done, order.length - 1)];
        const out = [];
        if (N[cur][4]) out.push([pos[cur][0], pos[cur][1], pos[cur][0] < b.x + b.w / 2 ? -1 : 1, -18, N[cur][4], "G"]);
        if (done >= order.length) out.push([pos[0][0], pos[0][1], 1, 30, "= cos(x)·x² + sin(x)·2x", "P"]);
        return out;
      },
    };
  })());

  // 8. Multiple dispatch: which method runs for f(3, 2.5)? (unit 09, lesson L01)
  SPECIMENS.push((() => {
    const sub = { Int: ["Int", "Number", "Any"], Float64: ["Float64", "Number", "Any"] };
    const depth = { Int: 0, Float64: 0, Number: 1, Any: 2 };
    const rows = [["Any", "Any"], ["Number", "Number"], ["Int", "Number"], ["Int", "Int"]];
    const call = ["Int", "Float64"];
    const ok = rows.map((r) => r.every((t, i) => sub[call[i]].includes(t)));
    const best = rows.reduce((bi, r, i) => (ok[i] && (bi < 0 || r.reduce((a, t) => a + depth[t], 0) < rows[bi].reduce((a, t) => a + depth[t], 0)) ? i : bi), -1);
    return {
      name: "METHOD DISPATCH", src: "unit 09 · f(3, 2.5) :: (Int, Float64)", c: "P",
      draw(b, p) {
        const rh = Math.min(30, b.h / 6), y0 = b.y + (b.h - rh * rows.length) / 2, x0 = b.x + b.w * 0.08;
        const k = clamp01(p) * (rows.length + 1);
        font(11, 500); ctx.textAlign = "left"; ctx.textBaseline = "middle";
        const out = [];
        rows.forEach((r, i) => {
          const y = y0 + i * rh + rh / 2, seen = k > i + 0.5, win = k >= rows.length + 0.5 && i === best;
          const c = !seen ? pal.M : win ? pal.G : ok[i] ? pal.B : pal.R;
          ctx.strokeStyle = rgba(c, win ? 0.9 : 0.35); ctx.lineWidth = win ? 1.5 : 1; glow(c, win);
          ctx.strokeRect(x0, y - rh * 0.4, b.w * 0.84, rh * 0.8); glow(c, false);
          ctx.fillStyle = rgba(c, 0.9);
          ctx.fillText(`f(::${r[0]}, ::${r[1]})`, x0 + 10, y);
          if (seen) { ctx.textAlign = "right"; ctx.fillText(win ? "◆ MOST SPECIFIC" : ok[i] ? "applies" : "no match", x0 + b.w * 0.84 - 10, y); ctx.textAlign = "left"; }
          if (win) out.push([x0 + b.w * 0.84, y, 1, -22, "Float64 <: Number, so (Int, Number) wins", "G"]);
        });
        const sy = y0 + Math.min(k, rows.length) * rh;
        ctx.strokeStyle = rgba(pal.B, 0.5 * (k < rows.length ? 1 : 0)); line(x0 - 8, sy, x0 + b.w * 0.84 + 8, sy);
        return out;
      },
    };
  })());

  // 9. BKT mastery: bkt_update with the defaults from src/models.jl.
  SPECIMENS.push((() => {
    const th = { init: 0.2, learn: 0.15, guess: 0.25, slip: 0.1 };
    const obs = [true, false, true, true, true, true, true];
    const ps = [th.init];
    for (const c of obs) {
      const p = ps[ps.length - 1];
      const num = c ? p * (1 - th.slip) : p * th.slip, den = num + (1 - p) * (c ? th.guess : 1 - th.guess);
      const post = num / den; ps.push(post + (1 - post) * th.learn);
    }
    return {
      name: "KNOWLEDGE TRACING", src: "src/models.jl · bkt_update, default priors", c: "A",
      draw(b, p) {
        const n = ps.length, bw = b.w * 0.8 / n, x0 = b.x + b.w * 0.1, base = b.y + b.h * 0.85, top = b.y + b.h * 0.12;
        const shown = clamp01(p) * n;
        ctx.strokeStyle = rgba(pal.M, 0.4); ctx.lineWidth = 1; line(x0, base, x0 + b.w * 0.8, base);
        for (let i = 0; i < n; i++) {
          const g = clamp01(shown - i), h = (base - top) * ps[i] * ease(g);
          const c = i === 0 ? pal.M : obs[i - 1] ? pal.G : pal.R;
          ctx.fillStyle = rgba(c, 0.18); ctx.strokeStyle = rgba(c, 0.85); glow(c, g >= 1 && i === n - 1);
          ctx.fillRect(x0 + i * bw + 3, base - h, bw - 6, h); ctx.strokeRect(x0 + i * bw + 3, base - h, bw - 6, h); glow(c, false);
          if (g > 0.9) { font(9.5, 500); ctx.textAlign = "center"; ctx.textBaseline = "bottom"; ctx.fillStyle = rgba(c, 0.9); ctx.fillText(ps[i].toFixed(2), x0 + (i + 0.5) * bw, base - h - 3); }
        }
        const lx = x0 + (n - 0.5) * bw, ly = base - (base - top) * ps[n - 1];
        return [
          [lx, ly, 1, -14, `P(L) = ${ps[n - 1].toFixed(3)} after ${obs.length} answers`, "A"],
          [x0 + 1.5 * bw, base - (base - top) * ps[2], -1, -24, "a wrong answer pulls it down", "R"],
          [x0 + 0.5 * bw, base, -1, 18, "p_init .2 · learn .15 · guess .25 · slip .1", "B"],
        ];
      },
    };
  })());

  // ---- scan events: lock → draw → annotate → hold → fade ----------------------
  const T_LOCK = 0.5, T_DRAW = 2.4, T_NOTE = 1.4, T_HOLD = 3.2, T_FADE = 0.7, T_GAP = 1.2;
  const T_EVENT = T_LOCK + T_DRAW + T_NOTE + T_HOLD + T_FADE + T_GAP;
  let placed = { idx: -1, box: null, ver: -1 };

  // Reserved zones: the course ring (bottom right) and the ticker (bottom left).
  function reserved() {
    const small = W < 760, R = small ? 70 : 120;
    return [[W - (small ? 36 : 70) - R - 40, H - (small ? 36 : 70) - R - 40, R * 2 + 80, R * 2 + 80], [0, H - 44, Math.min(W, 520), 44]];
  }
  // Largest scan that fits in free space: try sizes from big to small and take the
  // first spot whose padded area (labels included) is nearly free of content.
  function place(cycle) {
    const small = W < 760, top = 80;
    const sizes = small ? [Math.min(W - 60, 300), 240, 190] : [330, 290, 250, 210, 175, 125];
    const extra = reserved();
    const cost = (x, y, w, h) => overlap(x, y, w, h) + extra.reduce((a, [rx, ry, rw, rh]) => {
      const ox = Math.min(x + w, rx + rw) - Math.max(x, rx), oy = Math.min(y + h, ry + rh) - Math.max(y, ry);
      return a + (ox > 0 && oy > 0 ? ox * oy * 4 : 0);
    }, 0);
    for (const bw of sizes) {
      const mini = bw < 150, bh = bw * 0.78, lab = small || mini ? 8 : Math.round(bw * 0.45); // side room for callout labels
      const cands = [];
      for (let gy = 0; gy <= 8; gy++) for (let gx = 0; gx <= 12; gx++) {
        const x = lab + (W - 2 * lab - bw) * (gx / 12), y = top + 26 + (H - top - 26 - 60 - bh) * (gy / 8);
        if (W - 2 * lab - bw < 0 || H - top - 86 - bh < 0) continue;
        const area = (bw + 2 * lab) * (bh + 60);
        const c = cost(x - lab, y - 26, bw + 2 * lab, bh + 60) / area;
        cands.push({ c, x, y, bw, bh, mini });
      }
      if (!cands.length) continue;
      cands.sort((a, b) => a.c - b.c || a.x - b.x);
      const free = cands.filter((k) => k.c < 0.04);
      if (free.length) {
        // vary the spot between scans, deterministically, among the free ones
        const k = free[(cycle * 7) % free.length];
        placed = { idx: cycle, box: { x: k.x, y: k.y, w: k.bw, h: k.bh }, mini: k.mini };
        return;
      }
    }
    // No free space on this screen (a page full of cards): skip the scan rather
    // than draw it half-hidden behind content. Ambient layers still run.
    placed = { idx: cycle, box: null };
  }

  function scanEvent(t) {
    const cycle = Math.floor(t / T_EVENT), local = t - cycle * T_EVENT;
    const idx = cycle % SPECIMENS.length, sp = SPECIMENS[idx];
    if (placed.idx !== cycle) { if (rectsDirty) scanRects(performance.now()); place(cycle); placed.ver = rectsVersion; }
    else if (placed.ver !== rectsVersion) {
      // content moved (scroll, late-mounting app): move the scan if it is now covered,
      // or bring back a skipped one if room has opened up
      const pb = placed.box;
      if (!pb || overlap(pb.x, pb.y, pb.w, pb.h) / (pb.w * pb.h) > 0.15) place(cycle);
      placed.ver = rectsVersion;
    }
    const b = placed.box, C = pal[sp.c];
    if (!b) return;
    const fade = 1 - clamp01((local - (T_EVENT - T_GAP - T_FADE)) / T_FADE);
    if (local > T_EVENT - T_GAP) return;
    ctx.save(); ctx.globalAlpha = fade * (pal.dark ? 1 : 0.95);
    // flicker on entry (deterministic: two short dips)
    if (local < 0.25 && Math.floor(local * 24) % 3 === 1) ctx.globalAlpha *= 0.4;
    brackets(b, local / T_LOCK, C);
    // header / footer
    font(10.5, 600); ctx.textBaseline = "bottom"; ctx.textAlign = "left"; ctx.fillStyle = rgba(C, 0.9);
    const head = placed.mini ? `▸ ${sp.name}` : `▸ ANALYSIS ${String(idx + 1).padStart(2, "0")}/${String(SPECIMENS.length).padStart(2, "0")}  ${sp.name}`;
    const hx = Math.max(6, Math.min(b.x, W - 8 - ctx.measureText(head).width));
    ctx.fillText(typed(head, local / 0.6), hx, b.y - 8);
    font(9.5, 400); ctx.textBaseline = "top"; ctx.fillStyle = rgba(pal.M, 0.85);
    if (placed.mini) font(9, 400);
    ctx.fillText(typed(placed.mini ? sp.src.split(" · ")[0] : `source: ${sp.src}`, (local - 0.3) / 0.8), b.x, b.y + b.h + 8);
    if (!placed.mini && local > T_LOCK + T_DRAW + T_NOTE) { ctx.fillStyle = rgba(pal.G, 0.85); ctx.fillText("✓ computed in your browser", b.x, b.y + b.h + 22); }
    // subject
    const pd = ease((local - T_LOCK) / T_DRAW);
    const notes = local > T_LOCK ? sp.draw(b, pd, C, t) || [] : [];
    // analysis sweep while drawing
    if (local > T_LOCK && local < T_LOCK + T_DRAW) {
      const sx = b.x + b.w * clamp01((local - T_LOCK) / T_DRAW);
      const g = ctx.createLinearGradient(sx - 40, 0, sx, 0);
      g.addColorStop(0, rgba(C, 0)); g.addColorStop(1, rgba(C, 0.12));
      ctx.fillStyle = g; ctx.fillRect(sx - 40, b.y, 40, b.h);
      ctx.strokeStyle = rgba(C, 0.6); ctx.lineWidth = 1; line(sx, b.y - 4, sx, b.y + b.h + 4);
    }
    // callouts, staggered
    labelsUsed = [];
    if (!placed.mini) notes.forEach(([ax, ay, side, dy, text, ck], i) => {
      const pn = (local - T_LOCK - T_DRAW * 0.85 - i * 0.35) / 0.9;
      callout(ax, ay, side, dy, text, clamp01(pn), pal[ck] || C, b);
    });
    ctx.restore();
  }

  // ---- ambient: course ring (corner; one tick per unit, no printed counts) + ticker ---------------------------------
  function courseRing(t) {
    const small = W < 760, R = small ? 70 : 120, cx = W - (small ? 36 : 70), cy = H - (small ? 36 : 70);
    const total = COURSES.reduce((a, c) => a + c[1], 0), gap = 0.05, sweep = Math.PI * 2 - gap * COURSES.length;
    let a = -Math.PI / 2 + t * 0.02;
    ctx.lineCap = "butt";
    COURSES.forEach(([name, units, status], i) => {
      const span = sweep * units / total, c = [pal.P, pal.B, pal.G, pal.A, pal.R][i % 5];
      ctx.strokeStyle = rgba(c, 0.5); ctx.lineWidth = 6;
      if (status !== "ready") ctx.setLineDash([3, 3]);
      ctx.beginPath(); ctx.arc(cx, cy, R, a, a + span); ctx.stroke(); ctx.setLineDash([]);
      // unit ticks
      ctx.strokeStyle = rgba(c, 0.6); ctx.lineWidth = 1;
      for (let u = 0; u <= units; u++) {
        const ua = a + span * u / units;
        line(cx + Math.cos(ua) * (R + 6), cy + Math.sin(ua) * (R + 6), cx + Math.cos(ua) * (R + 10), cy + Math.sin(ua) * (R + 10));
      }
      const mid = a + span / 2, lx = cx + Math.cos(mid) * (R + 18), ly = cy + Math.sin(mid) * (R + 18);
      if (lx > 8 && ly > 70 && lx < W - 8 && ly < H - 8 && !small) {
        font(9.5, 600); ctx.textAlign = Math.cos(mid) >= 0 ? "left" : "right"; ctx.textBaseline = "middle";
        ctx.fillStyle = rgba(c, 0.75); ctx.fillText(`${name}${status === "ready" ? "" : " ·  IN PROGRESS"}`, lx, ly);
      }
      a += span + gap;
    });
    ctx.strokeStyle = rgba(pal.B, 0.25); ctx.lineWidth = 1;
    ctx.beginPath(); ctx.arc(cx, cy, R * 0.72, -t * 0.05, -t * 0.05 + Math.PI * 1.3); ctx.stroke();
    ctx.setLineDash([2, 5]); ctx.beginPath(); ctx.arc(cx, cy, R * 0.55, 0, 7); ctx.stroke(); ctx.setLineDash([]);
    if (!small) {
      font(9.5, 500); ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillStyle = rgba(pal.B, 0.7);
      ctx.fillText("COURSE MAP", cx - R * 0.25, cy - R * 0.25);
    }
  }
  function ticker(t) {
    if (W < 760) return;
    const k = Math.floor(t / 3.2) % TICKER.length, local = t % 3.2;
    font(9.5, 500); ctx.textAlign = "left"; ctx.textBaseline = "bottom";
    const x = 22, y = H - 20;
    ctx.fillStyle = rgba(pal.M, 0.7); ctx.fillText("REC ▸", x, y);
    ctx.fillStyle = rgba(pal.B, 0.8 * (1 - clamp01((local - 2.8) / 0.4)));
    ctx.fillText(typed(TICKER[k], local / 0.9), x + 46, y);
  }

  // ---- frame ---------------------------------------------------------------
  function frame(now, tOverride) {
    const t = tOverride != null ? tOverride : (now - t0) / 1000;
    // a page loaded in a hidden tab or frame starts at 0×0 and may get no resize event
    if (W !== window.innerWidth || H !== window.innerHeight) resize();
    if (!W || !H) return; // nothing to draw on (and drawImage throws on a 0-size canvas)
    if (rectsDirty || now - lastRectScan > 1000) scanRects(now);
    ctx.clearRect(0, 0, W, H);
    ctx.drawImage(hexLayer, 0, 0, W, H);
    hexSparks(t);
    courseRing(t);
    ticker(t);
    scanEvent(t);
    knockout();
  }
  function loop(now) {
    raf = requestAnimationFrame(loop);
    if (now - last < 1000 / FPS - 1) return;
    last = now; frame(now);
  }
  function start() {
    cancelAnimationFrame(raf); last = 0;
    if (frozen != null) frame(performance.now(), frozen);
    else if (reduce.matches) frame(performance.now(), T_LOCK + T_DRAW + T_NOTE + 1); // first scan, fully annotated, still
    else raf = requestAnimationFrame(loop);
  }
  const still = () => frozen != null || reduce.matches;

  window.__jtHudDebug = () => ({ placed, rects: rects.length, W, H }); // for tests
  readPalette(); resize(); start();
  window.addEventListener("resize", () => { resize(); if (still()) start(); });
  window.addEventListener("scroll", () => { rectsDirty = true; if (still()) start(); }, { passive: true });
  document.addEventListener("visibilitychange", () => { if (document.hidden) cancelAnimationFrame(raf); else start(); });
  reduce.addEventListener?.("change", start);
  new MutationObserver(() => { readPalette(); if (still()) start(); })
    .observe(document.body, { attributes: true, attributeFilter: ["class"] });
  // The app mounts after load and pages change size: in a still frame (reduced
  // motion), re-measure and redraw so the scan never stays behind late content.
  let redrawT = 0;
  const redrawSoon = () => { rectsDirty = true; if (!still() && W > 0) return; clearTimeout(redrawT); redrawT = setTimeout(start, 150); };
  new MutationObserver(redrawSoon).observe(document.body, { childList: true, subtree: true });
  if (window.ResizeObserver) new ResizeObserver(redrawSoon).observe(document.body);
})();
