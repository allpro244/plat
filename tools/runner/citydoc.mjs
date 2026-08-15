// THE plat-city/1 DOCUMENT, built from a generated city and a game state.
// Shared by the one-shot exporter (export-city.mjs) and the campaign runner
// (game-server.mjs) so both write byte-identical structure.
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
export function buildCityDoc(E, city, g, extra = {}) {
  const parcels = {};
  for (const [bbl, p] of Object.entries(city.parcels)) {
    let occ = 0, cond = null;
    const rec = E.resolveRec(city.parcels, g, bbl);
    if (rec && rec.class !== "land") {
      const h = g.holdings[bbl];
      occ = +(h ? E.physicalOcc(rec, h) : E.occupancy(rec, g.econ)).toFixed(3);
      if (h?.condIdx != null) cond = +h.condIdx.toFixed(3);
    }
    // THE MONEY LINES (docs/GAME-PLAN.md phase 3.1): appraisal by the
    // engine's own assetValue, asking price by the canonical rule the
    // acquisition desk uses (listing ask, else off-market approach ask,
    // else nothing — an unlisted parcel has no ask).
    let value = null, ask = null, listed = 0, distress = 0;
    if (rec && rec.class !== "land") {
      try { value = Math.round(E.assetValue(rec, g.econ, E.gradeOf(g, rec))); } catch { /* no read */ }
    } else if (rec) {
      try { value = Math.round(E.landValue(rec, g.econ)); } catch { /* no read */ }
    }
    const li = (g.listings ?? []).find((l) => l.bbl === bbl);
    if (li) { ask = Math.round(li.ask); listed = 1; distress = li.distress ? 1 : 0; }
    else if (g.approaches?.[bbl]?.ask) ask = Math.round(g.approaches[bbl].ask);
    parcels[bbl] = {
      occ,
      ...(cond != null ? { cond } : {}),
      ...(value != null ? { value } : {}),
      ...(ask != null ? { ask } : {}),
      ...(listed ? { listed: 1 } : {}),
      ...(distress ? { distress: 1 } : {}),
      // The player's deeds, marked: the renderer may celebrate them.
      ...(g.holdings[bbl] ? { held: 1 } : {}),
      class: p.class,
      ...(p.mix ? { mix: p.mix } : {}),
      floors: p.floors,
      lotArea: p.lotArea,
      bldgArea: p.bldgArea,
      yearBuilt: p.yearBuilt,
      address: p.address ?? "",
      district: p.district,
      demandScore: p.demandScore,
      shoreM: p.shoreM,
      corridorM: p.corridorM,
      corner: p.corner,
      centroid: p.centroid,
    };
  }
  return {
    format: "plat-city/1",
    id: city.id,
    seed: city.seed,
    size: city.size,
    name: city.name,
    manifest: city.manifest,
    stats: city.stats,
    context: city.context,
    stations: city.stations,
    buildings3d: city.buildings3d,
    parcels,
    ...extra,
  };
}

/** The line the game view prints: date, cash, book, occupancy. */
export function hudOf(E, city, g) {
  const year = 2000 + Math.floor(g.month / 12);
  const mo = g.month % 12;
  const MONTHS = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"];
  let heldSf = 0, occSum = 0, occN = 0;
  for (const bbl of Object.keys(g.holdings)) {
    const rec = E.resolveRec(city.parcels, g, bbl);
    if (!rec) continue;
    heldSf += rec.bldgArea ?? 0;
    occSum += E.physicalOcc(rec, g.holdings[bbl]);
    occN++;
  }
  const { nw, line, cf, book, attn } = readVitals(E, city, g);
  return {
    city: city.name,
    firm: g.firmName ?? "your firm",
    date: `${MONTHS[mo]} ${year}`,
    month: g.month,
    cash: g.cash,
    holdings: Object.keys(g.holdings).length,
    heldSf: Math.round(heldSf),
    occ: occN ? +(occSum / occN).toFixed(3) : null,
    baseRate: g.econ?.baseRateBps != null ? g.econ.baseRateBps / 100 : null,
    listings: (g.listings ?? []).length,
    year: Math.floor(g.month / 12) + 1,
    phase: g.econ?.phase ?? null,
    book: book.label,
    bookBad: !!book.bad,
    nw,
    cf,
    line,
    lineDrawn: g.loc?.balance ?? 0,
    // The inbox: routed items the glance rail can Open.
    attention: attn.map((a) => a.label),
    attentionItems: attn,
  };
}

function readVitals(E, city, g) {
  let nw = null, line = 0, cf = 0;
  let book = { label: "—", bad: false };
  try { nw = Math.round(E.netWorth(g, city.parcels)); } catch { /* */ }
  try { line = Math.round(E.locLimit(g, city.parcels, nw ?? undefined)); } catch { /* */ }
  try { cf = Math.round(E.portfolioMonthlyCF(g, city.parcels)); } catch { /* */ }
  try { book = E.firmBookStress(g); } catch { /* */ }
  const attn = [];
  try {
    for (const a of (E.attentionItems(g) ?? []).slice(0, 8)) {
      let page = "deals", bbl = null;
      try {
        const r = E.routeAttention(a.key, g);
        page = r.page ?? "deals";
        bbl = r.bbl ?? null;
      } catch { /* */ }
      attn.push({ key: a.key, label: a.label, page, bbl });
    }
  } catch { /* */ }
  return { nw, line, cf, book, attn };
}

const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** Calendar stamp the engine uses (Jan 2000 + month). Not an economic quantity. */
function monthLabel(m) {
  const n = Number(m) || 0;
  return `${MONTH_NAMES[((n % 12) + 12) % 12]} ${2000 + Math.floor(n / 12)}`;
}

function listedAsk(g, bbl) {
  const li = (g.listings ?? []).find((l) => l.bbl === bbl);
  return li ? Math.round(li.ask) : null;
}

function holdingsOf(g) {
  return Object.values(g.holdings ?? {}).filter((h) => h && h.bbl && !g.merged?.[h.bbl]);
}

/** Desk view-models. Engine numbers only — plat paints, it does not price. */
export function writeDesks(E, city, g, dir) {
  mkdirSync(join(dir, "desks"), { recursive: true });
  writeFileSync(join(dir, "desks", "market.json"), JSON.stringify({ rows: marketRows(E, city, g) }));
  const { attn, nw, line, cf } = readVitals(E, city, g);
  writeFileSync(join(dir, "desks", "attention.json"), JSON.stringify({ items: attn }));
  writeFileSync(join(dir, "desks", "portfolio.json"), JSON.stringify(portfolioDesk(E, city, g)));
  writeFileSync(join(dir, "desks", "news.json"), JSON.stringify(newsDesk(g)));
  writeFileSync(join(dir, "desks", "economy.json"), JSON.stringify(economyDesk(g)));
  writeFileSync(join(dir, "desks", "debt.json"), JSON.stringify(debtDesk(E, city, g, line)));
  writeFileSync(join(dir, "desks", "books.json"), JSON.stringify(booksDesk(g, nw, cf)));
}

function marketRows(E, city, g) {
  const rows = [];
  for (const li of g.listings ?? []) {
    const rec = E.resolveRec(city.parcels, g, li.bbl);
    if (!rec) continue;
    let value = null;
    try {
      value = rec.class === "land"
        ? Math.round(E.landValue(rec, g.econ))
        : Math.round(E.assetValue(rec, g.econ, E.gradeOf(g, rec)));
    } catch { /* */ }
    let occ = null;
    try {
      if (rec.class !== "land") occ = +E.occupancy(rec, g.econ).toFixed(3);
    } catch { /* */ }
    rows.push({
      bbl: li.bbl,
      address: rec.address ?? "",
      cls: rec.class,
      district: rec.district ?? "",
      sf: rec.bldgArea ?? 0,
      lotSf: rec.lotArea ?? 0,
      floors: rec.floors ?? 0,
      year: rec.yearBuilt ?? 0,
      ask: Math.round(li.ask),
      value,
      occ,
      distress: li.distress ? 1 : 0,
    });
  }
  rows.sort((a, b) => a.ask - b.ask);
  return rows;
}

function portfolioDesk(E, city, g) {
  const rows = [];
  let totV = 0, totNoi = 0, totDebt = 0;
  for (const h of holdingsOf(g)) {
    const rec = E.resolveRec(city.parcels, g, h.bbl);
    if (!rec) continue;
    let value = 0, noi = 0, occ = null, debt = 0;
    try { value = Math.round(E.ownedHoldingValue(g, city.parcels, h)); } catch { /* */ }
    try { noi = Math.round(E.ownedHoldingNoiYr(g, city.parcels, h)); } catch { /* */ }
    try {
      if (!E.isLeasedFee?.(h) && rec.class !== "land") {
        occ = +E.physicalOcc(rec, h).toFixed(3);
      }
    } catch { /* */ }
    try { debt = Math.round((h.loan?.balance ?? 0) + (E.allocatedAmount?.(g, city.parcels, h.bbl) ?? 0)); } catch {
      debt = Math.round(h.loan?.balance ?? 0);
    }
    const basis = Math.round(h.costBasis ?? 0);
    const pmt = h.loan?.monthlyPmt ?? 0;
    const ask = listedAsk(g, h.bbl);
    totV += value; totNoi += noi; totDebt += debt;
    rows.push({
      bbl: h.bbl,
      address: rec.address ?? h.bbl,
      cls: E.isLeasedFee?.(h) ? "leased-fee" : (rec.class ?? ""),
      district: rec.district ?? "",
      sf: rec.bldgArea ?? 0,
      lotSf: rec.lotArea ?? 0,
      floors: rec.floors ?? 0,
      year: rec.yearBuilt ?? 0,
      occ,
      noi,
      value,
      basis,
      gain: value - basis,
      debt,
      equity: value - debt,
      cf: Math.round(noi / 12 - pmt),
      cond: h.condition ?? null,
      listed: ask != null ? 1 : 0,
      ask,
    });
  }
  rows.sort((a, b) => b.value - a.value);
  let cf = 0;
  try { cf = Math.round(E.portfolioPropertyMonthlyCF(g, city.parcels)); } catch { /* */ }
  return {
    rows,
    totals: {
      n: rows.length,
      value: totV,
      noi: totNoi,
      debt: totDebt,
      equity: totV - totDebt,
      cf,
    },
  };
}

function newsDesk(g) {
  const items = (g.news ?? []).slice(0, 80).map((n) => ({
    q: n.q,
    when: monthLabel(n.q),
    kind: n.kind ?? "info",
    text: n.text ?? "",
    bbl: n.bbl ?? null,
  }));
  const counts = { all: items.length };
  for (const n of items) counts[n.kind] = (counts[n.kind] ?? 0) + 1;
  return { items, counts };
}

function economyDesk(g) {
  const e = g.econ ?? {};
  const CLASSES = ["office", "retail", "multifamily", "industrial"];
  const classes = {};
  for (const k of CLASSES) {
    classes[k] = {
      vac: e.cityVac?.[k] ?? null,
      rent: e.rentIdx?.[k] ?? null,
      cap: e.capRate?.[k] ?? null,
    };
  }
  const hist = e.history ?? [];
  const n = hist.length;
  let jobsYr = null;
  if (n > 12 && hist[n - 1]?.jobs && hist[n - 13]?.jobs) {
    jobsYr = +((hist[n - 1].jobs / hist[n - 13].jobs - 1) * 100).toFixed(1);
  }
  return {
    phase: e.phase ?? null,
    rumoredPhase: e.rumoredPhase ?? null,
    phaseMLeft: e.phaseMLeft ?? null,
    indexRate: e.indexRate ?? null,
    rateRegime: e.rateRegime ?? null,
    creditIdx: e.creditIdx ?? null,
    employIdx: e.employIdx ?? null,
    costIdx: e.costIdx ?? null,
    landIdx: e.landIdx ?? null,
    population: e.population ?? null,
    jobs: e.jobs ?? null,
    jobsYr,
    unemployment: e.unemployment ?? null,
    wageIdx: e.wageIdx ?? null,
    outputIdx: e.outputIdx ?? null,
    cpi: e.cpi ?? null,
    classes,
  };
}

function debtDesk(E, city, g, line) {
  const loans = [];
  let mortgage = 0, ds = 0;
  for (const h of holdingsOf(g)) {
    const rec = E.resolveRec(city.parcels, g, h.bbl);
    const addr = rec?.address ?? h.bbl;
    const add = (loan, kind) => {
      if (!loan || !(loan.balance > 0)) return;
      mortgage += loan.balance;
      ds += (loan.monthlyPmt ?? 0) * 12;
      loans.push({
        bbl: h.bbl,
        address: addr,
        kind,
        product: loan.product ?? kind,
        balance: Math.round(loan.balance),
        rate: loan.ratePct ?? null,
        pmt: Math.round(loan.monthlyPmt ?? 0),
        maturity: monthLabel(loan.maturityM),
        dueInM: loan.maturityM != null ? loan.maturityM - g.month : null,
        floating: !!(loan.floating ?? loan.product === "float"),
      });
    };
    add(h.loan, "senior");
    add(h.mezz, "mezz");
  }
  const f = g.facility;
  if (f?.balance > 0) {
    mortgage += f.balance;
    ds += (f.monthlyPmt ?? 0) * 12;
    loans.push({
      bbl: null,
      address: "Portfolio facility",
      kind: "facility",
      product: f.lender ?? "facility",
      balance: Math.round(f.balance),
      rate: f.ratePct ?? null,
      pmt: Math.round(f.monthlyPmt ?? 0),
      maturity: monthLabel(f.maturityM),
      dueInM: f.maturityM != null ? f.maturityM - g.month : null,
      floating: false,
    });
  }
  let construction = 0;
  for (const d of Object.values(g.developments ?? {})) {
    const bal = d.loanBalance ?? 0;
    if (!(bal > 0)) continue;
    construction += bal;
    const rec = E.resolveRec(city.parcels, g, d.bbl);
    loans.push({
      bbl: d.bbl,
      address: rec?.address ?? d.bbl,
      kind: "construction",
      product: d.lender ?? "construction",
      balance: Math.round(bal),
      rate: d.ratePct ?? null,
      pmt: null,
      maturity: d.deliverM != null ? monthLabel(d.deliverM) : null,
      dueInM: d.deliverM != null ? d.deliverM - g.month : null,
      floating: false,
    });
  }
  let locRate = null;
  try { locRate = E.locRate(g); } catch { /* */ }
  const drawn = g.loc?.balance ?? 0;
  return {
    loc: {
      limit: line,
      drawn: Math.round(drawn),
      available: Math.max(0, Math.round((line ?? 0) - drawn)),
      rate: locRate,
    },
    loans,
    totals: {
      n: loans.length,
      mortgage: Math.round(mortgage),
      construction: Math.round(construction),
      loc: Math.round(drawn),
      total: Math.round(mortgage + construction + drawn),
      ds: Math.round(ds),
    },
  };
}

function booksDesk(g, nw, cf) {
  const years = (g.books ?? []).slice(-8).map((y) => ({
    yr: y.yr,
    when: String(2000 + (y.yr ?? 0)),
    noi: Math.round(y.noi ?? 0),
    debtSvc: Math.round(y.debtSvc ?? 0),
    leasing: Math.round(y.leasing ?? 0),
    capex: Math.round(y.capex ?? 0),
    dev: Math.round(y.dev ?? 0),
    taxes: Math.round(y.taxes ?? 0),
    bought: Math.round(y.bought ?? 0),
    sold: Math.round(y.sold ?? 0),
    ga: Math.round(y.ga ?? 0),
    interest: Math.round(y.interest ?? 0),
    borrowed: Math.round(y.borrowed ?? 0),
  }));
  return {
    cash: Math.round(g.cash ?? 0),
    nw,
    cf,
    taxesPaid: Math.round(g.taxesPaid ?? 0),
    exits: (g.exits ?? []).length,
    years,
  };
}
