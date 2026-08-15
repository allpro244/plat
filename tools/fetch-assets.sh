#!/usr/bin/env bash
# Fetch the pinned CC0 assets into assets/downloaded/ (gitignored).
# Everything here is CC0 (Poly Haven / mirrors); no accounts, no licence
# tracking. Files are pinned by URL (+ sha256 where the mirror is static);
# a render is reproducible from this script alone.
#
# Two source profiles:
#   primary — first-party Poly Haven CDN: a LIBRARY of scan sets (several
#             masonry types, ground surfaces) + 4k skies. Used wherever the
#             CDN is reachable (e.g. CI).
#   mirror  — GitHub-hosted copies (pinned commits). Some sandboxes only
#             reach github.com; only ONE brick set and a 1k dusk sky exist
#             there, so every masonry slot maps to that set and the ground
#             falls back to plain color. The scene must render correctly
#             from either profile; CI reviews the primary look.
#
# Poly Haven file naming varies per asset (diff vs diffuse, rough vs
# roughness), so each map tries a chain of candidate names.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=assets/downloaded
mkdir -p "$DEST/sky"

GDP_COMMIT=34fc99545fc41520a958248f607101e7d0b95b05
GDP_RAW="https://raw.githubusercontent.com/godotengine/godot-demo-projects/$GDP_COMMIT"
MT="$GDP_RAW/3d/material_testers"
PH=https://dl.polyhaven.org/file/ph-assets

fetch() { # fetch <url> <dest> <sha256|->
  local url=$1 dest=$2 sha=$3
  if [[ -f $dest ]]; then
    if [[ $sha == - ]] || echo "$sha  $dest" | sha256sum -c --quiet 2>/dev/null; then
      echo "ok        $dest"
      return 0
    fi
  fi
  echo "fetching  $dest"
  curl -fsSL --retry 3 --max-time 300 -o "$dest.part" "$url"
  if [[ $sha != - ]]; then
    echo "$sha  $dest.part" | sha256sum -c --quiet
  fi
  mv "$dest.part" "$dest"
}

# fetch_first <dest> <url...> — try candidates until one succeeds.
fetch_first() {
  local dest=$1
  shift
  [[ -f $dest ]] && { echo "ok        $dest"; return 0; }
  local url
  for url in "$@"; do
    if curl -fsSL --retry 2 --max-time 300 -o "$dest.part" "$url" 2>/dev/null; then
      mv "$dest.part" "$dest"
      echo "fetched   $dest"
      return 0
    fi
  done
  rm -f "$dest.part"
  echo "MISSING   $dest (no candidate URL worked; scene falls back)"
  return 0
}

# ph_set <slot> <asset> — one Poly Haven 2k texture set into materials/<slot>/.
ph_set() {
  local slot=$1 asset=$2
  local dir="$DEST/materials/$slot"
  mkdir -p "$dir"
  local base="$PH/Textures/jpg/2k/$asset"
  fetch_first "$dir/albedo.jpg" \
    "$base/${asset}_diff_2k.jpg" "$base/${asset}_diffuse_2k.jpg" "$base/${asset}_col_2k.jpg" "$base/${asset}_col_01_2k.jpg"
  fetch_first "$dir/normal.jpg" \
    "$base/${asset}_nor_gl_2k.jpg" "$base/${asset}_normal_2k.jpg"
  fetch_first "$dir/ao.jpg" \
    "$base/${asset}_ao_2k.jpg"
  fetch_first "$dir/roughness.jpg" \
    "$base/${asset}_rough_2k.jpg" "$base/${asset}_roughness_2k.jpg"
}

primary_reachable() {
  curl -fsSL --max-time 15 -r 0-1023 -o /dev/null \
    "$PH/HDRIs/hdr/4k/kloofendal_43d_clear_puresky_4k.hdr" 2>/dev/null
}

if primary_reachable; then
  echo "== profile: primary (Poly Haven CDN) =="
  # Masonry library, assigned per era by the grammar (see grammar.gd):
  ph_set brick_red    brick_wall_001        # common red brick
  ph_set brick_mixed  mixed_brick_wall      # patched multi-tone brick
  ph_set brick_old    brick_wall_08         # older irregular brick
  ph_set stone_deco   cracked_concrete_wall # weathered render/limestone read
  ph_set stone_base   stone_brick_wall_001  # heavy stone base courses
  # Ground surfaces:
  ph_set asphalt      asphalt_02
  ph_set sidewalk     concrete_pavement
  # Skies. Daylight default: CLEAR pure sky (the partly-cloudy pin rendered
  # honest but soft shadows). Sun ~43 deg.
  fetch "$PH/HDRIs/hdr/4k/kloofendal_43d_clear_puresky_4k.hdr" "$DEST/sky/sky.hdr" -
else
  echo "== profile: mirror (GitHub; Poly Haven CDN unreachable from this network) =="
  # One brick set exists on the mirror; every masonry slot maps to it and
  # material variety comes from tints alone. Ground falls back to color.
  mkdir -p "$DEST/materials/brick_red"
  fetch "$MT/test_materials/texture_bricks.jpg"        "$DEST/materials/brick_red/albedo.jpg" \
    fce5acd91dbed00cc05798ae661d666f67a0cf2a1b3de48dbda57ade4b5ff811
  fetch "$MT/test_materials/texture_bricks_normal.jpg" "$DEST/materials/brick_red/normal.jpg" \
    8418b9a014649cc120633aba9d7afb50a9594adfd0196bba8495d602fea6def7
  fetch "$MT/test_materials/texture_bricks_ao.jpg"     "$DEST/materials/brick_red/ao.jpg" \
    75be56696c45cbd086c92d7f631b5b194dea4b88825db1c978c2f5d010b6f06f
  for slot in brick_mixed brick_old stone_deco stone_base; do
    mkdir -p "$DEST/materials/$slot"
    for f in albedo normal ao; do
      cp -n "$DEST/materials/brick_red/$f.jpg" "$DEST/materials/$slot/$f.jpg" 2>/dev/null || true
    done
  done
  # spruit_sunrise (Poly Haven CC0) via google/model-viewer — the only true
  # sky HDRI reachable over github.com. Low sun: the derived default moment
  # is an evening.
  MV_COMMIT=297ed2bdbea0c8f921d985ff0c71afd3a819e12e
  fetch "https://raw.githubusercontent.com/google/model-viewer/$MV_COMMIT/packages/shared-assets/environments/spruit_sunrise_1k_HDR.hdr" \
    "$DEST/sky/sky.hdr" \
    38199a31e945906f6778431e989256a92d9d78b0cfc0f902accad9f5244bf50f
fi

echo "assets ready under $DEST"
