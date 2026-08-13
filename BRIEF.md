# plat — the brief

**Read this first, then `CLAUDE.md`.** This file is the decision record: what
was settled before any code existed, and why. The reasons are here so they do
not get relitigated by a session that arrives with no memory of the argument.

A *plat* is the surveyor's map of how land is divided into lots. It is what
both halves of this program operate on, which is why it is the name.

---

## What this is

A commercial real estate simulation with a procedurally generated city rendered
at the highest fidelity achievable without an art team.

The predecessor, `broadway-and-wall`, has a genuinely good economy — an honest,
deterministic, adversarially tested simulation of the CRE business — behind a
2D map. This project keeps that standard of simulation and puts a real city
under it.

## The honest fidelity target

The reference point is Cities: Skylines 2. That game's look comes from three
things: a mature deferred renderer, a very large hand-authored art library, and
years of artist labour. This project can have the first and the third; it
cannot have the second, because nobody here is going to model four hundred
buildings.

The door through that wall is **procedural generation plus scanned CC0
materials**, and it is the reason the target is realistic rather than a
fantasy. Production-grade PBR texture sets and HDRI skies are freely available
under CC0 and fetchable by script. Combine those with buildings generated from
real massing rules, invest heavily in lighting and post, and the result reads
as photoreal at the distances this camera actually sits at.

**Expect roughly 80% of the impression from the air and considerably less at
street level.** That gap is why the camera contract exists. Do not promise
past it.

## Decisions already made

| Decision | Why |
|---|---|
| **Orbital camera, constrained height bands** | The single biggest determinant of achievable fidelity per unit of work. Constraining it buys baked AO, impostors, shell-only buildings and no interiors. See `CLAUDE.md`. |
| **Godot 4 as the client** | Free, MIT, no account, ~150 MB. Text-based scene files, so an agent authors them directly instead of clicking an editor. Exports both native and web. Headless-capable for CI renders. |
| **Simulation as an engine-agnostic core** | Makes the renderer decision reversible. If Godot disappoints, the client is replaced and the economy never notices. |
| **All geometry procedural** | No asset kit. Variety is a shape grammar with a seed. |
| **CC0 materials, fetched by script** | Poly Haven / ambientCG. No account, no licence tracking, commercial-grade scan data. |
| **Web preview build on every push** | The review loop is a URL, not a download. This is what makes the project hands-off for the owner. |

## Decisions deliberately deferred

**When the economy gets ported.** The predecessor's simulation is the rare and
expensive part and it *will* be ported — the question is only whether it comes
before or after the renderer is good.

The answer settled on is **after**, for a reason worth keeping: the two spend
entirely different budgets. The economy is turn-based and runs on the CPU once
per game-month; a tick could take 200 ms and no one would see it. The renderer
runs on the GPU sixty times a second. They do not compete, so porting early
buys nothing visual and costs weeks that would otherwise go into materials and
lighting.

So: build the renderer against a **synthetic feed with the same shape as the
real simulation's output**, get the look right, then swap the real economy in
behind the identical contract. The feed's shape is not optional — it is what
stops the renderer being designed around data the simulation cannot produce.

The synthetic feed must emit, per parcel, at minimum:

```
lot polygon · era / year built · use mix (office/retail/residential/industrial)
floors · gross floor area · occupancy per use · condition 0..1
under construction? (progress, months to delivery) · landmarked?
```

Every one of those is something the real simulation already knows, and every
one of them is something the renderer should eventually *show*.

## Milestone 1 — one block, fully dressed

The first build proves the whole pipeline end to end on a deliberately small
subject. It is a vertical slice, not a demo.

**Deliverables**

1. **Camera rig.** Orbital, locked to the defined height bands, with the band
   definitions written down as data rather than scattered through code.
2. **Procedural block generator.** One seeded city block, roughly forty
   buildings, generated from lot polygons by the shape grammar. Era-varied.
3. **Materials.** At least one CC0 PBR set correctly applied — albedo,
   roughness, normal, AO — plus an HDRI sky. Fetched by the pinned asset script,
   not committed as binaries.
4. **Lighting.** Real sun position for a stated latitude, date and time of day.
   Time of day must be a parameter, because the whole look lives or dies on it.
5. **Headless render in CI.** The build produces a screenshot without a human
   opening an editor.

**Acceptance**

- A screenshot exists, and it was produced by the build rather than by hand.
- The same seed and the same time of day produce the same image twice.
- The camera cannot leave its height bands.
- Nothing in the scene was hand-placed.

**Explicitly not in milestone 1:** traffic, pedestrians, weather, seasons, the
economy, more than one block, any UI.

## After milestone 1, roughly

2. **Scale.** The whole city at rough massing — instancing, streaming,
   impostors past the far band. Answers "does it run" before "does it look
   good" gets expensive.
3. **The ground plane.** Curbs, sidewalks at real widths, crosswalks, street
   trees, signage. Amateur city renders die at the pavement and this is cheap
   geometry with an enormous return.
4. **Reference renders.** Pinned seeds and cameras, committed images, a diff
   report on every build. The graphics `BASELINE.json`.
5. **The economy port**, behind the contract that already exists by then.
6. **Life as impression.** Crowd and traffic density driven by the employment
   model, not agent-simulated.

## Traps

Each of these has killed or damaged a real project.

- **Free-fly street-level camera.** Voids every saving the camera contract
  buys, spreads effort thin, and produces a game that looks *worse* because
  nothing gets the attention it needed. If it is ever wanted, cost it first.
- **The simulation dictating geometry.** The moment the sim owns shapes, the
  renderer cannot improve without economic regressions. Quantities in, form
  decided here.
- **Coupling the renderer to the simulation tick.** Cities: Skylines 2 shipped
  a beautiful renderer welded to a simulation and ran badly at both. The
  monthly tick emits keyframes; the renderer interpolates. That also gives a
  hundred-year timelapse almost for free.
- **Hand-modelling "just a few" buildings.** It never stays a few, and the
  moment the city is half procedural and half authored, the procedural half
  stops improving because the authored half looks better.
- **Claiming a look works without rendering it.** See the first rule in
  `CLAUDE.md`.

## Open questions for the owner

- Which city, if any, the procedural generator should take its character from.
  A generator tuned for this camera was chosen over real GIS data; that leaves
  the *architectural* reference open.
- Era and start year. The predecessor starts in 2000. A single-era city is
  cheaper; a century of accreted eras is far more convincing and is what the
  economy is built to produce.
- Whether native desktop builds matter, or whether the web build is the
  product.
