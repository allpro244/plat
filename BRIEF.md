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
street level.** The camera can now go to the street; that does not raise the
fidelity target. Do not promise past it, and do not spend the milestone
budget dressing a street view.

## Decisions already made

| Decision | Why |
|---|---|
| **Free-flow camera (owner override, 2026-08)** | Band clamp revoked. MapLibre / Broadway & Wall navigation plus a WASD free-fly. Street-level fidelity is not a goal; `camera_bands.json` is optional presets only. See `CLAUDE.md`. |
| **Godot 4 as the client** | Free, MIT, no account, ~150 MB. Text-based scene files, so an agent authors them directly instead of clicking an editor. Headless-capable for CI renders. |
| **Native build is the product. Forward+ renderer, Vulkan.** | Not a packaging preference — a renderer choice. See below. |
| **Simulation as an engine-agnostic core** | Makes the renderer decision reversible. If Godot disappoints, the client is replaced and the economy never notices. |
| **All geometry procedural** | No asset kit. Variety is a shape grammar with a seed. |
| **CC0 materials, fetched by script** | Poly Haven / ambientCG. No account, no licence tracking, commercial-grade scan data. |
| **Review by rendered image, not by playable build** | CI renders stills and short videos with the real renderer and attaches them. Higher fidelity than a web build and less friction. See below. |
| **New York massing, a full century of eras** | NYC's zoning history is legible in building *shape*, so eras are different rules rather than different textures. See below. |

### Why native, and why that does not cost the review loop

Godot has two renderers and this decision falls exactly on the split.
**Forward+ — SDFGI global illumination, volumetric fog, screen-space
reflections, SSIL/SSAO, compute shaders, cascaded shadows — requires Vulkan
and does not run in a browser.** A web export gets the Compatibility renderer,
which is WebGL2 and mobile-tier.

For a city that gap is enormous, because the three things Compatibility cannot
do are the three things that sell a city. Bounced light between building faces
is most of what separates a street from a diorama. Atmospheric scattering is
most of what makes a skyline read as *distance* rather than as flat cutouts.
Screen-space reflections are what make glass and wet asphalt look like glass
and wet asphalt. Add the browser's memory ceiling and the absurdity of shipping
gigabytes of scan textures over HTTP, and web caps the project well below the
fidelity target stated above.

So the shipping target is native, Forward+, Vulkan.

**The review loop does not suffer for it, and is in fact better.** Every push,
CI runs the real renderer headless and attaches stills — and, where useful, a
short orbit or timelapse video — to the pull request. The owner opens a PNG or
an MP4 in a browser tab: no install, no download, no WASM bundle. That is a
review of the *actual* renderer at full quality rather than of a degraded
proxy, which is strictly more informative than a playable web build.

It also collapses two mechanisms into one. `CLAUDE.md` already forbids shipping
a visual claim without a rendered image, and already specifies pinned-seed
reference renders as the graphics analogue of `BASELINE.json`. **Those renders
are the review feed.** Verification and review become the same artefact, so
neither can quietly rot without the other visibly rotting with it.

Caveat, stated now rather than discovered later: CI runners have no GPU, so
headless renders go through software Vulkan (lavapipe). The image is identical;
it is simply slow — seconds to minutes for a still, which is entirely
acceptable. Long timelapse video is where that stops being free, and is the
point at which a GPU runner earns its cost.

A playable native build gets produced for real platforms too, but it is an
occasional download for when the owner actually wants to fly around the city.
It is not the loop.

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

1. **Camera rig.** Free-flow (owner override): continuous pitch and zoom, no
   band clamp. Optional near/mid/far presets live in `data/camera_bands.json`.
2. **Procedural block generator.** One seeded city block, roughly forty
   buildings, generated from lot polygons by the shape grammar. Era-varied —
   at minimum a pre-1916 lot-line block, a 1916 setback tower and a 1961
   tower-in-plaza standing on the same street, because the whole argument for
   a century of eras is that they read differently side by side.
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
- The camera can leave any former height band (street through aerial).
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

- **Spending the art budget on street-level fidelity.** The camera can go
  there now; that is not a brief to dress interiors, close-range LOD, or
  doorway detail. The look target is still the air.
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

## The city: New York massing, a century of eras

The generator is tuned for this camera rather than fed by real GIS, so what is
borrowed from New York is its **rules**, not its parcel data.

This pairing is worth more than it first appears, and the reason is specific:
**New York's zoning history is legible in building shape.** Its eras are not a
texture swap, they are different generative rules, which is exactly what a
shape grammar wants and exactly what makes a century of accretion look earned
rather than dressed.

| Era | The rule that shapes it | What it looks like |
|---|---|---|
| **Pre-1916** | No envelope control. Build straight up from the lot line. | Masonry and cast-iron lofts, 6–12 floors, heavy cornices, punched windows, fire escapes, party walls exposed where a neighbour is shorter. |
| **1916 Resolution** | The sky-exposure plane: mass must step back as it rises, in proportion to the width of the street it faces. | The wedding-cake ziggurat. Art Deco crowns, setback terraces. Wide avenues permit taller sheer rise than side streets, so the grid itself starts shaping the skyline. |
| **1961 Resolution** | FAR-based with a plaza bonus: give up ground area, buy height. | Tower-in-a-plaza. Flat glass and steel slabs set back behind an open forecourt. International Style. |
| **1970s–80s** | Bonus-driven bulk, reaction against the flat slab. | Postmodern crowns, granite cladding, mirrored glass, ornamented tops on otherwise plain shafts. |
| **1990s–2000s** | Contextual zoning: match the street wall, then tower above it. | Base-and-tower articulation, brick-and-glass hybrids, a defined cornice line continuous along the block. |
| **2010s+** | Air-rights assembly and engineering, not envelope law. | Slender supertalls, full curtain wall, extreme slenderness ratios, mechanical voids. |

The 1916 sky-exposure plane is the single most valuable rule on this list: it
generates a whole era's distinctive silhouette from arithmetic on street width.
Implement it properly and the 1920s and 30s stock builds itself.

### Cheap New York details with an outsized return

These are small geometry with large character, and most of them are *derived
from data the simulation already has* rather than authored:

- **Rooftop water towers.** Tiny meshes, iconic silhouette, enormous per-block
  character. Placement follows building age and height, so it is a rule.
- **Exposed party walls.** A tall building beside a short one shows a blank
  brick flank, often with ghost signage. This falls straight out of comparing
  neighbouring parcel heights, which is exactly the sim-owns-quantities /
  renderer-owns-form line working as intended.
- **Rooftop mechanical bulkheads, stair overruns, setback terraces.** The
  roofscape is what this camera actually looks at. It deserves more attention
  than facades do.
- **Fire escapes** on pre-war stock, by era rule.

### How eras and the economy line up

The predecessor's simulation starts in 2000 and runs a century. That fits: the
**existing** stock at game start should show roughly 1900–2000 of accretion,
and the player's century then writes 2000–2100 on top of it — with the
generator's era rules continuing to apply to everything the simulation builds.
A building delivered in game-year 2043 should be visibly of its moment.

## Open questions for the owner

None outstanding. Architectural reference, era span and build target are all
settled above.
