// THE CAMPAIGN RUNNER — the process plat's game view drives.
//
//   node tools/game-server.mjs new --seed=1928 --density=village --dir=camp/
//   node tools/game-server.mjs advance --dir=camp/ --months=3
//   ./plat-sim new --dir=camp/          (Node SEA sidecar — docs/GAME-PLAN.md phase 1)
//
// A campaign directory holds the whole game on disk:
//   campaign.json ... seed / size / density (city identity — never changes)
//   state.json ...... the engine GameState, JSON round-trip proven safe
//   city.json ....... plat-city/1 doc with live occupancy (what plat renders)
//   hud.json ........ firm, date, cash, book — the game view's HUD line
//
// Same architecture as everything else here: the sim owns quantities, and it
// runs HERE, in node — the renderer (plat, the web app, anything) reads the
// files and issues commands. Deterministic: same campaign + same commands,
// byte-identical files.
//
// The engine import is static so esbuild can inline it into one CJS blob
// (tools/build-plat-sim.sh). `pnpm engine` must have written test/.engine.mjs.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { makeCity, PROCEDURAL, DEFAULT_SIZE } from "../src/citygen/index.mjs";
import { buildCityDoc, hudOf, writeDesks } from "./citydoc.mjs";
import * as Engine from "../test/.engine.mjs";

const E = globalThis.__PLAT_ENGINE ?? Engine;

// node tools/game-server.mjs CMD …  → argv[1] is the script, CMD at [2]
// ./plat-sim CMD …                  → argv[1] is the invocation path, CMD at [2]
// shebang ./game-server.mjs CMD …   → CMD at [1]
const VERBS = new Set([
  "new", "advance", "buy", "list", "delist", "accept-offer", "offer", "walk",
  "accept-counter", "close", "respond-loi", "draw", "repay", "refi-quotes",
  "refi", "develop-options", "develop",
]);
const userArgv = VERBS.has(process.argv[1]) ? process.argv.slice(1) : process.argv.slice(2);
const cmd = userArgv[0];
const arg = (name, dflt) => {
  const hit = userArgv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split("=").slice(1).join("=") : dflt;
};
const dir = arg("dir", "campaign");

function buildParcels(meta) {
  // Godot shells a fresh node process per verb. An in-memory cache dies
  // with the process. The island is a pure function of seed/size/density —
  // write it once, read it back. Advance is the tick, not a regen.
  const cached = join(dir, "island.json");
  if (existsSync(cached)) {
    const t0 = Date.now();
    const city = JSON.parse(readFileSync(cached, "utf8"));
    console.log(`island cache ${Date.now() - t0}ms`);
    return city;
  }
  const t0 = Date.now();
  const city = makeCity(PROCEDURAL, meta.seed, { size: meta.size, density: meta.density });
  E.normalizeParcels(city.parcels);
  writeFileSync(cached, JSON.stringify(city));
  console.log(`island gen ${Date.now() - t0}ms -> ${cached}`);
  return city;
}

function writeAll(meta, city, g) {
  writeFileSync(join(dir, "state.json"), JSON.stringify(g));
  // A century is long and mistakes are permanent: every write keeps a
  // dated snapshot too (docs/GAME-PLAN.md phase 5).
  mkdirSync(join(dir, "saves"), { recursive: true });
  writeFileSync(join(dir, "saves", `m${String(g.month).padStart(4, "0")}.json`), JSON.stringify(g));
  writeFileSync(join(dir, "city.json"),
    JSON.stringify(buildCityDoc(E, city, g, { months: g.month })));
  const hud = hudOf(E, city, g);
  writeFileSync(join(dir, "hud.json"), JSON.stringify(hud));
  writeDesks(E, city, g, dir);
  console.log(`${meta.seed}@${city.name} month=${g.month} cash=$${(g.cash / 1e6).toFixed(2)}M ` +
    `holdings=${hud.holdings} occ=${hud.occ ?? "—"} book=${hud.book} -> ${dir}/`);
}

if (cmd === "new") {
  const meta = {
    seed: (parseInt(arg("seed", String(((Math.random() * 0xffffffff) >>> 0) || 1)), 10) >>> 0) || 1,
    size: arg("size", DEFAULT_SIZE),
    density: arg("density", "village"),
  };
  mkdirSync(dir, { recursive: true });
  // Record the .mjs path so a front-end that only knows the campaign
  // directory can find the sim. Empty inside the SEA sidecar — plat then
  // looks for plat-sim beside its own executable.
  const script = process.argv[1] ?? "";
  meta.runner = /\.(mjs|cjs|js)$/.test(script) ? resolve(script) : "";
  const cash0 = Math.max(0, parseInt(arg("cash", "2500000"), 10) || 2500000);
  meta.cash0 = cash0;
  writeFileSync(join(dir, "campaign.json"), JSON.stringify(meta));
  const city = buildParcels(meta);
  const bbls = Object.keys(city.parcels);
  let g = E.firstListings(E.newGame(7000 + meta.seed, city.parcels, cash0), city.parcels, bbls);
  writeAll(meta, city, g);
} else if (cmd === "advance") {
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const months = Math.max(1, parseInt(arg("months", "1"), 10) || 1);
  const until = arg("until", "");
  const city = buildParcels(meta);
  const bbls = Object.keys(city.parcels);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  const before = new Set((() => { try { return E.attentionItems(g).map((a) => a.key); } catch { return []; } })());
  let stopped = "";
  for (let m = 0; m < months && !g.gameOver; m++) {
    g = E.advanceMonth(g, city.parcels, bbls, city.adjacency);
    if (until === "attention") {
      let now = [];
      try { now = E.attentionItems(g); } catch { /* */ }
      const fresh = now.find((a) => !before.has(a.key));
      if (fresh) { stopped = fresh.label; break; }
      if (months > 1 && now.length) { stopped = now[0].label; break; }
    }
  }
  writeAll(meta, city, g);
  if (stopped) console.log(`stopped: ${stopped}`);
} else if (cmd === "buy") {
  // BUY AT ASK (docs/GAME-PLAN.md phase 3.2): the canonical price rule,
  // then the engine's purchase path decides. The engine's err string is
  // the whole result contract — plat shows it verbatim.
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const city = buildParcels(meta);
  const bbls = Object.keys(city.parcels);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  const li = (g.listings ?? []).find((l) => l.bbl === bbl);
  const approach = g.approaches?.[bbl];
  const rec = E.resolveRec(city.parcels, g, bbl);
  const price = li?.ask ?? approach?.ask ??
    (rec ? (rec.class === "land" ? E.landValue(rec, g.econ)
          : E.assetValue(rec, g.econ, E.gradeOf(g, rec))) : 0);
  const r = E.executePurchase(g, city.parcels, bbl, price, "cash", !li, 1);
  const result = { op: "buy", bbl, price: Math.round(price), ok: !r.err, err: r.err ?? null };
  writeFileSync(join(dir, "result.json"), JSON.stringify(result));
  if (r.err) {
    console.error("BUY FAILED: " + r.err);
    writeAll(meta, city, g);
    process.exit(2);
  }
  g = r.s;
  writeAll(meta, city, g);
  console.log(`BOUGHT ${bbl} for $${(price / 1e6).toFixed(2)}M`);
} else if (cmd === "develop-options") {
  // What pencils on this lot: the engine underwrites candidate designs.
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const city = buildParcels(meta);
  const g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  const options = [];
  for (const use of ["office", "multifamily", "retail", "industrial"]) {
    for (const floors of [3, 6, 10, 16, 24]) {
      try {
        const uw = E.underwriteDevelopment(g, city.parcels, bbl, use, floors);
        if (uw?.plan) options.push({
          use, floors, sf: Math.round(uw.plan.sf), cost: Math.round(uw.plan.costTotal),
          months: uw.plan.months != null ? Math.round(uw.plan.months) : null,
          clears: !!uw.clears, financeable: !!uw.financeable, why: uw.why ?? null,
        });
      } catch { /* infeasible */ }
    }
  }
  writeFileSync(join(dir, "options.json"), JSON.stringify({ bbl, options }));
  console.log(`${options.length} designs underwritten for ${bbl} -> options.json`);
} else if (cmd === "list") {
  // LIST AT APPRAISAL (or --ask=). Quiet is the default; --mode=marketed
  // runs a process. The engine names the fee and the wait.
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const mode = arg("mode", "quiet") === "marketed" ? "marketed" : "quiet";
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  const h = g.holdings?.[bbl];
  let ask = Math.max(0, parseInt(arg("ask", "0"), 10) || 0);
  if (!(ask > 0) && h) {
    try { ask = Math.round(E.ownedHoldingValue(g, city.parcels, h)); } catch { /* */ }
  }
  const r = E.listForSale(g, city.parcels, bbl, ask, mode);
  const result = { op: "list", bbl, ask: Math.round(ask), mode, ok: !r.err, err: r.err ?? null };
  writeFileSync(join(dir, "result.json"), JSON.stringify(result));
  if (r.err) {
    console.error("LIST FAILED: " + r.err);
    writeAll(meta, city, g);
    process.exit(2);
  }
  g = r.s;
  writeAll(meta, city, g);
  console.log(`LISTED ${bbl} at $${(ask / 1e6).toFixed(2)}M (${mode})`);
} else if (cmd === "delist") {
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  if (!g.holdings?.[bbl]) {
    const result = { op: "delist", bbl, ok: false, err: "You don't own that parcel." };
    writeFileSync(join(dir, "result.json"), JSON.stringify(result));
    console.error("DELIST FAILED: " + result.err);
    process.exit(2);
  }
  g = E.delist(g, bbl);
  writeFileSync(join(dir, "result.json"), JSON.stringify({ op: "delist", bbl, ok: true, err: null }));
  writeAll(meta, city, g);
  console.log(`DELISTED ${bbl}`);
} else if (cmd === "accept-offer") {
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  const r = E.acceptSaleOffer(g, city.parcels, bbl);
  const result = { op: "accept-offer", bbl, ok: !r.err, err: r.err ?? null };
  writeFileSync(join(dir, "result.json"), JSON.stringify(result));
  if (r.err) {
    console.error("ACCEPT FAILED: " + r.err);
    writeAll(meta, city, g);
    process.exit(2);
  }
  g = r.s;
  writeAll(meta, city, g);
  console.log(`SOLD ${bbl}`);
} else if (cmd === "draw") {
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  let amt = Math.max(0, parseInt(arg("amt", "0"), 10) || 0);
  if (!(amt > 0)) {
    try { amt = Math.round(E.locAvailable(g, city.parcels)); } catch { /* */ }
  }
  const r = E.drawLoc(g, city.parcels, amt);
  const result = { op: "draw", amt, ok: !r.err, err: r.err ?? null };
  writeFileSync(join(dir, "result.json"), JSON.stringify(result));
  if (r.err) {
    console.error("DRAW FAILED: " + r.err);
    writeAll(meta, city, g);
    process.exit(2);
  }
  g = r.s;
  writeAll(meta, city, g);
  console.log(`DREW $${(amt / 1e6).toFixed(2)}M on the line`);
} else if (cmd === "repay") {
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  let amt = Math.max(0, parseInt(arg("amt", "0"), 10) || 0);
  if (!(amt > 0)) amt = Math.round(g.loc?.balance ?? 0);
  const r = E.repayLoc(g, amt);
  const result = { op: "repay", amt, ok: !r.err, err: r.err ?? null };
  writeFileSync(join(dir, "result.json"), JSON.stringify(result));
  if (r.err) {
    console.error("REPAY FAILED: " + r.err);
    writeAll(meta, city, g);
    process.exit(2);
  }
  g = r.s;
  writeAll(meta, city, g);
  console.log(`REPAID $${(amt / 1e6).toFixed(2)}M on the line`);
} else if (cmd === "refi-quotes") {
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const city = buildParcels(meta);
  const g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  let pack = { bbl, value: 0, payoff: 0, quotes: [] };
  try { pack = { bbl, ...E.refiQuotes(g, city.parcels, bbl) }; } catch { /* */ }
  const quotes = (pack.quotes ?? []).map((q) => ({
    id: q.id,
    label: q.label,
    rate: q.ratePct ?? null,
    proceeds: Math.round(q.maxProceeds ?? 0),
    available: !!q.available,
    why: q.why ?? null,
    binding: q.binding ?? null,
  }));
  writeFileSync(join(dir, "refi.json"), JSON.stringify({
    bbl, value: Math.round(pack.value ?? 0), payoff: Math.round(pack.payoff ?? 0), quotes,
  }));
  console.log(`${quotes.filter((q) => q.available).length}/${quotes.length} desks will quote ${bbl} -> refi.json`);
} else if (cmd === "refi") {
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const product = arg("product", "savings");
  const lev = Math.max(0, Math.min(1, parseFloat(arg("lev", "1")) || 1));
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  const r = E.refinance(g, city.parcels, bbl, product, lev);
  const result = { op: "refi", bbl, product, ok: !r.err, err: r.err ?? null };
  writeFileSync(join(dir, "result.json"), JSON.stringify(result));
  if (r.err) {
    console.error("REFI FAILED: " + r.err);
    writeAll(meta, city, g);
    process.exit(2);
  }
  g = r.s;
  writeAll(meta, city, g);
  console.log(`REFINANCED ${bbl} with ${product}`);
} else if (cmd === "develop") {
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const use = arg("use", "multifamily");
  const floors = parseInt(arg("floors", "6"), 10) || 6;
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  const r = E.startDevelopment(g, city.parcels, bbl, use, floors);
  const result = { op: "develop", bbl, use, floors, ok: !r.err, err: r.err ?? null };
  writeFileSync(join(dir, "result.json"), JSON.stringify(result));
  if (r.err) {
    console.error("DEVELOP FAILED: " + r.err);
    writeAll(meta, city, g);
    process.exit(2);
  }
  g = r.s;
  writeAll(meta, city, g);
  console.log(`DEVELOPING ${bbl}: ${floors}-floor ${use}`);
} else if (cmd === "approach") {
  // KNOCK. The engine names their ask, refuses, or says make-me-an-offer.
  // Reserve is not written to result.json.
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  const r = E.approachOwner(g, city.parcels, city.adjacency, bbl);
  const result = {
    op: "approach", bbl,
    ok: !r.err,
    err: r.err ?? null,
    refused: !!r.refused,
    blind: !!r.blind,
    ask: r.ask != null ? Math.round(r.ask) : null,
  };
  writeFileSync(join(dir, "result.json"), JSON.stringify(result));
  if (r.err) {
    console.error("APPROACH FAILED: " + r.err);
    writeAll(meta, city, g);
    process.exit(2);
  }
  g = r.s;
  writeAll(meta, city, g);
  if (r.refused) console.log(`APPROACHED ${bbl} — not selling`);
  else if (r.blind) console.log(`APPROACHED ${bbl} — make me an offer`);
  else console.log(`APPROACHED ${bbl} — they would take $${((r.ask ?? 0) / 1e6).toFixed(2)}M`);
} else if (cmd === "offer") {
  // OFFER AT ASK (or --price=). The engine negotiates; asking price is the
  // listing ask, not a coefficient we invent. A number at or above their
  // reserve is a handshake and a deposit, not a deed.
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  let price = Math.max(0, parseInt(arg("price", "0"), 10) || 0);
  if (!(price > 0)) {
    const li = (g.listings ?? []).find((l) => l.bbl === bbl);
    const approach = g.approaches?.[bbl];
    price = Math.round(li?.ask ?? approach?.ask ?? 0);
  }
  const r = E.negotiate(g, city.parcels, bbl, price, false);
  const result = { op: "offer", bbl, price, ok: !r.err, err: r.err ?? null, msg: r.msg ?? null };
  writeFileSync(join(dir, "result.json"), JSON.stringify(result));
  if (r.err) {
    console.error("OFFER FAILED: " + r.err);
    writeAll(meta, city, g);
    process.exit(2);
  }
  g = r.s;
  writeAll(meta, city, g);
  console.log(`OFFERED ${bbl} at $${(price / 1e6).toFixed(2)}M${r.msg ? " — " + r.msg : ""}`);
} else if (cmd === "walk") {
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  const r = E.walkAway(g, city.parcels, bbl);
  writeFileSync(join(dir, "result.json"), JSON.stringify({
    op: "walk", bbl, ok: true, err: null, msg: r.msg ?? null,
  }));
  g = r.s;
  writeAll(meta, city, g);
  console.log(`WALKED ${bbl}${r.msg ? " — " + r.msg : ""}`);
} else if (cmd === "accept-counter") {
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  const r = E.acceptCounter(g, city.parcels, bbl);
  const result = { op: "accept-counter", bbl, ok: !r.err, err: r.err ?? null, msg: r.msg ?? null };
  writeFileSync(join(dir, "result.json"), JSON.stringify(result));
  if (r.err) {
    console.error("ACCEPT-COUNTER FAILED: " + r.err);
    writeAll(meta, city, g);
    process.exit(2);
  }
  g = r.s;
  writeAll(meta, city, g);
  console.log(`ACCEPTED COUNTER ${bbl}${r.msg ? " — " + r.msg : ""}`);
} else if (cmd === "close") {
  // FUND THE AGREED PRICE. product and lev are the engine's closeDeal
  // arguments; cash / 1 is the unlevered close, not a default we priced.
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const bbl = arg("bbl", "");
  const product = arg("product", "cash");
  const lev = Math.max(0, Math.min(1, parseFloat(arg("lev", "1")) || 1));
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  const r = E.closeDeal(g, city.parcels, bbl, product, lev);
  const result = { op: "close", bbl, product, ok: !r.err, err: r.err ?? null, msg: r.msg ?? null };
  writeFileSync(join(dir, "result.json"), JSON.stringify(result));
  if (r.err) {
    console.error("CLOSE FAILED: " + r.err);
    writeAll(meta, city, g);
    process.exit(2);
  }
  g = r.s;
  writeAll(meta, city, g);
  console.log(`CLOSED ${bbl}${r.msg ? " — " + r.msg : ""}`);
} else if (cmd === "respond-loi") {
  // ACCEPT or PASS a letter. Counter waits — plat does not invent a rent.
  const meta = JSON.parse(readFileSync(join(dir, "campaign.json"), "utf8"));
  const id = parseInt(arg("id", "0"), 10) || 0;
  const action = arg("action", "accept") === "decline" ? "decline" : "accept";
  const fund = arg("fund", "") === "1";
  const city = buildParcels(meta);
  let g = JSON.parse(readFileSync(join(dir, "state.json"), "utf8"));
  const r = E.respondLOI(g, city.parcels, id, action, fund);
  const result = { op: "respond-loi", id, action, ok: !r.err, err: r.err ?? null, msg: r.msg ?? null };
  writeFileSync(join(dir, "result.json"), JSON.stringify(result));
  if (r.err) {
    console.error("LOI FAILED: " + r.err);
    writeAll(meta, city, g);
    process.exit(2);
  }
  g = r.s;
  writeAll(meta, city, g);
  console.log(`${action.toUpperCase()} LOI ${id}${r.msg ? " — " + r.msg : ""}`);
} else {
  console.error("usage: plat-sim new|advance|buy|list|delist|accept-offer|offer|walk|accept-counter|close|respond-loi|draw|repay|refi-quotes|refi|develop-options|develop --dir=D");
  process.exit(1);
}
