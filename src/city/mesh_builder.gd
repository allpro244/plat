class_name MeshBuilder
## Turns Grammar output into meshes. Each building becomes one MeshInstance3D
## with up to three surfaces (windowed facade, windowless flank, roof) plus
## prop instances. Face UVs are meters (u along face, v world height) so the
## facade shader can do dimensional window arithmetic.

const FACADE_SHADER := preload("res://src/city/facade.gdshader")

static var _roof_mat: StandardMaterial3D
static var _wood_mat: StandardMaterial3D
static var _steel_mat: StandardMaterial3D
static var _plaza_mat: StandardMaterial3D

static func building_node(b: Dictionary, wall_textures: Dictionary) -> Node3D:
	var node := Node3D.new()
	var f: Dictionary = b["facade"]
	var facade_mat := _facade_material(f, true, wall_textures)
	var flank_mat := _facade_material(f, false, wall_textures)

	var st_facade := _st()
	var st_flank := _st()
	var st_roof := _st()

	for box in b["boxes"]:
		_emit_box(st_facade, st_flank, st_roof, box["aabb"], box["win"])
	for prop in b["props"]:
		match prop["type"]:
			"cornice":
				_emit_cornice(st_flank, prop)
			"parapet":
				_emit_parapet(st_flank, prop)
			"bulkhead":
				_emit_aabb_all(st_flank, prop["aabb"])
				_emit_top(st_roof, prop["aabb"])
			"watertower":
				node.add_child(_water_tower_node(prop["pos"]))
			"plaza":
				pass  # plaza paving is emitted by the ground builder

	var mesh := ArrayMesh.new()
	_commit(mesh, st_facade, facade_mat)
	_commit(mesh, st_flank, flank_mat)
	_commit(mesh, st_roof, _roof_material())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	node.add_child(mi)
	return node

# --- materials -------------------------------------------------------------

static func _facade_material(f: Dictionary, windowed: bool, tex: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FACADE_SHADER
	var curtain: bool = f["kind"] == "curtain"
	if not curtain and tex.has("albedo"):
		m.set_shader_parameter("wall_albedo", tex["albedo"])
		m.set_shader_parameter("wall_normal", tex["normal"])
		m.set_shader_parameter("wall_ao", tex["ao"])
		m.set_shader_parameter("use_wall_texture", 1.0)
	else:
		m.set_shader_parameter("use_wall_texture", 0.0)
	m.set_shader_parameter("wall_tint", f["tint"])
	m.set_shader_parameter("windows_enabled", 1.0 if windowed else 0.0)
	m.set_shader_parameter("floor_height", f["floor_h"])
	m.set_shader_parameter("ground_floor_height", f["ground_h"])
	m.set_shader_parameter("bay_width", f["bay_w"])
	m.set_shader_parameter("window_frac_x", f["win_fx"])
	m.set_shader_parameter("window_frac_y", f["win_fy"])
	if curtain:
		# Anodized aluminum spandrel + colder, more reflective vision glass.
		m.set_shader_parameter("wall_roughness", 0.5)
		m.set_shader_parameter("wall_metallic", 0.6)
		m.set_shader_parameter("wall_tint", Color(0.38, 0.39, 0.40))
		m.set_shader_parameter("glass_color", Color(0.16, 0.20, 0.22))
		m.set_shader_parameter("glass_roughness", 0.08)
		m.set_shader_parameter("glass_metallic", 0.55)
	else:
		# The mirror texture set has no per-pixel roughness scan; fired brick
		# and mortar are uniformly matte, so a scalar is a fact, not a fudge.
		m.set_shader_parameter("wall_roughness", 0.87)
	return m

static func _roof_material() -> StandardMaterial3D:
	if _roof_mat == null:
		_roof_mat = StandardMaterial3D.new()
		_roof_mat.albedo_color = Color(0.16, 0.155, 0.15)  # tar / built-up roofing
		_roof_mat.roughness = 0.95
	return _roof_mat

static func _wood_material() -> StandardMaterial3D:
	if _wood_mat == null:
		_wood_mat = StandardMaterial3D.new()
		_wood_mat.albedo_color = Color(0.30, 0.21, 0.15)  # weathered cedar tank staves
		_wood_mat.roughness = 0.9
	return _wood_mat

static func _steel_material() -> StandardMaterial3D:
	if _steel_mat == null:
		_steel_mat = StandardMaterial3D.new()
		_steel_mat.albedo_color = Color(0.20, 0.19, 0.18)
		_steel_mat.roughness = 0.6
		_steel_mat.metallic = 0.7
	return _steel_mat

static func plaza_material() -> StandardMaterial3D:
	if _plaza_mat == null:
		_plaza_mat = StandardMaterial3D.new()
		_plaza_mat.albedo_color = Color(0.52, 0.50, 0.47)  # granite paving
		_plaza_mat.roughness = 0.55
	return _plaza_mat

# --- geometry emission -----------------------------------------------------

static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Flat shading: the default smooth group welds normals across box corners
	# and lights every box like a cylinder.
	st.set_smooth_group(-1)
	return st

static func _commit(mesh: ArrayMesh, st: SurfaceTool, mat: Material) -> void:
	st.generate_normals()
	st.generate_tangents()
	var idx := mesh.get_surface_count()
	if st.commit(mesh) != null and mesh.get_surface_count() > idx:
		mesh.surface_set_material(idx, mat)

## Quad with vertices in clockwise order viewed from outside (Godot front face).
static func _quad(st: SurfaceTool, p: Array, uv: Array) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(p[i])

static func _emit_box(stf: SurfaceTool, stk: SurfaceTool, str_: SurfaceTool,
		aabb: AABB, win: Dictionary) -> void:
	var a := aabb.position
	var s := aabb.size
	var y0 := a.y
	var y1 := a.y + s.y
	# north face (-Z), viewed from north: +X runs right-to-left
	_side(stf if win["n"] else stk,
		Vector3(a.x + s.x, y0, a.z), Vector3(a.x, y0, a.z), Vector3.UP, y1 - y0)
	# south face (+Z)
	_side(stf if win["s"] else stk,
		Vector3(a.x, y0, a.z + s.z), Vector3(a.x + s.x, y0, a.z + s.z), Vector3.UP, y1 - y0)
	# east face (+X)
	_side(stf if win["e"] else stk,
		Vector3(a.x + s.x, y0, a.z + s.z), Vector3(a.x + s.x, y0, a.z), Vector3.UP, y1 - y0)
	# west face (-X)
	_side(stf if win["w"] else stk,
		Vector3(a.x, y0, a.z), Vector3(a.x, y0, a.z + s.z), Vector3.UP, y1 - y0)
	_emit_top(str_, aabb)

## A vertical wall from bottom-left to bottom-right (as seen from outside),
## extruded up by h. UV: u = meters along the wall, v = world-height meters.
static func _side(st: SurfaceTool, bl: Vector3, br: Vector3, up: Vector3, h: float) -> void:
	var w := (br - bl).length()
	var u := up * h
	_quad(st,
		[bl + u, br + u, br, bl],
		[Vector2(0, bl.y + h), Vector2(w, bl.y + h), Vector2(w, bl.y), Vector2(0, bl.y)])

static func _emit_top(st: SurfaceTool, aabb: AABB) -> void:
	var a := aabb.position
	var s := aabb.size
	var y := a.y + s.y
	_quad(st,
		[Vector3(a.x, y, a.z), Vector3(a.x + s.x, y, a.z),
		 Vector3(a.x + s.x, y, a.z + s.z), Vector3(a.x, y, a.z + s.z)],
		[Vector2(a.x, a.z), Vector2(a.x + s.x, a.z),
		 Vector2(a.x + s.x, a.z + s.z), Vector2(a.x, a.z + s.z)])

static func _emit_aabb_all(st: SurfaceTool, aabb: AABB) -> void:
	_emit_box_faces_windowless(st, aabb)

static func _emit_box_faces_windowless(st: SurfaceTool, aabb: AABB) -> void:
	var a := aabb.position
	var s := aabb.size
	var h := s.y
	_side(st, Vector3(a.x + s.x, a.y, a.z), Vector3(a.x, a.y, a.z), Vector3.UP, h)
	_side(st, Vector3(a.x, a.y, a.z + s.z), Vector3(a.x + s.x, a.y, a.z + s.z), Vector3.UP, h)
	_side(st, Vector3(a.x + s.x, a.y, a.z + s.z), Vector3(a.x + s.x, a.y, a.z), Vector3.UP, h)
	_side(st, Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, a.z + s.z), Vector3.UP, h)

## Cornice: a shallow slab overhanging the street face.
static func _emit_cornice(st: SurfaceTool, prop: Dictionary) -> void:
	var r: Dictionary = prop["rect"]
	var y: float = prop["y"]
	var overhang := 0.45
	var box: AABB
	if prop["front"] == "north":
		box = AABB(Vector3(r["x0"] - 0.15, y - 0.9, r["z0"] - overhang),
				Vector3(r["x1"] - r["x0"] + 0.3, 0.9, overhang + 0.6))
	else:
		box = AABB(Vector3(r["x0"] - 0.15, y - 0.9, r["z1"] - 0.6),
				Vector3(r["x1"] - r["x0"] + 0.3, 0.9, overhang + 0.6))
	_emit_box_faces_windowless(st, box)
	_emit_top(st, box)

static func _emit_parapet(st: SurfaceTool, prop: Dictionary) -> void:
	var r: Dictionary = prop["rect"]
	var y: float = prop["y"]
	var t := 0.3
	var h := 0.9
	for seg in [
		AABB(Vector3(r["x0"], y, r["z0"]), Vector3(r["x1"] - r["x0"], h, t)),
		AABB(Vector3(r["x0"], y, r["z1"] - t), Vector3(r["x1"] - r["x0"], h, t)),
		AABB(Vector3(r["x0"], y, r["z0"]), Vector3(t, h, r["z1"] - r["z0"])),
		AABB(Vector3(r["x1"] - t, y, r["z0"]), Vector3(t, h, r["z1"] - r["z0"])),
	]:
		_emit_box_faces_windowless(st, seg)
		_emit_top(st, seg)

## Rooftop water tank: cedar drum + conical cap on a steel cross-frame.
static func _water_tower_node(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	var legs_h := 2.4
	var drum_h := 3.6
	var r := 1.9

	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(r * 1.5, legs_h, r * 1.5)
	frame.mesh = fb
	frame.material_override = _steel_material()
	frame.position = Vector3(0, legs_h * 0.5, 0)
	n.add_child(frame)

	var drum := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r * 0.92
	cyl.bottom_radius = r
	cyl.height = drum_h
	cyl.radial_segments = 14
	drum.mesh = cyl
	drum.material_override = _wood_material()
	drum.position = Vector3(0, legs_h + drum_h * 0.5, 0)
	n.add_child(drum)

	var cap := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.15
	cone.bottom_radius = r * 0.98
	cone.height = 1.4
	cone.radial_segments = 14
	cap.mesh = cone
	cap.material_override = _wood_material()
	cap.position = Vector3(0, legs_h + drum_h + 0.7, 0)
	n.add_child(cap)
	return n
