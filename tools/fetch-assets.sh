#!/usr/bin/env bash
# Fetch the pinned CC0 assets into assets/downloaded/ (gitignored).
# Every file is pinned by URL + sha256; a render is reproducible from this
# script alone. No accounts, no licence tracking — everything here is CC0.
#
# Two source profiles:
#   primary — first-party Poly Haven CDN (full scan sets incl. per-pixel
#             roughness). Preferred wherever the network can reach it.
#   mirror  — GitHub-hosted copies of the same CC0 scan data (via
#             godotengine/godot-demo-projects, pinned to a commit). Used
#             automatically when the primary CDN is unreachable — some
#             sandboxed environments only allow github.com. The mirror brick
#             set carries albedo/normal/AO but no per-pixel roughness map;
#             the facade material uses a scalar roughness there (see
#             mesh_builder.gd for why that is a fact, not a fudge).
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=assets/downloaded
mkdir -p "$DEST/brick" "$DEST/sky"

GDP_COMMIT=34fc99545fc41520a958248f607101e7d0b95b05
GDP_RAW="https://raw.githubusercontent.com/godotengine/godot-demo-projects/$GDP_COMMIT"
MT="$GDP_RAW/3d/material_testers"

fetch() { # fetch <url> <dest> <sha256|->
  local url=$1 dest=$2 sha=$3
  if [[ -f $dest && $sha != - ]] && echo "$sha  $dest" | sha256sum -c --quiet 2>/dev/null; then
    echo "ok        $dest"
    return 0
  fi
  echo "fetching  $dest"
  curl -fsSL --retry 3 --max-time 300 -o "$dest.part" "$url"
  if [[ $sha != - ]]; then
    echo "$sha  $dest.part" | sha256sum -c --quiet
  fi
  mv "$dest.part" "$dest"
}

primary_reachable() {
  curl -fsSL --max-time 10 -o /dev/null "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/kloofendal_48d_partly_cloudy_puresky_1k.hdr" 2>/dev/null
}

if primary_reachable; then
  echo "== profile: primary (Poly Haven CDN) =="
  PH=https://dl.polyhaven.org/file/ph-assets
  # brick_wall_001, CC0 (polyhaven.com/a/brick_wall_001)
  fetch "$PH/Textures/jpg/2k/brick_wall_001/brick_wall_001_diffuse_2k.jpg" "$DEST/brick/albedo.jpg" -
  fetch "$PH/Textures/jpg/2k/brick_wall_001/brick_wall_001_nor_gl_2k.jpg"  "$DEST/brick/normal.jpg" -
  fetch "$PH/Textures/jpg/2k/brick_wall_001/brick_wall_001_ao_2k.jpg"      "$DEST/brick/ao.jpg" -
  fetch "$PH/Textures/jpg/2k/brick_wall_001/brick_wall_001_rough_2k.jpg"   "$DEST/brick/roughness.jpg" -
  # partly-cloudy pure sky, CC0 (polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky)
  fetch "$PH/HDRIs/hdr/4k/kloofendal_48d_partly_cloudy_puresky_4k.hdr"     "$DEST/sky/sky.hdr" -
else
  echo "== profile: mirror (GitHub; Poly Haven CDN unreachable from this network) =="
  fetch "$MT/test_materials/texture_bricks.jpg"        "$DEST/brick/albedo.jpg" \
    fce5acd91dbed00cc05798ae661d666f67a0cf2a1b3de48dbda57ade4b5ff811
  fetch "$MT/test_materials/texture_bricks_normal.jpg" "$DEST/brick/normal.jpg" \
    8418b9a014649cc120633aba9d7afb50a9594adfd0196bba8495d602fea6def7
  fetch "$MT/test_materials/texture_bricks_ao.jpg"     "$DEST/brick/ao.jpg" \
    75be56696c45cbd086c92d7f631b5b194dea4b88825db1c978c2f5d010b6f06f
  # "spruit_sunrise" (Poly Haven CC0), mirrored in google/model-viewer's
  # shared assets: an open low-sun sky, the only true sky HDRI reachable
  # over github.com. 1k — the primary profile's 4k sky replaces it wherever
  # the Poly Haven CDN is reachable.
  MV_COMMIT=297ed2bdbea0c8f921d985ff0c71afd3a819e12e
  fetch "https://raw.githubusercontent.com/google/model-viewer/$MV_COMMIT/packages/shared-assets/environments/spruit_sunrise_1k_HDR.hdr" \
    "$DEST/sky/sky.hdr" \
    38199a31e945906f6778431e989256a92d9d78b0cfc0f902accad9f5244bf50f
fi

echo "assets ready under $DEST"
