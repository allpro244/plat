class_name ContextGen
## Rough massing for the blocks surrounding the hero block, so it sits in a
## city instead of on a table: seeded boxes with shader-windowed faces, no
## facade depth, no props. This is explicitly BACKGROUND — the impostor tier
## of the camera contract, one step below the hero block's geometry. Same
## seed, same neighbors.

const FACADE_SHADER := preload("res://src/city/facade.gdshader")

# Ring of neighbor block origins around the hero block (which spans
# x -90..90, z -30.5..30.5; side street 18 m north, avenue 30 m south,
# cross streets 18 m).
const PITCH_X := 198.0   # 180 block + 18 cross street

static func build(seed_value: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + "/context")
	# Two rows of neighbor blocks north (beyond the side street) and south
	# (across the avenue), three columns each; plus flanking blocks east/west
	# of the hero block on the same row.
	var origins := []
	for i in [-1, 0, 1]:
		origins.append(Vector2(i * PITCH_X, -79.0 - 61.0))          # north row (z -140..-79)
		origins.append(Vector2(i * PITCH_X, 91.0))                  # south row (z 91..152)
		origins.append(Vector2(i * PITCH_X, -79.0 - 61.0 - 79.0))   # far north row
		origins.append(Vector2(i * PITCH_X, 91.0 + 61.0 + 30.0))    # far south row
	origins.append(Vector2(-PITCH_X, -30.5))                        # west, same row
	origins.append(Vector2(PITCH_X, -30.5))                         # east, same row

	for o in origins:
		_block(root, rng, o.x - 90.0, o.y)
	return root

static func _block(root: Node3D, rng: RandomNumberGenerator, x0: float, z0: float) -> void:
	# Subdivide a 180x61 block into 5-9 masses along its length, two rows deep
	# where the masses are shallow, one where deep.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var x := x0
	var x1 := x0 + 180.0
	# Darker than the hero palette on purpose: untextured masses read lighter
	# than textured ones under the same sun, and background must not outshine
	# foreground.
	var tint_pool := [
		Color(0.45, 0.37, 0.31), Color(0.55, 0.48, 0.41), Color(0.40, 0.38, 0.37),
		Color(0.58, 0.44, 0.35), Color(0.50, 0.47, 0.42), Color(0.35, 0.31, 0.29),
	]
	var node := Node3D.new()
	root.add_child(node)
	while x < x1 - 8.0:
		var w := rng.randf_range(14.0, 34.0)
		w = minf(w, x1 - x)
		# Height distribution biased low with occasional towers, like a real
		# midtown fringe block.
		var h: float
		var r := rng.randf()
		if r < 0.55:
			h = rng.randf_range(18.0, 40.0)
		elif r < 0.85:
			h = rng.randf_range(40.0, 75.0)
		else:
			h = rng.randf_range(75.0, 130.0)
		# South of the hero block sits between it and the default camera:
		# keep that row low so the background never blocks the subject.
		if z0 > 60.0 and z0 < 130.0:
			h = minf(h, 26.0)
		var d := rng.randf_range(40.0, 61.0)
		var mi := MeshInstance3D.new()
		# Hand-built box so face UVs are METERS (u along face, v world height),
		# which the window shader's dimensional grid requires. BoxMesh UVs are
		# an atlas, not meters, and would scramble the windows.
		var bw := w - rng.randf_range(0.5, 3.0)
		var ax := x + (w - bw) * 0.5
		var az := z0 + 30.5 - d * 0.5
		var stm := SurfaceTool.new()
		stm.begin(Mesh.PRIMITIVE_TRIANGLES)
		stm.set_smooth_group(-1)
		_wall(stm, Vector3(ax + bw, 0, az), Vector3(ax, 0, az), h)
		_wall(stm, Vector3(ax, 0, az + d), Vector3(ax + bw, 0, az + d), h)
		_wall(stm, Vector3(ax + bw, 0, az + d), Vector3(ax + bw, 0, az), h)
		_wall(stm, Vector3(ax, 0, az), Vector3(ax, 0, az + d), h)
		_top(stm, ax, az, bw, d, h)
		stm.generate_normals()
		stm.generate_tangents()
		mi.mesh = stm.commit()
		var m := ShaderMaterial.new()
		m.shader = FACADE_SHADER
		m.set_shader_parameter("use_wall_texture", 0.0)
		m.set_shader_parameter("wall_tint", tint_pool[rng.randi_range(0, tint_pool.size() - 1)])
		m.set_shader_parameter("windows_enabled", 1.0)
		m.set_shader_parameter("floor_height", 3.5)
		m.set_shader_parameter("ground_floor_height", 4.5)
		m.set_shader_parameter("bay_width", rng.randf_range(2.4, 3.2))
		m.set_shader_parameter("window_frac_x", 0.42)
		m.set_shader_parameter("window_frac_y", 0.5)
		m.set_shader_parameter("wall_roughness", 0.85)
		mi.material_override = m
		node.add_child(mi)
		x += w

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
