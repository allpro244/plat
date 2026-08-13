class_name ContextGen
## The rest of the city, tiered by distance from the hero block — the Scale
## phase's answer to "does it run" before per-building detail gets expensive.
##
## Tiers (Chebyshev ring around the hero block):
##   ring 1      NEAR — one merged mesh per block, one windowed-shader surface
##               per mass (per-mass tint via vertex color).
##   rings 2..4  MID  — one merged mesh + ONE windowed material per block;
##               per-mass tint via vertex color.
##   rings 5..R  FAR  — three blocks merged per instance, plain vertex-color
##               material, no window shader. Impostor tier: silhouette and
##               value only, which is all the far band can resolve.
##
## Heights fall off with distance from the core (a downtown gradient), with
## rare outlier towers anywhere — the skyline shape real districts have.
## Same seed, same city.

const FACADE_SHADER := preload("res://src/city/facade.gdshader")

const RINGS := CityPlan.RINGS

static var _wall_tex := {}

static func build(seed_value: int, matlib: Dictionary, plan: CityPlan) -> Node3D:
	_wall_tex = matlib.get("brick_red", {})
	var root := Node3D.new()
	var far_st := _st()   # accumulates FAR tier geometry, flushed in batches
	var far_count := 0
	for gy in range(-RINGS, RINGS + 1):
		for gx in range(-RINGS, RINGS + 1):
			var cell := Vector2i(gx, gy)
			var ring := maxi(absi(gx), absi(gy))
			if ring == 0:
				continue  # the hero block
			if plan.cell_type[cell] != "blocks":
				continue  # parks and water carry no massing
			# Per-block RNG: one block's rules never reshuffle another's.
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("%d/ctx/%d/%d" % [seed_value, gx, gy])
			var x0: float = plan.col_x0[gx]
			var z0: float = plan.row_z0[gy]
			if ring <= 4:
				root.add_child(_block_windowed(rng, x0, z0, cell, plan))
			else:
				_block_far(far_st, rng, x0, z0, cell, plan)
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

## Masses for one block: [x, z, w, d, h]. District params set footprint and
## height character; the core-distance falloff shapes the skyline.
static func _masses(rng: RandomNumberGenerator, x0: float, z0: float,
		cell: Vector2i, plan: CityPlan) -> Array:
	var out := []
	var p := plan.params(cell)
	var x := x0
	var x1 := x0 + CityPlan.BLOCK_W
	var falloff: float = plan.falloff(cell) * p["height_mul"]
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
		var d := rng.randf_range(40.0, CityPlan.BLOCK_D)
		var bw := w - rng.randf_range(0.5, 3.0)
		out.append([x + (w - bw) * 0.5, z0 + CityPlan.BLOCK_D * 0.5 - d * 0.5, bw, d, h])
		x += w
	return out

static func _emit_mass(st: SurfaceTool, m: Array, tint: Color) -> void:
	var ax: float = m[0]
	var az: float = m[1]
	var w: float = m[2]
	var d: float = m[3]
	var h: float = m[4]
	st.set_color(tint)
	_wall(st, Vector3(ax + w, 0, az), Vector3(ax, 0, az), h)
	_wall(st, Vector3(ax, 0, az + d), Vector3(ax + w, 0, az + d), h)
	_wall(st, Vector3(ax + w, 0, az + d), Vector3(ax + w, 0, az), h)
	_wall(st, Vector3(ax, 0, az), Vector3(ax, 0, az + d), h)
	_top(st, ax, az, w, d, h)

# --- tiers ------------------------------------------------------------------

static func _block_windowed(rng: RandomNumberGenerator, x0: float, z0: float,
		cell: Vector2i, plan: CityPlan) -> MeshInstance3D:
	var st := _st()
	var p := plan.params(cell)
	var tints: Array = p["tints"]
	var ring := maxi(absi(cell.x), absi(cell.y))
	for m in _masses(rng, x0, z0, cell, plan):
		# Ring 1 south of the hero sits between it and the sun-derived
		# camera: keep it low so background never blocks subject.
		if ring == 1 and z0 > 31.0 and m[4] > 30.0:
			m[4] = rng.randf_range(18.0, 30.0)
		_emit_mass(st, m, tints[rng.randi_range(0, tints.size() - 1)])
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
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
	mi.material_override = mat
	return mi

static func _block_far(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, z0: float,
		cell: Vector2i, plan: CityPlan) -> void:
	var tints: Array = plan.params(cell)["tints"]
	for m in _masses(rng, x0, z0, cell, plan):
		_emit_mass(st, m, (tints[rng.randi_range(0, tints.size() - 1)] as Color) * 0.9)

static var _far_mat: StandardMaterial3D

static func _flush_far(st: SurfaceTool) -> MeshInstance3D:
	if _far_mat == null:
		_far_mat = StandardMaterial3D.new()
		_far_mat.vertex_color_use_as_albedo = true
		_far_mat.albedo_color = Color(0.5, 0.48, 0.46)  # masonry-mean base
		_far_mat.roughness = 0.9
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _far_mat
	return mi

# --- geometry ---------------------------------------------------------------

static func _wall(st: SurfaceTool, bl: Vector3, br: Vector3, h: float) -> void:
	var w := (br - bl).length()
	var u := Vector3.UP * h
	for pair in [[bl + u, Vector2(0, h)], [br + u, Vector2(w, h)], [br, Vector2(w, 0)],
			[bl + u, Vector2(0, h)], [br, Vector2(w, 0)], [bl, Vector2(0, 0)]]:
		st.set_uv(pair[1])
		st.add_vertex(pair[0])

static func _top(st: SurfaceTool, ax: float, az: float, w: float, d: float, h: float) -> void:
	var pts := [Vector3(ax, h, az), Vector3(ax + w, h, az),
			Vector3(ax + w, h, az + d), Vector3(ax, h, az + d)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(Vector2(pts[i].x, pts[i].z))
		st.add_vertex(pts[i])
