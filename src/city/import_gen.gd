class_name ImportGen
extends RefCounted
## Stage-2 renderer for an imported engine city (docs/ECONOMY-ADAPTER.md):
## the coast, the paving, the parks, and one correctly placed, correctly
## tall mass per buildings3d record. Deliberately grey — this stage proves
## placement and silhouette agree with the engine before any dressing is
## wired to the quantities. Footprints can be concave (L-shaped lots), so
## caps go through Geometry2D.triangulate_polygon rather than a centroid fan.

static func build(ci: CityImport) -> Node3D:
	var root := Node3D.new()
	root.name = "ImportedCity"

	# Land: triangulated coast polygon + a skirt down past the waterline,
	# same reading as the planned island (seawall base above the water).
	var land := SurfaceTool.new()
	land.begin(Mesh.PRIMITIVE_TRIANGLES)
	land.set_smooth_group(-1)
	_cap(land, ci.coast, 0.0)
	_skirt(land, ci.coast, 0.0, -4.0)
	land.generate_normals()
	root.add_child(_mesh(land, _mat(Color(0.21, 0.21, 0.215), 0.92)))

	var pave := SurfaceTool.new()
	pave.begin(Mesh.PRIMITIVE_TRIANGLES)
	pave.set_smooth_group(-1)
	for ring in ci.pavements:
		_cap(pave, ring, 0.12)
	for ring in ci.esplanade:
		_cap(pave, ring, 0.10)
	for ring in ci.piers:
		_cap(pave, ring, 0.35)
		_skirt(pave, ring, 0.35, -3.0)
	pave.generate_normals()
	root.add_child(_mesh(pave, _mat(Color(0.36, 0.35, 0.33), 0.85)))

	var lawn := SurfaceTool.new()
	lawn.begin(Mesh.PRIMITIVE_TRIANGLES)
	lawn.set_smooth_group(-1)
	for ring in ci.parks:
		_cap(lawn, ring, 0.10)
	lawn.generate_normals()
	root.add_child(_mesh(lawn, _mat(Color(0.30, 0.37, 0.24), 1.0)))

	# Massing: prisms from z0 to z1. Slightly varied grey by the engine's
	# tone index so adjacent volumes separate; decorative volumes (ships,
	# cranes, sheds) darker. Vacant lots arrive with z1 == 0 and render as
	# their outline only (a kerb-height slab), which is exactly what an
	# undressed empty lot is.
	var masses := SurfaceTool.new()
	masses.begin(Mesh.PRIMITIVE_TRIANGLES)
	masses.set_smooth_group(-1)
	for b in ci.buildings:
		var ring: PackedVector2Array = b["ring"]
		var z1: float = b["z1"]
		if z1 <= 0.05:
			_cap(masses, ring, 0.18)
			continue
		var g := 0.42 + 0.05 * float(int(b["tone"]) % 5)
		if b["deco"]:
			g = 0.30
		_prism_colored(masses, ring, float(b["z0"]), z1, Color(g, g, g * 1.02))
	masses.generate_normals()
	var mmat := _mat(Color(1, 1, 1), 0.9)
	mmat.vertex_color_use_as_albedo = true
	root.add_child(_mesh(masses, mmat))

	# Water: one plane under everything, past the coast to the horizon.
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24000, 24000)
	water.mesh = plane
	water.position.y = -1.5
	var wmat := _mat(Color(0.12, 0.16, 0.19), 0.15)
	wmat.metallic = 0.5
	water.material_override = wmat
	root.add_child(water)
	return root

static func _cap(st: SurfaceTool, ring: PackedVector2Array, y: float) -> void:
	var idx := Geometry2D.triangulate_polygon(ring)
	if idx.is_empty():
		# Self-touching rings fail triangulation; skip rather than guess.
		return
	# Both windings: ring orientation varies by source layer, and a cap that
	# guesses wrong is invisible from above. Doubled tris are cheap at this
	# stage's counts; the dressed renderer will normalize orientation.
	for t in range(0, idx.size(), 3):
		for j in [t + 2, t + 1, t, t, t + 1, t + 2]:
			var p := ring[idx[j]]
			st.set_uv(Vector2(p.x, p.y) * 0.25)
			st.add_vertex(Vector3(p.x, y, p.y))

static func _skirt(st: SurfaceTool, ring: PackedVector2Array, y0: float, y1: float) -> void:
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var av0 := Vector3(a.x, y0, a.y)
		var bv0 := Vector3(b.x, y0, b.y)
		var av1 := Vector3(a.x, y1, a.y)
		var bv1 := Vector3(b.x, y1, b.y)
		for q in [av0, bv0, bv1, av0, bv1, av1]:
			st.set_uv(Vector2(q.x + q.z, q.y))
			st.add_vertex(q)
		for q in [av0, bv1, bv0, av0, av1, bv1]:
			st.set_uv(Vector2(q.x + q.z, q.y))
			st.add_vertex(q)

static func _prism_colored(st: SurfaceTool, ring: PackedVector2Array, z0: float,
		z1: float, tint: Color) -> void:
	st.set_color(tint)
	var idx := Geometry2D.triangulate_polygon(ring)
	if idx.is_empty():
		return
	for t in range(0, idx.size(), 3):
		for j in [t + 2, t + 1, t]:
			var p := ring[idx[j]]
			st.set_color(tint)
			st.set_uv(Vector2(p.x, p.y) * 0.25)
			st.add_vertex(Vector3(p.x, z1, p.y))
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		# Both windings: silhouette correctness beats one draw-order saving
		# at this stage, and it sidesteps ring-orientation ambiguity.
		for q in [Vector3(a.x, z0, a.y), Vector3(b.x, z0, b.y), Vector3(b.x, z1, b.y),
				Vector3(a.x, z0, a.y), Vector3(b.x, z1, b.y), Vector3(a.x, z1, a.y),
				Vector3(a.x, z0, a.y), Vector3(b.x, z1, b.y), Vector3(b.x, z0, b.y),
				Vector3(a.x, z0, a.y), Vector3(a.x, z1, a.y), Vector3(b.x, z1, b.y)]:
			st.set_color(tint)
			st.set_uv(Vector2(q.x + q.z, q.y) * 0.25)
			st.add_vertex(q)

static func _mesh(st: SurfaceTool, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi

static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
