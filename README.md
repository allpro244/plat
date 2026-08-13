# plat

A commercial real estate simulation under a procedurally generated city,
rendered with Godot 4 (Forward+, Vulkan). Read `BRIEF.md` for what this is and
why, and `CLAUDE.md` for the working rules. Both predate the code and are
binding.

## Milestone 1 — one block, fully dressed

One seeded city block of ~35 procedurally generated buildings spanning three
zoning eras — pre-1916 lot-line lofts, 1916 setback towers stepped inside the
sky-exposure plane, and a 1961 tower-in-plaza — on the same street, under a
real computed sun, shot by an orbital camera that cannot leave its height
bands.

![reference render](renders/reference/block_1928_evening.png)

Nothing in the scene is hand-placed: `BlockGen` subdivides the block into lots
and assigns eras, `Grammar` turns each lot into massing + facade parameters by
era rule, `MeshBuilder` turns those into meshes. Windows are dimensional
arithmetic in a shader (floors × bays at stated sizes), not a texture.

## Running

```sh
tools/setup-linux.sh     # Godot 4.5 + lavapipe + Xvfb (one-time; no GPU needed)
tools/fetch-assets.sh    # pinned CC0 assets (Poly Haven / mirrors), gitignored
tools/shoot.sh           # headless render -> renders/shot.png
tools/shoot.sh --check   # renders twice, fails unless byte-identical
tools/shoot.sh --seed=7 --time=7.25 --band=mid --az=140  # any parameter varies
godot --path .           # interactive orbit (same rig, same clamps)
```

Every shot prints its full parameter line (seed, date, time, computed sun
azimuth/elevation, camera band/position) so any image is reproducible.

## Layout

| path | what |
|---|---|
| `data/camera_bands.json` | THE camera contract as data: orbital bands (height/radius) |
| `src/camera_rig.gd` | orbital rig; clamps every write into the active band |
| `src/sun_position.gd` | solar ephemeris (NOAA low-precision) — date+time+place → az/el |
| `src/city/block_gen.gd` | seeded lot subdivision + era assignment (quantities) |
| `src/city/grammar.gd` | era shape rules: lot → massing + facade params (form) |
| `src/city/mesh_builder.gd` | massing → ArrayMesh surfaces + roof props |
| `src/city/facade.gdshader` | dimensional window grid over the scanned wall set |
| `src/city_scene.gd` | assembles env/sky/sun/ground/block/camera from params |
| `src/shoot.gd` | headless entry: build, settle, save PNG, print params, quit |
| `tools/` | setup, pinned asset fetch, headless shoot |

## Notes for this environment

Headless rendering uses the real Forward+/Vulkan renderer through lavapipe
(software Vulkan) under Xvfb. Godot's `--headless` flag would swap in the
dummy renderer — `tools/shoot.sh` uses Xvfb precisely to avoid that.

The asset script prefers first-party Poly Haven URLs and falls back to pinned
GitHub mirrors of the same CC0 scan data when only github.com is reachable
(the case in the sandbox this was built in). **Both profiles serve the same
sky** — `spruit_sunrise`, at 4k from Poly Haven or 1k from the mirror — so the
picture cannot silently depend on which network built it. A panorama's sun
elevation is baked in and cannot be rotated away, so the scene's default time
of day (19:40 EDT, 21 June) is the time at which the computed solar elevation
for this latitude matches the sky's measured 7.7°. `CityScene` measures the
sky's sun at load and warns if the two disagree by more than 8°; every shot
prints the delta as `sky_delta`.

The profiles still differ in one respect: the mirror brick set has
albedo/normal/AO but no per-pixel roughness scan, so masonry there uses a
scalar roughness — brick is uniformly matte, so that is a material fact, not
a look tweak.
