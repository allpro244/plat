class_name ContextGen
## The rest of the city, tiered by distance from the hero block — the Scale
## phase's answer to "does it run" before per-building detail gets expensive.
##
## Consumes CityPlan.blocks: world-placed, possibly ROTATED block footprints
## from several grid domains. Masses are generated in the block's local frame
## and transformed out, so a turned grid costs nothing extra.
##
## Tiers (by distance from the hero block):
##   < NEAR_R    one merged mesh per block, windowed facade shader,
##               per-mass tint via vertex color.
##   otherwise   FAR — three blocks merged per instance, plain vertex-color
##               material, no window shader. Impostor tier: silhouette and
##               value only, which is all the far band can resolve.
##
## Heights fall off with distance from the core (a downtown gradient), with
## rare outlier towers anywhere — the skyline shape real districts have.
## Same seed, same city.

const FACADE_SHADER := preload("res://src/city/facade.gdshader")

const NEAR_R := 3200.0  # windowed-tier radius: the WHOLE island renders full-quality.
## The 850 m tiering was a frame-cost decision from the orbital-hero era;
## with island-wide beauty cameras the impostor tier filled most of every
## frame and read as white boxes (user-reported). Stills can afford full
## quality everywhere; the far tier code remains for a future LOD dial.

## ERAS: the master variable real streets have and parameter jitter does
## not. A building's era dictates its floor heights, window shapes, base
## treatment, cornice odds and roof events — so two eras differ in KIND.
## Surface A carries victorian/tenement fabric, B carries deco/prewar,
## C carries midcentury — so era also correlates with wall material.
const ERAS := {
	"victorian":  {"floor_h": 3.9, "gfh": 4.8, "bay": 2.9, "wfx": 0.32, "wfy": 0.64,
			"cornice_p": 0.85, "mansard_p": 0.22, "wt_p": 0.3, "base_floors": 1.0,
			"base_tint": Color(0.78, 0.72, 0.66), "base_stone": 1.0},
	"prewar":     {"floor_h": 3.4, "gfh": 4.4, "bay": 2.35, "wfx": 0.45, "wfy": 0.5,
			"cornice_p": 0.55, "mansard_p": 0.0, "wt_p": 0.3, "base_floors": 2.0,
			"base_tint": Color(0.88, 0.85, 0.8), "base_stone": 1.0},
	"midcentury": {"floor_h": 3.05, "gfh": 3.9, "bay": 3.5, "wfx": 0.62, "wfy": 0.44,
			"cornice_p": 0.0, "mansard_p": 0.0, "wt_p": 0.08, "base_floors": 1.0,
			"base_tint": Color(1.02, 1.02, 1.0), "base_stone": 0.0},
}

static var _wall_tex := {}
static var _matlib := {}
## Per-building UV2 (style hash, texture offset), set before emitting each
## building; every _wall/_top vertex carries it.
static var _uv2 := Vector2.ZERO

static var night := 0.0   # 0 = full day, 1 = full dusk; set by the scene

static func build(seed_value: int, matlib: Dictionary, plan: CityPlan,
		night_factor: float = 0.0) -> Node3D:
	night = night_factor
	_wall_tex = matlib.get("brick_red", {})
	_matlib = matlib
	var root := Node3D.new()
	var far_st := _st()   # accumulates FAR tier geometry, flushed in batches
	var far_count := 0
	for b in plan.blocks:
		# Per-block RNG: one block's rules never reshuffle another's.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d/ctx/%s" % [seed_value, b["key"]])
		var xf := Transform3D(Basis(Vector3.UP, -float(b["angle"])),
				Vector3(float(b["x"]), 0.0, float(b["z"])))
		if float(b["dist"]) < NEAR_R:
			root.add_child(_block_windowed(rng, b, xf, plan))
		else:
			_block_far(far_st, rng, b, xf, plan)
			far_count += 1
			if far_count % 3 == 0:
				root.add_child(_flush_far(far_st))
				far_st = _st()
	if far_count % 3 != 0:
		root.add_child(_flush_far(far_st))
	return root

## Dress an IMPORTED engine city (docs/ECONOMY-ADAPTER.md, Stage 3): every
## quantity that drives form here came out of the economy engine's parcel
## table, not a seeded roll. yearBuilt picks the era, class picks masonry
## vs curtain wall, the district picks the palette, the footprint is the
## engine's ring verbatim. The seeded parts that REMAIN seeded (bay jitter,
## repaints, roof furniture) are form — the renderer's half of the line.
## Map overlay for the game view (docs/GAME-PLAN.md phase 4): "" is the
## true city; "owners" recolors the player's deeds gold and the for-sale
## tape green so the game state reads at any band. Set by the viewer,
## consumed at build time — an overlay toggle is a rebuild.
static var overlay := ""

static func build_imported(ci: CityImport, matlib: Dictionary,
		night_factor: float) -> Node3D:
	night = night_factor
	_matlib = matlib
	_wall_tex = matlib.get("brick_red", {})
	var root := Node3D.new()
	# City-wide palette family, seeded by the city's own seed; per-district
	# tint lists derive from it so districts read as quarters of one town.
	var crng := RandomNumberGenerator.new()
	crng.seed = hash("family/%d" % ci.seed_value)
	var fam: Dictionary = CityPlan.FAMILIES[CityPlan.FAMILIES.keys()[
			crng.randi_range(0, CityPlan.FAMILIES.keys().size() - 1)]]
	var district_p := {}
	# Chunk the city so each mesh stays a reasonable upload; grouping by
	# stride keeps neighbours in different chunks irrelevant — materials
	# are per-era surfaces inside each chunk either way.
	# Chunks are grouped by OCCUPANCY BUCKET, because lit_fraction is a
	# per-material uniform: every building in a chunk shares one lit level,
	# so the buckets make dusk windows follow the economy's occupancy to
	# within ~6%. Old exports without occupancy fall into one bucket and
	# keep the district constants.
	var chunk := 140
	var buckets := {}
	for i in range(ci.buildings.size()):
		var occ: float = ci.buildings[i]["occ"]
		var k := -1 if occ < 0.0 else clampi(int(occ * 8.0), 0, 7)
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(i)
	for k in buckets:
		var idxs: Array = buckets[k]
		var lit := -1.0 if k == -1 else (float(k) + 0.5) / 8.0
		for c0 in range(0, idxs.size(), chunk):
			root.add_child(_imported_chunk(ci, idxs.slice(c0, mini(c0 + chunk, idxs.size())),
					fam, district_p, lit))
	return root

static func _imported_district_p(district: String, seed_value: int,
		fam: Dictionary, cache: Dictionary) -> Dictionary:
	if cache.has(district):
		return cache[district]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/dp/%s" % [seed_value, district])
	var tints: Array = []
	for base in [Color(0.58, 0.52, 0.46), Color(0.66, 0.60, 0.52),
			Color(0.52, 0.44, 0.38), Color(0.72, 0.68, 0.62)]:
		tints.append((base as Color) * (fam["mul"] as Color))
	for extra in fam["extra"]:
		tints.append(extra)
	var p := {
		"tints": tints,
		"bay": rng.randf_range(1.3, 1.8),
		"win_fx": rng.randf_range(0.5, 0.62),
		# Lit fractions are still per-district constants; the engine does
		# not export occupancy yet. When it does (adapter Stage 4), this
		# is the line that starts reading it.
		"lit": rng.randf_range(0.18, 0.45),
		"shop_lit": rng.randf_range(0.4, 0.7),
	}
	cache[district] = p
	return p

static func _imported_chunk(ci: CityImport, indices: Array,
		fam: Dictionary, district_p: Dictionary, lit_occ: float) -> MeshInstance3D:
	var st := _st()
	var st_b := _st()
	var st_c := _st()
	var roof := _st()
	var tw := _st()
	var xf := Transform3D.IDENTITY
	var p_any: Dictionary = {}
	for i in indices:
		var b: Dictionary = ci.buildings[i]
		if b["deco"] or float(b["z1"]) <= 0.05:
			continue   # scenery and vacant lots are ImportGen's problem
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d/imp/%s/%d" % [ci.seed_value, b["bbl"], int(b["crown"])])
		var p := _imported_district_p(str(b["district"]), ci.seed_value, fam, district_p)
		p_any = p
		var ring: PackedVector2Array = b["ring"]
		var z0: float = b["z0"]
		var h: float = float(b["z1"]) - z0
		var year: int = b["year"]
		var cls: String = b["cls"]
		# ERA FROM THE RECORD, not from a roll: the one master variable the
		# import flips from seeded to real.
		var era_name := "victorian" if year < 1916 else \
				("prewar" if year < 1950 else "midcentury")
		var tint: Color = p["tints"][rng.randi_range(0, (p["tints"] as Array).size() - 1)]
		if overlay == "owners":
			if b.get("held", false):
				tint = Color(0.95, 0.72, 0.18)      # your deeds: gold
			elif b.get("listed", false):
				tint = Color(0.30, 0.78, 0.38)      # the for-sale tape: green
			else:
				tint = Color(0.40, 0.40, 0.42)      # everything else recedes
		elif overlay == "listings":
			if b.get("listed", false):
				tint = Color(0.30, 0.78, 0.38)
			elif b.get("held", false):
				tint = Color(0.95, 0.72, 0.18)
			else:
				tint = Color(0.42, 0.42, 0.44)
		tint.a = clampf(float(b["z1"]) / 400.0, 0.02, 1.0)
		_uv2 = Vector2(rng.randf_range(0.001, 1.0), rng.randf_range(0.0, 37.0))
		# Curtain wall: a tall office building of the glass era. Class and
		# year are the engine's; the glazing is ours.
		var glassy := (cls == "office" or cls == "mix") and year >= 1958 \
				and float(b["z1"]) > 40.0 and overlay == ""
		# Roof tone from the engine's tone index, weighted dark — a city of
		# white lids was the single loudest thing in the first street-level
		# frame. Crown volumes (the engine's pitched/parapet roof caps,
		# x:1) are ROOF, not facade: they were wearing wall tint and
		# reading as pale slabs over every midrise.
		var rtones := [Color(0.13, 0.13, 0.14), Color(0.16, 0.16, 0.17),
				Color(0.20, 0.20, 0.21), Color(0.30, 0.19, 0.15),
				Color(0.17, 0.21, 0.18)]
		var rtone: Color = rtones[(int(b["tone"]) + int(rng.randf() * 2.0)) % rtones.size()] \
				* rng.randf_range(0.85, 1.15)
		# x:1 marks the topmost volume of a building — for most buildings
		# that IS the windowed body (first render treating every x:1 as a
		# roof turned half the city into toneless grey prisms). Only a
		# THIN cap sitting on a body below it is roof furniture.
		if b["crown"] and h < 5.0 and z0 > 3.0:
			roof.set_color(rtone)
			_ring_walls(roof, ring, z0, h)
			_ring_cap(roof, ring, z0 + h, rtone)
			continue
		var sti: SurfaceTool = tw if glassy else \
				(st if era_name == "victorian" else (st_b if era_name == "prewar" else st_c))
		sti.set_color(Color(1, 1, 1) if glassy else tint)
		_ring_walls(sti, ring, z0, h)
		roof.set_color(rtone)
		_ring_cap(roof, ring, z0 + h, rtone)
		# Roof furniture only on near-rectangular main volumes: parapet
		# boxes follow the bounding box, and on an L-plan they would float.
		if not b["crown"] and z0 < 0.5:
			var bb := _ring_bbox(ring)
			var bba: float = bb.size.x * bb.size.y
			if bba > 30.0 and absf(CityImport._shoelace(ring)) / bba > 0.72:
				_roofscape(roof, rng, [bb.position.x, bb.position.y,
						bb.size.x, bb.size.y, z0 + h], xf)
				# Masonry eras carry a projecting cornice — the shadow line
				# that caps a pre-war street wall (probability by era).
				if not glassy and era_name != "midcentury" \
						and rng.randf() < float(ERAS[era_name]["cornice_p"]):
					_cornice(roof, xf, bb.position.x, bb.position.y,
							bb.size.x, bb.size.y, z0 + h, tint)
	var mi := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = hash("%d/impmat/%d" % [ci.seed_value,
			int(indices[0]) if not indices.is_empty() else 0])
	if p_any.is_empty():
		p_any = {"bay": 1.5, "win_fx": 0.55, "lit": 0.25, "shop_lit": 0.5}
	var mats: Array = []
	for entry in [[st, "victorian", true], [roof, null, false],
			[st_b, "prewar", true], [st_c, "midcentury", true], [tw, "tower", true]]:
		var stool: SurfaceTool = entry[0]
		var arr: Array = stool.commit_to_arrays()
		var verts = arr[Mesh.ARRAY_VERTEX]
		if not (verts is PackedVector3Array) or (verts as PackedVector3Array).is_empty():
			continue
		stool.generate_normals()
		if entry[2]:
			stool.generate_tangents()
		stool.commit(mesh)
		if entry[1] == null:
			mats.append(_roof_material())
		elif entry[1] == "tower":
			var tm := _tower_material(rng2)
			if lit_occ >= 0.0:
				tm.set_shader_parameter("lit_fraction", lit_occ * night)
			mats.append(tm)
		else:
			var em := _facade_material(rng2, p_any)
			_apply_era(em, ERAS[entry[1]], rng2)
			# STAGE 4 (docs/ECONOMY-ADAPTER.md): dusk windows follow the
			# SIMULATED occupancy of this chunk's bucket, not a district
			# constant — a vacant building goes dark because it is vacant.
			if lit_occ >= 0.0:
				em.set_shader_parameter("lit_fraction", lit_occ * night)
			if overlay != "":
				# An overlay is a MAP: flat color reads, brick texture
				# muting the gold does not (seen in the first overlay
				# frame — the held parcel came out faint amber).
				em.set_shader_parameter("use_wall_texture", 0.0)
			mats.append(em)
	mi.mesh = mesh
	for i in range(mats.size()):
		mi.set_surface_override_material(i, mats[i])
	return mi

## Walls along an arbitrary CCW footprint, through the same _wall emitter
## the planned city uses — meter UVs, UV2 identity, vertex tint.
static func _ring_walls(st: SurfaceTool, ring: PackedVector2Array,
		z0: float, h: float) -> void:
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		_wall(st, Transform3D.IDENTITY, Vector3(b.x, z0, b.y), Vector3(a.x, z0, a.y), h)

## Triangulated cap (concave-safe), both windings so orientation quirks in
## source rings can never delete a roof.
static func _ring_cap(st: SurfaceTool, ring: PackedVector2Array, y: float,
		tint: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(ring)
	if idx.is_empty():
		return
	st.set_color(tint)
	for t in range(0, idx.size(), 3):
		for j in [t + 2, t + 1, t, t, t + 1, t + 2]:
			var p := ring[idx[j]]
			st.set_uv(Vector2(p.x, p.y))
			st.set_uv2(_uv2)
			st.add_vertex(Vector3(p.x, y, p.y))

static func _ring_bbox(ring: PackedVector2Array) -> Rect2:
	var r := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		r = r.expand(p)
	return r

# --- shared -----------------------------------------------------------------

static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	return st

## Masses for one block, in the block's LOCAL frame (origin at block center):
## [x, z, w, d, h]. District params set footprint and height character; the
## core-distance falloff shapes the skyline.
static func _masses(rng: RandomNumberGenerator, b: Dictionary, plan: CityPlan) -> Array:
	var out := []
	var p := plan.params_for(b)
	var bw: float = b["w"]
	var bd: float = b["d"]
	var x := -bw * 0.5
	var x1 := bw * 0.5
	var falloff: float = plan.falloff(b) * p["height_mul"]
	var wmin: float = p["mass_w"][0]
	var wmax: float = p["mass_w"][1]
	# ROWHOUSE blocks: ~40% of residential fabric is parceled at the real
	# NYC tenement grain — narrow 7-13 m lots shoulder to shoulder, sawtooth
	# heights around a shared base. The wide-slab-only fabric was the
	# biggest sameness in every close screenshot.
	var dist_name: String = b["district"]
	var rowhouse: bool = (dist_name == "prewar" or dist_name == "walkup") \
			and rng.randf() < 0.4
	if rowhouse:
		var base_h := rng.randf_range(12.0, 26.0) * maxf(falloff, 0.55)
		while x < x1 - 5.0:
			var w := rng.randf_range(7.0, 13.0)
			w = minf(w, x1 - x)
			var h := clampf(base_h * rng.randf_range(0.72, 1.32), 7.0, p["cap"])
			var d := rng.randf_range(minf(14.0, bd - 8.0), minf(24.0, bd - 4.0))
			out.append([x + 0.25, bd * 0.5 - d - 2.0, w - 0.5, d, h])
			x += w
			if rng.randf() < plan.gap_p * 0.5:
				x += rng.randf_range(4.0, 9.0)
		return out
	while x < x1 - 8.0:
		var w := rng.randf_range(wmin, wmax)
		w = minf(w, x1 - x)
		var h: float
		var r := rng.randf()
		if r < 0.55:
			h = rng.randf_range(18.0, 40.0) * falloff
		elif r < 0.85:
			h = rng.randf_range(40.0, 75.0) * falloff
		elif r < 0.97:
			h = rng.randf_range(75.0, 150.0) * falloff
		else:
			# Outlier tower. Contemporary skylines carry 200 m+ peaks.
			h = rng.randf_range(90.0, 230.0) * maxf(falloff, 0.7)
		# Wider per-mass jitter: neighbors in the same band still differ.
		h = clampf(h * rng.randf_range(0.78, 1.28), 7.0, p["cap"])
		var d := rng.randf_range(minf(40.0, bd - 6.0), bd - 2.0)
		var mw := w - rng.randf_range(0.5, 3.0)
		out.append([x + (w - mw) * 0.5, -d * 0.5, mw, d, h])
		x += w
		# Vacant slices: some cities are gap-toothed, some solid street wall.
		if rng.randf() < plan.gap_p:
			x += rng.randf_range(6.0, 18.0)
	return out

static func _emit_mass(st: SurfaceTool, m: Array, tint: Color, xf: Transform3D) -> void:
	var ax: float = m[0]
	var az: float = m[1]
	var w: float = m[2]
	var d: float = m[3]
	var h: float = m[4]
	st.set_color(tint)
	_wall(st, xf, Vector3(ax + w, 0, az), Vector3(ax, 0, az), h)
	_wall(st, xf, Vector3(ax, 0, az + d), Vector3(ax + w, 0, az + d), h)
	_wall(st, xf, Vector3(ax + w, 0, az + d), Vector3(ax + w, 0, az), h)
	_wall(st, xf, Vector3(ax, 0, az), Vector3(ax, 0, az + d), h)
	_top(st, xf, ax, az, w, d, h)

# --- tiers ------------------------------------------------------------------

## Roof furniture for one mass: a parapet lip around the edge plus a seeded
## handful of bulkheads and mech units. The camera contract says the closest
## band still looks DOWN, so roofs are as visible as facades — and a bare
## flat plane is the loudest thing in an aerial frame.
static func _roofscape(st: SurfaceTool, rng: RandomNumberGenerator, m: Array,
		xf: Transform3D) -> void:
	var ax: float = m[0]
	var az: float = m[1]
	var w: float = m[2]
	var d: float = m[3]
	var h: float = m[4]
	# Parapet tone varies per building: concrete, painted, dark metal cap.
	st.set_color(Color(0.30, 0.30, 0.31) * rng.randf_range(0.55, 1.3))
	# Parapet: the roof edge of a real building stands ~1 m proud, which is
	# what casts the thin shadow line that reads as "roof" from above.
	var lip := 0.55
	var ph := rng.randf_range(0.7, 1.15)
	_box(st, xf, ax, az, w, lip, h, ph)
	_box(st, xf, ax, az + d - lip, w, lip, h, ph)
	_box(st, xf, ax, az + lip, lip, d - lip * 2.0, h, ph)
	_box(st, xf, ax + w - lip, az + lip, lip, d - lip * 2.0, h, ph)
	# Bulkhead (stair/lift overrun) and mech units. Count rises with roof
	# area: a 12 m infill roof gets one box, a full block gets several.
	var n := clampi(int(w * d / 260.0), 1, 5)
	for k in range(n):
		var bw := rng.randf_range(2.5, minf(7.0, w * 0.45))
		var bd := rng.randf_range(2.5, minf(6.0, d * 0.45))
		var bh := rng.randf_range(1.2, 3.6) if k > 0 else rng.randf_range(2.8, 4.6)
		_box(st, xf, ax + rng.randf_range(1.5, maxf(1.6, w - bw - 1.5)),
				az + rng.randf_range(1.5, maxf(1.6, d - bd - 1.5)), bw, bd, h, bh)

static func _box(st: SurfaceTool, xf: Transform3D, x: float, z: float,
		w: float, d: float, y: float, h: float) -> void:
	_wall(st, xf, Vector3(x + w, y, z), Vector3(x, y, z), h)
	_wall(st, xf, Vector3(x, y, z + d), Vector3(x + w, y, z + d), h)
	_wall(st, xf, Vector3(x + w, y, z + d), Vector3(x + w, y, z), h)
	_wall(st, xf, Vector3(x, y, z), Vector3(x, y, z + d), h)
	_top(st, xf, x, z, w, d, y + h)

## Arbitrary-plan prism: CCW footprint points, walls + centroid-fan top.
## This is what frees buildings from the rectangle.
static func _prism(st: SurfaceTool, xf: Transform3D, pts: Array, y0: float, h: float) -> void:
	var n := pts.size()
	var cx := 0.0
	var cz := 0.0
	for q in pts:
		cx += (q as Vector2).x
		cz += (q as Vector2).y
	var c := Vector2(cx / float(n), cz / float(n))
	for i in range(n):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		_wall(st, xf, Vector3(b.x, y0, b.y), Vector3(a.x, y0, a.y), h)
	for i in range(n):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		for q in [Vector3(c.x, y0 + h, c.y), Vector3(a.x, y0 + h, a.y),
				Vector3(b.x, y0 + h, b.y)]:
			st.set_uv(Vector2(q.x, q.z))
			st.set_uv2(_uv2)
			st.add_vertex(xf * q)

## Chamfered rectangle: the four corners cut at 45 deg — the classic prewar
## corner treatment, and an octagonal silhouette against the sky.
static func _chamfer_pts(x: float, z: float, w: float, d: float, c: float) -> Array:
	return [Vector2(x + c, z), Vector2(x + w - c, z), Vector2(x + w, z + c),
			Vector2(x + w, z + d - c), Vector2(x + w - c, z + d),
			Vector2(x + c, z + d), Vector2(x, z + d - c), Vector2(x, z + c)]

## Projecting cornice: a band standing proud of the facade at the top —
## the shadow line that caps a masonry building.
static func _cornice(roof: SurfaceTool, xf: Transform3D, x: float, z: float,
		w: float, d: float, h: float, tint: Color) -> void:
	roof.set_color(tint * 0.8)
	_box(roof, xf, x - 0.35, z - 0.35, w + 0.7, d + 0.7, h - 1.0, 1.0)

## One building from one mass. Real massing, not extruded boxes:
##   - tall masses in tower districts become PODIUM + GLASS TOWER (the
##     shaft goes to its own curtain-wall surface),
##   - mid-rise masses over ~55 m step back in 2-3 tiers,
##   - low masses stay simple.
static func _emit_building(st: SurfaceTool, tw: SurfaceTool, roof: SurfaceTool,
		rng: RandomNumberGenerator, m: Array, tint: Color, xf: Transform3D,
		tower_p: float, era: Dictionary = {}) -> void:
	# The style hash IS the building's identity in the shader.
	_uv2 = Vector2(rng.randf_range(0.001, 1.0), rng.randf_range(0.0, 37.0))
	# Building height rides COLOR.a (as h/400) so the shader can compose
	# base / shaft / crown against the real top of THIS building.
	tint.a = clampf(float(m[4]) / 400.0, 0.02, 1.0)
	var ax: float = m[0]
	var az: float = m[1]
	var w: float = m[2]
	var d: float = m[3]
	var h: float = m[4]
	if h > 75.0 and w > 18.0 and d > 18.0 and rng.randf() < tower_p:
		# Podium (street-wall masonry) + curtain shaft(s) + mech cap.
		var ph := rng.randf_range(8.0, 18.0)
		_emit_mass(st, [ax, az, w, d, ph], tint, xf)
		_roofscape(roof, rng, [ax, az, w, d, ph], xf)
		var inx := rng.randf_range(2.0, minf(5.0, w * 0.2))
		var inz := rng.randf_range(2.0, minf(5.0, d * 0.2))
		st.set_color(tint)  # tower tint rides vertex color too
		tw.set_color(Color(1, 1, 1))
		if w > 34.0 and rng.randf() < 0.3:
			# TWIN shafts on one podium — a paired-slab skyline moment.
			var sw := (w - inx * 3.0) * 0.5
			_box(tw, xf, ax + inx, az + inz, sw, d - inz * 2.0, ph, h - ph)
			_box(tw, xf, ax + inx * 2.0 + sw, az + inz, sw, d - inz * 2.0, ph,
					(h - ph) * rng.randf_range(0.75, 1.0))
		else:
			# The shaft sits ASYMMETRICALLY on the podium — centered shafts
			# were another every-tower-alike tell.
			var tw_w := w - inx * 2.0
			var tw_d := d - inz * 2.0
			var sx := ax + rng.randf_range(0.6, maxf(0.7, w - tw_w - 0.6))
			var sz := az + rng.randf_range(0.6, maxf(0.7, d - tw_d - 0.6))
			_box(tw, xf, sx, sz, tw_w, tw_d, ph, h - ph)
			ax = sx  # spire cap follows the shaft
			az = sz
			w = tw_w
			d = tw_d
			if rng.randf() < 0.35:
				# Spire cap: a slender crown on the shaft.
				var cw := (w - inx * 2.0) * rng.randf_range(0.2, 0.35)
				_box(tw, xf, ax + w * 0.5 - cw * 0.5, az + d * 0.5 - cw * 0.5,
						cw, cw, h, rng.randf_range(6.0, 22.0))
		var mw := (w - inx * 2.0) * rng.randf_range(0.3, 0.5)
		var md := (d - inz * 2.0) * rng.randf_range(0.3, 0.5)
		roof.set_color(Color(0.30, 0.30, 0.31))
		_box(roof, xf, ax + w * 0.5 - mw * 0.5, az + d * 0.5 - md * 0.5,
				mw, md, h, rng.randf_range(2.5, 5.0))
	elif h > 150.0 and w > 26.0 and d > 26.0 and rng.randf() < 0.4:
		# CROSS-PLAN supertall: two crossing bars and a central crown —
		# the Empire State profile, unmistakable on a skyline.
		st.set_color(tint)
		var bh := h * rng.randf_range(0.6, 0.72)
		_box(st, xf, ax, az + d * 0.3, w, d * 0.4, 0.0, bh)
		_box(st, xf, ax + w * 0.3, az, w * 0.4, d, 0.0, bh)
		var m3 := [ax + w * 0.32, az + d * 0.32, w * 0.36, d * 0.36, h]
		_emit_mass(st, m3, tint * 1.02, xf)
		_roofscape(roof, rng, m3, xf)
		_cornice(roof, xf, ax, az + d * 0.3, w, d * 0.4, bh, tint)
	elif h > 110.0:
		# Ziggurat: three masonry tiers — the deco wedding-cake profile.
		# 40% get chamfered corners: an octagonal crown against the sky.
		var t1 := h * rng.randf_range(0.4, 0.5)
		var t2 := h * rng.randf_range(0.68, 0.8)
		var i1 := rng.randf_range(2.0, minf(5.0, w * 0.14))
		var cham := rng.randf() < 0.4
		var cc := rng.randf_range(2.0, minf(4.5, w * 0.12))
		st.set_color(tint)
		if cham:
			_prism(st, xf, _chamfer_pts(ax, az, w, d, cc), 0.0, t1)
		else:
			_emit_mass(st, [ax, az, w, d, t1], tint, xf)
		_roofscape(roof, rng, [ax, az, w, d, t1], xf)
		if w - i1 * 2.0 > 6.0:
			st.set_color(tint * rng.randf_range(0.97, 1.03))
			if cham:
				_prism(st, xf, _chamfer_pts(ax + i1, az + i1 * 0.5,
						w - i1 * 2.0, d - i1, cc), 0.0, t2)
			else:
				_emit_mass(st, [ax + i1, az + i1 * 0.5, w - i1 * 2.0, d - i1, t2],
						tint * rng.randf_range(0.97, 1.03), xf)
			var i2 := i1 * 2.0
			if w - i2 * 2.0 > 5.0:
				var m3 := [ax + i2, az + i2 * 0.5, w - i2 * 2.0, d - i2, h]
				_emit_mass(st, m3, tint * rng.randf_range(0.97, 1.03), xf)
				_roofscape(roof, rng, m3, xf)
		_cornice(roof, xf, ax, az, w, d, t1, tint)
	elif h > 55.0:
		# Setback tiers: 55-70% / rest, each stepping in on every side.
		var h1 := h * rng.randf_range(0.55, 0.7)
		var i1 := rng.randf_range(1.5, minf(4.0, w * 0.15))
		_emit_mass(st, [ax, az, w, d, h1], tint, xf)
		_roofscape(roof, rng, [ax, az, w, d, h1], xf)
		var w2 := w - i1 * 2.0
		var d2 := d - i1 * 2.0
		if w2 > 6.0 and d2 > 6.0:
			var m2 := [ax + i1, az + i1, w2, d2, h]
			_emit_mass(st, m2, tint * rng.randf_range(0.96, 1.04), xf)
			_roofscape(roof, rng, m2, xf)
	elif h < 42.0 and w > 26.0 and d > 30.0 and rng.randf() < 0.4:
		# Courtyard pair: street-wall bar + rear wing, a dark court between.
		var fd := d * rng.randf_range(0.35, 0.45)
		var m1 := [ax, az + d - fd, w, fd, h]
		_emit_mass(st, m1, tint, xf)
		_roofscape(roof, rng, m1, xf)
		_cornice(roof, xf, ax, az + d - fd, w, fd, h, tint)
		var bw := w * rng.randf_range(0.4, 0.7)
		var m2 := [ax + rng.randf_range(0.0, w - bw), az, bw, d * 0.35,
				h * rng.randf_range(0.7, 1.0)]
		_emit_mass(st, m2, tint * rng.randf_range(0.94, 1.02), xf)
		_roofscape(roof, rng, m2, xf)
	elif h < 55.0 and w > 20.0 and d > 26.0 and rng.randf() < 0.3:
		# L-PLAN: street bar plus a perpendicular wing — the notch reads at
		# every band and breaks the rectangle monotony on corners.
		var fd := d * rng.randf_range(0.5, 0.6)
		var m1 := [ax, az, w, fd, h]
		_emit_mass(st, m1, tint, xf)
		_roofscape(roof, rng, m1, xf)
		var ww := w * rng.randf_range(0.35, 0.5)
		var wing := [ax if rng.randf() < 0.5 else ax + w - ww, az + fd,
				ww, d - fd, h * rng.randf_range(0.8, 1.05)]
		_emit_mass(wing_st(st), wing, tint * rng.randf_range(0.96, 1.02), xf)
		_roofscape(roof, rng, wing, xf)
	else:
		_emit_mass(st, m, tint, xf)
		_roofscape(roof, rng, m, xf)
		var cornice_p: float = float(era.get("cornice_p", 0.45))
		if h > 12.0 and h < 90.0 and rng.randf() < cornice_p:
			_cornice(roof, xf, ax, az, w, d, h, tint)
		if rng.randf() < float(era.get("mansard_p", 0.0)) and w > 8.0:
			# Mansard cap: the steep slate top of the victorian rowhouse.
			roof.set_color(Color(0.12, 0.12, 0.135))
			_taper(roof, xf, ax + 0.2, az + 0.2, w - 0.4, d - 0.4, h,
					rng.randf_range(2.2, 3.2), minf(1.3, w * 0.12), 1.3)
		elif rng.randf() < float(era.get("wt_p", 0.0)) and w > 12.0 and h > 18.0:
			_water_tower(roof, rng, ax, az, w, d, h, xf)

## Rooftop water tower, merged-octagon edition: the NYC roofline's
## signature. Dark timber drum on a short plinth with a shallow cap.
static func _water_tower(roof: SurfaceTool, rng: RandomNumberGenerator,
		ax: float, az: float, w: float, d: float, h: float, xf: Transform3D) -> void:
	var r := rng.randf_range(1.3, 1.9)
	var cx := ax + rng.randf_range(r + 1.0, maxf(r + 1.1, w - r - 1.0))
	var cz := az + rng.randf_range(r + 1.0, maxf(r + 1.1, d - r - 1.0))
	var pts := []
	for k in range(8):
		var a := TAU * float(k) / 8.0
		pts.append(Vector2(cx + cos(a) * r, cz + sin(a) * r))
	roof.set_color(Color(0.30, 0.30, 0.31))
	_box(roof, xf, cx - 0.8, cz - 0.8, 1.6, 1.6, h, 1.6)   # plinth / legs mass
	roof.set_color(Color(0.17, 0.12, 0.08))                 # tarred cedar
	_prism(roof, xf, pts, h + 1.6, rng.randf_range(3.0, 4.2))
	roof.set_color(Color(0.10, 0.10, 0.10))
	_taper(roof, xf, cx - r, cz - r, r * 2.0, r * 2.0, h + 1.6 + 3.6,
			1.1, r * 0.85, r * 0.85)

## Four inward-sloping quads and a cap: mansards, spires, tower caps.
static func _taper(st: SurfaceTool, xf: Transform3D, x: float, z: float,
		w: float, d: float, y0: float, h: float, ix: float, iz: float) -> void:
	var b := [Vector2(x, z), Vector2(x + w, z), Vector2(x + w, z + d), Vector2(x, z + d)]
	var t := [Vector2(x + ix, z + iz), Vector2(x + w - ix, z + iz),
			Vector2(x + w - ix, z + d - iz), Vector2(x + ix, z + d - iz)]
	for i in range(4):
		var bl: Vector2 = b[(i + 1) % 4]
		var br: Vector2 = b[i]
		var tl: Vector2 = t[(i + 1) % 4]
		var tr: Vector2 = t[i]
		for q in [[Vector3(tl.x, y0 + h, tl.y), Vector2(0, h)],
				[Vector3(tr.x, y0 + h, tr.y), Vector2(1, h)],
				[Vector3(br.x, y0, br.y), Vector2(1, 0)],
				[Vector3(tl.x, y0 + h, tl.y), Vector2(0, h)],
				[Vector3(br.x, y0, br.y), Vector2(1, 0)],
				[Vector3(bl.x, y0, bl.y), Vector2(0, 0)]]:
			st.set_uv(q[1] as Vector2)
			st.set_uv2(_uv2)
			st.add_vertex(xf * (q[0] as Vector3))
	_top(st, xf, x + ix, z + iz, w - ix * 2.0, d - iz * 2.0, y0 + h)

## The wing joins the same surface; helper exists so the call site reads.
static func wing_st(st: SurfaceTool) -> SurfaceTool:
	return st

const AWNING_COLORS := [Color(0.35, 0.12, 0.10), Color(0.10, 0.22, 0.14),
		Color(0.12, 0.16, 0.28), Color(0.35, 0.28, 0.16), Color(0.28, 0.28, 0.28)]

## Storefront awnings along a mass's street face: shallow sloped boxes at
## transom height in seeded shop-front colors. Near rings only — this is
## street-level texture, invisible past the mid band.
static func _awnings(roof: SurfaceTool, rng: RandomNumberGenerator, m: Array,
		bd: float, xf: Transform3D) -> void:
	var ax: float = m[0]
	var az: float = m[1]
	var w: float = m[2]
	var d: float = m[3]
	# Which long face touches a street? The one nearest the block edge.
	var front_z: float
	if absf(az + d - bd * 0.5) < 8.0:
		front_z = az + d + 0.02
	elif absf(az + bd * 0.5) < 8.0:
		front_z = az - 1.22
	else:
		return
	var x := ax + rng.randf_range(0.5, 2.5)
	while x < ax + w - 3.0:
		var aw := rng.randf_range(2.2, 4.0)
		if rng.randf() < 0.55:
			roof.set_color(AWNING_COLORS[rng.randi_range(0, AWNING_COLORS.size() - 1)]
					* rng.randf_range(0.8, 1.2))
			_box(roof, xf, x, front_z, minf(aw, ax + w - x - 0.5), 1.2, 3.1, 0.22)
		x += aw + rng.randf_range(0.6, 2.2)

static func _block_windowed(rng: RandomNumberGenerator, b: Dictionary,
		xf: Transform3D, plan: CityPlan) -> MeshInstance3D:
	var st := _st()
	var st_b := _st()   # extra facade surfaces: independent materials
	var st_c := _st()
	var p := plan.params_for(b)
	var tints: Array = p["tints"]
	var near_hero: bool = float(b["dist"]) < 300.0
	var roof := _st()
	var tw := _st()   # glass tower shafts: curtain-wall surface
	var tower_p: float = p.get("tower_p", 0.0)
	for m in _masses(rng, b, plan):
		# Blocks just south of the hero sit between it and the sun-derived
		# camera: keep them low so background never blocks subject.
		if near_hero and float(b["z"]) > 31.0 and m[4] > 30.0:
			m[4] = rng.randf_range(18.0, 30.0)
		# ERA per building: the city's era bias (old port vs young metro)
		# shifts the mix; district nudges it (walkups skew old, core new).
		var roll: float = rng.randf() + plan.era_bias * 0.5 \
				+ (0.25 if b["district"] == "core" else 0.0)
		var era_name := "victorian" if roll < 0.4 else ("prewar" if roll < 0.95 else "midcentury")
		if roll >= 1.15:
			era_name = "midcentury"
		var era: Dictionary = ERAS[era_name]
		var sti: SurfaceTool = st if era_name == "victorian" \
				else (st_b if era_name == "prewar" else st_c)
		_emit_building(sti, tw, roof, rng, m,
				tints[rng.randi_range(0, tints.size() - 1)], xf, tower_p, era)
		if float(b["dist"]) < 500.0:
			_awnings(roof, rng, m, float(b["d"]), xf)
	# Commit only NON-EMPTY surfaces, and assign each material by the
	# index its surface actually landed at. The old fixed-index scheme
	# committed empty surface 0 when every mass rolled onto st_b/st_c
	# ("UVs are required" spam) and then mis-assigned every material
	# after it — blocks silently wore the wrong skins.
	var mi := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = FACADE_SHADER
	if _wall_tex.has("albedo"):
		mat.set_shader_parameter("wall_albedo", _wall_tex["albedo"])
		mat.set_shader_parameter("wall_normal", _wall_tex["normal"])
		mat.set_shader_parameter("wall_ao", _wall_tex["ao"])
		mat.set_shader_parameter("use_wall_texture", 1.0)
	else:
		mat.set_shader_parameter("use_wall_texture", 0.0)
	mat.set_shader_parameter("wall_tint", Color.WHITE)  # tint rides vertex COLOR
	mat.set_shader_parameter("windows_enabled", 1.0)
	_apply_era(mat, ERAS["victorian"], rng)
	mat.set_shader_parameter("wall_roughness", 0.85)
	mat.set_shader_parameter("lit_fraction", float(p["lit"]) * night)
	mat.set_shader_parameter("shop_lit_fraction", float(p["shop_lit"]) * night)
	mat.set_shader_parameter("win_seed", rng.randf() * 100.0)
	var mats: Array = []
	for entry in [[st, mat, true], [roof, _roof_material(), false],
			[st_b, "prewar", true], [st_c, "midcentury", true], [tw, null, true]]:
		var stool: SurfaceTool = entry[0]
		var arr: Array = stool.commit_to_arrays()
		var verts = arr[Mesh.ARRAY_VERTEX]
		if not (verts is PackedVector3Array) or (verts as PackedVector3Array).is_empty():
			continue
		stool.generate_normals()
		if entry[2]:
			stool.generate_tangents()
		stool.commit(mesh)
		if entry[1] is String:
			var em := _facade_material(rng, p)
			_apply_era(em, ERAS[entry[1]], rng)
			mats.append(em)
		elif entry[1] != null:
			mats.append(entry[1])
		else:
			mats.append(_tower_material(rng))
	mi.mesh = mesh
	for i in range(mats.size()):
		mi.set_surface_override_material(i, mats[i])
	return mi

## Push an era's architecture into a material: floor heights, bay rhythm,
## window shape, base composition.
static func _apply_era(mat: ShaderMaterial, era: Dictionary, rng: RandomNumberGenerator) -> void:
	mat.set_shader_parameter("floor_height", float(era["floor_h"]) * rng.randf_range(0.96, 1.05))
	mat.set_shader_parameter("ground_floor_height", float(era["gfh"]))
	mat.set_shader_parameter("bay_width", float(era["bay"]) * rng.randf_range(0.9, 1.12))
	mat.set_shader_parameter("window_frac_x", float(era["wfx"]) * rng.randf_range(0.92, 1.1))
	mat.set_shader_parameter("window_frac_y", float(era["wfy"]))
	mat.set_shader_parameter("base_floors", float(era["base_floors"]))
	mat.set_shader_parameter("base_tint", era["base_tint"])
	mat.set_shader_parameter("base_stone", float(era["base_stone"]))

## An independent facade material: its own wall set (when the library has
## more than one), floor height, bay rhythm and window proportions.
static func _facade_material(rng: RandomNumberGenerator, p: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FACADE_SHADER
	var keys: Array = _matlib.keys()
	var tex: Dictionary = {}
	if not keys.is_empty():
		tex = _matlib[keys[rng.randi_range(0, keys.size() - 1)]]
	if tex.has("albedo"):
		mat.set_shader_parameter("wall_albedo", tex["albedo"])
		mat.set_shader_parameter("wall_normal", tex["normal"])
		mat.set_shader_parameter("wall_ao", tex["ao"])
		mat.set_shader_parameter("use_wall_texture", 1.0)
		if tex.has("roughness"):
			mat.set_shader_parameter("wall_roughness_tex", tex["roughness"])
			mat.set_shader_parameter("use_roughness_texture", 1.0)
	else:
		mat.set_shader_parameter("use_wall_texture", 0.0)
	mat.set_shader_parameter("wall_tint", Color.WHITE)
	mat.set_shader_parameter("windows_enabled", 1.0)
	mat.set_shader_parameter("floor_height", rng.randf_range(3.1, 3.9))
	mat.set_shader_parameter("ground_floor_height", rng.randf_range(3.9, 5.2))
	mat.set_shader_parameter("bay_width", float(p["bay"]) * rng.randf_range(0.8, 1.25))
	mat.set_shader_parameter("window_frac_x", float(p["win_fx"]) * rng.randf_range(0.85, 1.15))
	mat.set_shader_parameter("window_frac_y", rng.randf_range(0.42, 0.58))
	mat.set_shader_parameter("wall_roughness", 0.85)
	mat.set_shader_parameter("lit_fraction", float(p["lit"]) * night)
	mat.set_shader_parameter("shop_lit_fraction", float(p["shop_lit"]) * night)
	mat.set_shader_parameter("win_seed", rng.randf() * 100.0)
	return mat

## Curtain-wall material for context glass towers: near-full glazing on the
## meter-grid shader, mullion-dark walls, floor-tall panes.
static func _tower_material(rng: RandomNumberGenerator) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FACADE_SHADER
	m.set_shader_parameter("use_wall_texture", 0.0)
	m.set_shader_parameter("wall_tint", Color(0.16, 0.17, 0.19))
	m.set_shader_parameter("windows_enabled", 1.0)
	m.set_shader_parameter("floor_height", 3.6)
	m.set_shader_parameter("ground_floor_height", 3.6)
	m.set_shader_parameter("bay_width", rng.randf_range(1.4, 2.2))
	m.set_shader_parameter("window_frac_x", 0.86)
	m.set_shader_parameter("window_frac_y", 0.82)
	m.set_shader_parameter("wall_roughness", 0.45)
	m.set_shader_parameter("wall_metallic", 0.25)
	m.set_shader_parameter("glass_color", [Color(0.10, 0.14, 0.16),
			Color(0.13, 0.16, 0.14), Color(0.09, 0.12, 0.18),
			Color(0.16, 0.17, 0.18)][rng.randi_range(0, 3)])
	m.set_shader_parameter("glass_roughness", 0.06)
	m.set_shader_parameter("glass_metallic", 0.7)
	m.set_shader_parameter("lit_fraction", 0.30 * night)
	m.set_shader_parameter("shop_lit_fraction", 0.30 * night)
	m.set_shader_parameter("win_seed", rng.randf() * 100.0)
	return m

static var _roof_mat: StandardMaterial3D

## Built-up roofing and painted metal plant: near-black, matte. Vertex color
## carries the slight per-piece variation.
static func _roof_material() -> StandardMaterial3D:
	if _roof_mat == null:
		_roof_mat = StandardMaterial3D.new()
		_roof_mat.vertex_color_use_as_albedo = true
		_roof_mat.albedo_color = Color(0.34, 0.335, 0.33)
		_roof_mat.roughness = 0.95
	return _roof_mat

static func _block_far(st: SurfaceTool, rng: RandomNumberGenerator, b: Dictionary,
		xf: Transform3D, plan: CityPlan) -> void:
	var p := plan.params_for(b)
	var tints: Array = p["tints"]
	# Lit fraction rides COLOR.a: the merged far instance spans districts,
	# and each block still glows (or does not) by its own district's rules.
	var lit: float = float(p["lit"]) * night * 0.9
	for m in _masses(rng, b, plan):
		var t: Color = (tints[rng.randi_range(0, tints.size() - 1)] as Color) * 0.9
		t.a = lit
		_emit_mass(st, m, t, xf)
		# Roof clutter, far edition: 1-2 bulkhead boxes on any big roof.
		# Near-tier roofs got furniture long ago; bare far planes were the
		# loudest remaining flatness at altitude.
		if m[2] * m[3] > 260.0:
			for k in range(rng.randi_range(1, 2)):
				var bw: float = rng.randf_range(3.0, 8.0)
				var bd: float = rng.randf_range(3.0, 7.0)
				st.set_color(Color(0.10, 0.10, 0.10, 0.0))
				_box(st, xf, m[0] + rng.randf_range(1.0, maxf(1.1, m[2] - bw - 1.0)),
						m[1] + rng.randf_range(1.0, maxf(1.1, m[3] - bd - 1.0)),
						bw, bd, m[4], rng.randf_range(1.5, 4.0))

static var _far_mat: ShaderMaterial

const FAR_SHADER := preload("res://src/city/far.gdshader")

static func _flush_far(st: SurfaceTool) -> MeshInstance3D:
	if _far_mat == null:
		_far_mat = ShaderMaterial.new()
		_far_mat.shader = FAR_SHADER
		_far_mat.set_shader_parameter("base_mul", Vector3(0.5, 0.48, 0.46))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _far_mat
	return mi

# --- geometry ---------------------------------------------------------------

static func _wall(st: SurfaceTool, xf: Transform3D, bl: Vector3, br: Vector3, h: float) -> void:
	var w := (br - bl).length()
	var u := Vector3.UP * h
	for pair in [[bl + u, Vector2(0, h)], [br + u, Vector2(w, h)], [br, Vector2(w, 0)],
			[bl + u, Vector2(0, h)], [br, Vector2(w, 0)], [bl, Vector2(0, 0)]]:
		st.set_uv(pair[1])
		st.set_uv2(_uv2)
		st.add_vertex(xf * (pair[0] as Vector3))

static func _top(st: SurfaceTool, xf: Transform3D, ax: float, az: float, w: float, d: float, h: float) -> void:
	var pts := [Vector3(ax, h, az), Vector3(ax + w, h, az),
			Vector3(ax + w, h, az + d), Vector3(ax, h, az + d)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(Vector2(pts[i].x, pts[i].z))
		st.set_uv2(_uv2)
		st.add_vertex(xf * (pts[i] as Vector3))
