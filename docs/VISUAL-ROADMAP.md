# Visual roadmap: from "recognizable city" to "finished product"

The current known limitations, in the order they hurt the image, each with
the mechanism that fixes it and the render that proves it. This is the
working plan; items land as individual commits with before/after renders,
same as everything else in this repository. The economy stays parked until
the owner says otherwise.

## Phase 1 — Footprint variety (the last big massing lever)

**Limitation:** every building's plan is a rectangle. No amount of facade
work can fix a skyline of right-angled extrusions.

**Mechanism:** extend `_emit_building` with plan-shape recipes composed
from the existing box emitter (still merged, still cheap):
- **L / T / U plans** for mid-rise: two or three overlapping bars; the
  notch reads at every band and doubles silhouette variety on corners.
- **Chamfered and stepped corners** on tall masonry: corner bay cut at 45
  degrees or stepped in — the classic prewar corner treatment.
- **Cross-plan towers** (four wings) for supertall — the Empire State
  profile — and slab-with-wings for housing blocks.
- **Podium plan differs from shaft plan** (round 1 gave them the same
  rectangle; the shaft should sit asymmetrically on street-corner podiums).

**Proof:** near-band render where no two adjacent footprints match; far
band where tower silhouettes differ against the sky.

## Phase 2 — Street-level truth (the closest band looks down a street)

**Limitation:** ground floors are a shader band; sidewalks are clean; the
street reads right from 400 m but generic from 150 m.

**Mechanism:**
- **Storefront geometry** on avenue frontages in the near ring: recessed
  shop bays, awning boxes (seeded color), signage slabs — reusing the
  hero block's reveal-geometry approach, budgeted to the first ~2 rings.
- **Street furniture as impressions:** hydrants, poles, and bus shelters
  are 4-12 triangle merged boxes at seeded intervals; they read as street
  texture, not props.
- **Pavement wear:** avenue asphalt darker down the lane lines, crosswalk
  paint erosion via the existing style-hash trick on the paint surface.
- Cars remain ON HOLD per owner instruction.

**Proof:** a 150 m-radius near shot that survives a phone-crop zoom.

## Phase 3 — Terrain relief (the island is a billiard table)

**Limitation:** the island is perfectly flat; real islands have a spine.

**Mechanism:** a seeded low-frequency height field (2-3 harmonics over the
island, amplitude 4-18 m) sampled by: the ground fan, every block's base
elevation (blocks tilt never — they terrace, curb-to-curb), esplanade and
pier bases pinned to the waterline. Streets between terraced blocks get
retaining-wall skirts where the step exceeds ~1.5 m — instant San
Francisco-adjacent identity for hilly seeds, and another per-city axis
(flat port vs hilly city).

**Risk:** touches every generator's y=0 assumption; do it in one commit
with the determinism gate and all three bands rendered.

## Phase 4 — Bridges (the piers make their absence loud)

**Mechanism:** 1-3 seeded crossings from the main island: to islets when
present, else toward the mainland arcs. Suspension impression (two pylons,
catenary deck curve, cable triangles) or truss impression, chosen by span;
approach ramps carve their corridor through fabric like boulevards already
do. Bridges light at dusk via the existing speckle trick.

**Proof:** far-band dusk render with a lit bridge crossing the harbor.

## Phase 5 — Material breadth (kill the one-brick sandbox bias)

**Limitation:** local renders share one brick scan; CI has five sets, but
five is still not a city, and material choice is not yet driven per
building.

**Mechanism:**
- Extend `tools/fetch-assets.sh` primary profile to ~10-12 pinned CC0 sets
  (2-3 bricks, limestone, sandstone, painted wood, 2 concretes, stucco,
  metal panel) — each with sha-pinned URLs, same discipline as now.
- Find 2-3 more GitHub-hosted CC0 sets for the mirror profile so local
  renders stop being single-texture (godot demo assets, ambientCG GitHub
  mirrors — verify licenses before pinning).
- Assign texture per SURFACE by district-weighted seeded choice (already
  plumbed: three facade surfaces per block choose from the library).

**Proof:** CI render where adjacent buildings differ in actual material,
not just tint; local render with 3+ materials.

## Phase 6 — Sky and light variety (every render is one June afternoon)

**Limitation:** one pinned sky, sky-derived single time; every city is lit
identically — a big residual sameness between screenshots.

**Mechanism:** extend the fetch script to pin 3-4 skies (clear noon,
golden hour, overcast, dusk); a seeded per-city default pick (overridable
by --time/--sky) makes new cities differ in weather and hour, and the
sky-derived-time architecture already keeps any pinned sky self-consistent.
Overcast needs its own sun-energy branch (soft shadows, flat ambient — the
ratio math is already parameterized).

**Proof:** the same seed under two skies; two seeds whose default moods
differ.

## Phase 7 — The 4K pass and the standing gates

- Re-render the reference set and the PR gallery at 2560x1440 or 4K;
  full-res judging will surface the next tier of nits (AA, texture
  filtering, LOD pops at band edges).
- Re-seed the perceptual baseline once Phases 1-2 land and the look
  stabilizes; keep the determinism gate green through every phase.
- Refresh the PR body gallery, which still shows pre-island renders.

## Standing constraints (unchanged)

Camera stays banded and orbital. Sim owns quantities, renderer owns form.
Procedural only. Every constant a fact about the world or a measured
calibration, never a thumb on the scale. Every visual claim ships with the
render that proves it.
