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
	root.add_child(_mesh(land, _mat(Color(0.12, 0.12, 0.125), 0.94)))

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
		_cap(pave, ring, 0.10)
	for ring in ci.esplanade:
		_cap(pave, ring, 0.10)
	for ring in ci.piers:
		_cap(pave, ring, 0.35)
		_skirt(pave, ring, 0.35, -3.0)
	pave.generate_normals()
	root.add_child(_mesh(pave, walk_mat if walk_mat != null
			else _mat(Color(0.245, 0.24, 0.225), 0.85)))

	var lots := SurfaceTool.new()
	lots.begin(Mesh.PRIMITIVE_TRIANGLES)
	lots.set_smooth_group(-1)
	for ring in ci.blocks:
		_cap(lots, ring, 0.14)
	lots.generate_normals()
	root.add_child(_mesh(lots, _mat(Color(0.16, 0.155, 0.15), 0.95)))

	# Road paint: crosswalks and dashed centerlines, aged thermoplastic —
	# same tone the planned city uses (fresh paint is ~0.75, city paint
	# weathers well below that).
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	paint.set_smooth_group(-1)
	for ring in ci.crosswalks:
		_cap(paint, ring, 0.13)
	# Street hierarchy, MEASURED: the engine cuts avenues 2-4x wider than
	# lanes (district streetW 8-30 m, aveW to 38), but painting one center
	# dash on everything erased that. For each kerb edge, cast to the
	# facing kerb to get the real carriageway width, then mark lanes:
	# a narrow lane gets its center dash, an avenue gets a lane line per
	# 3.4 m of roadway. Junction-trimmed as before.
	var kerb_edges: Array = []
	var edge_hash := {}
	for ring in ci.blocks:
		var n := (ring as PackedVector2Array).size()
		for i in range(n):
			var a := (ring as PackedVector2Array)[i]
			var b := (ring as PackedVector2Array)[(i + 1) % n]
			if (b - a).length() < 4.0:
				continue
			var idx := kerb_edges.size()
			kerb_edges.append([a, b])
			for cx in range(int(minf(a.x, b.x) / 40.0) - 1, int(maxf(a.x, b.x) / 40.0) + 2):
				for cy in range(int(minf(a.y, b.y) / 40.0) - 1, int(maxf(a.y, b.y) / 40.0) + 2):
					var key := "%d:%d" % [cx, cy]
					if not edge_hash.has(key):
						edge_hash[key] = []
					edge_hash[key].append(idx)
	for ring in ci.blocks:
		var n := (ring as PackedVector2Array).size()
		for i in range(n):
			var a := (ring as PackedVector2Array)[i]
			var b := (ring as PackedVector2Array)[(i + 1) % n]
			var seg := (b - a).length()
			if seg < 26.0:
				continue
			var dir := (b - a) / seg
			var out := Vector2(dir.y, -dir.x)   # CCW ring: outward is right
			var mid := (a + b) * 0.5
			var g := _gap_to_facing_kerb(mid, out, kerb_edges, edge_hash)
			if g < 5.0 or g > 42.0:
				continue   # alley or waterfront void: no paint
			# Marking density like real streets: narrow ways get one center
			# dash; avenues get a long-dash center divider plus one lane
			# line per side, leaving the kerb (parking) lanes unpainted —
			# marking every 3.4 m read as paint soup at the mid band.
			if g < 12.0:
				var c0 := a + dir * 8.0 + out * (g * 0.5)
				var c1 := b - dir * 8.0 + out * (g * 0.5)
				_dashes(paint, PackedVector2Array([c0, c1]), 0.3, 2.8, 3.2, 0.10)
			else:
				for off_frac: float in [0.5, 0.28, 0.72]:
					var off := g * off_frac
					var p0 := a + dir * 8.0 + out * off
					var p1 := b - dir * 8.0 + out * off
					var center: bool = off_frac == 0.5
					_dashes(paint, PackedVector2Array([p0, p1]), 0.3,
							7.0 if center else 2.8, 2.4 if center else 3.6, 0.10)
	paint.generate_normals()
	root.add_child(_mesh(paint, _mat(Color(0.62, 0.61, 0.58), 0.75)))

	# Park paths: gravel ribbons.
	var path := SurfaceTool.new()
	path.begin(Mesh.PRIMITIVE_TRIANGLES)
	path.set_smooth_group(-1)
	for line in ci.parkpaths:
		_ribbon(path, line, 2.4, 0.28)
	path.generate_normals()
	root.add_child(_mesh(path, _mat(Color(0.42, 0.39, 0.34), 0.9)))

	# Park ponds: still water, above the lawn.
	var pond := SurfaceTool.new()
	pond.begin(Mesh.PRIMITIVE_TRIANGLES)
	pond.set_smooth_group(-1)
	for ring in ci.ponds:
		_cap(pond, ring, 0.30)
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
			GroundGen._tree(tst, Vector3(p.x, 0.27, p.y), trng.randf_range(2.4, 4.0),
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
		_cap(lawn, ring, 0.26)
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
			_cap(masses, ring, 0.26)
			continue
		if not b["deco"]:
			continue
		masses.set_color(Color(0.30, 0.30, 0.31))
		_prism_colored(masses, ring, float(b["z0"]), z1, Color(0.30, 0.30, 0.31))
	masses.generate_normals()
	# Fixed dirt albedo, NOT vertex colors: the debug-color frame proved
	# the vertex tints never landed on this surface, which rendered every
	# vacant lot white — the "confetti" in three mid-band frames.
	root.add_child(_mesh(masses, _mat(Color(0.30, 0.275, 0.24), 0.95)))

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


## One tower crane per developing BBL. Height is the job's floor count
## (exported as devFloors) times a 3.5 m floor-to-floor — a construction
## fact, not a look tweak — plus clearance for the jib over the future roof.
## Yellow is construction-equipment yellow (approx. RAL 1003). The orbital
## camera looks down, so the readable mark is the mast + horizontal jib.
static func build_cranes(ci: CityImport) -> Node3D:
	var root := Node3D.new()
	var seen := {}
	var yellow := _mat(Color(0.91, 0.68, 0.12), 0.45)
	yellow.metallic = 0.35
	var steel := _mat(Color(0.22, 0.22, 0.23), 0.55)
	steel.metallic = 0.6
	var weight := _mat(Color(0.16, 0.16, 0.17), 0.7)
	for b in ci.buildings:
		if not b.get("developing", false) or b.get("deco", false):
			continue
		var bbl := str(b.get("bbl", ""))
		if bbl == "" or seen.has(bbl):
			continue
		seen[bbl] = true
		var floors := maxi(int(b.get("devFloors", 0)), 3)
		root.add_child(_tower_crane(b, floors, yellow, steel, weight))
	if seen.size() > 0:
		print("[plat] cranes: %d on site" % seen.size())
	return root


static func _tower_crane(b: Dictionary, floors: int, yellow: Material,
		steel: Material, weight: Material) -> Node3D:
	var ring: PackedVector2Array = b["ring"]
	var c := Vector2.ZERO
	for p in ring:
		c += p
	c /= float(ring.size())
	# Sit the mast on a lot corner, inset, so the jib covers the pad.
	# Seeded by BBL so the same job does not wander between rebuilds.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("crane/%s" % str(b.get("bbl", "")))
	var corner: Vector2 = ring[rng.randi_range(0, ring.size() - 1)]
	var inward := (c - corner)
	if inward.length() < 0.5:
		inward = Vector2(1, 0)
	var foot: Vector2 = corner + inward.normalized() * minf(4.0, inward.length() * 0.25)
	var mast_h := maxf(18.0, float(floors) * 3.5 + 10.0)
	var span := 0.0
	for p in ring:
		span = maxf(span, foot.distance_to(p))
	var jib_len := clampf(span * 1.15, 16.0, 48.0)
	var aim := (c - foot)
	if aim.length() < 0.5:
		aim = Vector2(1, 0)
	var dir := aim.normalized()
	# BoxMesh long axis is +X. Rotate about Y so +X lands on (dir.x, dir.y).
	var yaw := atan2(-dir.y, dir.x)
	var node := Node3D.new()
	node.name = "crane_%s" % str(b.get("bbl", "x"))
	var y0 := 0.26
	var jib_y := y0 + mast_h + 2.4
	node.add_child(_box(Vector3(foot.x, y0 + mast_h * 0.5, foot.y),
			Vector3(1.15, mast_h, 1.15), yellow))
	node.add_child(_box(Vector3(foot.x, y0 + mast_h + 1.1, foot.y),
			Vector3(2.8, 2.2, 2.8), yellow))
	var jib_mid := foot + dir * (jib_len * 0.5)
	node.add_child(_box(Vector3(jib_mid.x, jib_y, jib_mid.y),
			Vector3(jib_len, 0.7, 0.7), yellow, yaw))
	var c_len := jib_len * 0.38
	var c_mid := foot - dir * (c_len * 0.5)
	node.add_child(_box(Vector3(c_mid.x, jib_y, c_mid.y),
			Vector3(c_len, 0.7, 0.7), yellow, yaw))
	var c_end := foot - dir * c_len
	node.add_child(_box(Vector3(c_end.x, y0 + mast_h + 1.2, c_end.y),
			Vector3(2.4, 1.6, 2.4), weight))
	var hook := foot + dir * (jib_len * 0.62)
	var drop := mast_h * 0.45
	node.add_child(_box(Vector3(hook.x, jib_y - drop * 0.5, hook.y),
			Vector3(0.18, drop, 0.18), steel))
	node.add_child(_box(Vector3(hook.x, jib_y - drop, hook.y),
			Vector3(1.1, 0.7, 1.1), steel))
	node.add_child(_box(Vector3(foot.x, y0 + 0.15, foot.y),
			Vector3(3.2, 0.3, 3.2), steel))
	return node


static func _box(center: Vector3, size: Vector3, mat: Material,
		yaw: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = center
	mi.rotation.y = yaw
	mi.material_override = mat
	return mi


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

## Distance from a kerb point to the facing kerb across the carriageway:
## a ray cast against nearby kerb edges through the spatial hash. Returns
## 99.0 when nothing faces this edge within 45 m (waterfront, park side).
static func _gap_to_facing_kerb(p: Vector2, dir: Vector2, edges: Array,
		ehash: Dictionary) -> float:
	var best := 99.0
	var seen := {}
	for step in range(0, 4):
		var probe := p + dir * (float(step) * 30.0)
		var key := "%d:%d" % [int(probe.x / 40.0), int(probe.y / 40.0)]
		for idx in ehash.get(key, []):
			if seen.has(idx):
				continue
			seen[idx] = true
			var e: Array = edges[idx]
			var t := _ray_seg(p, dir, e[0], e[1])
			if t > 0.5 and t < best:
				best = t
	return best

static func _ray_seg(p: Vector2, d: Vector2, a: Vector2, b: Vector2) -> float:
	var v := b - a
	var denom := d.x * v.y - d.y * v.x
	if absf(denom) < 0.0001:
		return -1.0
	var t := ((a.x - p.x) * v.y - (a.y - p.y) * v.x) / denom
	var s := ((a.x - p.x) * d.y - (a.y - p.y) * d.x) / denom
	return t if s >= 0.0 and s <= 1.0 else -1.0

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
