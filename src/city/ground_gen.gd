class_name GroundGen
## The ground between the buildings. Until this existed, every street in the
## city was one undifferentiated asphalt sheet — the single biggest tell at
## the near band, where the camera looks DOWN and the ground is half the
## frame.
##
## What it makes, all merged into a handful of surfaces so a thousand blocks
## cost a handful of draw calls:
##   - a raised sidewalk apron around every block, following that block's own
##     rotation (so a turned domain's sidewalks turn with it),
##   - painted crosswalk bars at the near-band block ends,
##   - a planted median down the middle of every boulevard.
##
## Everything is derived from CityPlan geometry; nothing is placed by hand.

## Curb height. NYC standard curb reveal is ~6 in; 0.15 m is that in metric,
## and it is enough to read as a step at the near band without becoming a
## wall at the mid band.
const CURB_H := 0.15
const WALK_W := 5.0     # sidewalk width, m — a real city cross-street walk
const CROSSWALK_R := 900.0   # paint crosswalks within this radius only

const TREE_R := 900.0        # plant street trees within this radius
## Streets are planted where real zoning plants them: residential fabric
## densely, the core sparsely (shafts and vaults under the walk), industry
## not at all. Probability per district that a block's street edge has trees.
const TREE_P := {"prewar": 0.75, "walkup": 0.9, "core": 0.3, "industrial": 0.0}

static func build(seed_value: int, plan: CityPlan, walk_mat: Material,
		paint_mat: Material, grass_mat: Material) -> Node3D:
	var root := Node3D.new()
	var walks := _st()
	var paint := _st()
	var green := _st()
	var trees := _st()
	for b in plan.blocks:
		var c := Vector2(float(b["x"]), float(b["z"]))
		var ang: float = b["angle"]
		var hw: float = float(b["w"]) * 0.5 + WALK_W
		var hd: float = float(b["d"]) * 0.5 + WALK_W
		_slab(walks, c, Vector2(hw, hd), ang, CURB_H)
		if float(b["dist"]) < CROSSWALK_R:
			_crosswalks(paint, c, Vector2(hw, hd), ang)
			_lane_line(paint, c, Vector2(hw, hd), ang, float(b["road"]))
		if float(b["dist"]) < TREE_R:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("%d/trees/%s" % [seed_value, b["key"]])
			if rng.randf() < float(TREE_P[b["district"]]):
				_street_trees(trees, rng, c, Vector2(hw, hd), ang)
	for bl in plan.boulevards:
		_median(green, plan, bl)
	# Parks: scattered canopies over the lawn, one per ~220 m2 — from the
	# bands a park is a texture of treetops with grass showing through.
	for pi in range(plan.parks.size()):
		var pk: Dictionary = plan.parks[pi]
		var prng := RandomNumberGenerator.new()
		prng.seed = hash("%d/parktrees/%d" % [seed_value, pi])
		var n := int(float(pk["w"]) * float(pk["d"]) / 220.0)
		var u := Vector2(cos(float(pk["angle"])), sin(float(pk["angle"])))
		var v := Vector2(-u.y, u.x)
		for k in range(n):
			var lp: Vector2 = (pk["center"] as Vector2) 					+ u * prng.randf_range(-0.48, 0.48) * float(pk["w"]) 					+ v * prng.randf_range(-0.48, 0.48) * float(pk["d"])
			var green_c := Color(0.075, 0.115, 0.045) * prng.randf_range(0.75, 1.35)
			_tree(trees, Vector3(lp.x, 0.10, lp.y), prng.randf_range(3.0, 5.5),
					prng.randf_range(6.0, 10.0), green_c)
	for pair in [[walks, walk_mat], [paint, paint_mat], [green, grass_mat],
			[trees, _tree_material()]]:
		var mi := _commit(pair[0] as SurfaceTool, pair[1] as Material)
		if mi != null:
			root.add_child(mi)
	return root

static var _tree_mat: StandardMaterial3D

static func _tree_material() -> StandardMaterial3D:
	if _tree_mat == null:
		_tree_mat = StandardMaterial3D.new()
		_tree_mat.vertex_color_use_as_albedo = true
		# Vertex colors reach the shader brighter than authored (sRGB->linear
		# path); this multiplier brings rendered foliage back to the ~0.12
		# reflectance real canopies have. Set by comparing a render to the
		# authored value, not by taste.
		_tree_mat.albedo_color = Color(0.45, 0.45, 0.45)
		_tree_mat.roughness = 1.0
		# No specular: the sky-dome reflection was washing small dark
		# canopies toward grey at the mid band.
		_tree_mat.metallic_specular = 0.0
	return _tree_mat

## A row of trees down each long sidewalk edge, 1 m inside the curb. Each
## tree is a trunk stick and an octahedron canopy — an IMPRESSION: from the
## banded camera a street tree is a soft green lump with a shadow, and eight
## triangles buy exactly that.
static func _street_trees(st: SurfaceTool, rng: RandomNumberGenerator,
		c: Vector2, half: Vector2, ang: float) -> void:
	var u := Vector2(cos(ang), sin(ang))
	var v := Vector2(-sin(ang), cos(ang))
	for side in [-1.0, 1.0]:
		var edge: Vector2 = c + v * (half.y - 1.0) * side
		var t := -half.x + 4.0
		while t < half.x - 4.0:
			if rng.randf() < 0.8:   # gaps: dead pits, hydrants, curb cuts
				var p: Vector2 = edge + u * t
				# Foliage albedo is LOW — leaves absorb: ~0.10-0.15 green.
				var green := Color(0.075, 0.115, 0.045) * rng.randf_range(0.8, 1.3)
				_tree(st, Vector3(p.x, CURB_H, p.y), rng.randf_range(2.6, 4.2),
						rng.randf_range(5.5, 8.5), green)
			t += rng.randf_range(7.5, 11.0)

static func _tree(st: SurfaceTool, base: Vector3, r: float, h: float, col: Color) -> void:
	st.set_color(Color(0.16, 0.13, 0.10))
	_tree_octa(st, base, 0.18, 0.18, h * 0.45, 0.0, 0.0)  # trunk: thin dark spike
	st.set_color(col)
	# Two interlocked octahedra, one turned 45 deg: eight lobes instead of
	# four, so the canopy reads as a rounded mass, not a paper dart.
	_tree_octa(st, base, r, r, h - h * 0.4, h * 0.4, 0.0)
	_tree_octa(st, base, r * 0.8, r * 0.8, (h - h * 0.4) * 0.85, h * 0.45, PI * 0.25)

## Octahedron: 4 upper + 4 lower faces around a mid "equator".
static func _tree_octa(st: SurfaceTool, base: Vector3, rx: float, rz: float,
		h: float, y0: float, rot: float) -> void:
	var mid := base + Vector3(0, y0 + h * 0.45, 0)
	var top := base + Vector3(0, y0 + h, 0)
	var bot := base + Vector3(0, y0, 0)
	var e := []
	for k in range(4):
		var a := rot + float(k) * PI * 0.5
		e.append(mid + Vector3(cos(a) * rx, 0, sin(a) * rz))
	for i in range(4):
		var a: Vector3 = e[i]
		var b: Vector3 = e[(i + 1) % 4]
		for q in [top, a, b]:
			st.set_uv(Vector2(q.x, q.z))
			st.add_vertex(q)
		for q in [bot, b, a]:
			st.set_uv(Vector2(q.x, q.z))
			st.add_vertex(q)

# --- pieces -----------------------------------------------------------------

## Six bars of paint at each end of the block, laid across the cross street.
## Real crosswalks are ladder-striped; at these distances the ladder is the
## only part that reads, so that is what gets built.
static func _crosswalks(st: SurfaceTool, c: Vector2, half: Vector2, ang: float) -> void:
	var u := Vector2(cos(ang), sin(ang))
	var v := Vector2(-sin(ang), cos(ang))
	for side in [-1.0, 1.0]:
		# Across the cross street, at each end of the block.
		var base: Vector2 = c + u * (half.x + 4.5) * side
		for k in range(6):
			var off := (float(k) - 2.5) * 1.9
			# Paint sits on the ROADWAY, below the curb, not on the walk.
			_slab(st, base + v * off, Vector2(2.6, 0.6), ang, 0.016)
		# And across the long street, at the block corners — a real
		# intersection is crossable on all four approaches.
		for end in [-1.0, 1.0]:
			var b2: Vector2 = c + v * (half.y + 4.5) * side + u * (half.x - 3.0) * end
			for k in range(5):
				_slab(st, b2 + u * ((float(k) - 2.0) * 1.9 * end),
						Vector2(0.6, 2.6), ang, 0.016)

## Dashed centerline down the roadway on the block's +v side. Dash geometry
## is the US standard: 10 ft stripe, 30 ft gap (3.05 m / 9.14 m), which is
## what makes a painted line read as a ROAD and not a stripe of concrete.
static func _lane_line(st: SurfaceTool, c: Vector2, half: Vector2, ang: float,
		road: float) -> void:
	var u := Vector2(cos(ang), sin(ang))
	var v := Vector2(-sin(ang), cos(ang))
	var base: Vector2 = c + v * (half.y - WALK_W + road * 0.5)
	var n := int(half.x * 2.0 / 12.19)
	for k in range(n):
		var t := (float(k) + 0.5) * 12.19 - half.x
		_slab(st, base + u * t, Vector2(1.52, 0.075), ang, 0.016)

## A planted strip down the boulevard's centerline, clipped to the city.
static func _median(st: SurfaceTool, plan: CityPlan, bl: Dictionary) -> void:
	var dir: Vector2 = bl["dir"]
	var p0: Vector2 = bl["p"]
	var ang := atan2(dir.y, dir.x)
	var step := 60.0
	var t := -CityPlan.CITY_R
	while t < CityPlan.CITY_R:
		var c: Vector2 = p0 + dir * t
		# Only where the boulevard is actually inside the built city — a
		# median running out into open ground would read as a fence.
		if c.length() < plan.city_limit(atan2(c.y, c.x)) * 0.96:
			_slab(st, c, Vector2(step * 0.46, float(bl["w"]) * 0.16), ang, CURB_H + 0.02)
		t += step

# --- mesh -------------------------------------------------------------------

static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	return st

## An axis-turned slab: top face plus four sides down to the street. The
## sides are what make a curb rather than a decal.
static func _slab(st: SurfaceTool, c: Vector2, half: Vector2, ang: float, h: float) -> void:
	var u := Vector2(cos(ang), sin(ang)) * half.x
	var v := Vector2(-sin(ang), cos(ang)) * half.y
	var p := []
	for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
		var q: Vector2 = c + u * float(s[0]) + v * float(s[1])
		p.append(Vector3(q.x, h, q.y))
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(Vector2(p[i].x, p[i].z))
		st.add_vertex(p[i])
	for i in range(4):
		var a: Vector3 = p[i]
		var b: Vector3 = p[(i + 1) % 4]
		var a0 := Vector3(a.x, 0.0, a.z)
		var b0 := Vector3(b.x, 0.0, b.z)
		for q in [a, b, b0, a, b0, a0]:
			st.set_uv(Vector2(q.x + q.z, q.y))
			st.add_vertex(q)

static func _commit(st: SurfaceTool, mat: Material) -> MeshInstance3D:
	var arr := st.commit_to_arrays()
	if (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return null
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi
