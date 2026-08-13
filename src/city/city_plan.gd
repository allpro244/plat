class_name CityPlan
## The layout DNA of one city, derived entirely from its seed. This is the
## layer that makes two cities feel like two PLACES rather than two rerolls
## of the same place: where the wide avenues run, where the parks are, where
## the water is, and which district a block belongs to.
##
## Owns QUANTITIES AND ASSIGNMENT only (street widths, cell types, district
## params); what a district's buildings look like remains the generators'
## business, parameterized by what this hands them.
##
## Grid convention: block columns gx in [-RINGS..RINGS], rows gy likewise.
## The hero block is cell (0,0) and is always buildable; the streets touching
## it keep the hero contract's widths (18 m north, 30 m south, 18 m cross).

const RINGS := 12
const BLOCK_W := 180.0
const BLOCK_D := 61.0

var seed_value: int
var col_x0 := {}        # gx -> west edge of that block column
var row_z0 := {}        # gy -> north edge of that block row
var street_wx := {}     # boundary index i -> width of street west of column i
var street_wz := {}     # boundary index j -> width of street north of row j
var cell_type := {}     # Vector2i -> "blocks" | "park" | "water"
var district := {}      # Vector2i -> district type string
var core_center := Vector2i.ZERO

## Per-district generation parameters, consumed by ContextGen.
## height_mul scales the base distribution; cap clamps it; mass_w widens
## footprints; win_fx shrinks windows (industrial reads near-blind).
const DISTRICTS := {
	"core":       {"height_mul": 1.45, "cap": 999.0, "mass_w": [16.0, 36.0], "bay": 1.9,
			"win_fx": 0.55, "tints": [Color(0.55, 0.56, 0.60), Color(0.42, 0.44, 0.48),
			Color(0.70, 0.70, 0.72), Color(0.60, 0.55, 0.50)]},
	"prewar":     {"height_mul": 1.0, "cap": 999.0, "mass_w": [14.0, 34.0], "bay": 2.6,
			"win_fx": 0.42, "tints": [Color(0.80, 0.68, 0.58), Color(0.95, 0.85, 0.74),
			Color(1.0, 0.78, 0.62), Color(0.72, 0.69, 0.67)]},
	"walkup":     {"height_mul": 0.62, "cap": 34.0, "mass_w": [12.0, 24.0], "bay": 2.4,
			"win_fx": 0.40, "tints": [Color(0.85, 0.72, 0.60), Color(0.75, 0.62, 0.52),
			Color(0.90, 0.82, 0.70), Color(0.68, 0.60, 0.55)]},
	"industrial": {"height_mul": 0.50, "cap": 26.0, "mass_w": [40.0, 85.0], "bay": 4.5,
			"win_fx": 0.30, "tints": [Color(0.62, 0.58, 0.54), Color(0.55, 0.50, 0.46),
			Color(0.70, 0.66, 0.60), Color(0.58, 0.56, 0.55)]},
}

func _init(city_seed: int) -> void:
	seed_value = city_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(city_seed) + "/plan")
	_streets(rng)
	_positions()
	_water(rng)
	_parks(rng)
	_districts(rng)

# --- streets ---------------------------------------------------------------

func _streets(rng: RandomNumberGenerator) -> void:
	# Cross streets default 18 m; a seeded handful of column boundaries are
	# 36 m avenues — the grid itself becomes part of the city's fingerprint.
	var avenue_every := rng.randi_range(4, 7)
	var phase := rng.randi_range(0, avenue_every - 1)
	for i in range(-RINGS, RINGS + 2):
		street_wx[i] = 36.0 if posmod(i + phase, avenue_every) == 0 else 18.0
	# Row boundaries: 24 m typical, rare 34 m crosstown avenue. The hero
	# block's own frontages are contract-fixed.
	for j in range(-RINGS, RINGS + 2):
		street_wz[j] = 34.0 if rng.randf() < 0.12 else 24.0
	street_wz[0] = 18.0   # hero north side street
	street_wz[1] = 30.0   # hero south avenue

func _positions() -> void:
	col_x0[0] = -BLOCK_W * 0.5
	for gx in range(1, RINGS + 1):
		col_x0[gx] = col_x0[gx - 1] + BLOCK_W + street_wx[gx]
	for gx in range(-1, -RINGS - 1, -1):
		col_x0[gx] = col_x0[gx + 1] - street_wx[gx + 1] - BLOCK_W
	row_z0[0] = -BLOCK_D * 0.5
	for gy in range(1, RINGS + 1):
		row_z0[gy] = row_z0[gy - 1] + BLOCK_D + street_wz[gy]
	for gy in range(-1, -RINGS - 1, -1):
		row_z0[gy] = row_z0[gy + 1] - street_wz[gy + 1] - BLOCK_D

# --- features --------------------------------------------------------------

func _water(rng: RandomNumberGenerator) -> void:
	for gy in range(-RINGS, RINGS + 1):
		for gx in range(-RINGS, RINGS + 1):
			cell_type[Vector2i(gx, gy)] = "blocks"
	# Roughly half of cities get a waterfront: every cell beyond a seeded
	# edge line becomes water. The strongest single identity feature a city
	# silhouette has.
	if rng.randf() < 0.55:
		var side := rng.randi_range(0, 3)  # 0=E 1=W 2=N 3=S
		var at := rng.randi_range(5, 10)
		for gy in range(-RINGS, RINGS + 1):
			for gx in range(-RINGS, RINGS + 1):
				var beyond := false
				match side:
					0: beyond = gx > at
					1: beyond = gx < -at
					2: beyond = gy < -at
					3: beyond = gy > at
				if beyond:
					cell_type[Vector2i(gx, gy)] = "water"

func _parks(rng: RandomNumberGenerator) -> void:
	# 2-5 parks, each 1x1 or 1x2 cells, never the hero cell, never water.
	var count := rng.randi_range(2, 5)
	for k in range(count):
		var gx := rng.randi_range(-RINGS + 1, RINGS - 1)
		var gy := rng.randi_range(-RINGS + 1, RINGS - 1)
		var long := rng.randf() < 0.4
		for cell in ([Vector2i(gx, gy), Vector2i(gx + 1, gy)] if long else [Vector2i(gx, gy)]):
			if cell == Vector2i.ZERO:
				continue
			if cell_type.get(cell, "blocks") == "blocks":
				cell_type[cell] = "park"

func _districts(rng: RandomNumberGenerator) -> void:
	# The dense core sits near (not necessarily on) the hero block; the other
	# districts seed outward. Cells join the nearest center, so districts are
	# coherent patches, not noise.
	core_center = Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
	var centers := [[core_center, "core"]]
	# Two standing pre-war anchors keep mid-rise fabric the DEFAULT fill;
	# specialty districts carve into it rather than dominating the map.
	centers.append([core_center + Vector2i(-6, 3), "prewar"])
	centers.append([core_center + Vector2i(5, -4), "prewar"])
	var others := ["prewar", "walkup", "industrial", "walkup", "prewar"]
	for k in range(rng.randi_range(3, 4)):
		var c := Vector2i(rng.randi_range(-RINGS, RINGS), rng.randi_range(-RINGS, RINGS))
		if Vector2(c - core_center).length() < 5.0:
			c = core_center + Vector2i(rng.randi_range(5, 8), rng.randi_range(5, 8))
		# Seeded pick, never the global RNG — the plan must be reproducible.
		centers.append([c, others[rng.randi_range(0, others.size() - 1)]])
	for gy in range(-RINGS, RINGS + 1):
		for gx in range(-RINGS, RINGS + 1):
			var cell := Vector2i(gx, gy)
			var best := ""
			var best_d := 1e9
			for c in centers:
				var d: float = Vector2(cell - (c[0] as Vector2i)).length()
				if d < best_d:
					best_d = d
					best = c[1]
			district[cell] = best
	# The hero block's own neighborhood always reads pre-war: that is what
	# its detailed generator builds.
	district[Vector2i.ZERO] = "prewar"

# --- queries ---------------------------------------------------------------

func params(cell: Vector2i) -> Dictionary:
	return DISTRICTS[district.get(cell, "prewar")]

## Distance-from-core falloff for the skyline gradient.
func falloff(cell: Vector2i) -> float:
	var ring := Vector2(cell - core_center).length()
	return clampf(1.25 - ring * 0.075, 0.45, 1.25)

func describe() -> String:
	var counts := {}
	for cell in cell_type:
		var t: String = cell_type[cell]
		counts[t] = counts.get(t, 0) + 1
	return "plan seed=%d core=%s cells=%s" % [seed_value, str(core_center), str(counts)]
