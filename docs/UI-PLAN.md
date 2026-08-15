# plat UI plan — Broadway & Wall chrome, native, mouse-first

The last UI pass painted parchment over a label HUD. That is not Broadway &
Wall. B&W is a **firm desk sitting on a city**. Plat is still a **city with a
scoreboard**. This document is the gap, the contract, and the order of work.

The architecture does not change: the sim owns quantities; plat owns form;
the game UI is a third thing — a client of the campaign runner. Nothing below
moves a number into GDScript. The web app stays the reference client until
plat covers it; divergence on the same campaign file is a bug.

---

## 1. What B&W actually is (from the running app, not memory)

B&W is one screen with four kinds of chrome. Every verb a player needs is a
**click**. Keyboard shortcuts exist (Space / Y / N advance, M map-only, P
photo frame, Esc close) but they are accelerators. A player who never touches
the keyboard can found a firm, read the market, buy, finance, lease, build,
and survive a century.

### 1.1 The start room

`StartMenu.tsx` is a full-screen room over dark water, not a keypress.

- **Continue** is first when a save exists: town name, size, build-out, date,
  year, cash in hand, one **Resume ▸** button.
- **Cut a new town** is three (now four) parchment columns of radio sheets:
  how big, how built up, age · capital. Each option is a named button with a
  note in the game's own numbers, not a slider.
- **Break ground** lives in a footer **outside** the scroller so it cannot
  fall off the window. Nothing generates until that click.

Plat today: F1 or an auto-start on launch. No dials. No continue row. No
room.

### 1.2 The top bar (the firm's pulse)

`TopBar.tsx` + `.topbar` in `index.css`. A frosted parchment **plate** the
full width of the window, measured height published as `--topbar-h` so
everything below it (parcel card, inbox, desk rooms) clears it.

Left island:

- Serif wordmark.
- Firm name + headline epithet (who the city thinks you are).
- City name, locked for the run.

Centre — two rows of **fixed-width vitals** so Advance does not walk the
buttons under the cursor:

| Keep (never hide) | May drop on a narrow window |
|---|---|
| Date / year | Net worth |
| Cash (GP liquidity) | Market phase |
| Line / line drawn | Vacant lots |
| CF / yr | |
| Occupancy | |
| Base rate | |
| Vac Δ / yr | |
| Book (stress) | |

Right of vitals — **job nav**, not a flat list of pages:

| Job | Rooms it opens | Badge |
|---|---|---|
| Acquire | Marketplace · Deals · Notes | live deals + off-market + books |
| Assets | Portfolio · Leasing · Staff | — |
| Capital | Debt · Books | ⚠ if swept / hot |
| World | Research · News | unread events |
| Economy | Economy | — |

Then **map lenses** as toggle buttons: Market, Land, Demand, Zoning, Owners,
Leases. Then **time**: Advance (one month), Year (stop on attention), Skip
(next decision, up to 3 years). Then utilities: Map, Frame, Saves, Primer,
Settings, New city (two-click arm).

Plat today: five readouts (date, cash, holdings, occ, listings) and an fps
number. No jobs. No lenses except a bottom Owners toggle. No year/skip. No
saves. No primer.

### 1.3 The glance card (the map's right hand)

`ParcelDesk.tsx` — 330px parchment card, `top: calc(var(--topbar-h) + 10px)`.

- Serif **address**, mono **Parcel BBL**.
- Chip row: use colour, zone, OWNED / FOR SALE / MOTIVATED / UNDER
  CONSTRUCTION / LANDMARKED / CASH SWEEP.
- Summary / Full OM toggle.
- Key/value grid (sf, floors, year, occ, appraisal band, NOI, owner).
- Deal block with **Buy at ask** / offer / list — real buttons.
- **full view** opens the property as a desk room.

Click a building on the map. Click Buy. That is the whole acquire-at-ask
loop, and it never needs a key.

Plat today: a card that can show class / sf / ask. No address. No tabs. No
owner. No OM. Buy exists if you already know B exists.

### 1.4 Desk rooms (the thing plat does not have)

`RightPanel.tsx`. A job click does **not** cram a rent roll into 330px. It
opens a **centered parchment sheet** (~1120px) over a blurred wash of the
city (`.page-backdrop`). Kicker (Acquire / Assets / Capital / World) + serif
title + subtitle + ×. Click the wash or × to return to the map.

This is why B&W feels like a game you can play with a mouse: the map is the
board, the card is a glance, the **room** is where you do the work.

Rooms that exist today in the reference client:

| Page | What the player does with a mouse |
|---|---|
| Marketplace | Sortable listings tape, class filters, click a row → property, buy street books, distress, auction |
| Deals | Every live LOI, bid, contract, clock |
| Notes | Distressed paper |
| Portfolio | Holdings, income, concentration |
| Leasing | Occupancy, expirations, mandate |
| Staff | People, capacity |
| Debt | Loans, line, maturity wall, refi |
| Books | Cash movement, ledger, saves used to hide here (they do not any more) |
| Research | Comps, submarkets |
| News | The tape |
| Economy | Cycle, space markets, construction |
| Property | One deed as a file — see tabs below |
| Saves / Settings / Primer | Campaign and teaching |

Property room tabs (`PropertyPage.tsx`) — shown only when they have content:

Overview · Rent roll · Money · Operations · Acquire/Sell · Build · Deed history.

### 1.5 Rails that tell you what to do next

- **InboxRail** (left, under the bar): `attentionItems` from the engine, each
  with an **Open** button that routes to the right desk. Year one also shows
  the next milestone and an **Acquire** button.
- **MapHud** (left): construction deliveries, balloon cliffs, sites that
  pencil, City / Book / Cranes filters, Zoning lens. Every row is a click
  that focuses a parcel or opens a desk.
- **Modals** sit above everything: decision cards, alerts, auction, default
  notice, game over. Advance is blocked until the card is answered.

Plat today: attention strings concatenated onto the city line. No Open.
Advance never stops.

### 1.6 The mouse contract (this is the product)

A first-session B&W player, keyboard unplugged:

1. Continue or set three dials → Break ground.
2. Read vitals. Click **◉ Market**. Green lots appear.
3. Click a building. Card: chips, ask, **Buy at ask**.
4. Or click **Acquire → Marketplace**, click a row, same card / full view.
5. Click **Advance**. If the engine raises attention, a card or inbox
   **Open** appears. Click it. Decide. Advance again.
6. Click **Assets → Portfolio** to see what they own. Click a row to go
   back to the building.

Plat today, keyboard unplugged: you can pan the camera and… that is most of
it. Break ground / Advance / Buy / Listings exist as buttons on a rail that
did not even read in the last evidence frame. There is no market tape, no
job, no room, no inbox Open, no start dials.

---

## 2. The honest gap

| Surface | B&W | plat now |
|---|---|---|
| Start room | Full mouse menu | F1 / auto-start |
| Top bar | Vitals + jobs + lenses + time + utilities | 5 numbers + fps |
| Parcel glance | Address, chips, grid, buy, full view | Thin card |
| Desk rooms | 15 parchment pages | None |
| Property tabs | 7 contextual tabs | None |
| Inbox | Open → routed desk | Text on the city line |
| Map HUD | Clickable city status | None |
| Lenses | 6 | Owners only |
| Time | Month / year / skip-to-attention | One Advance (3 months) |
| Mouse-only | Yes | No — Space, B, Tab, F1, M, H are the game |
| Runner verbs | Full store (buy, LOI, refi, develop, lease…) | `new`, `advance`, `buy`, `list`, `delist`, `accept-offer`, `draw`, `repay`, `refi-quotes`, `refi`, `develop-options`, `develop` |
| Exported HUD | Thin `hud.json` | Same thin file |

The embarrassing part is not missing desks 8–15. It is that **the session
you can already play in B&W with a mouse has no equivalent in plat**. We
ported colors. We did not port the product.

---

## 3. Rules for the port

1. **Native Godot.** No React embed, no WebView. `docs/GAME-PLAN.md` already
   decided this. Theme tokens live in `src/ui/bw_theme.gd` (paper, ink, gold,
   teal, danger, StyleBox elevation). Grow that file; do not fork a second
   palette.
2. **The sim still owns every number.** If a panel needs NOI, cap rate, or
   an attention route, the runner writes it. GDScript formats and paints.
3. **Keyboard is optional.** Every verb that exists as a key must exist as a
   visible, labelled control. A selftest (and a human) must complete
   break-ground → listing → buy → advance **without sending a key event**.
4. **Glance vs room.** The map card stays ≤330px. Anything that is a table,
   a rent roll, or a negotiation opens a desk room (centered sheet, dimmed
   city, × and wash-click to close).
5. **Jobs, not a strip of twelve peers.** Acquire / Assets / Capital / World
   / Economy. Dropdowns for rooms. Badges on the job that owns them.
6. **Fixed-width vitals.** A value changing from `$2.5M` to `$12.4M` must
   not shift Advance under the cursor. B&W already solved this; copy the
   reservations.
7. **One evidence frame per phase.** CLAUDE.md rule 1. If a claim is about
   how it looks, the commit has a render. If a claim is about mouse-only,
   the selftest clicks the controls.

---

## 4. Work, in the order a player can feel

Each phase is playable alone. Do not start U3 until U1 is mouse-complete.
Do not open Portfolio as a pretty empty room before Marketplace can buy.

### U0 — Make the chrome we already have actually a game (this week)

Goal: a player who refuses the keyboard can start, buy, and advance.

- Top bar is a **full-width plate** (the current bar reads as a left-hand
  sticker). Measure its height; park the parcel card and inbox below it.
- Command rail is a **centered island** of Advance / Buy / Listings /
  Owners, always visible, always clickable. Hide "Listings (Tab)" — the
  button is the control; the key is a tooltip.
- Parcel card: address-or-class title, chips, grid, **Buy at ask** that
  works. Close ×.
- Compass / + / − stay. Map drag stays.
- Help is a `?` button, not a wall of keybinds dumped on the city.
- Selftest drives the **buttons**, not `KEY_SPACE` / `KEY_B`.

Acceptance: `renders/ui_current.png` shows bar + card + rail. A click-only
selftest buys a listing.

### U1 — Start room

Godot Control over the harbor (city already there, chrome off).

- Continue row from `user://campaigns/` (name, date, cash).
- Three columns: size, build-out, cash/age — the same lists the engine
  already exposes (`sizeList`, `developmentList`, `START_CASH_CHOICES`).
- Break ground in a pinned footer → `plat-sim new` with those flags.
- Generating state: serif title + one line of copy, no spinner jokes.

Runner: `new` already takes `--size` / `--density`. Add `--cash=` if the
opening bankroll is not yet a flag.

Acceptance: frame of the start room. No F1 required in a shipped build.

### U2 — Job nav + empty rooms (the skeleton)

Top bar grows the B&W job cluster. Each job opens a **page-backdrop room**
with kicker / title / ×. Rooms that are not built yet show one sentence and
a close button — never a fake table.

Lenses: Market, Owners, (Land / Demand / Zoning / Leases as they gain
exports). Time: Advance month, Advance year, Skip-to-attention (year and
skip can wait one phase if the runner cannot stop on attention yet).

Acceptance: click Acquire → a parchment room titled The Marketplace. Click
wash → map. No keyboard.

### U3 — Marketplace tape (first real desk)

This is the desk that makes the game feel like B&W.

Runner: `listings` (or a richer `hud.json` / `desks/market.json`) with, per
row, only numbers the engine already has: bbl, address, class, district,
sf, floors, year, ask, value, occ, distress, owner name if known.

Godot: sortable table, class chips, click row → select parcel + close room
or open Property. **Buy** on the row or on the glance card.

Acceptance: frame of the tape over the dimmed city. Click-only buy from the
tape.

### U4 — Property room + glance upgrade

Glance card grows chips + money lines + **Full view**.

Property room tabs, shown only when they have data:

| Tab | Source | First cut |
|---|---|---|
| Overview | city.json + listing | What the glance already shows, readable |
| Acquire / Sell | `buy` / later LOI | Buy at ask button, engine error verbatim |
| Build | `develop-options` / `develop` | Pick a program, confirm |
| Rent roll / Money / Ops / History | later exports | Hidden until the runner writes them |

Acceptance: click Full view on a listed lot → Overview + Acquire. Buy from
the room.

### U5 — Inbox and attention

Runner: `attention` array becomes `{key, label, route}` (page + optional
bbl), not a string list. Advance stops when the engine says so — same rule
as B&W's Space-blocked-by-modal.

Godot: left inbox rail, each row **Open**. Skip-to-attention button on the
bar.

Acceptance: selftest advances into a blocker; the rail shows it; a click
opens the routed room.

### U6 — Read-only firm rooms

Portfolio, Books, Debt, Economy, News — **read the export, do not invent**.

Each room is a stat strip + a table. Click a BBL → property. No write verbs
until U7.

Runner grows `desks/*.json` (or one `desk.json` keyed by page) written
beside `hud.json` on every `writeAll`.

### U7 — Write verbs as buttons

One runner command per verb, same as GAME-PLAN phase 3: LOI / accept, list,
sell, refi, draw line, develop-start, lease extend. Each button shows the
engine's error string on failure.

Order: sell and list (so a bought building is not a dead end), then develop
(crane already in the export), then debt, then leasing.

### U8 — The rest of the firm

Deals, Notes, Staff, Research, Primer, Settings, Saves (named snapshots —
autosave already writes `saves/mXXXX.json`). Property tabs that were hidden
in U4 light up as their exports arrive.

### U9 — The last 10% that is most of the feel

- Two-shadow elevation + top-edge hairline (already specified in
  `index.css`; port the numbers, do not restyle from taste).
- Tabular figures, reserved vital widths, bar wrap instead of overlap.
- Toast, photo frame, map-only.
- Year-one milestone copy on the inbox.
- Delivery ceremony as a camera move (GAME-PLAN phase 5).

---

## 5. Runner / export work (the bottleneck)

Plat cannot grow rooms faster than the runner writes files. Today
`hudOf()` is a pulse line. Desks need **documents**.

Proposed campaign dir after U6:

```
campaign.json
state.json
city.json
hud.json              # vitals only — what the bar reads
desks/market.json     # listings tape
desks/portfolio.json
desks/attention.json  # routed inbox
desks/property/<bbl>.json   # lazy, on select
```

Rules:

- Same `writeAll` path; no second book.
- A desk file is a view model. If plat and the web app disagree on a number
  in the same campaign, the export is wrong.
- `pnpm gate` stays green. New commands get a runner test before the Godot
  panel lands.

---

## 6. Godot shape (so the work does not rot in `main.gd`)

```
src/ui/bw_theme.gd      # tokens, StyleBoxes, fonts
src/ui/game_ui.gd       # shell: bar, glance, rail, inbox, page stack
src/ui/start_menu.gd    # U1
src/ui/top_bar.gd       # vitals + jobs + lenses + time
src/ui/parcel_card.gd   # glance
src/ui/page_room.gd     # backdrop + kicker + title + scroll
src/ui/pages/*.gd       # one script per desk
src/ui/inbox_rail.gd
src/ui/map_hud.gd
```

`main.gd` keeps the camera, picking, and runner I/O. It must not layout
another Label HUD.

---

## 7. What this is not

- Not a pixel-perfect clone of the React tree. It has to be **similar**:
  parchment, ink, gold, jobs, glance + room, mouse-complete.
- Not "make the current strip prettier." Pretty without desks is how we got
  here.
- Not embedding `plat-econ`'s Vite app in a viewport. That would freeze the
  3D city behind a browser and break the one-download promise.
- Not re-deriving NOI / cap / line in GDScript because the export was thin.

---

## 8. How we will know we are no longer embarrassing

A person who has played B&W sits down with a mouse and no legend.

- They can start or continue without opening a terminal or pressing F1.
- They can find every for-sale lot in a tape, not by tabbing the city.
- They can buy, see the deed on a card with OWNED, and open a room that
  looks like a file.
- They can advance time from a button that does not move.
- When the engine wants a decision, a card or an Open button appears.
- They never need a key. If they learned Space in B&W, it still works.

Until that session exists, we are not "close." We are on U0.

---

## 10. This cut (executed)

Shipped in the same PR as the first playable B&W session:

- Runner: `--cash=` on `new`; `--until=attention` on `advance`; richer
  `hud.json` (line, CF, book, year, routed attention); `desks/market.json`
  and `desks/attention.json` on every write. Address on city parcels.
- Start room: Continue + size / build-out / capital → Break ground.
- Full-width bar: reserved vitals, job nav, Market / Owners lenses,
  Advance / Year / Skip.
- Marketplace desk room: click a row → glance card.
- Glance card: address, chips, grid, Buy at ask, Full view.
- Inbox: Open → routed page. Empty state offers Acquire.
- Mouse-only for the session. Keys remain accelerators.

U7 (shipped): List / Delist / Accept offer / Build, then the money desk.
Runner verbs `list`, `delist`, `accept-offer`, `draw`, `repay`,
`refi-quotes`, `refi` sit next to the existing `develop-options` /
`develop`. Ask, proceeds, and the coupon are the engine's.

U4 leftover + U9 first slice (this cut): the desks you already have
become files, not logs.

- Property room tabs — Overview / Acquire·Sell / Build / Refinance —
  shown only when that desk has something to do. Glance **Build…**
  opens the Build tab; **Full view** opens Overview.
- Tables are columns with reserved widths, not `"%s    %s"` paste.
  Marketplace, portfolio, economy, debt, books, and the build
  programmes all use the same row helper.
- Marketplace class chips (All / land / office / retail / multifamily /
  industrial) filter the exported tape. A strip counts listings and
  motivated sellers. **Highlight on map** is the Market lens from
  inside the room.
- Elevation: two-shadow numbers from `index.css` (`--lift-2` / `--lift-3`)
  plus a top-edge hairline on the page sheet. FPS leaves the bar —
  it is not a vital.

Still stubs: Notes, Staff, Research. Do not open those rooms as
pretty empty tables.

U8 (shipped): the contract path. Buy at ask stays the cash
shortcut. Offer at ask calls the engine's `negotiate` at the
listing ask — no bid slider, no invented default. A number that
clears their reserve is a handshake and a 1.5% deposit, not a
deed. The Deals desk lists talks (contracts first). Close funds
the agreed price; Walk tears it up; Accept their number takes a
counter. Seller reserve is not exported.

U10 (shipped): the first lease. Buy a building with floors
(not vacant dirt). `respond-loi` accept / pass — no rent slider.
`desks/leasing.json` is the roll and the letters. The Leasing
room and the property Rent roll tab paint them. Accept / Pass
also sit on Deals, where the inbox already routes a letter.
Signing cost is `loiSigningCost`. Counter waits.

U11 (shipped): interruptions. A letter or an offer on one of
yours takes the screen. Advance / Year / Skip will not walk
past it — the bar says Decide until you Accept, Pass, or
Decide later. The card paints the exported letter, not a
paragraph we wrote. Decide later leaves it on Deals.

U12 (shipped): the property file grows two tabs the engine
already knows how to fill. **Deed history** is
`propertyTimeline` + `describePropertyEvent` — trades, major
leases, construction, planning, enforcement. **Money** is
`Holding.hist`, decoded the way the engine stored it
(`[month, occ×1000, rent psf ×100, NOI/yr]`). A named offer
slider stays out: B&W's `defaultOffer` / `counterPriceBounds`
live in the web UI, not the engine, and plat will not invent
them.

U13 (this cut): off-market approach. Click a building that is
not on the tape → **Approach the owner**. `approachOwner`
returns their ask, a refusal, or "make me an offer." Reserve
is not exported. If they named a number, **Buy at their
number** is `executePurchase` at that ask (the existing `buy`
path with `offMarket`). A blind bid waits — plat will not
invent one.

U5 leftover + U9 inbox / map HUD (this cut): the city tells you
what to do, and a room owns the screen.

- Year-one inbox reads the engine's next milestone (`MILESTONES.test`),
  not "Nothing waiting." Months left are `12 - month`. The button
  routes to the desk that milestone lives on.
- Map HUD under the inbox: deliveries, balloons inside 18 months,
  City / Book / Cranes filters. Book is the owners overlay; Cranes
  tints jobs under construction. Numbers come from `desks/map.json`.
- Opening a desk room hides the glance, inbox, and map HUD. Closing
  it puts them back. The sheet sits on a washed city, not a collage.
- **Map** on the bar closes the room.

---

## 9. Current evidence

- `renders/ui_start.png` — start room
- `renders/ui_current.png` — marketplace tape
- `renders/ui_portfolio.png` — one deed after the selftest buy
- `renders/ui_economy.png` — cycle + four space markets
- `renders/ui_news.png` — the tape
- `renders/ui_debt.png` — the line, no mortgages yet
- `renders/ui_books.png` — cash / NW / year-2000 ledger
- `renders/ui_drawn.png` — Draw $X on the line; vitals show drawn / limit
- `renders/ui_listed.png` — list the bought lot at appraisal
- `renders/ui_build.png` — underwritten programmes on vacant dirt
- `renders/ui_refi.png` — Refinance tab: First Harbor land loan
- `renders/ui_market.png` — tape with class chips and aligned columns
- `renders/ui_inbox.png` — year-one milestone on the map
- `renders/ui_map.png` — inbox + map HUD after the first deed
- `renders/ui_deals.png` — under contract after Offer at ask
- `renders/ui_leasing.png` — renewal letter on the roll
- `renders/ui_leased.png` — after Accept
- `renders/ui_decision.png` — the letter takes the screen
- `renders/ui_history.png` — deed history on 76 Ropewalk after the buy
- `renders/ui_money.png` — quarterly stamps on the same hold
- `renders/ui_glance.png` — click a building: the glance card
- `renders/ui_card.png` — listed lot glance (Offer / Buy at ask)
- `renders/ui_knock.png` — unlisted building, Approach the owner
- `renders/ui_approach.png` — after the knock: their number, a refusal, or make-me-an-offer
- `renders/ui_property.png` — Full view / Acquire on that deed
- `renders/playable_selftest.png` — the click path that produced them
