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
    const sale = g.holdings[bbl]?.sale;
    if (li) { ask = Math.round(li.ask); listed = 1; distress = li.distress ? 1 : 0; }
    else if (sale?.ask) { ask = Math.round(sale.ask); listed = 1; }
    else if (g.approaches?.[bbl]?.ask) ask = Math.round(g.approaches[bbl].ask);
    const approach = approachView(g, bbl);
    parcels[bbl] = {
      occ,
      ...(cond != null ? { cond } : {}),
      ...(value != null ? { value } : {}),
      ...(ask != null ? { ask } : {}),
      ...(listed ? { listed: 1 } : {}),
      ...(distress ? { distress: 1 } : {}),
      // The player's deeds, marked: the renderer may celebrate them.
      ...(g.holdings[bbl] ? { held: 1 } : {}),
      ...(g.developments?.[bbl] ? { developing: 1 } : {}),
      ...(g.talks?.[bbl] ? { talk: 1, contracted: g.talks[bbl].agreed ? 1 : 0 } : {}),
      ...(approach ? { approach } : {}),
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
  const yo = yearOneOf(E, city, g, nw);
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
    yearOne: yo.yearOne,
    monthsLeft: yo.monthsLeft,
    next: yo.next,
    rungs: yo.rungs,
    deals: Object.keys(g.talks ?? {}).length + principalLetters(E, g).length,
    letters: principalLetters(E, g).length,
  };
}

const YEAR_ONE_IDS = ["deed1", "lease1", "tower1", "exit1", "nw25"];

const RUNG_SHORT = {
  deed1: "Deed",
  lease1: "Lease",
  tower1: "Tower",
  exit1: "Exit",
  nw25: "$25M",
};

function milestonePage(id) {
  if (id === "deed1") return "market";
  if (id === "lease1") return "leasing";
  if (id === "tower1") return "property";
  return "portfolio";
}

/** A holding with floors. Vacant dirt has no roll — lease1 cannot fire on it. */
function holdingHasFloors(E, city, g) {
  for (const bbl of Object.keys(g.holdings ?? {})) {
    const rec = E.resolveRec?.(city?.parcels, g, bbl);
    if (rec && rec.class !== "land" && Number(rec.floors ?? rec.bldgArea ?? 0) > 0) {
      return true;
    }
  }
  return false;
}

function holdingHasLand(E, city, g) {
  for (const bbl of Object.keys(g.holdings ?? {})) {
    if (g.developments?.[bbl]) continue;
    const rec = E.resolveRec?.(city?.parcels, g, bbl);
    if (rec?.class === "land") return true;
  }
  return false;
}

function lease1Hint(E, city, g) {
  if (Object.keys(g.developments ?? {}).length && !holdingHasFloors(E, city, g)) {
    return { page: "portfolio", note: "The job is in the ground. A new tenant comes after it delivers." };
  }
  if (!holdingHasFloors(E, city, g)) {
    return { page: "market", note: "Buy a building. Vacant dirt has no roll." };
  }
  return { page: "leasing", note: "A new tenant, after you bought. Renewing inherited paper does not count." };
}

/** Every founding rung, done or not. The engine's test decides; we paint.
 *  After January 2001 the header is no longer YEAR ONE, but unfinished
 *  rungs stay — lease1 must not hide a tower or an exit. */
function yearOneOf(E, city, g, nw) {
  const month = g.month ?? 0;
  const yearOne = month < 12;
  const rungs = [];
  let next = null;
  try {
    for (const m of (E.MILESTONES ?? [])) {
      if (!YEAR_ONE_IDS.includes(m.id)) continue;
      const done = typeof m.test === "function" && !!m.test(g, nw ?? 0);
      const stamped = g.milestones?.[m.id];
      const row = {
        id: m.id,
        label: m.label,
        short: RUNG_SHORT[m.id] ?? m.id,
        page: milestonePage(m.id),
        done,
        at: stamped != null ? monthLabel(stamped) : null,
      };
      if (!done && m.id === "lease1") {
        const hint = lease1Hint(E, city, g);
        row.page = hint.page;
        row.note = hint.note;
      }
      if (!done && m.id === "tower1") {
        row.page = holdingHasLand(E, city, g) ? "property" : "portfolio";
      }
      if (!done && m.id === "exit1") {
        row.page = Object.keys(g.holdings ?? {}).length ? "portfolio" : "market";
      }
      rungs.push(row);
      if (!done && !next) {
        next = { id: row.id, label: row.label, page: row.page, ...(row.note ? { note: row.note } : {}) };
      }
    }
  } catch { /* */ }
  return { yearOne, monthsLeft: yearOne ? Math.max(0, 12 - month) : 0, next, rungs };
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
      if (!bbl && String(a.key).startsWith("loi:")) {
        const id = Number(String(a.key).split(":")[1]);
        const l = (g.lois ?? []).find((x) => x.id === id);
        if (l) bbl = l.bbl;
        page = page || "deals";
      }
      attn.push(enrichAttention(E, city, g, a, page, bbl));
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

/** Inbox row plus enough payload to paint a decision card. */
function enrichAttention(E, city, g, a, page, bbl) {
  const key = String(a.key ?? "");
  const head = key.split(":")[0];
  const item = {
    key, label: a.label, page, bbl,
    kind: head, blocking: false, letter: null, offer: null,
  };
  if (head === "loi") {
    const id = Number(key.split(":")[1]);
    const l = (g.lois ?? []).find((x) => x.id === id);
    if (l) {
      item.blocking = true;
      item.kind = "loi";
      item.letter = letterOf(E, city, g, l);
      item.bbl = item.bbl ?? l.bbl;
    }
  } else if (head === "offer" || head === "sale-bids") {
    item.blocking = true;
    const bb = bbl ?? key.split(":")[1];
    const h = g.holdings?.[bb];
    const rec = E.resolveRec(city.parcels, g, bb);
    if (h?.sale?.offer) {
      item.offer = {
        bbl: bb,
        address: rec?.address ?? bb,
        price: Math.round(h.sale.offer.price),
        ask: Math.round(h.sale.ask ?? 0),
        expires: h.sale.offer.expiresM != null ? monthLabel(h.sale.offer.expiresM) : null,
      };
    }
  }
  return item;
}

/**
 * Off-market conversation, view-model only. Never export reserve — that
 * number stays in the owner's head (engine/types.ts Approach).
 */
function approachView(g, bbl) {
  const a = g.approaches?.[bbl];
  if (!a) return null;
  const untilM = a.coldUntilM ?? ((a.q ?? 0) + 6);
  const row = {
    q: a.q ?? 0,
    until: monthLabel(untilM),
    untilM,
    refused: a.refused ? 1 : 0,
    inbound: a.inbound ? 1 : 0,
    named: a.named ? 1 : 0,
  };
  if (a.refused) return row;
  if (a.ask != null && a.ask > 0) {
    row.ask = Math.round(a.ask);
    return row;
  }
  row.blind = 1;
  return row;
}

function listedAsk(g, bbl) {
  const li = (g.listings ?? []).find((l) => l.bbl === bbl);
  return li ? Math.round(li.ask) : null;
}

function holdingsOf(g) {
  return Object.values(g.holdings ?? {}).filter((h) => h && h.bbl && !g.merged?.[h.bbl]);
}

/**
 * One deed's file extras. History is propertyTimeline + describePropertyEvent
 * (engine prose). Money is Holding.hist, decoded the way the engine stored it:
 * [month, occ×1000, rent psf ×100, NOI/yr]. No invented offer bounds.
 */
function deedOf(E, city, g, bbl) {
  const rec = E.resolveRec?.(city.parcels, g, bbl);
  const h = g.holdings?.[bbl];
  let timeline = [];
  try { timeline = E.propertyTimeline(g, bbl) ?? []; } catch { /* */ }
  const history = timeline.map((e) => {
    const row = { when: monthLabel(e.m), title: e.kind ?? "event", detail: "", kind: e.kind ?? "" };
    try {
      const d = E.describePropertyEvent(e);
      if (d) {
        if (d.when) row.when = d.when;
        if (d.title) row.title = d.title;
        if (d.detail) row.detail = d.detail;
      }
    } catch { /* */ }
    return row;
  });
  let money = null;
  if (h) {
    const stamps = (h.hist ?? []).map((r) => ({
      m: r[0],
      when: monthLabel(r[0]),
      occ: (r[1] ?? 0) / 1000,
      rentPsf: (r[2] ?? 0) / 100,
      noi: Math.round(r[3] ?? 0),
    }));
    const n = stamps.length;
    let delta = null;
    if (n >= 2) {
      const a = stamps[0];
      const b = stamps[n - 1];
      const yrs = Math.max(0.25, (b.m - a.m) / 12);
      delta = {
        occPp: +((b.occ - a.occ) * 100).toFixed(1),
        rentPct: a.rentPsf > 0 ? +((b.rentPsf / a.rentPsf - 1) * 100).toFixed(1) : null,
        yrs: +yrs.toFixed(2),
      };
    }
    money = {
      heldSince: monthLabel(h.boughtM),
      stamps,
      latest: n ? stamps[n - 1] : null,
      delta,
    };
  }
  if (!history.length && !money) return null;
  return {
    bbl,
    address: rec?.address ?? bbl,
    history,
    money,
  };
}

function deedsDesk(E, city, g) {
  const seen = new Set();
  const add = (bbl) => { if (bbl) seen.add(String(bbl)); };
  for (const h of holdingsOf(g)) add(h.bbl);
  for (const li of (g.listings ?? [])) add(li.bbl);
  for (const bbl of Object.keys(g.talks ?? {})) add(bbl);
  for (const bbl of Object.keys(g.propertyLog ?? {})) add(bbl);
  for (const bbl of Object.keys(g.approaches ?? {})) add(bbl);
  for (const bbl of Object.keys(g.developments ?? {})) add(bbl);
  for (const c of (g.comps ?? [])) add(c.bbl);
  const files = {};
  for (const bbl of seen) {
    const d = deedOf(E, city, g, bbl);
    if (d) files[bbl] = d;
  }
  return { files };
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
  writeFileSync(join(dir, "desks", "map.json"), JSON.stringify(mapDesk(E, city, g, attn)));
  writeFileSync(join(dir, "desks", "deals.json"), JSON.stringify(dealsDesk(E, city, g)));
  writeFileSync(join(dir, "desks", "leasing.json"), JSON.stringify(leasingDesk(E, city, g)));
  writeFileSync(join(dir, "desks", "deeds.json"), JSON.stringify(deedsDesk(E, city, g)));
}

/** Letters the principal still owns. Staff / agent coverage is the engine's. */
function principalLetters(E, g) {
  const out = [];
  for (const l of (g.lois ?? [])) {
    try {
      if (typeof E.loiNeedsPrincipal === "function" && !E.loiNeedsPrincipal(g, l)) continue;
    } catch { /* */ }
    out.push(l);
  }
  return out;
}

/** Engine CREDIT_LABEL is C/B/A. A display table, not a quantity. */
function creditLabel(n) {
  return ["C", "B", "A"][n] ?? String(n ?? "");
}

function letterOf(E, city, g, l) {
  const rec = E.resolveRec(city.parcels, g, l.bbl);
  let signing = null;
  try {
    const h = g.holdings?.[l.bbl];
    const fee = h && E.exclusiveFeeRate ? E.exclusiveFeeRate(h) : undefined;
    signing = Math.round(E.loiSigningCost(l, fee));
  } catch { /* */ }
  return {
    id: l.id,
    bbl: l.bbl,
    address: rec?.address ?? l.bbl,
    name: l.name ?? "",
    kind: l.kind ?? "new",
    use: l.use ?? rec?.class ?? "",
    sf: Math.round(l.sf ?? 0),
    rentPsf: l.rentPsf ?? null,
    termM: l.termM ?? null,
    tiPsf: l.tiPsf ?? 0,
    freeM: l.freeM ?? 0,
    bumpPct: l.bumpPct ?? null,
    credit: creditLabel(l.credit),
    sector: l.sector ?? "",
    expires: l.expiresM != null ? monthLabel(l.expiresM) : null,
    monthsLeft: l.expiresM != null ? l.expiresM - (g.month ?? 0) : null,
    signing,
    stage: l.stage ?? "open",
    referred: !!l.referred,
  };
}

function leasingDesk(E, city, g) {
  const buildings = [];
  let leasedSf = 0, vacantSf = 0, noi = 0;
  for (const h of holdingsOf(g)) {
    const rec = E.resolveRec(city.parcels, g, h.bbl);
    if (!rec || rec.class === "land") continue;
    const tenants = (h.tenants ?? []).map((t) => ({
      name: t.name ?? "",
      use: t.use ?? rec.class ?? "",
      sector: t.sector ?? "",
      credit: creditLabel(t.credit),
      sf: Math.round(t.sf ?? 0),
      rentPsf: t.rentPsf ?? null,
      start: monthLabel(t.startM),
      end: monthLabel(t.endM),
      monthsLeft: t.endM != null ? t.endM - (g.month ?? 0) : null,
    }));
    let occ = null, vac = 0, holdingNoi = 0;
    try {
      if (!E.isLeasedFee?.(h)) occ = +E.physicalOcc(rec, h).toFixed(3);
    } catch { /* */ }
    try { vac = Math.round(E.vacantSf(rec, h)); } catch { /* */ }
    try { holdingNoi = Math.round(E.ownedHoldingNoiYr(g, city.parcels, h)); } catch { /* */ }
    const letSf = tenants.reduce((a, t) => a + t.sf, 0);
    leasedSf += letSf;
    vacantSf += vac;
    noi += holdingNoi;
    buildings.push({
      bbl: h.bbl,
      address: rec.address ?? h.bbl,
      cls: rec.class ?? "",
      sf: rec.bldgArea ?? 0,
      occ,
      vacantSf: vac,
      noi: holdingNoi,
      tenants,
    });
  }
  buildings.sort((a, b) => (b.vacantSf ?? 0) - (a.vacantSf ?? 0) || (b.sf ?? 0) - (a.sf ?? 0));
  const letters = principalLetters(E, g).map((l) => letterOf(E, city, g, l));
  return {
    buildings,
    letters,
    totals: {
      n: buildings.length,
      leasedSf: Math.round(leasedSf),
      vacantSf: Math.round(vacantSf),
      noi,
      letters: letters.length,
    },
  };
}

/** Live talks, inbound sale offers, and letters — view models only. */
function dealsDesk(E, city, g) {
  const talks = [];
  for (const t of Object.values(g.talks ?? {})) {
    const rec = E.resolveRec(city.parcels, g, t.bbl);
    const agreed = !!t.agreed;
    talks.push({
      bbl: t.bbl,
      address: rec?.address ?? t.bbl,
      cls: rec?.class ?? "",
      district: rec?.district ?? "",
      seller: t.sellerName ?? "",
      yourPrice: Math.round(t.yourPrice ?? 0),
      theirPrice: Math.round(t.theirPrice ?? 0),
      agreed,
      agreedPrice: t.agreedPrice != null ? Math.round(t.agreedPrice) : null,
      deposit: Math.round(t.deposit ?? 0),
      closeBy: t.closeByM != null ? monthLabel(t.closeByM) : null,
      monthsLeft: t.closeByM != null ? t.closeByM - (g.month ?? 0) : null,
      note: t.note ?? "",
      final: !!t.final,
      status: agreed ? "agreed" : (t.final ? "final" : "talking"),
    });
  }
  talks.sort((a, b) => (b.agreed ? 1 : 0) - (a.agreed ? 1 : 0)
    || (a.monthsLeft ?? 99) - (b.monthsLeft ?? 99));
  const lois = principalLetters(E, g).map((l) => letterOf(E, city, g, l));
  const inbound = [];
  for (const h of holdingsOf(g)) {
    const offer = h.sale?.offer;
    if (!offer) continue;
    const rec = E.resolveRec(city.parcels, g, h.bbl);
    inbound.push({
      bbl: h.bbl,
      address: rec?.address ?? h.bbl,
      ask: Math.round(h.sale?.ask ?? 0),
      price: Math.round(offer.price ?? 0),
      expires: offer.expiresM != null ? monthLabel(offer.expiresM) : null,
    });
  }
  const committed = talks
    .filter((t) => t.agreed)
    .reduce((a, t) => a + (t.agreedPrice ?? 0), 0);
  return {
    talks,
    lois,
    inbound,
    counts: {
      talks: talks.length,
      agreed: talks.filter((t) => t.agreed).length,
      lois: lois.length,
      inbound: inbound.length,
    },
    committed,
    maxTalks: E.MAX_TALKS ?? 4,
  };
}

function mapDesk(E, city, g, attn) {
  const deliveries = [];
  for (const d of Object.values(g.developments ?? {})) {
    const rec = E.resolveRec(city.parcels, g, d.bbl);
    const address = rec?.address ?? d.bbl;
    deliveries.push({
      bbl: d.bbl,
      address,
      deliverM: d.deliverM ?? null,
      label: `${address} · delivers ${d.deliverM != null ? monthLabel(d.deliverM) : "?"}`,
    });
  }
  deliveries.sort((a, b) => (a.deliverM ?? 0) - (b.deliverM ?? 0));
  const balloons = [];
  for (const h of holdingsOf(g)) {
    if (!h.loan) continue;
    const months = (h.loan.maturityM ?? 0) - (g.month ?? 0);
    if (months <= 0 || months > 18) continue;
    const rec = E.resolveRec(city.parcels, g, h.bbl);
    const address = rec?.address ?? h.bbl;
    balloons.push({
      bbl: h.bbl,
      address,
      months,
      label: `${address} · balloon ${monthLabel(h.loan.maturityM)} (${months} mo)`,
    });
  }
  balloons.sort((a, b) => a.months - b.months);
  let deliveredSf = 0;
  for (const h of holdingsOf(g)) {
    if (h.deliveredM === undefined) continue;
    const b = g.built?.[h.bbl];
    if (b) deliveredSf += b.bldgArea ?? 0;
  }
  return {
    attentionN: (attn ?? []).length,
    deliveries: deliveries.slice(0, 3),
    balloons: balloons.slice(0, 3),
    deliveredSf: Math.round(deliveredSf),
  };
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
    const sale = h.sale;
    const tapeAsk = listedAsk(g, h.bbl);
    const ask = sale?.ask ?? tapeAsk;
    const job = g.developments?.[h.bbl];
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
      listAsk: value,
      saleMode: sale?.mode ?? null,
      offer: sale?.offer?.price ?? null,
      developing: job ? 1 : 0,
      jobUse: job?.use ?? null,
      jobFloors: job?.floors ?? null,
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
  let available = Math.max(0, Math.round((line ?? 0) - drawn));
  try { available = Math.round(E.locAvailable(g, city.parcels)); } catch { /* */ }
  const cash = Math.round(g.cash ?? 0);
  return {
    loc: {
      limit: line,
      drawn: Math.round(drawn),
      available,
      rate: locRate,
      cash,
      drawAmt: available,
      repayAmt: Math.min(Math.round(drawn), Math.max(0, cash)),
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
