class_name CityPlan
## The layout DNA of one city, derived entirely from its seed. This is the
## layer that makes two cities feel like two PLACES rather than two rerolls
## of the same place — and, as of v2, the layer that breaks the single
## Manhattan grid. A city is now several GRID DOMAINS: patches of street
## grid, each with its own orientation, block size and road rhythm, assigned
## by nearest-center. Where two domains meet, their grids collide and the
## streets bend — the irregular seams that real grown cities have and a
## one-grid city never does. On top of that: 0-2 diagonal boulevards carved
## straight through whatever fabric they cross, an angled shoreline (not an
## axis-aligned edge), and parks as world-space rectangles.
##
## Owns QUANTITIES AND ASSIGNMENT only (block placement, orientation,
## district params); what a block's buildings look like remains the
## generators' business.
##
## The hero block's contract is untouchable: domain 0 is the old axis-
## aligned grid with the contract street widths, and boulevards, water and
## parks are all kept out of the hero's neighborhood.

const RINGS := 12          # hero-domain grid half-extent, in blocks
const BLOCK_W := 180.0     # hero-domain block size (the contract block)
const BLOCK_D := 61.0
const CITY_R := 2600.0     # world radius the plan populates, meters

var seed_value: int
var domains := []          # {center:Vector2, angle, bw, bd, rx, rz, ave_every, ave_phase}
var boulevards := []       # {p:Vector2, dir:Vector2 (unit), w}
var water := {}            # {} or {n:Vector2 (unit), d:float} — water where dot(p,n)>d
var parks := []            # {center:Vector2, w, d, angle}
var blocks := []           # {key, x, z, angle, w, d, dist, district}
var core_center := Vector2.ZERO   # world meters
var _district_centers := []       # [[Vector2, type], ...]

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
	_make_domains(rng)
	_make_boulevards(rng)
	_make_water(rng)
	_make_parks(rng)
	_make_districts(rng)
	_make_blocks()

# --- layout DNA -------------------------------------------------------------

func _make_domains(rng: RandomNumberGenerator) -> void:
	# Domain 0 is the hero's: axis-aligned, contract block size, contract
	# street widths near the origin (see _hero_positions). Always present.
	domains.append({"center": Vector2.ZERO, "angle": 0.0,
			"bw": BLOCK_W, "bd": BLOCK_D, "rx": 18.0, "rz": 24.0,
			"ave_every": rng.randi_range(4, 7), "ave_phase": rng.randi_range(0, 6)})
	# 2-4 more domains, each a differently-turned, differently-pitched grid.
	# Their collisions with each other (and with domain 0) are where the city
	# stops looking like one endless Manhattan.
	for k in range(rng.randi_range(2, 4)):
		var ang := rng.randf_range(0.6, 2.5)                 # 34-143 deg around
		var r := rng.randf_range(650.0, 2100.0)
		var center := Vector2(cos(ang * TAU), sin(ang * TAU)).normalized() * r
		domains.append({
			"center": center,
			"angle": deg_to_rad(rng.randf_range(8.0, 42.0)) * (1.0 if rng.randf() < 0.5 else -1.0),
			"bw": rng.randf_range(110.0, 200.0),
			"bd": rng.randf_range(55.0, 80.0),
			"rx": rng.randf_range(15.0, 22.0),
			"rz": rng.randf_range(18.0, 26.0),
			"ave_every": rng.randi_range(4, 7),
			"ave_phase": rng.randi_range(0, 6),
		})

func _make_boulevards(rng: RandomNumberGenerator) -> void:
	# 0-2 wide corridors cut straight across the fabric at a non-grid angle,
	# Broadway-style. Routed to miss the hero neighborhood.
	for k in range(rng.randi_range(0, 2)):
		var ang := rng.randf_range(0.0, TAU)
		var dir := Vector2(cos(ang), sin(ang))
		var n := Vector2(-dir.y, dir.x)
		var offset := rng.randf_range(220.0, 1400.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		boulevards.append({"p": n * offset, "dir": dir,
				"w": rng.randf_range(30.0, 44.0)})

func _make_water(rng: RandomNumberGenerator) -> void:
	# ~55% of cities get a waterfront. The shoreline is a half-plane at a
	# seeded ANGLE — an axis-aligned shore was the old grid showing through.
	if rng.randf() < 0.55:
		var ang := rng.randf_range(0.0, TAU)
		water = {"n": Vector2(cos(ang), sin(ang)),
				"d": rng.randf_range(750.0, 1800.0)}

func _make_parks(rng: RandomNumberGenerator) -> void:
	# 3-6 parks as world rectangles aligned to their owning domain's grid.
	for k in range(rng.randi_range(3, 6)):
		var ang := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(260.0, 1700.0)
		var center := Vector2(cos(ang), sin(ang)) * r
		if _in_water(center):
			continue
		parks.append({"center": center,
				"w": rng.randf_range(150.0, 330.0), "d": rng.randf_range(70.0, 160.0),
				"angle": float(domains[_nearest_domain(center)]["angle"])})

func _make_districts(rng: RandomNumberGenerator) -> void:
	var ca := rng.randf_range(0.0, TAU)
	core_center = Vector2(cos(ca), sin(ca)) * rng.randf_range(0.0, 380.0)
	_district_centers = [[core_center, "core"]]
	# Two standing pre-war anchors keep mid-rise fabric the DEFAULT fill;
	# specialty districts carve into it rather than dominating the map.
	_district_centers.append([core_center + Vector2(-1150.0, 520.0), "prewar"])
	_district_centers.append([core_center + Vector2(980.0, -700.0), "prewar"])
	var others := ["prewar", "walkup", "industrial", "walkup", "prewar"]
	for k in range(rng.randi_range(3, 4)):
		var ang := rng.randf_range(0.0, TAU)
		var c := Vector2(cos(ang), sin(ang)) * rng.randf_range(800.0, 2300.0)
		_district_centers.append([c, others[rng.randi_range(0, others.size() - 1)]])

# --- block placement --------------------------------------------------------

func _nearest_domain(p: Vector2) -> int:
	var best := 0
	var best_d := 1e12
	for i in range(domains.size()):
		var d: float = p.distance_squared_to(domains[i]["center"])
		if d < best_d:
			best_d = d
			best = i
	return best

func _in_water(p: Vector2) -> bool:
	return not water.is_empty() and p.dot(water["n"]) > float(water["d"]) - 50.0

func _in_park(p: Vector2) -> bool:
	for pk in parks:
		var local: Vector2 = (p - pk["center"]).rotated(-float(pk["angle"]))
		if absf(local.x) < float(pk["w"]) * 0.5 + 8.0 and absf(local.y) < float(pk["d"]) * 0.5 + 8.0:
			return true
	return false

func _on_boulevard(p: Vector2, half_w: float, half_d: float) -> bool:
	for b in boulevards:
		var n: Vector2 = Vector2(-b["dir"].y, b["dir"].x)
		if absf((p - (b["p"] as Vector2)).dot(n)) < float(b["w"]) * 0.5 + minf(half_w, half_d):
			return true
	return false

func _district_of(p: Vector2) -> String:
	if p.length() < 260.0:
		return "prewar"  # the hero's own neighborhood: what its generator builds
	var best := "prewar"
	var best_d := 1e12
	for c in _district_centers:
		var d: float = p.distance_squared_to(c[0])
		if d < best_d:
			best_d = d
			best = c[1]
	return best

func _keep(p: Vector2, dom: int, half_w: float, half_d: float, key: String) -> bool:
	# Ragged perimeter: each block draws its own city-limit radius from a
	# hash of its key, so the edge frays out over ~700 m instead of ending
	# on a compass-perfect circle (which no real city does).
	var fray := float(hash(key) & 0xffff) / 65535.0
	if p.length() > CITY_R * (0.73 + 0.30 * fray):
		return false
	if _nearest_domain(p) != dom:
		return false  # another domain's grid owns this ground
	if _in_water(p) or _in_park(p):
		return false
	if _on_boulevard(p, half_w, half_d):
		return false
	return true

## Hero-domain column/row edges: uniform pitch EXCEPT the streets touching
## the hero block, which keep the contract widths (18 m north side street,
## 30 m south avenue; 36 m avenues on the domain rhythm).
func _hero_positions() -> Dictionary:
	var d: Dictionary = domains[0]
	var col_x0 := {0: -BLOCK_W * 0.5}
	var row_z0 := {0: -BLOCK_D * 0.5}
	var wx := {}
	var wz := {}
	for i in range(-RINGS, RINGS + 2):
		wx[i] = 36.0 if posmod(i + int(d["ave_phase"]), int(d["ave_every"])) == 0 else float(d["rx"])
		wz[i] = float(d["rz"])
	wz[0] = 18.0   # hero north side street (contract)
	wz[1] = 30.0   # hero south avenue (contract)
	for gx in range(1, RINGS + 1):
		col_x0[gx] = col_x0[gx - 1] + BLOCK_W + wx[gx]
	for gx in range(-1, -RINGS - 1, -1):
		col_x0[gx] = col_x0[gx + 1] - wx[gx + 1] - BLOCK_W
	for gy in range(1, RINGS + 1):
		row_z0[gy] = row_z0[gy - 1] + BLOCK_D + wz[gy]
	for gy in range(-1, -RINGS - 1, -1):
		row_z0[gy] = row_z0[gy + 1] - wz[gy + 1] - BLOCK_D
	return {"col_x0": col_x0, "row_z0": row_z0}

func _make_blocks() -> void:
	# Domain 0: the hero grid, axis-aligned, contract widths.
	var pos := _hero_positions()
	for gy in range(-RINGS, RINGS + 1):
		for gx in range(-RINGS, RINGS + 1):
			if gx == 0 and gy == 0:
				continue  # the hero block itself is BlockGen's
			var c := Vector2(float(pos["col_x0"][gx]) + BLOCK_W * 0.5,
					float(pos["row_z0"][gy]) + BLOCK_D * 0.5)
			if not _keep(c, 0, BLOCK_W * 0.5, BLOCK_D * 0.5, "0/%d/%d" % [gx, gy]):
				continue
			blocks.append(_block(c, 0.0, BLOCK_W, BLOCK_D, "0/%d/%d" % [gx, gy]))
	# Other domains: rotated lattices anchored at the domain center.
	for di in range(1, domains.size()):
		var d: Dictionary = domains[di]
		var pitch_x: float = float(d["bw"]) + float(d["rx"])
		var pitch_z: float = float(d["bd"]) + float(d["rz"])
		var n_i := int(ceil((CITY_R * 2.2) / pitch_x))
		var n_j := int(ceil((CITY_R * 2.2) / pitch_z))
		var ang: float = float(d["angle"])
		var u := Vector2(cos(ang), sin(ang))
		var v := Vector2(-sin(ang), cos(ang))
		for j in range(-n_j, n_j + 1):
			for i in range(-n_i, n_i + 1):
				var extra: float = (36.0 - float(d["rx"])) \
						* float(posmod(i + int(d["ave_phase"]), int(d["ave_every"])) == 0)
				var c: Vector2 = (d["center"] as Vector2) \
						+ u * (float(i) * pitch_x + extra * 0.5) + v * (float(j) * pitch_z)
				if not _keep(c, di, float(d["bw"]) * 0.5, float(d["bd"]) * 0.5, "%d/%d/%d" % [di, i, j]):
					continue
				blocks.append(_block(c, ang, float(d["bw"]) - extra, float(d["bd"]),
						"%d/%d/%d" % [di, i, j]))

func _block(c: Vector2, ang: float, w: float, d: float, key: String) -> Dictionary:
	return {"key": key, "x": c.x, "z": c.y, "angle": ang, "w": w, "d": d,
			"dist": c.length(), "district": _district_of(c)}

# --- queries ----------------------------------------------------------------

func params_for(b: Dictionary) -> Dictionary:
	return DISTRICTS[b["district"]]

## Distance-from-core falloff for the skyline gradient. 0.000375/m matches
## the old per-ring 0.075 at the ~200 m hero-block pitch.
func falloff(b: Dictionary) -> float:
	var dist: float = Vector2(b["x"], b["z"]).distance_to(core_center)
	return clampf(1.25 - dist * 0.000375, 0.45, 1.25)

func describe() -> String:
	var per_district := {}
	for b in blocks:
		per_district[b["district"]] = int(per_district.get(b["district"], 0)) + 1
	return "plan seed=%d domains=%d blocks=%d boulevards=%d parks=%d water=%s core=(%.0f,%.0f) %s" % [
			seed_value, domains.size(), blocks.size(), boulevards.size(), parks.size(),
			"none" if water.is_empty() else "yes", core_center.x, core_center.y,
			str(per_district)]
