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

const NEAR_R := 850.0   # windowed-tier radius, meters (~old rings 1-4)

static var _wall_tex := {}

static var night := 0.0   # 0 = full day, 1 = full dusk; set by the scene

static func build(seed_value: int, matlib: Dictionary, plan: CityPlan,
		night_factor: float = 0.0) -> Node3D:
	night = night_factor
	_wall_tex = matlib.get("brick_red", {})
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
			h = rng.randf_range(75.0, 130.0) * falloff
		else:
			h = rng.randf_range(80.0, 150.0) * maxf(falloff, 0.7)  # outlier tower
		h = clampf(h, 7.0, p["cap"])
		var d := rng.randf_range(minf(40.0, bd - 6.0), bd - 2.0)
		var mw := w - rng.randf_range(0.5, 3.0)
		out.append([x + (w - mw) * 0.5, -d * 0.5, mw, d, h])
		x += w
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

static func _block_windowed(rng: RandomNumberGenerator, b: Dictionary,
		xf: Transform3D, plan: CityPlan) -> MeshInstance3D:
	var st := _st()
	var p := plan.params_for(b)
	var tints: Array = p["tints"]
	var near_hero: bool = float(b["dist"]) < 300.0
	var roof := _st()
	for m in _masses(rng, b, plan):
		# Blocks just south of the hero sit between it and the sun-derived
		# camera: keep them low so background never blocks subject.
		if near_hero and float(b["z"]) > 31.0 and m[4] > 30.0:
			m[4] = rng.randf_range(18.0, 30.0)
		_emit_mass(st, m, tints[rng.randi_range(0, tints.size() - 1)], xf)
		_roofscape(roof, rng, m, xf)
	st.generate_normals()
	st.generate_tangents()
	roof.generate_normals()
	var mi := MeshInstance3D.new()
	var mesh: ArrayMesh = st.commit()
	roof.commit(mesh)   # surface 1: roof furniture, its own material
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
	return mi

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
		st.add_vertex(xf * (pair[0] as Vector3))

static func _top(st: SurfaceTool, xf: Transform3D, ax: float, az: float, w: float, d: float, h: float) -> void:
	var pts := [Vector3(ax, h, az), Vector3(ax + w, h, az),
			Vector3(ax + w, h, az + d), Vector3(ax, h, az + d)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(Vector2(pts[i].x, pts[i].z))
		st.add_vertex(xf * (pts[i] as Vector3))
