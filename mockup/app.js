// Click dummy only: example data, hash routing, hand-drawn SVG charts.
(() => {
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const eur = (v, d = 2) => v.toLocaleString("de-DE", { minimumFractionDigits: d, maximumFractionDigits: d }) + " €";
  const pct = (v, d = 1) => (v > 0 ? "+" : v < 0 ? "−" : "") + Math.abs(v).toLocaleString("de-DE", { minimumFractionDigits: d, maximumFractionDigits: d });
  const MONTHS = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"];
  const NS = "http://www.w3.org/2000/svg";
  const svg = (tag, attrs = {}, text) => {
    const el = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
    if (text != null) el.textContent = text;
    return el;
  };
  const rng = seed => () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;

  // ------------------------------------------------------------ data
  // A depot's value includes its reference account, which is listed under it; accounts of no depot come last.
  const depots = [
    { id: "langfristig", name: "Langfristig", tone: "var(--felt-denim)", securities: 146377.4, konto: "konto-langfristig", sub: "2 Wertpapiere · Konto Langfristig" },
    { id: "sparplan", name: "Sparplan EM/Europa", tone: "var(--felt-moss)", securities: 0, konto: "konto-sparplan", sub: "noch keine Wertpapiere · Konto Sparplan" },
  ];
  const konten = [
    { id: "konto-langfristig", name: "Konto Langfristig", value: 240.18 },
    { id: "konto-sparplan", name: "Konto Sparplan", value: 1500 },
    { id: "tagesgeld", name: "Tagesgeld", value: 1000 },
  ];

  const upcoming = [
    { pay: "23.10.2026", ex: "15.10.", name: "L&G Global Quality Dividends", per: "0,0353 USD", amount: 187.23, announced: true },
    { pay: "20.11.2026", ex: "12.11.", name: "L&G Global Quality Dividends", per: "~0,0353 USD", amount: 187.5 },
    { pay: "27.11.2026", ex: "13.11.", name: "HSBC MSCI Emerging Markets", per: "~0,075 USD", amount: 5.9 },
    { pay: "04.12.2026", ex: "27.11.", name: "Xtrackers Stoxx Europe 600 1D", per: "~0,093 EUR", amount: 2.8 },
    { pay: "18.12.2026", ex: "10.12.", name: "L&G Global Quality Dividends", per: "~0,0353 USD", amount: 187.5 },
    { pay: "30.12.2026", ex: "17.12.", name: "Vanguard FTSE All-World", per: "~0,48 USD", amount: 215 },
    { pay: "22.01.2027", ex: "14.01.", name: "L&G Global Quality Dividends", per: "~0,0353 USD", amount: 187.5 },
  ];

  const next12 = [
    ["Okt", 187, true], ["Nov", 194], ["Dez", 406], ["Jan", 188], ["Feb", 194], ["Mär", 191],
    ["Apr", 393], ["Mai", 194], ["Jun", 191], ["Jul", 593], ["Aug", 194], ["Sep", 436],
  ];

  const byYear = {
    2024: { color: "var(--felt-taupe)", values: [0, 0, 0, 158, 0, 0, 331, 0, 0, 189, 0, 172] },
    2025: { color: "var(--felt-mustard)", values: [0, 0, 0, 176, 0, 0, 368, 0, 0, 212, 0, 195] },
    2026: { color: "var(--felt-primary)", values: [0, 186, 187, 390, 188, 187, 589, 188, 429, 187, 194, 406], forecastFrom: 9 },
  };

  const received = [
    { date: "30.09.2026", name: "Vanguard FTSE All-World", gross: 241.44, tax: 44.58, pdf: true },
    { date: "18.09.2026", name: "L&G Global Quality Dividends", gross: 187.05, tax: 34.53, pdf: true },
    { date: "21.08.2026", name: "L&G Global Quality Dividends", gross: 186.9, tax: 34.5, pdf: true },
    { date: "24.07.2026", name: "L&G Global Quality Dividends", gross: 187.4, tax: 0, pdf: true },
    { date: "01.07.2026", name: "Vanguard FTSE All-World", gross: 401.22, tax: 0, pdf: true },
    { date: "19.06.2026", name: "L&G Global Quality Dividends", gross: 187.12, tax: 0, pdf: false },
  ];

  const allocations = {
    regions: [
      ["USA", 48.5, 28.2], ["Europa", 23.0, 23.5], ["Japan", 10.6, 3.8],
      ["Schwellenländer", 9.6, 38.6], ["Pazifik ohne Japan", 4.1, 3.1], ["Kanada", 3.8, 2.2],
    ],
    sectors: [
      ["Technologie", 21.4], ["Finanzen", 17.2], ["Industrie", 11.3], ["Gesundheit", 10.1],
      ["Konsum zyklisch", 9.0], ["Basiskonsum", 7.6], ["Kommunikation", 7.1], ["Energie", 5.2],
      ["Grundstoffe", 4.4], ["Versorger", 3.9], ["Immobilien", 2.8],
    ],
    classes: [["Aktien", 98.2, 90], ["Immobilien", 0, 10], ["Cash", 1.8, 0]],
  };

  const heat = {
    2020: [1.6, -7.9, -12.4, 9.8, 3.1, 1.9, 0.4, 5.8, -1.6, -2.2, 9.6, 2.1],
    2021: [0.8, 2.5, 5.1, 1.9, -0.4, 3.6, 1.4, 2.9, -2.0, 4.6, 0.6, 3.4],
    2022: [-4.4, -2.5, 3.8, -2.4, -2.9, -6.3, 8.8, -1.2, -6.4, 3.2, 2.1, -6.1],
    2023: [4.9, 0.4, 0.6, 0.3, 2.1, 3.4, 2.3, -1.4, -1.7, -3.1, 5.9, 3.4],
    2024: [2.6, 3.9, 3.2, -1.5, 1.4, 4.4, 0.5, -0.2, 1.8, 1.2, 6.0, -1.0],
    2025: [3.8, -1.9, -7.2, -3.6, 5.6, 0.8, 4.9, -0.1, 2.4, 4.1, -0.4, -0.2],
    2026: [1.8, 1.6, -5.2, 8.1, 5.6, 0.9, -1.6, 2.1, -2.1, 1.24],
  };

  const bookings = [
    ["Oktober 2026", [
      { icon: "i-wallet", tone: "secondary", title: "Einlage", sub: "Sparplan EM/Europa · Konto Sparplan …0816", amount: 1500, pdf: false },
    ]],
    ["September 2026", [
      { icon: "i-coins", tone: "success", title: "Ausschüttung · Vanguard FTSE All-World", sub: "520 Stück · brutto 241,44 € · Steuern 44,58 €", amount: 196.86, pdf: true },
      { icon: "i-coins", tone: "success", title: "Ausschüttung · L&G Global Quality Dividends", sub: "6.200 Stück · brutto 187,05 € · Steuern 34,53 €", amount: 152.52, pdf: true },
    ]],
    ["August 2026", [
      { icon: "i-coins", tone: "success", title: "Ausschüttung · L&G Global Quality Dividends", sub: "6.200 Stück · brutto 186,90 € · Steuern 34,50 €", amount: 152.4, pdf: true },
      { icon: "i-layers", tone: "primary", title: "Kauf · Vanguard FTSE All-World", sub: "20 Stück à 158,90 € · Gebühren 1,00 €", amount: -3179, pdf: true },
    ]],
    ["Juli 2026", [
      { icon: "i-coins", tone: "success", title: "Ausschüttung · L&G Global Quality Dividends", sub: "6.200 Stück · brutto 187,40 €", amount: 187.4, pdf: true },
      { icon: "i-coins", tone: "success", title: "Ausschüttung · Vanguard FTSE All-World", sub: "500 Stück · brutto 401,22 €", amount: 401.22, pdf: true },
    ]],
  ];

  // ------------------------------------------------------------ navigation: sidebar, tab bar, depots, depot switcher
  const num = v => (v < 0 ? "−" : "") + Math.abs(v).toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const money = v => num(v) + " €";
  const sum = list => list.reduce((a, x) => a + x.value, 0);
  const depot = id => depots.find(d => d.id === id);
  const konto = id => konten.find(k => k.id === id);
  // an account that several depots settle against belongs to the first
  const ownerOf = k => depots.find(d => d.konto === k.id);
  const tree = depots.map(d => {
    const k = konto(d.konto), own = k && ownerOf(k) === d;
    return { ...d, value: d.securities + (own ? k.value : 0), account: own ? k : null };
  });
  const orphans = konten.filter(k => !ownerOf(k));
  const depotHref = d => `#bestand?depot=${d.id}`;
  const kontoHref = k => (ownerOf(k) ? `#bestand?depot=${ownerOf(k).id}&konto=${k.id}` : `#bestand?konto=${k.id}`);
  const tone = v => (v < 0 ? " is-neg" : v ? "" : " is-zero");
  const chip = d => `<span class="app-chip" style="--chip:${d.tone}" aria-hidden="true">${d.name[0]}</span>`;
  const walletChip = '<span class="app-chip app-chip-acc" aria-hidden="true"><svg class="app-icon"><use href="#i-wallet"/></svg></span>';
  const wallet = '<svg class="app-icon" aria-hidden="true"><use href="#i-wallet"/></svg>';

  // sidebar: one row per depot with its account indented below, then the accounts of no depot
  const sideRow = (href, name, value, icon, cls = "") =>
    `<a class="nav-link app-acc${cls}" href="${href}">${icon}<span class="app-acc-name">${name}</span><span class="app-bal${tone(value)}">${num(value)}</span>` +
    `<span class="app-fly" aria-hidden="true">${name} <span>${money(value)}</span></span></a>`;
  const sideHead = (label, value) => `<div class="app-side-h"><span>${label}</span><span>${num(value)}</span></div>`;
  $("[data-side-groups]").innerHTML =
    sideHead("Depots", sum(tree)) +
    `<nav class="nav flex-column" data-nav aria-label="Depots">${tree.map(d =>
      sideRow(depotHref(d), d.name, d.value, chip(d)) + (d.account ? sideRow(kontoHref(d.account), d.account.name, d.account.value, wallet, " app-sub") : "")).join("")}</nav>` +
    (orphans.length ? sideHead("Konten", sum(orphans)) +
      `<nav class="nav flex-column" data-nav aria-label="Konten">${orphans.map(k => sideRow(kontoHref(k), k.name, k.value, walletChip)).join("")}</nav>` : "");

  // phone: the same tree as a screen, after the total of everything
  const chev = '<svg class="app-icon app-chev" aria-hidden="true"><use href="#i-chevron"/></svg>';
  const treeRow = (href, name, value, icon, cls = "") =>
    `<a class="list-group-item list-group-item-action${cls}" href="${href}">${icon}<span class="me-auto text-truncate">${name}</span><span class="tabular-nums text-nowrap${value ? "" : " text-body-secondary"}">${money(value)}</span>${chev}</a>`;
  const treeHead = (label, value) => `<h2 class="app-sheet-h"><span>${label}</span><span>${money(value)}</span></h2>`;
  const worth = sum(tree) + sum(orphans);
  $("[data-depots-tree]").innerHTML =
    `<div class="list-group mb-4">${treeRow("#bestand", "Gesamt", worth, '<span class="app-chip app-chip-all" aria-hidden="true"><svg class="app-icon"><use href="#i-layers"/></svg></span>')}</div>` +
    treeHead("Depots", sum(tree)) +
    `<div class="list-group mb-4">${tree.map(d =>
      treeRow(depotHref(d), d.name, d.value, chip(d)) + (d.account ? treeRow(kontoHref(d.account), d.account.name, d.account.value, wallet, " app-sub") : "")).join("")}</div>` +
    (orphans.length ? treeHead("Konten", sum(orphans)) + `<div class="list-group">${orphans.map(k => treeRow(kontoHref(k), k.name, k.value, walletChip)).join("")}</div>` : "");

  $("[data-sheet]").addEventListener("click", e => {
    if (e.target.closest("a[href^='#']")) bootstrap.Offcanvas.getInstance($("#moreSheet"))?.hide();
  });

  $("[data-depot-menu]").innerHTML =
    `<li><a class="dropdown-item" href="#bestand">Gesamt</a></li><li><hr class="dropdown-divider"></li>` +
    tree.map(d => `<li><a class="dropdown-item d-flex align-items-center gap-2" href="${depotHref(d)}">${chip(d)}${d.name}</a></li>`).join("");

  // hash routes: #screen or #bestand?depot=…&konto=…
  const parse = hash => {
    const [screen, query = ""] = hash.replace(/^#/, "").split("?");
    const q = new URLSearchParams(query);
    return { screen: screen || "uebersicht", depot: q.get("depot") || "", konto: q.get("konto") || "" };
  };
  const screens = $$("[data-screen]");
  const sideFor = id => (id === "wertpapier" ? "bestand" : id);
  const tabFor = id => (["bestand", "wertpapier"].includes(id) ? "depots" : id);
  const MORE = ["performance", "plan", "einstellungen"];

  const showDepot = ({ depot: id, konto: k }) => {
    const d = depot(id);
    $("[data-depot-label]").textContent = d ? d.name : "Gesamt";
    $("[data-depot-sub]").textContent = d ? d.sub : `${depots.length} Depots · 2 Wertpapiere · ${konten.length} Konten`;
    $$("[data-depot-menu] .dropdown-item").forEach(a => a.classList.toggle("active", parse(a.getAttribute("href")).depot === (d ? id : "")));
    $$("tbody[data-depot]").forEach(tb => (tb.hidden = !!d && tb.dataset.depot !== id));
    $$("tfoot [data-foot]").forEach(tr => (tr.hidden = tr.dataset.foot !== (d ? id : "")));
    $$("tr[data-konto]").forEach(tr => tr.classList.toggle("table-active", tr.dataset.konto === k));
  };

  const mark = (a, on) => {
    a.classList.toggle("active", on);
    if (on) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current");
  };
  const show = () => {
    const route = parse(location.hash);
    const target = screens.find(s => s.dataset.screen === route.screen) || screens[0];
    const screen = target.dataset.screen;
    const here = { screen: sideFor(screen), depot: screen === "bestand" ? route.depot : "", konto: screen === "bestand" ? route.konto : "" };
    screens.forEach(s => (s.hidden = s !== target));
    // sidebar: the screen, or the depot or account that is open
    $$("[data-nav] .nav-link[href]").forEach(a => {
      const l = parse(a.getAttribute("href"));
      mark(a, l.screen === here.screen && l.depot === here.depot && l.konto === here.konto);
    });
    // tab bar: the screen (Depots also on the holdings); „Mehr“ for the screens in its sheet
    $$("[data-tabs] .nav-link[href]").forEach(a => mark(a, parse(a.getAttribute("href")).screen === tabFor(screen)));
    $("[data-more-tab]").classList.toggle("active", MORE.includes(screen));
    if (screen === "bestand") showDepot(route);
    window.scrollTo({ top: 0 });
  };
  addEventListener("hashchange", show);

  // sidebar width: from 1280 px open or collapsed as stored on this device; below it a rail that opens over the content
  const root = document.documentElement;
  const store = (k, v) => { try { localStorage.setItem(k, v); } catch {} };
  const stored = k => { try { return localStorage.getItem(k); } catch { return null; } };
  const wide = matchMedia("(min-width: 1280px)");
  const toggle = $("[data-side-toggle]"), scrim = $("[data-side-scrim]");
  let peek = false;
  const layout = () => {
    if (wide.matches) peek = false;
    const rail = wide.matches ? stored("side") === "mini" : !peek;
    root.classList.toggle("app-rail", rail);
    root.classList.toggle("app-side-peek", peek);
    scrim.hidden = !peek;
    // while it lies over the page, the rest of the page is out of reach
    $$("main, body > header, .app-fab, .app-tabbar").forEach(el => (el.inert = peek));
    toggle.setAttribute("aria-label", rail ? "Seitenleiste ausklappen" : "Seitenleiste einklappen");
    toggle.setAttribute("aria-expanded", String(!rail));
  };
  const openPeek = () => {
    peek = true;
    layout();
    ($(".app-side .nav-link.active") || $(".app-side .nav-link")).focus();
  };
  // back to the toggle, unless a link in the sidebar was followed
  const closePeek = (refocus = true) => {
    if (!peek) return;
    peek = false;
    layout();
    if (refocus) toggle.focus();
  };
  wide.addEventListener("change", layout);
  toggle.addEventListener("click", () => {
    if (wide.matches) { store("side", root.classList.contains("app-rail") ? "full" : "mini"); layout(); }
    else if (peek) closePeek();
    else openPeek();
  });
  scrim.addEventListener("click", () => closePeek());
  document.addEventListener("click", e => { if (e.target.closest(".app-side a[href^='#']")) closePeek(false); });
  document.addEventListener("keydown", e => {
    if (!peek) return;
    if (e.key === "Escape" && !$(".app-side .dropdown-menu.show")) closePeek();
    if (e.key !== "Tab") return;
    // Tab and Shift+Tab go round inside the sidebar
    const stops = $$(".app-side :is(a[href], button):not([disabled])").filter(el => el.getClientRects().length);
    const first = stops[0], last = stops[stops.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  });
  layout();

  document.addEventListener("click", e => {
    const b = e.target.closest("[data-toast-msg]");
    if (!b) return;
    $("#toast .toast-body").textContent = b.dataset.toastMsg;
    bootstrap.Toast.getOrCreateInstance($("#toast"), { delay: 2500 }).show();
  });

  // ------------------------------------------------------------ charts
  function axes(el, { w, h, pad, max, ticks, fmt }) {
    for (let i = 0; i <= ticks; i++) {
      const v = (max / ticks) * i, y = h - pad.b - (v / max) * (h - pad.t - pad.b);
      el.append(svg("line", { class: "grid", x1: pad.l, x2: w - pad.r, y1: y, y2: y, "stroke-dasharray": i ? "3 4" : "" }));
      el.append(svg("text", { x: pad.l - 6, y: y + 4, "text-anchor": "end" }, fmt(v)));
    }
  }

  function lineChart(el, series, { min, max, labels, markers = [] }) {
    const w = 640, h = +el.getAttribute("viewBox").split(" ")[3], pad = { t: 10, r: 8, b: 24, l: 56 };
    const n = series[0].values.length;
    const x = i => pad.l + (i / (n - 1)) * (w - pad.l - pad.r);
    const y = v => h - pad.b - ((v - min) / (max - min)) * (h - pad.t - pad.b);
    for (let i = 0; i <= 4; i++) {
      const v = min + ((max - min) / 4) * i;
      el.append(svg("line", { class: "grid", x1: pad.l, x2: w - pad.r, y1: y(v), y2: y(v), "stroke-dasharray": "3 4" }));
      el.append(svg("text", { x: pad.l - 6, y: y(v) + 4, "text-anchor": "end" }, v >= 1000 ? Math.round(v / 1000) + " T€" : Math.round(v) + " €"));
    }
    labels.forEach(([i, t]) => el.append(svg("text", { x: x(i), y: h - 6, "text-anchor": "middle" }, t)));
    series.forEach(({ values, color, area, dashed }) => {
      const d = values.map((v, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join("");
      if (area) el.append(svg("path", { d: `${d}L${x(n - 1)},${h - pad.b}L${x(0)},${h - pad.b}Z`, style: `fill:${color};fill-opacity:.14` }));
      el.append(svg("path", { d, style: `fill:none;stroke:${color};stroke-width:${area ? 2.5 : 1.75};stroke-linejoin:round${dashed ? ";stroke-dasharray:5 4" : ""}` }));
    });
    const last = series[0].values[n - 1];
    el.append(svg("circle", { cx: x(n - 1), cy: y(last), r: 4.5, style: `fill:${series[0].color};stroke:var(--felt-body-bg);stroke-width:2` }));
    markers.forEach(i => el.append(svg("circle", { cx: x(i), cy: y(series[0].values[i]), r: 4, style: "fill:var(--felt-body-bg);stroke:var(--felt-success);stroke-width:2.5" })));
  }

  function groupedBars(el, groups, keys, { max, ticks = 4 }) {
    const [, , w, h] = el.getAttribute("viewBox").split(" ").map(Number), pad = { t: 10, r: 4, b: 22, l: 44 };
    axes(el, { w, h, pad, max, ticks, fmt: v => Math.round(v) + " €" });
    const gw = (w - pad.l - pad.r) / groups.length, bw = Math.min(22, (gw * 0.8) / keys.length);
    groups.forEach((g, gi) => {
      const x0 = pad.l + gi * gw + (gw - bw * keys.length) / 2;
      keys.forEach((k, ki) => {
        const v = k.values[gi] || 0;
        if (!v) return;
        const bh = (v / max) * (h - pad.t - pad.b), forecast = k.forecastFrom != null && gi >= k.forecastFrom;
        const attrs = { x: x0 + ki * bw + 1, y: h - pad.b - bh, width: bw - 2, height: bh, rx: 2 };
        el.append(svg("rect", { ...attrs, style: forecast ? `fill:${k.color};fill-opacity:.28;stroke:${k.color};stroke-dasharray:3 2` : `fill:${k.color}` },));
        el.lastChild.append(svg("title", {}, `${g} ${k.label ?? ""}: ${eur(v, 0)}${forecast ? " (Prognose)" : ""}`));
      });
      el.append(svg("text", { x: pad.l + gi * gw + gw / 2, y: h - 6, "text-anchor": "middle" }, g));
    });
  }

  // Overview: value vs invested, 26 weeks
  {
    const r = rng(7), n = 27, value = [], invested = [];
    let v = 135800;
    for (let i = 0; i < n; i++) {
      v *= 1 + (r() - 0.43) * 0.022;
      value.push(v);
      invested.push(i >= n - 1 ? 109310 : i >= 17 ? 107810 : 104631);
    }
    const scale = 147617.58 / value[n - 2];
    for (let i = 0; i < n - 1; i++) value[i] *= scale;
    value[n - 1] = 149117.58;
    const bench = value.map((v, i) => v * (1 - 0.011 * (i / (n - 1)) - (r() - 0.5) * 0.006));
    lineChart($("#chart-value"), [
      { values: value, color: "var(--felt-primary)", area: true },
      { values: bench, color: "var(--felt-mustard)" },
      { values: invested, color: "var(--felt-secondary)", dashed: true },
    ], { min: 80000, max: 160000, labels: [[0, "Apr"], [4, "Mai"], [9, "Jun"], [13, "Jul"], [17, "Aug"], [22, "Sep"], [26, "Okt"]] });
  }

  // Security price, 52 weeks
  {
    const r = rng(42), n = 53, p = [];
    let v = 141;
    for (let i = 0; i < n; i++) { v *= 1 + (r() - 0.44) * 0.03; p.push(v); }
    const k = 166.64 / p[n - 1];
    lineChart($("#chart-price"), [{ values: p.map(x => x * k), color: "var(--felt-primary)", area: true }],
      { min: 120, max: 180, labels: [[0, "Okt"], [9, "Dez"], [17, "Feb"], [26, "Apr"], [35, "Jun"], [44, "Aug"], [52, "Okt"]], markers: [14, 45] });
  }

  groupedBars($("#chart-next12"), next12.map(m => m[0]),
    [{ values: next12.map(m => m[1]), color: "var(--felt-primary)", forecastFrom: 1 }], { max: 600, ticks: 3 });

  groupedBars($("#chart-months"), MONTHS,
    Object.entries(byYear).map(([label, y]) => ({ ...y, label })), { max: 600 });

  $("[data-year-legend]").innerHTML = Object.entries(byYear).map(([y, { color }]) =>
    `<span><span class="legend-swatch" style="background:${color}"></span> ${y}</span>`).join("") +
    '<span><span class="legend-swatch is-forecast"></span> Prognose</span>';

  $("#table-months").innerHTML =
    `<thead><tr><th></th>${MONTHS.map(m => `<th class="text-end">${m}</th>`).join("")}<th class="text-end">Σ</th></tr></thead><tbody>` +
    Object.entries(byYear).map(([y, { values, forecastFrom }]) =>
      `<tr><th>${y}</th>${values.map((v, i) =>
        `<td class="text-end${forecastFrom != null && i >= forecastFrom ? " text-body-secondary fst-italic" : ""}">${v ? v.toLocaleString("de-DE") : "–"}</td>`).join("")}` +
      `<td class="text-end fw-bold">${values.reduce((a, b) => a + b, 0).toLocaleString("de-DE")}</td></tr>`).join("") + "</tbody>";

  // ------------------------------------------------------------ lists
  const badge = d => d.announced
    ? '<span class="badge text-bg-primary forecast-tag">angekündigt</span>'
    : '<span class="badge text-bg-light forecast-tag">Prognose</span>';

  $$("[data-upcoming]").forEach(ul => {
    ul.innerHTML = upcoming.slice(0, +ul.dataset.upcoming).map(d => `
      <li class="list-group-item d-flex align-items-center gap-3">
        <span class="text-center lh-1" style="width:2.5rem"><span class="d-block fw-bold fs-5 tabular-nums">${d.pay.slice(0, 2)}</span><span class="small text-body-secondary">${MONTHS[+d.pay.slice(3, 5) - 1]}</span></span>
        <span class="me-auto" style="min-width:0"><span class="d-block fw-semibold text-truncate">${d.name}</span>${badge(d)}</span>
        <span class="fw-bold tabular-nums text-nowrap">${d.announced ? "" : "~"}${eur(d.amount)}</span>
      </li>`).join("");
  });

  {
    const groups = {};
    upcoming.forEach(d => {
      const key = MONTHS[+d.pay.slice(3, 5) - 1] + " " + d.pay.slice(6);
      (groups[key] ??= []).push(d);
    });
    $("[data-calendar]").innerHTML = Object.entries(groups).map(([month, items]) => `
      <h2 class="small text-uppercase fw-bold text-body-secondary d-flex justify-content-between mb-2"><span>${month.replace("Okt", "Oktober").replace("Nov", "November").replace("Dez", "Dezember").replace("Jan", "Januar")}</span><span class="tabular-nums">${eur(items.reduce((a, d) => a + d.amount, 0))}</span></h2>
      <div class="list-group mb-4">${items.map(d => `
        <div class="list-group-item d-flex align-items-center gap-3">
          <span class="app-avatar rounded-circle ${d.announced ? "bg-primary-subtle text-primary-emphasis" : "bg-body-tertiary text-body-secondary"} d-flex align-items-center justify-content-center"><svg class="app-icon" aria-hidden="true"><use href="#${d.announced ? "i-calendar" : "i-spark"}"/></svg></span>
          <span class="me-auto" style="min-width:0"><span class="d-block fw-semibold">${d.name}</span><span class="small text-body-secondary">Zahltag ${d.pay} · Ex-Tag ${d.ex} · ${d.per} je Anteil</span></span>
          <span class="text-end text-nowrap"><span class="d-block fw-bold tabular-nums">${d.announced ? "" : "~"}${eur(d.amount)}</span>${badge(d)}</span>
        </div>`).join("")}
      </div>`).join("");
  }

  $("[data-received]").innerHTML = received.map(d => `
    <div class="list-group-item d-flex align-items-center gap-3">
      <span class="app-avatar rounded-circle bg-success-subtle text-success-emphasis d-flex align-items-center justify-content-center"><svg class="app-icon" aria-hidden="true"><use href="#i-coins"/></svg></span>
      <span class="me-auto" style="min-width:0"><span class="d-block fw-semibold">${d.name}</span><span class="small text-body-secondary">${d.date} · brutto ${eur(d.gross)}${d.tax ? " · Steuern " + eur(d.tax) : " · steuerfrei (Freistellungsauftrag)"}</span></span>
      ${d.pdf ? '<span class="badge text-bg-light d-none d-sm-inline-flex align-items-center gap-1"><svg class="app-icon app-icon-sm" aria-hidden="true"><use href="#i-file"/></svg>PDF</span>' : ""}
      <span class="fw-bold tabular-nums text-success text-nowrap">+${eur(d.gross - d.tax)}</span>
    </div>`).join("");

  const fmt1 = v => v.toLocaleString("de-DE", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
  $$("[data-alloc]").forEach(el => {
    const rows = allocations[el.dataset.alloc];
    const max = Math.max(...rows.flatMap(([, is, target]) => [is, target ?? 0]));
    const w = v => (v / max) * 100;
    el.innerHTML = rows.map(([name, is, target]) => {
      const tone = target == null ? "" : is > target + 5 ? "text-warning-emphasis" : is < target - 5 ? "text-danger" : "text-success";
      return `
      <div>
        <div class="d-flex justify-content-between small mb-1"><span class="fw-semibold">${name}</span><span class="tabular-nums"><span class="${tone}">${fmt1(is)} %</span>${target == null ? "" : ` <span class="text-body-secondary">/ Ziel ${fmt1(target)} %</span>`}</span></div>
        <div class="position-relative bg-body-tertiary rounded-pill" style="height:.6rem">
          <div class="region-bar" style="width:${w(is)}%"></div>
          ${target == null ? "" : `<div class="region-target" style="left:${w(target)}%" title="Ziel ${fmt1(target)} %"></div>`}
        </div>
      </div>`;
    }).join("") + (el.dataset.alloc === "sectors" ? '<div class="small text-body-secondary">Für Sektoren ist kein Ziel gesetzt.</div>' : "");
  });

  // ------------------------------------------------------------ plan
  {
    const months = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"];
    const el = $("#chart-contrib");
    groupedBars(el, months, [{ values: [0, 0, 0, 0, 0, 0, 0, 3179, 0, 1500, 1500, 1500], color: "var(--felt-success)", forecastFrom: 10 }], { max: 3500, ticks: 2 });
    const [, , w, h] = el.getAttribute("viewBox").split(" ").map(Number), pad = { t: 10, r: 4, b: 22, l: 44 };
    const gw = (w - pad.l - pad.r) / 12, y = h - pad.b - (1500 / 3500) * (h - pad.t - pad.b);
    el.append(svg("path", { d: `M${pad.l + 9 * gw},${y}H${w - pad.r}`, style: "stroke:var(--felt-emphasis-color);stroke-width:2;stroke-dasharray:6 4;fill:none" }));
  }

  {
    const prices = { em: 12.11, eu: 12.49 }, total = 149117.58, emNow = 0.096 * total;
    const render = () => {
      const amount = parseFloat($("#rb-amount").value.replace(",", ".")) || 0;
      const gap = $("#rb-gap").checked;
      const em = gap ? amount : amount * 0.75, eu = amount - em;
      const row = (name, sum, price) => `<li class="list-group-item d-flex justify-content-between"><span>${name}</span><span><strong>${eur(sum)}</strong> <span class="small text-body-secondary">≈ ${(sum / price).toLocaleString("de-DE", { maximumFractionDigits: 3 })} Stück</span></span></li>`;
      $("[data-rebuy]").innerHTML = row("HSBC MSCI Emerging Markets", em, prices.em) + (eu > 0 ? row("Xtrackers Stoxx Europe 600 1D", eu, prices.eu) : "");
      const after = ((emNow + em) / total) * 100;
      $("[data-rebuy-effect]").innerHTML = `Schwellenländer danach <strong>${fmt1(after)} %</strong> statt 9,6 % (Ziel 38,6 %).${gap ? " Europa liegt schon am Ziel und bekommt nichts." : ""}`;
    };
    $("#rb-amount").addEventListener("input", render);
    $$('input[name="rb-mode"]').forEach(i => i.addEventListener("change", render));
    render();
  }

  {
    const start = 149117.58, today = new Date(2026, 9, 1);
    const categories = [["Miete", 1050], ["Lebensmittel", 520], ["Auto", 310], ["Urlaub", 250], ["Restaurants", 180], ["Hobbys", 120], ["Abos", 65], ["Sonstiges", 455]];
    const num = id => parseFloat($(id).value.replace(",", ".")) || 0;
    const simulate = (target, save, ret, limit = 720) => {
      const r = Math.pow(1 + ret / 100, 1 / 12) - 1;
      let v = start, paid = 0, m = 0;
      const path = [v];
      while (v < target && m < limit) { v = v * (1 + r) + save; paid += save; m++; path.push(v); }
      return { months: m, value: v, paid, path, reached: v >= target };
    };
    const label = m => { const d = new Date(today); d.setMonth(d.getMonth() + m); return d.toLocaleDateString("de-DE", { month: "long", year: "numeric" }); };
    const span = m => { const y = Math.floor(m / 12), mo = m % 12; return [y && `${y} J.`, mo && `${mo} M.`].filter(Boolean).join(" ") || "erreicht"; };
    const render = () => {
      const exp = num("#fi-exp"), save = num("#fi-save"), ret = num("#fi-ret"), fi = exp * 12 * 25;
      const stones = [
        ["FU-Geld", "10 % vom Ziel", fi * 0.1], ["Lean FI", "nur Grundbedarf (65 %)", fi * 0.65], ["Halbzeit", "50 %", fi * 0.5],
        ["Flex FI", "80 %", fi * 0.8], ["FI", "25 × Ausgaben", fi], ["Fat FI", "120 %", fi * 1.2], ["1,5 × FI", "150 %", fi * 1.5],
      ].sort((a, b) => a[2] - b[2]);
      const main = simulate(fi, save, ret);
      $("[data-fi-number]").textContent = eur(fi, 0);
      $("[data-fi-date]").textContent = main.reached ? `${label(main.months)} · in ${span(main.months)}` : "nicht in 60 Jahren";
      $("[data-fi-table]").innerHTML = `<thead><tr><th>Meilenstein</th><th class="text-end">Vermögen</th><th>Datum</th><th class="text-end">noch</th><th class="text-end d-none d-md-table-cell">davon eingezahlt</th></tr></thead><tbody>` +
        stones.map(([name, note, target]) => {
          const s = simulate(target, save, ret), done = start >= target;
          return `<tr${name === "FI" ? ' class="fw-bold"' : ""}><td>${name} <span class="small text-body-secondary fw-normal">${note}</span></td><td class="text-end">${eur(target, 0)}</td><td>${done ? '<span class="badge text-bg-success">erreicht</span>' : label(s.months)}</td><td class="text-end">${done ? "–" : span(s.months)}</td><td class="text-end d-none d-md-table-cell">${done ? "–" : eur(s.paid, 0)}</td></tr>`;
        }).join("") + "</tbody>";

      const el = $("#chart-fi"); el.replaceChildren();
      const top = stones[stones.length - 1][2], full = simulate(top, save, ret);
      const n = full.path.length, w = 640, h = 300, pad = { t: 10, r: 70, b: 24, l: 56 };
      const x = i => pad.l + (i / Math.max(1, n - 1)) * (w - pad.l - pad.r);
      const y = v => h - pad.b - (v / (top * 1.05)) * (h - pad.t - pad.b);
      let lastY = Infinity;
      stones.forEach(([name, , target]) => {
        el.append(svg("line", { class: "grid", x1: pad.l, x2: w - pad.r, y1: y(target), y2: y(target), "stroke-dasharray": "3 4" }));
        if (lastY - y(target) < 13 && name !== "FI") return;
        el.append(svg("text", { x: w - pad.r + 6, y: y(target) + 4, style: name === "FI" ? "font-weight:700;fill:var(--felt-body-color)" : "" }, name));
        lastY = y(target);
      });
      [0, top / 2, top].forEach(v => el.append(svg("text", { x: pad.l - 6, y: y(v) + 4, "text-anchor": "end" }, Math.round(v / 1000) + " T€")));
      for (let yr = 0; yr * 12 < n; yr += 2) el.append(svg("text", { x: x(yr * 12), y: h - 6, "text-anchor": "middle" }, 2026 + yr));
      const d = full.path.map((v, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join("");
      el.append(svg("path", { d: `${d}L${x(n - 1)},${h - pad.b}L${x(0)},${h - pad.b}Z`, style: "fill:var(--felt-primary);fill-opacity:.14" }));
      el.append(svg("path", { d, style: "fill:none;stroke:var(--felt-primary);stroke-width:2.5" }));
      if (main.reached) el.append(svg("circle", { cx: x(main.months), cy: y(fi), r: 5, style: "fill:var(--felt-primary);stroke:var(--felt-body-bg);stroke-width:2" }));

      const base = main.months;
      const impacts = categories.map(([name, c]) => [name, c, base - simulate((exp - c) * 300, save + c, ret).months]).sort((a, b) => b[2] - a[2]);
      const most = Math.max(...impacts.map(i => i[2]), 1);
      $("[data-fi-impact]").innerHTML = impacts.map(([name, c, m]) => `
        <div class="list-group-item d-flex align-items-center gap-3">
          <span style="width:8rem" class="fw-semibold">${name}</span>
          <span class="tabular-nums text-body-secondary" style="width:5rem">${eur(c, 0)}</span>
          <span class="flex-fill bg-body-tertiary rounded-pill" style="height:.5rem"><span class="d-block region-bar" style="width:${(m / most) * 100}%;height:100%;background:var(--felt-warning)"></span></span>
          <span class="tabular-nums text-end" style="width:6rem">${m ? "−" + span(m) : "–"}</span>
        </div>`).join("");
    };
    ["#fi-exp", "#fi-save", "#fi-ret"].forEach(id => $(id).addEventListener("input", render));
    render();
  }

  document.addEventListener("click", e => {
    const a = e.target.closest("[data-scroll]");
    if (!a) return;
    e.preventDefault();
    document.getElementById(a.dataset.scroll).scrollIntoView({ behavior: "smooth", block: "start" });
  });

  {
    const cell = v => {
      if (v == null) return "<td></td>";
      const a = Math.min(85, 12 + Math.abs(v) * 7);
      const tone = v >= 0 ? "var(--felt-success)" : "var(--felt-danger)";
      return `<td style="background:color-mix(in srgb, ${tone} ${a}%, transparent)${a > 50 ? ";color:#fff" : ""}">${pct(v)}</td>`;
    };
    $("#heatmap").innerHTML = `<thead><tr><th></th>${MONTHS.map(m => `<th>${m}</th>`).join("")}<th>Σ</th></tr></thead><tbody>` +
      Object.entries(heat).reverse().map(([y, vals]) => {
        const sum = (vals.reduce((a, v) => a * (1 + v / 100), 1) - 1) * 100;
        return `<tr><th>${y}</th>${Array.from({ length: 12 }, (_, i) => cell(vals[i])).join("")}${cell(sum).replace("<td", '<td class="sum"')}</tr>`;
      }).join("") + "</tbody>";
  }

  $("[data-bookings]").innerHTML = bookings.map(([month, items]) => `
    <h2 class="small text-uppercase fw-bold text-body-secondary mb-2">${month}</h2>
    <div class="list-group mb-4">${items.map(b => `
      <a href="#buchungen" class="list-group-item list-group-item-action d-flex align-items-center gap-3">
        <span class="app-avatar rounded-circle bg-${b.tone}-subtle text-${b.tone}-emphasis d-flex align-items-center justify-content-center"><svg class="app-icon" aria-hidden="true"><use href="#${b.icon}"/></svg></span>
        <span class="me-auto" style="min-width:0"><span class="d-block fw-semibold">${b.title}</span><span class="small text-body-secondary">${b.sub}</span></span>
        ${b.pdf ? '<span class="badge text-bg-light d-none d-sm-inline-flex align-items-center gap-1"><svg class="app-icon app-icon-sm" aria-hidden="true"><use href="#i-file"/></svg>PDF</span>' : ""}
        <span class="fw-bold tabular-nums text-nowrap ${b.amount >= 0 ? "text-success" : ""}">${b.amount >= 0 ? "+" : "−"}${eur(Math.abs(b.amount))}</span>
      </a>`).join("")}
    </div>`).join("");

  // ------------------------------------------------------------ forms, look, theme
  $$("form[data-close-on-submit]").forEach(f => f.addEventListener("submit", e => {
    e.preventDefault();
    bootstrap.Modal.getInstance(f.closest(".modal"))?.hide();
    $("#toast .toast-body").textContent = "Gebucht.";
    bootstrap.Toast.getOrCreateInstance($("#toast"), { delay: 2000 }).show();
  }));

  $(`#look-${root.dataset.look}`).checked = true;
  $(`#theme-${root.dataset.bsTheme || "auto"}`).checked = true;
  $$('input[name="look"]').forEach(i => i.addEventListener("change", () => { root.dataset.look = i.value; store("look", i.value); }));
  $$('input[name="theme"]').forEach(i => i.addEventListener("change", () => {
    if (i.value === "auto") delete root.dataset.bsTheme; else root.dataset.bsTheme = i.value;
    store("theme", i.value);
  }));

  show();
})();
