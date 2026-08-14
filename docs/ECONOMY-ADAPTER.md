# The economy adapter: how plat becomes the renderer of a simulated city

The economy engine lives at `allpro244/plat-econ` (ported from
Broadway-and-Wall, headless, its four gate harnesses green in CI). This
document specifies how the two programs meet, and it starts from the rule that
decides everything else (CLAUDE.md):

> **The sim owns quantities. The renderer owns form.**

## Direction: the engine is the source of truth

`makeCity(cityId, seed)` in plat-econ generates the island — coast, districts,
parks, piers, stations, parcels, buildings — as *quantities*: a parcel table
keyed by BBL, footprint rings with base/height metres, classes, years, floor
counts, demand scores. Deeds in a save point at those parcels, so that
generator cannot be replaced without breaking every save.

plat's `CityPlan`/`ContextGen` today generate their own island. That was the
right way to build the renderer — form needed a substrate to be developed
against — but two generators of one city is one generator too many. The
migration is that plat stops inventing the city and starts *dressing* the
engine's city. Everything plat learned about form — the era system, the UV2
per-building identity, the massing recipes, the palette families — survives
intact, because none of it ever owned a quantity; it consumed them.

## The wire format: `plat-city/1`

`node tools/export-city.mjs --seed=N --out=city.json` (in plat-econ) writes
the renderer-facing subset, byte-deterministic per seed:

| field | contents | plat consumes it as |
|---|---|---|
| `manifest` | seed, name, projection origin | HUD plan line, reproducibility stamp |
| `context` | GeoJSON rings: `land` (coast), `shallows`, `esplanade`, `pier`, `park`, `apron`, `coastline` | island fan + skirt, seawall, esplanade, piers, park lawns |
| `stations` | transit points, names, weights | street-life density kernels (later: station props) |
| `buildings3d` | per volume: footprint ring (lon/lat), `z0`/`z1` metres, `f` floors, `c` class, `y` year built, `t` tone, `x` crown flag, `d` decorative flag | one mass per record — the massing input `_emit_building` already takes |
| `parcels` | per BBL: `class`, `mix`, `floors`, `lotArea`, `bldgArea`, `yearBuilt`, `district`, `demandScore`, `shoreM`, `corridorM`, `corner`, `centroid` | everything form keys off (below) |

Coordinates are lon/lat; plat re-projects with the same local-metre projection
the engine uses (`makeProjection` about the manifest origin) so both programs
measure the same city in the same metres.

## Quantity → form mapping

Every visual rule plat has keeps its input, the input just becomes real:

| engine quantity | plat form decision it feeds |
|---|---|
| `yearBuilt` | era (victorian/prewar/midcentury routing, floor heights, cornice/mansard/water-tower probabilities) — replaces the seeded era roll |
| `floors`, `z0..z1` | massing height — replaces the height-mode sample |
| `class` / `mix` | facade vocabulary: office → curtain wall/punched masonry by era; residential → rowhouse/loft grain; retail leg → shopfront band + awnings; `land` → gravel-and-fence vacant lot (engine exports these flat, `k:1`) |
| `district` | palette family + street culture per district — replaces Voronoi district assignment |
| `demandScore`, occupancy (later) | lit-window fraction at dusk — the CLAUDE.md "no fake frames" rule finally gets its real signal |
| `shoreM`, `corner` | corner shopfronts, esplanade-facing frontages |
| `t` tone | seeds the UV2 style hash so identity stays per-building stable |

What plat must *stop* doing under the adapter: rolling its own coastline,
districts, block grid, heights, eras. What plat keeps sole custody of: bay
rhythms, materials, window typology, color, roof clutter, trees, water, sky,
camera — form, all of it.

## Staged migration

1. **Export (done).** plat-econ writes `city.json`; deterministic, verified.
2. **Ingest.** plat gains a loader: `tools/shoot.sh --city=city.json` builds
   the scene from the file instead of `CityPlan`. First target: massing only —
   every `buildings3d` record becomes a correctly placed, correctly tall grey
   mass on the engine's coast. Rendered and compared against the engine's own
   2D tile output for agreement of silhouette.
3. **Dress.** Wire the mapping table above into `ContextGen` so the era,
   palette, and typology systems read engine quantities. `CityPlan` shrinks to
   a fallback for `--seed=` runs with no city file.
4. **Live loop (later).** The exporter's static file becomes a message: the
   running sim streams parcel-state deltas (occupancy, condition, construction)
   and plat re-dresses only what changed. Format unchanged — `plat-city/1`
   records, sent incrementally.

The practical test stays what CLAUDE.md says it is: the engine passes its full
gate with the renderer deleted (it does, in CI, today), and plat renders a
city it was handed without deriving one economic number.
