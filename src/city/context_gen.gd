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
		h = clampf(h, 7.0, p["cap"])
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
	st.set_color(Color(0.30, 0.30, 0.31))
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

## One building from one mass. Real massing, not extruded boxes:
##   - tall masses in tower districts become PODIUM + GLASS TOWER (the
##     shaft goes to its own curtain-wall surface),
##   - mid-rise masses over ~55 m step back in 2-3 tiers,
##   - low masses stay simple.
static func _emit_building(st: SurfaceTool, tw: SurfaceTool, roof: SurfaceTool,
		rng: RandomNumberGenerator, m: Array, tint: Color, xf: Transform3D,
		tower_p: float) -> void:
	# The style hash IS the building's identity in the shader.
	_uv2 = Vector2(rng.randf_range(0.001, 1.0), rng.randf_range(0.0, 37.0))
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
			_box(tw, xf, ax + inx, az + inz, w - inx * 2.0, d - inz * 2.0, ph, h - ph)
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
	elif h > 110.0:
		# Ziggurat: three masonry tiers — the deco wedding-cake profile.
		var t1 := h * rng.randf_range(0.4, 0.5)
		var t2 := h * rng.randf_range(0.68, 0.8)
		var i1 := rng.randf_range(2.0, minf(5.0, w * 0.14))
		_emit_mass(st, [ax, az, w, d, t1], tint, xf)
		_roofscape(roof, rng, [ax, az, w, d, t1], xf)
		if w - i1 * 2.0 > 6.0:
			_emit_mass(st, [ax + i1, az + i1 * 0.5, w - i1 * 2.0, d - i1, t2],
					tint * rng.randf_range(0.97, 1.03), xf)
			var i2 := i1 * 2.0
			if w - i2 * 2.0 > 5.0:
				var m3 := [ax + i2, az + i2 * 0.5, w - i2 * 2.0, d - i2, h]
				_emit_mass(st, m3, tint * rng.randf_range(0.97, 1.03), xf)
				_roofscape(roof, rng, m3, xf)
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
		var bw := w * rng.randf_range(0.4, 0.7)
		var m2 := [ax + rng.randf_range(0.0, w - bw), az, bw, d * 0.35,
				h * rng.randf_range(0.7, 1.0)]
		_emit_mass(st, m2, tint * rng.randf_range(0.94, 1.02), xf)
		_roofscape(roof, rng, m2, xf)
	else:
		_emit_mass(st, m, tint, xf)
		_roofscape(roof, rng, m, xf)

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
		# Three facade materials per block (different wall scans where the
		# library has them) x per-building style hashes in the shader.
		var roll := rng.randf()
		_emit_building(st if roll < 0.4 else (st_b if roll < 0.72 else st_c),
				tw, roof, rng, m,
				tints[rng.randi_range(0, tints.size() - 1)], xf, tower_p)
	st.generate_normals()
	st.generate_tangents()
	roof.generate_normals()
	var mi := MeshInstance3D.new()
	var mesh: ArrayMesh = st.commit()
	roof.commit(mesh)   # surface 1: roof furniture, its own material
	var extra_facades := 0
	for sti in [st_b, st_c]:
		var b_arr: Array = (sti as SurfaceTool).commit_to_arrays()
		var b_verts = b_arr[Mesh.ARRAY_VERTEX]
		if b_verts != null and not (b_verts as PackedVector3Array).is_empty():
			sti.generate_normals()
			sti.generate_tangents()
			sti.commit(mesh)
			extra_facades += 1
	# Empty-check BEFORE generate_tangents: tangents on an empty surface
	# throw, and the first version of this lost every towerless block to
	# that throw (whole blocks rendered as bare sidewalk aprons).
	var tower_arr: Array = tw.commit_to_arrays()
	# An empty surface returns NULL at ARRAY_VERTEX, not an empty array —
	# the direct cast threw and silently dropped every towerless block.
	var tower_verts = tower_arr[Mesh.ARRAY_VERTEX]
	var has_towers: bool = tower_verts != null \
			and not (tower_verts as PackedVector3Array).is_empty()
	if has_towers:
		tw.generate_normals()
		tw.generate_tangents()
		tw.commit(mesh)  # surface 2: curtain glass
	mi.mesh = mesh
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
	mat.set_shader_parameter("floor_height", 3.5)
	mat.set_shader_parameter("ground_floor_height", 4.5)
	mat.set_shader_parameter("bay_width", p["bay"] * rng.randf_range(0.92, 1.1))
	mat.set_shader_parameter("window_frac_x", p["win_fx"])
	mat.set_shader_parameter("window_frac_y", 0.5)
	mat.set_shader_parameter("wall_roughness", 0.85)
	# Dusk life: how much of this block is home (or still at a desk) comes
	# from the district; whether a GIVEN window is lit is the shader's hash.
	mat.set_shader_parameter("lit_fraction", float(p["lit"]) * night)
	mat.set_shader_parameter("shop_lit_fraction", float(p["shop_lit"]) * night)
	mat.set_shader_parameter("win_seed", rng.randf() * 100.0)
	mi.set_surface_override_material(0, mat)
	if mesh.get_surface_count() > 1:
		mi.set_surface_override_material(1, _roof_material())
	var next_idx := 2
	for k in range(extra_facades):
		mi.set_surface_override_material(next_idx, _facade_material(rng, p))
		next_idx += 1
	if has_towers:
		mi.set_surface_override_material(next_idx, _tower_material(rng))
	return mi

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
