# plat, the game: Broadway & Wall's engine and UI inside the 3D city

The goal, stated once: **plat's rendered city is the game board.** Everything
the Broadway & Wall web app can do — found a firm, read a market, negotiate,
buy, develop, lease, borrow, survive a century — happens by clicking on the
buildings plat draws, with the same engine deciding every number. The web app
becomes a debug view; the shipped game is one download.

The architecture already decided how: the sim owns quantities and runs
headless (plat-econ, gate-green in CI); plat owns form. The game UI is a
third thing — a *client* of the sim — and it lives in plat, talking to the
engine through the campaign runner. Nothing below moves a number into GDScript.

## What exists today (the foundation this builds on)

- Campaign runner (`plat-econ/tools/game-server.mjs`, overlaid from
  `tools/runner/`): the year-one verb surface on a JSON campaign dir.
  GameState proven JSON-round-trip safe; city.json carries live occupancy
  and `held` flags; hud.json carries firm/date/cash.
- `plat-sim` / `plat-sim.exe`: Node SEA sidecar (`tools/build-plat-sim.sh`).
  The shipped zip is `plat.exe` + `plat-sim.exe`. Dev still shells
  `node` + the `.mjs`.
- plat opens engine cities by default, `--campaign=` mode shows the firm HUD,
  SPACE advances a month through the sidecar (or `node` + the `.mjs` in dev).
- The parcel card: click a building, read BBL / class / district / sqft /
  floors / year / occupancy (selftest-proven, in the shipped build).
- The full BW web UI runs in plat-econ (`pnpm dev`) — the reference
implementation for every desk, and the spec for panel behavior. The
native Godot port is specified in `docs/UI-PLAN.md`: mouse-first, jobs
and desk rooms, glance card vs parchment page. Do not implement chrome
that the plan has not reached.

## Phase 1 — The sim ships inside the game (no Node install) — done

The campaign runner + engine compile into one sidecar. Stock Node SEA, no
new runtime.

- `tools/build-plat-sim.sh` overlays `tools/runner/*.mjs` onto plat-econ,
  esbuild-bundles `game-server.mjs` + engine to one CJS file, injects the
  SEA blob into official Node 22 linux-x64 and win-x64 binaries. CI
  (`.github/workflows/plat-sim.yml`) builds both and smokes `new` +
  `advance` on the Linux binary — no `node` on the argv, no plat-econ path.
- plat looks for `plat-sim` / `plat-sim.exe` NEXT TO its own executable
  first, then falls back to `node` + a `.mjs` (dev flow unchanged).
  Callers pass only the verb and flags.
- Ship = `plat.exe` + `plat-sim.exe` (see `tools/package-release.sh`). The
  zip no longer carries a Node install or a plat-econ tree. A clean
  Windows sitting with neither Godot nor Node is the remaining proof —
  cut a `v*` tag and unzip on a machine that has neither.

## Phase 2 — Break ground in plat (start menu)

Godot UI over the harbor: the same three dials the web start menu has —
island size, build-out stage (landing → metropolis), age & capital — and a
Break ground button that shells `plat-sim new` and opens the city. Continue
row lists campaign dirs found in `user://campaigns/`. This replaces "run a
CLI command first" as the way a player starts.

## Phase 3 — The deal loop (the game becomes a game)

Runner grows the engine's action surface, one JSON command per verb; plat
grows the UI that drives it. Order chosen so each step is playable alone:

1. **Pricing on the card.** Export `landPsf`, appraisal, cap rate, asking
   price for listed parcels. The parcel card grows its money lines — the
   record becomes an investment memo.
2. **Buy.** `plat-sim buy --bbl=… --dir=…` is the cash shortcut at ask.
   The contract path is `offer` (`negotiate` at the listing ask) → Deals
   desk → `close` (`closeDeal`). A handshake posts the engine's 1.5%
   deposit; Close funds the agreed price. Failure returns the engine's
   reason verbatim.
3. **Listings layer.** `plat-sim listings` → for-sale parcels; plat tints
   them on the map (the first BW map layer in 3D) and TAB cycles a listings
   rail with prices — click focuses the camera on the parcel.
4. **Develop.** `plat-sim develop-options --bbl` / `develop-start` — the
   engine's buildable programs for a lot; pick one, a crane appears (the
   construction state is already in the export's quantities), delivery
   changes the massing on the next rebuild.
5. **Money desk.** Credit line, refi, sell — same pattern: engine verbs
   exposed as runner commands, thin Godot panels, engine text for outcomes.
6. **Attention.** The engine's `attentionItems` become an inbox rail;
   advancing stops on items that demand a decision, exactly as BW does.

## Phase 4 — The city shows the game state

- **Map layers** (Market / Land / Demand / Zoning / Owners / Leases): flat
  color overlays over building tops per layer, driven by exported per-parcel
  values. Renderer-only; no new engine work.
- **Held portfolio glow**, vacancy reading at street level: dusk windows
  follow exported occupancy; vacant ground-floor bays are boarded by day
  (same cell hash — the window that would be dark at night is plywood at noon).
- **Construction cranes**: a tower crane stands on every lot the sim has
  marked `developing`. Height is `devFloors` × 3.5 m. Raised on the
  develop verb without remeshing the city.
- **Delta rebuilds**: advancing a season re-imports only parcels whose
  records changed (the export is already per-BBL; chunk rebuild keyed by
  changed BBLs) so time passes in ~a second, not a full regeneration.

## Phase 5 — A century in one sitting

Autosave per season into the campaign dir; saves menu on the start screen;
the year rail (BW's timeline) along the bottom; game-over and milestone
ceremonies rendered as plat scenes (the delivery flyover is a camera move
this renderer was born for).

## Rules that hold throughout

- Engine numbers never re-derive in GDScript; if plat needs a number, the
  runner exports it. The gate stays green in plat-econ on every commit.
- Every phase ends with the selftest exercising the new verb headless and a
  committed frame showing it (the card taught us why: the first one rendered
  1,180 px off-screen and only the frame caught it).
- The web app stays runnable as the reference client until plat's UI covers
  it; divergence between the two on the same campaign file is a bug.

## Order of work

Phase 1 (sidecar) is done. Phase 2 polish and 3.3–3.6 next, then 4, then 5.
A tagged zip on a clean Windows machine is the Phase 1 sitting.
