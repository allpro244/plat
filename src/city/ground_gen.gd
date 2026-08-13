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

static func build(plan: CityPlan, walk_mat: Material, paint_mat: Material,
		grass_mat: Material) -> Node3D:
	var root := Node3D.new()
	var walks := _st()
	var paint := _st()
	var green := _st()
	for b in plan.blocks:
		var c := Vector2(float(b["x"]), float(b["z"]))
		var ang: float = b["angle"]
		var hw: float = float(b["w"]) * 0.5 + WALK_W
		var hd: float = float(b["d"]) * 0.5 + WALK_W
		_slab(walks, c, Vector2(hw, hd), ang, CURB_H)
		if float(b["dist"]) < CROSSWALK_R:
			_crosswalks(paint, c, Vector2(hw, hd), ang)
			_lane_line(paint, c, Vector2(hw, hd), ang, float(b["road"]))
	for bl in plan.boulevards:
		_median(green, plan, bl)
	for pair in [[walks, walk_mat], [paint, paint_mat], [green, grass_mat]]:
		var mi := _commit(pair[0] as SurfaceTool, pair[1] as Material)
		if mi != null:
			root.add_child(mi)
	return root

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
