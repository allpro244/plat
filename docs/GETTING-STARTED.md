# Getting started (no prior Godot experience)

A tagged **release zip** is the double-click path: `plat.exe` + `plat-sim.exe`
in one folder, no Godot, no Node. This page is the **dev** path — you are
opening the Godot project and driving plat-econ from source.

You need three installs once, then two folders on disk.

## What is Godot?

[Godot](https://godotengine.org/download) is a free game engine — think of it as
the **player** for this project, like VLC is a player for video files. You
download Godot 4.5 (Standard, not .NET), open the `plat` folder in it, and press
Play.

## What you download (two GitHub repos, not one file)

| Repo | What it is |
|------|------------|
| [allpro244/plat](https://github.com/allpro244/plat) | The 3D city and game view (this repo) |
| [allpro244/plat-econ](https://github.com/allpro244/plat-econ) | The economy engine (cash, listings, buys) |

**Do not** download `game-server.mjs` by itself from GitHub. That file is only
one piece of plat-econ; it needs the rest of that repo plus a one-time build step.

Put the folders **side by side**, same parent directory:

```
MyGames/
  plat/          ← you already have this
  plat-econ/     ← clone or unzip this next to plat
```

plat will look for `../plat-econ/tools/game-server.mjs` automatically.

## One-time setup

### 1. Godot 4.5

Download from [godotengine.org/download](https://godotengine.org/download) —
**Godot Engine – Standard – 4.5.x** for your OS. Unzip or install; no account.

### 2. Node.js (for the economy)

Download the **LTS** installer from [nodejs.org](https://nodejs.org/). Needed so
plat can run “advance month” and “buy building” through plat-econ.

### 3. plat assets (textures and sky)

Open a terminal in the **plat** folder and run:

```sh
bash tools/fetch-assets.sh
```

On Windows without Git Bash, use Godot’s terminal or WSL, or ask for help — the
city works without this but looks flat and warns about missing files.

### 4. plat-econ build (creates the engine bundle)

Open a terminal in the **plat-econ** folder:

```sh
npm install -g pnpm
pnpm install
pnpm engine
```

If the last command errors, fix that before playing — `game-server.mjs` will say
`no engine bundle — run pnpm engine first`.

## Run the game

1. Open **Godot**.
2. **Import** → pick the `plat` folder (the one containing `project.godot`).
3. Press **F5** (or the ▶ Play button at top right).
4. Wait a few seconds while the city generates.
5. Press **F1** — **Break ground** (starts your firm and campaign).

If F1 shows **“no simulation found”**:

- Is `plat-econ` in the folder **next to** `plat` (not inside Downloads alone)?
- Did you run `pnpm install` and `pnpm engine` inside plat-econ?
- Is Node installed? (In a terminal: `node --version` should print v18 or newer.)

## Controls once you’re in

Press **H** in-game for the full list. Minimum to play:

| Key | Action |
|-----|--------|
| **F1** | Start a new campaign (do this first) |
| **Click** a building | Parcel card (price, BBL, floors, etc.) |
| **Space** | Advance a season |
| **B** | Buy the selected listing |
| **Left-drag** | Pan the map |
| **Right-drag** | Rotate / tilt |
| **Wheel** | Zoom |

## Still stuck?

Tell us your OS (Windows / Mac / Linux) and what happens when you press **F1**
(exact message on screen). That narrows it down fast.
