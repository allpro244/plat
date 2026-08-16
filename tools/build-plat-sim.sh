#!/usr/bin/env bash
# Bundle plat-econ's campaign runner + engine into plat-sim / plat-sim.exe
# via Node's Single Executable Application blob. Stock Node, no new runtime.
#
#   tools/build-plat-sim.sh              # linux + windows
#   tools/build-plat-sim.sh linux        # this machine's proof binary
#   tools/build-plat-sim.sh windows      # plat-sim.exe (inject into official win-x64 node)
#
# Acceptance: ./dist/plat-sim new --dir=… then advance — no node on the argv,
# no plat-econ path. The Windows exe is produced the same way; running it is
# a clean-machine sitting, not this script.
set -euo pipefail
cd "$(dirname "$0")/.."

NODE_VER="${NODE_VER:-22.14.0}"
DIST="${DIST:-dist}"
CACHE="${CACHE:-dist/node-cache}"
TARGETS="${1:-linux,windows}"
FUSE="NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2"
POSTJECT_VER="${POSTJECT_VER:-1.0.0-alpha.6}"

want() { [[ ",$TARGETS," == *",$1,"* ]] || [[ "$TARGETS" == "all" ]]; }

mkdir -p "$DIST" "$CACHE"

echo "== plat-econ =="
if [ ! -d plat-econ/.git ] && [ ! -f plat-econ/package.json ]; then
  git clone --depth 1 https://github.com/allpro244/plat-econ.git plat-econ
fi
if [ ! -f plat-econ/node_modules/esbuild/bin/esbuild ]; then
  (
    cd plat-econ
    export CI=true
    corepack enable 2>/dev/null || true
    corepack prepare pnpm@10.33.3 --activate 2>/dev/null || true
    pnpm install --frozen-lockfile
  )
fi
if [ ! -f plat-econ/test/.engine.mjs ]; then
  (cd plat-econ && export CI=true && pnpm engine)
fi

# Desk exports + richer HUD live in plat until plat-econ merges them.
cp -a tools/runner/citydoc.mjs plat-econ/tools/citydoc.mjs
cp -a tools/runner/game-server.mjs plat-econ/tools/game-server.mjs

echo "== esbuild (one CJS blob) =="
ESBUILD="plat-econ/node_modules/.bin/esbuild"
"$ESBUILD" plat-econ/tools/game-server.mjs \
  --bundle \
  --platform=node \
  --format=cjs \
  --outfile="$DIST/plat-sim.cjs" \
  --legal-comments=none
# SEA wants CommonJS. Code cache is V8/arch-specific — one blob for both OSes.
cat > "$DIST/sea-config.json" <<EOF
{
  "main": "$(pwd)/$DIST/plat-sim.cjs",
  "output": "$(pwd)/$DIST/sea-prep.blob",
  "disableExperimentalSEAWarning": true,
  "useSnapshot": false,
  "useCodeCache": false
}
EOF
node --experimental-sea-config "$DIST/sea-config.json"

inject() {
  local dest="$1"
  npx --yes "postject@${POSTJECT_VER}" "$dest" NODE_SEA_BLOB "$DIST/sea-prep.blob" \
    --sentinel-fuse "$FUSE"
}

fetch_node() {
  local os="$1"  # linux-x64 | win-x64
  local url="https://nodejs.org/dist/v${NODE_VER}/node-v${NODE_VER}-${os}"
  if [ "$os" = "win-x64" ]; then
    local zip="$CACHE/node-v${NODE_VER}-win-x64.zip"
    if [ ! -f "$zip" ]; then
      curl -fsSL -o "$zip" "${url}.zip"
    fi
    local unpacked="$CACHE/node-v${NODE_VER}-win-x64"
    if [ ! -f "$unpacked/node.exe" ]; then
      unzip -qo "$zip" -d "$CACHE"
    fi
    echo "$unpacked/node.exe"
  else
    local txz="$CACHE/node-v${NODE_VER}-linux-x64.tar.xz"
    if [ ! -f "$txz" ]; then
      curl -fsSL -o "$txz" "${url}.tar.xz"
    fi
    local unpacked="$CACHE/node-v${NODE_VER}-linux-x64"
    if [ ! -f "$unpacked/bin/node" ]; then
      tar -xJf "$txz" -C "$CACHE"
    fi
    echo "$unpacked/bin/node"
  fi
}

if want linux; then
  echo "== plat-sim (linux-x64) =="
  src="$(fetch_node linux-x64)"
  cp "$src" "$DIST/plat-sim"
  chmod +x "$DIST/plat-sim"
  inject "$DIST/plat-sim"
  chmod +x "$DIST/plat-sim"
  echo "Wrote $DIST/plat-sim ($(wc -c < "$DIST/plat-sim") bytes)"
fi

if want windows; then
  echo "== plat-sim.exe (win-x64) =="
  src="$(fetch_node win-x64)"
  cp "$src" "$DIST/plat-sim.exe"
  inject "$DIST/plat-sim.exe"
  echo "Wrote $DIST/plat-sim.exe ($(wc -c < "$DIST/plat-sim.exe") bytes)"
fi

if want linux && [ "${SKIP_SMOKE:-}" != "1" ]; then
  echo "== smoke (linux sidecar, no node argv) =="
  proof=$(mktemp -d)
  "$DIST/plat-sim" new --dir="$proof" --seed=1928 --size=city --density=village --cash=2500000
  "$DIST/plat-sim" advance --dir="$proof" --months=1
  test -f "$proof/hud.json"
  test -f "$proof/city.json"
  test -f "$proof/state.json"
  # Recorded runner must stay empty so plat does not try to re-exec a .mjs.
  node -e 'const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); if(m.runner){console.error("SEA wrote meta.runner:", m.runner); process.exit(1)}' \
    "$proof/campaign.json"
  echo "smoke OK -> $proof"
  rm -rf "$proof"
fi
