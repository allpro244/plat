class_name MeshBuilder
## Turns Grammar output into meshes.
##
## Masonry facades are REAL DEPTH: spandrel bands and brick piers in the wall
## plane, glass recessed behind them with reveal jambs and a projecting sill.
## Self-shadowing under a low sun is most of what makes masonry read as
## masonry from the air, and a shader on a flat quad cannot produce it.
## Curtain walls stay flush quads with the dimensional window shader — flush
## glass is what an International Style wall physically is.
##
## Wall UVs are meters (u along face, v world height) everywhere, so scans
## tile at true scale.

const FACADE_SHADER := preload("res://src/city/facade.gdshader")

## Diagnostic: force plain StandardMaterial3D everywhere (no custom shader).
static var plain_materials := false
## Diagnostic: replace windowed facades with plain walls.
static var skip_windows := false
## Diagnostic: skip roof props (cornice/parapet/bulkhead/water tower).
static var skip_props := false

## 0 = day, 1 = dusk; set by the scene before building. Drives lit windows
## on curtain-wall surfaces (the hero 1961 tower goes to evening with the
## city around it).
static var night_factor := 0.0

static var _roof_mat: StandardMaterial3D
static var _wood_mat: StandardMaterial3D
static var _steel_mat: StandardMaterial3D
static var _plaza_mat: StandardMaterial3D
static var _glass_mat: StandardMaterial3D

static func building_node(b: Dictionary, wall_textures: Dictionary) -> Node3D:
	var node := Node3D.new()
	var f: Dictionary = b["facade"]
	var curtain: bool = f["kind"] == "curtain"

	var st_wall := _st()    # brick/masonry, no windows (walls, piers, reveals, props)
	var st_glass := _st()   # recessed window glass
	var st_roof := _st()
	var st_curtain := _st() # flush curtain-wall surface (shader windows)

	for box in b["boxes"]:
		_emit_box(b, box, st_wall, st_glass, st_curtain, st_roof)
	for prop in (([] if skip_props else b["props"]) as Array):
		match prop["type"]:
			"cornice":
				_emit_cornice(st_wall, prop)
			"parapet":
				_emit_parapet(st_wall, prop)
			"bulkhead":
				_emit_box_faces_windowless(st_wall, prop["aabb"])
				_emit_top(st_roof, prop["aabb"])
			"watertower":
				node.add_child(_water_tower_node(prop["pos"]))
			"plaza":
				pass  # plaza paving is emitted by the ground builder

	var mesh := ArrayMesh.new()
	_commit(mesh, st_wall, _wall_material(f, wall_textures))
	_commit(mesh, st_glass, _glass_material(f))
	_commit(mesh, st_curtain, _curtain_material(f))
	_commit(mesh, st_roof, _roof_material())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	node.add_child(mi)
	return node

# --- materials -------------------------------------------------------------

static func _wall_material(f: Dictionary, texlib: Dictionary) -> Material:
	if plain_materials:
		var pm := StandardMaterial3D.new()
		pm.albedo_color = f["tint"]
		pm.roughness = 0.87
		return pm
	# Resolve the building's material slot against the fetched library, with
	# brick_red as the universal fallback (the mirror profile's only scan).
	var tex: Dictionary = texlib.get(f.get("mat", ""), texlib.get("brick_red", {}))
	var m := ShaderMaterial.new()
	m.shader = FACADE_SHADER
	if tex.has("albedo"):
		m.set_shader_parameter("wall_albedo", tex["albedo"])
		m.set_shader_parameter("wall_normal", tex["normal"])
		m.set_shader_parameter("wall_ao", tex["ao"])
		m.set_shader_parameter("use_wall_texture", 1.0)
		if tex.has("roughness"):
			m.set_shader_parameter("wall_roughness_tex", tex["roughness"])
			m.set_shader_parameter("use_roughness_texture", 1.0)
	else:
		m.set_shader_parameter("use_wall_texture", 0.0)
	m.set_shader_parameter("wall_tint", f["tint"])
	m.set_shader_parameter("windows_enabled", 0.0)
	# The mirror texture set has no per-pixel roughness scan; fired brick and
	# mortar are uniformly matte, so a scalar is a fact, not a fudge.
	m.set_shader_parameter("wall_roughness", 0.87)
	return m

static func _glass_material(f: Dictionary) -> StandardMaterial3D:
	# Unlit interior behind glazing reads near-black with a hard sky
	# reflection; tint and roughness vary per building by era rule (set in
	# the grammar). Lit-window variation waits for the occupancy feed —
	# painting it on now would be a fake frame.
	var m := StandardMaterial3D.new()
	m.albedo_color = f.get("glass", Color(0.03, 0.045, 0.055))
	m.roughness = f.get("glass_rough", 0.08)
	m.metallic = 0.85
	return m

static func _curtain_material(f: Dictionary) -> Material:
	if plain_materials:
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.2, 0.22, 0.24)
		pm.roughness = 0.3
		pm.metallic = 0.5
		return pm
	var m := ShaderMaterial.new()
	m.shader = FACADE_SHADER
	m.set_shader_parameter("use_wall_texture", 0.0)
	m.set_shader_parameter("wall_tint", Color(0.38, 0.39, 0.40))
	m.set_shader_parameter("windows_enabled", 1.0)
	m.set_shader_parameter("floor_height", f["floor_h"])
	m.set_shader_parameter("ground_floor_height", f["ground_h"])
	m.set_shader_parameter("bay_width", f["bay_w"])
	m.set_shader_parameter("window_frac_x", f["win_fx"])
	m.set_shader_parameter("window_frac_y", f["win_fy"])
	m.set_shader_parameter("wall_roughness", 0.5)
	m.set_shader_parameter("wall_metallic", 0.6)
	m.set_shader_parameter("glass_color", Color(0.16, 0.20, 0.22))
	m.set_shader_parameter("glass_roughness", 0.08)
	m.set_shader_parameter("glass_metallic", 0.55)
	# An office slab at dusk: some floors still working, most gone home.
	m.set_shader_parameter("lit_fraction", 0.30 * night_factor)
	m.set_shader_parameter("shop_lit_fraction", 0.45 * night_factor)
	m.set_shader_parameter("win_seed", f["bay_w"] * 37.7 + f["floor_h"] * 91.3)
	return m

static func _roof_material() -> StandardMaterial3D:
	if _roof_mat == null:
		_roof_mat = StandardMaterial3D.new()
		_roof_mat.albedo_color = Color(0.09, 0.088, 0.085)  # tar / built-up roofing
		_roof_mat.roughness = 0.95
	return _roof_mat

static func _wood_material() -> StandardMaterial3D:
	if _wood_mat == null:
		_wood_mat = StandardMaterial3D.new()
		_wood_mat.albedo_color = Color(0.38, 0.28, 0.20)  # weathered cedar tank staves
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
	# An untouched SurfaceTool has no vertices; generate_tangents errors on it.
	var arrays := st.commit_to_arrays()
	var verts = arrays[Mesh.ARRAY_VERTEX]
	if not (verts is PackedVector3Array) or (verts as PackedVector3Array).is_empty():
		return
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

static func _emit_box(b: Dictionary, box: Dictionary, st_wall: SurfaceTool,
		st_glass: SurfaceTool, st_curtain: SurfaceTool, st_roof: SurfaceTool) -> void:
	var aabb: AABB = box["aabb"]
	var win: Dictionary = box["win"]
	var f: Dictionary = b["facade"]
	var curtain: bool = f["kind"] == "curtain"
	var a := aabb.position
	var s := aabb.size
	# Each side: (bottom-left seen from outside, bottom-right, windowed flag)
	var sides := [
		[Vector3(a.x + s.x, a.y, a.z), Vector3(a.x, a.y, a.z), win["n"]],
		[Vector3(a.x, a.y, a.z + s.z), Vector3(a.x + s.x, a.y, a.z + s.z), win["s"]],
		[Vector3(a.x + s.x, a.y, a.z + s.z), Vector3(a.x + s.x, a.y, a.z), win["e"]],
		[Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, a.z + s.z), win["w"]],
	]
	for side in sides:
		if not side[2]:
			_side(st_wall, side[0], side[1], s.y)
		elif curtain:
			_side(st_curtain, side[0], side[1], s.y)
		elif skip_windows:
			_side(st_wall, side[0], side[1], s.y)
		else:
			_side_windowed(st_wall, st_glass, side[0], side[1], s.y, f)
	_emit_top(st_roof, aabb)

## A flat vertical wall from bl to br (seen from outside), extruded up by h.
static func _side(st: SurfaceTool, bl: Vector3, br: Vector3, h: float) -> void:
	var w := (br - bl).length()
	var u := Vector3.UP * h
	_quad(st,
		[bl + u, br + u, br, bl],
		[Vector2(0, bl.y + h), Vector2(w, bl.y + h), Vector2(w, bl.y), Vector2(0, bl.y)])

## A masonry facade with punched openings as REAL geometry.
## Layout: bays of width f.bay_w centered on the face; in each bay and floor,
## a window rect (win_fx x win_fy of the cell), glass recessed by REVEAL with
## jamb/head/sill reveal faces and a projecting sill.
const REVEAL := 0.25          # depth of the window reveal, m
const SILL_PROJECT := 0.07    # sill projection past the wall face, m
const SILL_H := 0.09

static func _side_windowed(st_wall: SurfaceTool, st_glass: SurfaceTool,
		bl: Vector3, br: Vector3, h: float, f: Dictionary) -> void:
	var w := (br - bl).length()
	var along := (br - bl) / w          # unit vector left->right along the face
	var out := Vector3(-along.z, 0.0, along.x)  # outward normal = along x up
	var base_y := bl.y

	var bay_w: float = f["bay_w"]
	var n_bays := int(floor(w / bay_w))
	if n_bays < 1 or h < 3.0:
		_side(st_wall, bl, br, h)
		return
	var margin := (w - float(n_bays) * bay_w) * 0.5

	# Floor rows: [y0, y1, wx_frac, wy_frac]
	var rows := []
	var ground_h: float = f["ground_h"]
	var floor_h: float = f["floor_h"]
	var y := 0.0
	if h > ground_h:
		rows.append([0.0, ground_h, minf(f["win_fx"] * 1.7, 0.82), 0.66])
		y = ground_h
	while y + floor_h <= h + 0.01:
		rows.append([y, y + floor_h, f["win_fx"], f["win_fy"]])
		y += floor_h
	if rows.is_empty():
		_side(st_wall, bl, br, h)
		return
	var top_y: float = rows[-1][1]

	# Wall strip above the last full floor, and end margins full height.
	if h - top_y > 0.01:
		_wall_rect(st_wall, bl, along, base_y, w, top_y, h - top_y, 0.0)
	if margin > 0.01:
		_wall_rect(st_wall, bl, along, base_y, margin, 0.0, top_y, 0.0)
		_wall_rect(st_wall, bl, along, base_y, margin, 0.0, top_y, w - margin)

	for row in rows:
		var y0: float = row[0]
		var y1: float = row[1]
		var wx: float = row[2]
		var wy: float = row[3]
		var cell_h := y1 - y0
		var win_w := bay_w * wx
		var win_h := cell_h * wy
		# Window vertical placement: more head than sill below, like real bays.
		var sill_y := y0 + cell_h * 0.54 - win_h * 0.5
		var head_y := sill_y + win_h
		# Horizontal spandrel band below sills and above heads, full row width.
		_wall_rect(st_wall, bl, along, base_y, w - 2.0 * margin, y0, sill_y - y0, margin)
		_wall_rect(st_wall, bl, along, base_y, w - 2.0 * margin, head_y, y1 - head_y, margin)
		for i in range(n_bays):
			var x0 := margin + float(i) * bay_w
			var wx0 := x0 + (bay_w - win_w) * 0.5
			# Piers between/beside windows for the window-height zone.
			_wall_rect(st_wall, bl, along, base_y, wx0 - x0, sill_y, win_h, x0)
			_wall_rect(st_wall, bl, along, base_y, wx0 - x0, sill_y, win_h, x0 + (bay_w + win_w) * 0.5)
			_window_unit(st_wall, st_glass, bl, along, out, base_y, wx0, sill_y, win_w, win_h)

## A rectangle of wall in the face plane. x_off/w along the face, y0/h vertical.
static func _wall_rect(st: SurfaceTool, bl: Vector3, along: Vector3, base_y: float,
		w: float, y0: float, h: float, x_off: float) -> void:
	if w < 0.005 or h < 0.005:
		return
	var p0 := bl + along * x_off + Vector3.UP * y0
	var p1 := p0 + along * w
	_quad(st,
		[p0 + Vector3.UP * h, p1 + Vector3.UP * h, p1, p0],
		[Vector2(x_off, base_y + y0 + h), Vector2(x_off + w, base_y + y0 + h),
		 Vector2(x_off + w, base_y + y0), Vector2(x_off, base_y + y0)])

## Recessed glass + reveal faces + projecting sill for one window.
static func _window_unit(st_wall: SurfaceTool, st_glass: SurfaceTool,
		bl: Vector3, along: Vector3, out: Vector3, base_y: float,
		x0: float, y0: float, w: float, h: float) -> void:
	var up := Vector3.UP
	var rec := -out * REVEAL
	var wl := bl + along * x0 + up * y0            # window sill, left, wall plane
	var wr := wl + along * w
	var tl := wl + up * h
	var tr := wr + up * h

	# Glass, recessed.
	_quad(st_glass,
		[tl + rec, tr + rec, wr + rec, wl + rec],
		[Vector2(x0, base_y + y0 + h), Vector2(x0 + w, base_y + y0 + h),
		 Vector2(x0 + w, base_y + y0), Vector2(x0, base_y + y0)])
	# Reveal jambs: left faces right (+along), right faces left.
	_quad(st_wall,
		[tl, tl + rec, wl + rec, wl],
		[Vector2(x0, base_y + y0 + h), Vector2(x0 + REVEAL, base_y + y0 + h),
		 Vector2(x0 + REVEAL, base_y + y0), Vector2(x0, base_y + y0)])
	_quad(st_wall,
		[tr + rec, tr, wr, wr + rec],
		[Vector2(x0 + w, base_y + y0 + h), Vector2(x0 + w + REVEAL, base_y + y0 + h),
		 Vector2(x0 + w + REVEAL, base_y + y0), Vector2(x0 + w, base_y + y0)])
	# Head reveal (faces down) and sill reveal (faces up).
	_quad(st_wall,
		[tl, tr, tr + rec, tl + rec],
		[Vector2(x0, base_y + y0 + h), Vector2(x0 + w, base_y + y0 + h),
		 Vector2(x0 + w, base_y + y0 + h - REVEAL), Vector2(x0, base_y + y0 + h - REVEAL)])
	_quad(st_wall,
		[wl + rec, wr + rec, wr, wl],
		[Vector2(x0, base_y + y0 + REVEAL), Vector2(x0 + w, base_y + y0 + REVEAL),
		 Vector2(x0 + w, base_y + y0), Vector2(x0, base_y + y0)])
	# Projecting sill: a small ledge just below the opening.
	var sl := wl - up * SILL_H + along * -0.05
	var sw := w + 0.1
	var sill_out := out * SILL_PROJECT
	# top face of sill ledge (faces up, catches sun)
	_quad(st_wall,
		[wl + along * -0.05, wl + along * -0.05 + along * sw, wl + along * -0.05 + along * sw + sill_out, wl + along * -0.05 + sill_out],
		[Vector2(x0, base_y + y0), Vector2(x0 + sw, base_y + y0),
		 Vector2(x0 + sw, base_y + y0 + SILL_PROJECT), Vector2(x0, base_y + y0 + SILL_PROJECT)])
	# front face of sill
	_quad(st_wall,
		[wl + along * -0.05 + sill_out, wl + along * -0.05 + along * sw + sill_out,
		 sl + along * sw + sill_out, sl + sill_out],
		[Vector2(x0, base_y + y0), Vector2(x0 + sw, base_y + y0),
		 Vector2(x0 + sw, base_y + y0 - SILL_H), Vector2(x0, base_y + y0 - SILL_H)])

static func _emit_top(st: SurfaceTool, aabb: AABB) -> void:
	var a := aabb.position
	var s := aabb.size
	var y := a.y + s.y
	_quad(st,
		[Vector3(a.x, y, a.z), Vector3(a.x + s.x, y, a.z),
		 Vector3(a.x + s.x, y, a.z + s.z), Vector3(a.x, y, a.z + s.z)],
		[Vector2(a.x, a.z), Vector2(a.x + s.x, a.z),
		 Vector2(a.x + s.x, a.z + s.z), Vector2(a.x, a.z + s.z)])

static func _emit_box_faces_windowless(st: SurfaceTool, aabb: AABB) -> void:
	var a := aabb.position
	var s := aabb.size
	var h := s.y
	_side(st, Vector3(a.x + s.x, a.y, a.z), Vector3(a.x, a.y, a.z), h)
	_side(st, Vector3(a.x, a.y, a.z + s.z), Vector3(a.x + s.x, a.y, a.z + s.z), h)
	_side(st, Vector3(a.x + s.x, a.y, a.z + s.z), Vector3(a.x + s.x, a.y, a.z), h)
	_side(st, Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, a.z + s.z), h)

## Cornice: a profiled crown — three stacked slabs stepping outward, the way
## a pressed-metal cornice actually builds up. The steps self-shadow.
static func _emit_cornice(st: SurfaceTool, prop: Dictionary) -> void:
	var r: Dictionary = prop["rect"]
	var y: float = prop["y"]
	var north: bool = prop["front"] == "north"
	var steps := [
		[0.18, 0.35],   # [overhang, height] lowest band
		[0.34, 0.28],
		[0.50, 0.22],   # topmost, widest
	]
	var y0 := y - 0.85
	for stp in steps:
		var o: float = stp[0]
		var sh: float = stp[1]
		var box: AABB
		if north:
			box = AABB(Vector3(r["x0"] - 0.15 - o * 0.3, y0, r["z0"] - o),
					Vector3(r["x1"] - r["x0"] + 0.3 + o * 0.6, sh, o + 0.5))
		else:
			box = AABB(Vector3(r["x0"] - 0.15 - o * 0.3, y0, r["z1"] - 0.5),
					Vector3(r["x1"] - r["x0"] + 0.3 + o * 0.6, sh, o + 0.5))
		_emit_box_faces_windowless(st, box)
		_emit_top(st, box)
		y0 += sh

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
