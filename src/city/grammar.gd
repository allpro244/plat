class_name Grammar
## The shape grammar: lot + era + seed -> massing and facade parameters.
## Owns FORM ONLY. Floor heights, setback arithmetic and envelope rules are
## era facts with sources noted inline; everything stochastic draws from the
## per-building RNG so the block is reproducible from one seed.
##
## Output building dictionary:
## {
##   era, lot,
##   boxes: [{aabb: AABB, win: {n,e,s,w: bool}}],   # massing, y-up
##   props: [{type, ...}],                          # water towers, bulkheads, cornices
##   facade: {kind, tint, bay_w, floor_h, ground_h, win_fx, win_fy}
## }

const MASONRY_FLOOR_H := 3.5   # typical pre-war office/loft floor-to-floor
const CURTAIN_FLOOR_H := 3.9   # International Style slab floor-to-floor
const GROUND_FLOOR_H := 4.5

# Brick albedo is reddish; tints multiply it toward the range of NYC masonry:
# painted brick, brownstone-brown, buff/limestone-ish, soot-darkened.
const MASONRY_TINTS := [
	Color(1.0, 1.0, 1.0), Color(0.95, 0.72, 0.58), Color(0.70, 0.52, 0.45),
	Color(1.10, 1.04, 0.92), Color(0.52, 0.47, 0.45), Color(0.85, 0.58, 0.45),
	Color(0.72, 0.70, 0.68), Color(0.98, 0.88, 0.72),
]

static func build(lot: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	match lot["era"]:
		"pre1916":
			return _pre1916(lot, rng)
		"setback1916":
			return _setback1916(lot, rng)
		"plaza1961":
			return _plaza1961(lot, rng)
	push_error("unknown era " + str(lot["era"]))
	return {}

# --- era rules -------------------------------------------------------------

## Pre-1916: no envelope control. Extrude the lot straight up from the lot
## line. 6–12 floors, cornice, punched windows, party-wall flanks.
static func _pre1916(lot: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var floors := rng.randi_range(5, 12)
	var h := GROUND_FLOOR_H + float(floors - 1) * MASONRY_FLOOR_H
	# Lofts do not always fill the full 30 m lot depth.
	var depth := minf(lot["z1"] - lot["z0"], rng.randf_range(20.0, 28.0))
	var rect := _lot_rect(lot, depth)
	var b := _base_building(lot, "masonry", rng)
	b["boxes"].append({"aabb": _box(rect, 0.0, h), "win": _street_only_windows(lot)})
	b["props"].append({"type": "cornice", "rect": rect, "y": h, "front": lot["front"]})
	b["props"].append({"type": "parapet", "rect": rect, "y": h})
	if rng.randf() < 0.55:
		b["props"].append(_bulkhead(rect, h, rng))
	# NYC gravity-tank rule: buildings above ~6 stories need a rooftop tank.
	if floors > 6:
		b["props"].append(_water_tower(rect, h, rng))
	return b

## 1916 Zoning Resolution: the sky-exposure plane. The street wall may rise
## 1.5x the street width (the common "1.5 times" district multiplier), then
## the mass steps back inside the plane; a tower covering <= 25% of the lot
## may rise without limit. Wider avenue -> taller sheer wall, which is why
## the avenue and the side street read differently.
static func _setback1916(lot: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var street_w: float = lot["street_w"]
	var wall_h := snappedf(1.5 * street_w, MASONRY_FLOOR_H)
	var big: bool = (lot["x1"] - lot["x0"]) > 15.0
	var total_h := rng.randf_range(95.0, 125.0) if big else rng.randf_range(55.0, 78.0)
	var rect := _lot_rect(lot, lot["z1"] - lot["z0"])
	var b := _base_building(lot, "masonry", rng)
	# Buff masonry range for the deco stock — the era rarely reads as red brick.
	b["facade"]["tint"] = [Color(1.08, 1.02, 0.90), Color(0.95, 0.90, 0.84),
			Color(1.0, 0.94, 0.85)][rng.randi_range(0, 2)]

	var y := 0.0
	var tier_h := wall_h
	var tier := rect
	var win := _street_only_windows(lot)
	var tiers := []
	# Real 1916-era towers take a FEW, DEEP steps — small repeated insets read
	# as a smooth taper from the air, which is exactly wrong.
	var max_steps := 3 if big else 2
	while y + tier_h < total_h and tiers.size() <= max_steps:
		tiers.append([tier, y, y + tier_h])
		b["boxes"].append({"aabb": _box(tier, y, y + tier_h), "win": win.duplicate()})
		y += tier_h
		tier = _inset(tier, lot, rng.randf_range(3.4, 5.0), rng.randf_range(2.6, 3.8))
		win = {"n": true, "e": tier["inset_e"], "s": true, "w": tier["inset_w"]}
		tier_h = snappedf(rng.randf_range(15.0, 26.0), MASONRY_FLOOR_H)
		if tier["x1"] - tier["x0"] < 9.0 or tier["z1"] - tier["z0"] < 9.0:
			break
	# Tower cap: 25% lot coverage, centered on the street half of the lot.
	var lot_area: float = (rect["x1"] - rect["x0"]) * (rect["z1"] - rect["z0"])
	var tower_w := minf(sqrt(lot_area * 0.25) * 1.25, tier["x1"] - tier["x0"])
	var tower_d := minf(lot_area * 0.25 / tower_w, tier["z1"] - tier["z0"])
	if total_h - y > 8.0 and tower_w > 7.5 and tower_d > 7.0:
		# The tower stands on the last tier, at its street edge — never
		# cantilevered past the mass below it.
		var cx: float = (tier["x0"] + tier["x1"]) * 0.5
		var tz0: float = tier["z0"] if lot["front"] == "north" else tier["z1"] - tower_d
		var trect := {"x0": cx - tower_w * 0.5, "x1": cx + tower_w * 0.5,
				"z0": tz0, "z1": tz0 + tower_d}
		trect["x0"] = maxf(trect["x0"], tier["x0"])
		trect["x1"] = minf(trect["x1"], tier["x1"])
		b["boxes"].append({"aabb": _box(trect, y, total_h),
				"win": {"n": true, "e": true, "s": true, "w": true}})
		b["props"].append({"type": "parapet", "rect": trect, "y": total_h})
		b["props"].append(_bulkhead(trect, total_h, rng))
		if rng.randf() < 0.8:
			b["props"].append(_water_tower(trect, total_h, rng))
	for t in tiers:
		b["props"].append({"type": "parapet", "rect": t[0], "y": t[2]})
	return b

## 1961 Zoning Resolution: FAR with a plaza bonus. Give up ground coverage,
## buy height: a sheer glass slab set back behind an open plaza.
static func _plaza1961(lot: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var rect := _lot_rect(lot, lot["z1"] - lot["z0"])
	var b := _base_building(lot, "curtain", rng)
	var floors := rng.randi_range(26, 33)
	var h := float(floors) * CURTAIN_FLOOR_H
	var slab_w: float = (rect["x1"] - rect["x0"]) * rng.randf_range(0.60, 0.72)
	var slab_d := rng.randf_range(17.0, 21.0)
	var setback := rng.randf_range(11.0, 15.0)
	var cx: float = (rect["x0"] + rect["x1"]) * 0.5
	var sz0: float
	if lot["front"] == "north":
		sz0 = rect["z0"] + setback
	else:
		sz0 = rect["z1"] - setback - slab_d
	var srect := {"x0": cx - slab_w * 0.5, "x1": cx + slab_w * 0.5,
			"z0": sz0, "z1": sz0 + slab_d}
	b["boxes"].append({"aabb": _box(srect, 0.0, h),
			"win": {"n": true, "e": true, "s": true, "w": true}})
	# Mechanical penthouse — the dark hat every International Style slab wears.
	var mech := {"x0": srect["x0"] + 2.0, "x1": srect["x1"] - 2.0,
			"z0": srect["z0"] + 2.0, "z1": srect["z1"] - 2.0}
	b["boxes"].append({"aabb": _box(mech, h, h + 4.0),
			"win": {"n": false, "e": false, "s": false, "w": false}})
	b["props"].append({"type": "plaza", "rect": rect})
	return b

# --- shared pieces ---------------------------------------------------------

static func _base_building(lot: Dictionary, kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var facade: Dictionary
	if kind == "curtain":
		facade = {
			"kind": "curtain",
			"tint": Color(0.16, 0.17, 0.18),
			"bay_w": 1.65, "floor_h": CURTAIN_FLOOR_H, "ground_h": CURTAIN_FLOOR_H * 1.4,
			"win_fx": 0.93, "win_fy": 0.74,
		}
	else:
		facade = {
			"kind": "masonry",
			"tint": MASONRY_TINTS[rng.randi_range(0, MASONRY_TINTS.size() - 1)],
			"bay_w": rng.randf_range(2.3, 2.9), "floor_h": MASONRY_FLOOR_H,
			"ground_h": GROUND_FLOOR_H,
			"win_fx": rng.randf_range(0.38, 0.46), "win_fy": 0.52,
		}
	return {"era": lot["era"], "lot": lot, "boxes": [], "props": [], "facade": facade}

static func _lot_rect(lot: Dictionary, depth: float) -> Dictionary:
	# Building mass always meets the STREET lot line; unused depth is at the rear.
	if lot["front"] == "north":
		return {"x0": lot["x0"], "x1": lot["x1"], "z0": lot["z0"], "z1": lot["z0"] + depth}
	return {"x0": lot["x0"], "x1": lot["x1"], "z0": lot["z1"] - depth, "z1": lot["z1"]}

static func _box(r: Dictionary, y0: float, y1: float) -> AABB:
	return AABB(Vector3(r["x0"], y0, r["z0"]),
			Vector3(r["x1"] - r["x0"], y1 - y0, r["z1"] - r["z0"]))

## Party-wall rule, falling straight out of the lot geometry: the street face
## and the rear face get windows, the lot-line flanks do not.
static func _street_only_windows(_lot: Dictionary) -> Dictionary:
	return {"n": true, "s": true, "e": false, "w": false}

static func _inset(tier: Dictionary, lot: Dictionary, front_in: float, side_in: float) -> Dictionary:
	var t := {"x0": tier["x0"] + side_in, "x1": tier["x1"] - side_in}
	if lot["front"] == "north":
		t["z0"] = tier["z0"] + front_in
		t["z1"] = tier["z1"] - front_in * 0.5
	else:
		t["z1"] = tier["z1"] - front_in
		t["z0"] = tier["z0"] + front_in * 0.5
	t["inset_e"] = true
	t["inset_w"] = true
	return t

static func _water_tower(rect: Dictionary, roof_y: float, rng: RandomNumberGenerator) -> Dictionary:
	return {"type": "watertower",
		"pos": Vector3(
			rng.randf_range(rect["x0"] + 3.0, rect["x1"] - 3.0),
			roof_y,
			rng.randf_range(rect["z0"] + 3.0, rect["z1"] - 3.0))}

static func _bulkhead(rect: Dictionary, roof_y: float, rng: RandomNumberGenerator) -> Dictionary:
	var w := 4.0
	var d := 3.2
	var x0 := rng.randf_range(rect["x0"] + 1.0, maxf(rect["x1"] - 1.0 - w, rect["x0"] + 1.01))
	var z0 := rng.randf_range(rect["z0"] + 1.0, maxf(rect["z1"] - 1.0 - d, rect["z0"] + 1.01))
	return {"type": "bulkhead",
		"aabb": AABB(Vector3(x0, roof_y, z0), Vector3(w, 2.8, d))}
