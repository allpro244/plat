class_name ImportGen
extends RefCounted
## Stage-2 renderer for an imported engine city (docs/ECONOMY-ADAPTER.md):
## the coast, the paving, the parks, and one correctly placed, correctly
## tall mass per buildings3d record. Deliberately grey — this stage proves
## placement and silhouette agree with the engine before any dressing is
## wired to the quantities. Footprints can be concave (L-shaped lots), so
## caps go through Geometry2D.triangulate_polygon rather than a centroid fan.

static func build(ci: CityImport, street_mat: Material = null,
		walk_mat: Material = null) -> Node3D:
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
	# Darker than the planned island's asphalt: on the imported city the
	# land plane IS the street network (blocks sit on their own lighter
	# plates), and at noon 0.21 reads nearly the same as the 0.36 paving —
	# measured on the first dressed render, where the streets vanished.
	root.add_child(_mesh(land, _mat(Color(0.145, 0.145, 0.15), 0.94)))

	# The street reading, from the engine's actual topology (measured on
	# seed 31337: 540 "pavement" sidewalk plates wrap 377 "block" lot
	# interiors, and the streets are the paveland left between them):
	#   paveland .... dark asphalt — the carriageway
	#   pavement .... light concrete sidewalk plates, kerb-height above it
	#   block ....... lot-interior ground, backlot-dark like planned cities
	# The old single mid-grey pile made all three the same surface, which
	# is exactly why the street layout read as mush.
	var street := SurfaceTool.new()
	street.begin(Mesh.PRIMITIVE_TRIANGLES)
	street.set_smooth_group(-1)
	for ring in ci.streets:
		_cap(street, ring, 0.06)
	street.generate_normals()
	root.add_child(_mesh(street, street_mat if street_mat != null
			else _mat(Color(0.155, 0.155, 0.16), 0.92)))

	var pave := SurfaceTool.new()
	pave.begin(Mesh.PRIMITIVE_TRIANGLES)
	pave.set_smooth_group(-1)
	for ring in ci.pavements:
		_cap(pave, ring, 0.12)
		# The kerb FACE: 12 cm of vertical concrete stepping down to the
		# asphalt. A floating plate has no shadow line; a kerb does, and
		# the shadow line is most of what makes a street read as a street.
		_skirt(pave, ring, 0.12, 0.04)
	for ring in ci.esplanade:
		_cap(pave, ring, 0.10)
	for ring in ci.piers:
		_cap(pave, ring, 0.35)
		_skirt(pave, ring, 0.35, -3.0)
	pave.generate_normals()
	root.add_child(_mesh(pave, walk_mat if walk_mat != null
			else _mat(Color(0.335, 0.325, 0.30), 0.85)))

	var lots := SurfaceTool.new()
	lots.begin(Mesh.PRIMITIVE_TRIANGLES)
	lots.set_smooth_group(-1)
	for ring in ci.blocks:
		_cap(lots, ring, 0.14)
	lots.generate_normals()
	root.add_child(_mesh(lots, _mat(Color(0.185, 0.18, 0.17), 0.95)))

	# Road paint: crosswalks and dashed centerlines, aged thermoplastic —
	# same tone the planned city uses (fresh paint is ~0.75, city paint
	# weathers well below that).
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	paint.set_smooth_group(-1)
	for ring in ci.crosswalks:
		_cap(paint, ring, 0.13)
	# Lane dashes on the actual carriageway: each kerb edge long enough to
	# be a street frontage, offset OUTWARD by half the ~9 m carriageway the
	# engine reserves between blocks (its own crosswalk emitter uses
	# road=9), trimmed 8 m short of each corner so junctions stay clean.
	# Facing kerbs from adjacent blocks land their dashes in the same
	# place, which is exactly where the centerline belongs.
	for ring in ci.pavements:
		var n := (ring as PackedVector2Array).size()
		for i in range(n):
			var a := (ring as PackedVector2Array)[i]
			var b := (ring as PackedVector2Array)[(i + 1) % n]
			var seg := (b - a).length()
			if seg < 26.0:
				continue
			var dir := (b - a) / seg
			var out := Vector2(dir.y, -dir.x)   # CCW ring: outward is right
			var p0 := a + dir * 8.0 + out * 4.5
			var p1 := b - dir * 8.0 + out * 4.5
			_dashes(paint, PackedVector2Array([p0, p1]), 0.3, 2.8, 3.2, 0.10)
	paint.generate_normals()
	root.add_child(_mesh(paint, _mat(Color(0.62, 0.61, 0.58), 0.75)))

	# Park paths: gravel ribbons.
	var path := SurfaceTool.new()
	path.begin(Mesh.PRIMITIVE_TRIANGLES)
	path.set_smooth_group(-1)
	for line in ci.parkpaths:
		_ribbon(path, line, 2.4, 0.18)
	path.generate_normals()
	root.add_child(_mesh(path, _mat(Color(0.42, 0.39, 0.34), 0.9)))

	# Park ponds: still water, above the lawn.
	var pond := SurfaceTool.new()
	pond.begin(Mesh.PRIMITIVE_TRIANGLES)
	pond.set_smooth_group(-1)
	for ring in ci.ponds:
		_cap(pond, ring, 0.19)
	pond.generate_normals()
	var pmat := _mat(Color(0.10, 0.14, 0.15), 0.15)
	pmat.metallic = 0.4
	root.add_child(_mesh(pond, pmat))

	# Trees: the engine plants them (street rows, park stands); the canopy
	# impression is the planned city's — trunk spike + interlocked octahedra
	# at real foliage albedo, through GroundGen's calibrated material.
	if not ci.trees.is_empty():
		var tst := SurfaceTool.new()
		tst.begin(Mesh.PRIMITIVE_TRIANGLES)
		tst.set_smooth_group(-1)
		var trng := RandomNumberGenerator.new()
		trng.seed = hash("trees/%d" % ci.seed_value)
		for p in ci.trees:
			var green := Color(0.075, 0.115, 0.045) * trng.randf_range(0.8, 1.3)
			GroundGen._tree(tst, Vector3(p.x, 0.17, p.y), trng.randf_range(2.4, 4.0),
					trng.randf_range(5.0, 8.0), green)
		tst.generate_normals()
		root.add_child(_mesh(tst, GroundGen._tree_material()))

	var lawn := SurfaceTool.new()
	lawn.begin(Mesh.PRIMITIVE_TRIANGLES)
	lawn.set_smooth_group(-1)
	for ring in ci.parks:
		# Above the block/pavement plates (0.12): parks occupy block
		# positions in the engine's plan, and a lawn under the plate is
		# invisible — instrumented at 540 built verts rendering nowhere.
		_cap(lawn, ring, 0.16)
	lawn.generate_normals()
	root.add_child(_mesh(lawn, _mat(Color(0.30, 0.37, 0.24), 1.0)))

	# Only the volumes ContextGen.build_imported does NOT dress: vacant
	# lots (kerb-height slabs — undressed dirt reads honestly as an empty
	# lot) and decorative harbour scenery (ships, cranes, sheds), which
	# have no era, class or windows to dress.
	var masses := SurfaceTool.new()
	masses.begin(Mesh.PRIMITIVE_TRIANGLES)
	masses.set_smooth_group(-1)
	for b in ci.buildings:
		var ring: PackedVector2Array = b["ring"]
		var z1: float = b["z1"]
		if z1 <= 0.05:
			# Bare dirt with a hint of the lot's tone index — an empty lot,
			# not a white void.
			masses.set_color(Color(0.32, 0.29, 0.25) * (0.9 + 0.06 * float(int(b["tone"]) % 3)))
			_cap(masses, ring, 0.18)
			continue
		if not b["deco"]:
			continue
		masses.set_color(Color(0.30, 0.30, 0.31))
		_prism_colored(masses, ring, float(b["z0"]), z1, Color(0.30, 0.30, 0.31))
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
		# Self-touching rings fail triangulation. A tiny inward offset
		# through the polygon clipper repairs most of them (it re-noded
		# the park lawns, which silently vanished before this existed);
		# each repaired piece caps recursively.
		for piece in Geometry2D.offset_polygon(ring, -0.05):
			if not Geometry2D.is_polygon_clockwise(piece) and piece.size() >= 3 \
					and piece.size() < ring.size() + 8:
				_cap(st, piece, y)
		return
	# Both windings: ring orientation varies by source layer, and a cap that
	# guesses wrong is invisible from above. Doubled tris are cheap at this
	# stage's counts; the dressed renderer will normalize orientation.
	for t in range(0, idx.size(), 3):
		for j in [t + 2, t + 1, t, t, t + 1, t + 2]:
			var p := ring[idx[j]]
			st.set_uv(Vector2(p.x, p.y) * 0.25)
			st.add_vertex(Vector3(p.x, y, p.y))

## Flat ribbon along a polyline (paths, lines). Both windings, like _cap.
static func _ribbon(st: SurfaceTool, line: PackedVector2Array, w: float, y: float) -> void:
	var hw := w * 0.5
	for i in range(line.size() - 1):
		var a := line[i]
		var b := line[i + 1]
		var d := (b - a)
		if d.length() < 0.01:
			continue
		var n := Vector2(-d.y, d.x).normalized() * hw
		_quad(st, a + n, b + n, b - n, a - n, y)

## Dashed ribbon: dash/gap metres along the polyline.
static func _dashes(st: SurfaceTool, line: PackedVector2Array, w: float,
		dash: float, gap: float, y: float) -> void:
	var hw := w * 0.5
	for i in range(line.size() - 1):
		var a := line[i]
		var b := line[i + 1]
		var seg := (b - a).length()
		if seg < 0.01:
			continue
		var dir := (b - a) / seg
		var n := Vector2(-dir.y, dir.x) * hw
		var t := 0.0
		while t < seg:
			var t1 := minf(t + dash, seg)
			var p0 := a + dir * t
			var p1 := a + dir * t1
			_quad(st, p0 + n, p1 + n, p1 - n, p0 - n, y)
			t = t1 + gap

static func _quad(st: SurfaceTool, p0: Vector2, p1: Vector2, p2: Vector2,
		p3: Vector2, y: float) -> void:
	var v := [Vector3(p0.x, y, p0.y), Vector3(p1.x, y, p1.y),
			Vector3(p2.x, y, p2.y), Vector3(p3.x, y, p3.y)]
	for j in [0, 1, 2, 0, 2, 3, 2, 1, 0, 3, 2, 0]:
		st.set_uv(Vector2((v[j] as Vector3).x, (v[j] as Vector3).z) * 0.25)
		st.add_vertex(v[j])

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
