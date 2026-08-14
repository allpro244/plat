class_name CityScene
extends Node3D
## Assembles the whole world from a parameter dictionary: environment + HDRI
## sky, sun from real solar position, ground plane, the generated block, and
## the banded camera rig. Everything stochastic flows from params.seed —
## nothing in here is hand-placed.

const ASSET_DIR := "res://assets/downloaded"
## How far the sky's baked sun may sit from the computed sun before the build
## says so. 8 deg is roughly half an hour of summer sun at this latitude —
## below that the mismatch is not readable in the image, above it the shadows
## and the sky start telling different stories.
const SKY_SUN_TOLERANCE_DEG := 8.0

var params: Dictionary
var rig: CameraRig
var sun_info: Dictionary
var sky_sun_delta_deg := 0.0
var _matlib := {}
var _plan: CityPlan = null
var _import: CityImport = null

static func defaults() -> Dictionary:
	return {
		"seed": 1928,
		# Place and moment. NYC City Hall latitude. "time": null means the
		# default moment is DERIVED from the pinned sky: the sky's baked sun
		# elevation is measured from the image and the clock time solved so
		# the computed sun matches it. A sky can be rotated to any azimuth but
		# its sun elevation is fixed at capture — so the honest default time
		# of day is the time the sky was shot. Pass --time to override; the
		# sky_delta warning then reports any disagreement.
		"latitude": 40.7128, "longitude": -74.0060, "utc_offset": -4.0,
		"year": 2026, "month": 6, "day": 21, "time": null,
		# null = derive from the sun: the camera puts the sun over its right
		# shoulder (sun azimuth - 50 deg), so lit faces AND their shadows are
		# both in frame for ANY pinned sky. A fixed azimuth kept losing this
		# fight every time the sky (and so the derived sun) changed. --az
		# still overrides.
		"band": "near", "cam_azimuth": null, "cam_height": 120.0, "cam_radius": 195.0,
		"gi": true,
	}

func _init(p: Dictionary = {}) -> void:
	params = defaults()
	params.merge(p, true)

func _ready() -> void:
	_matlib = _load_material_library()
	_build_environment()
	_build_sun()
	# The plan must exist before the ground: the island's coastline IS the
	# plan's lobed city limit. Diagnostic no-context runs keep a flat slab.
	# An imported city (docs/ECONOMY-ADAPTER.md) replaces the plan wholesale:
	# the engine already decided the coast, the parcels and the heights, so
	# nothing here may invent them. ImportGen builds its own ground and water.
	if params.get("city", ""):
		_import = CityImport.load_city(str(params["city"]))
	if _import == null and not params.get("no_context", false):
		_plan = CityPlan.new(int(params["seed"]))
		print("[plat] ", _plan.describe())
	if _import == null:
		_build_ground()
	# Dusk factor from the sun the environment just derived: fades in below
	# 14 deg elevation, full by 4 deg. Drives lit windows everywhere.
	var night: float = clampf((14.0 - float(sun_info["elevation_deg"])) / 10.0, 0.0, 1.0)
	MeshBuilder.night_factor = night
	MeshBuilder.plain_materials = params.get("plain_mats", false)
	MeshBuilder.skip_windows = params.get("skip_windows", false)
	MeshBuilder.skip_props = params.get("skip_props", false)
	if _import != null:
		# The scanned ground set, same as planned cities: streets read as
		# asphalt and walks as concrete because they ARE those scans, not
		# flat greys (flat greys were why the layout refused to read).
		add_child(ImportGen.build(_import,
				_ground_material("asphalt", Color(0.155, 0.155, 0.16), 0.92, 6.0),
				_ground_material("sidewalk", Color(0.335, 0.325, 0.30), 0.85, 4.0)))
		add_child(ContextGen.build_imported(_import, _matlib, night))
	if _import == null and not params.get("no_block", false):
		_build_block()
	if _plan != null:
		add_child(ContextGen.build(int(params["seed"]), _matlib, _plan, night))
		_build_plan_features(_plan)
		if not params.get("skip_ground", false):
			add_child(GroundGen.build(int(params["seed"]), _plan,
					_ground_material("sidewalk", Color(0.36, 0.35, 0.33), 0.8, 4.0),
					_paint_material(), _grass_material()))
	rig = CameraRig.new()
	# An imported city aims at ITS OWN downtown (the manifest's core) — the
	# engine puts the core wherever the island wants it, not at the origin.
	if _import != null:
		rig.set_target_xz(_import.core.x, _import.core.y)
	if params.get("target_x") != null:
		rig.set_target_xz(float(params["target_x"]), float(params.get("target_z", 0.0)))
	add_child(rig)
	rig.set_band(params["band"])
	if params["cam_azimuth"] == null:
		params["cam_azimuth"] = fposmod(sun_info["azimuth_deg"] - 50.0, 360.0)
	rig.set_view(params["cam_azimuth"], params["cam_height"], params["cam_radius"])

func _build_environment() -> void:
	var env := Environment.new()
	if params.get("env_plain", false):
		# Diagnostic: probe-level environment (no sky, no fog, no SSAO, default
		# tonemap) to isolate which env feature eats the sun.
		var sunp := SunPosition.compute(params["year"], params["month"], params["day"],
				15.98 if params["time"] == null else params["time"],
				params["latitude"], params["longitude"], params["utc_offset"])
		params["time"] = 15.98 if params["time"] == null else params["time"]
		sun_info = sunp
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.6, 0.75, 0.9)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.6, 0.65, 0.7)
		env.ambient_light_energy = 0.55
		var wep := WorldEnvironment.new()
		wep.environment = env
		add_child(wep)
		return
	var hdri_path := ASSET_DIR + "/sky/sky.hdr"
	var baked := {}
	var img: Image = _load_image(hdri_path)
	if img != null:
		baked = _measure_hdri_sun(img)
	if params["time"] == null:
		params["time"] = _solve_time_for_elevation(
				baked.get("elevation_deg", 40.0))
	var sun := SunPosition.compute(params["year"], params["month"], params["day"],
			params["time"], params["latitude"], params["longitude"], params["utc_offset"])
	sun_info = sun
	if img != null:
		var sky_tex := ImageTexture.create_from_image(img)
		var sky_mat := PanoramaSkyMaterial.new()
		sky_mat.panorama = sky_tex
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		# Rotate the panorama so its baked sun sits at the computed azimuth.
		# The HDRI's own sun position is measured from the image, so this stays
		# true for whatever sky the fetch script pins.
		env.sky_rotation = Vector3(0.0,
				deg_to_rad(baked["azimuth_deg"] - sun["azimuth_deg"]), 0.0)
		_check_sky_sun_agreement(baked, sun)
	else:
		push_warning("HDRI missing — run tools/fetch-assets.sh. Falling back to flat sky.")
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.55, 0.70, 0.85)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.6, 0.7, 0.8)
		env.ambient_light_energy = 1.0
	# Ambient is a controlled COLOR term, not sky IBL: sky-sourced ambient
	# ignores the energy dial (verified across two CI runs whose ambient
	# energy differed 2x with no visible change) and fills every shadow with
	# full-brightness skylight, flattening the image. The sky still provides
	# the visible background and specular reflections; diffuse ambient is a
	# neutral daylight tone at ~1/5 of direct sun, the real clear-sky ratio.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.62, 0.70)
	# With SDFGI on, real bounce replaces most of the flat ambient term; the
	# residual covers what four cascades cannot resolve.
	env.ambient_light_energy = 0.30 if params.get("gi", false) else 0.5
	# Distance haze: softens the HDRI horizon and gives the skyline depth.
	env.fog_enabled = not params.get("no_fog", false)
	env.fog_light_color = Color(0.75, 0.78, 0.82)
	# Extinction sized for city-scale sightlines (2-3 km at the far band):
	# 0.00004/m keeps ~90% transmittance at 2.5 km, haze without milk.
	env.fog_density = 0.00004
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.45
	if params.get("gi", false):
		# SDFGI: real-time GI from signed distance fields. The cost of this on
		# software Vulkan is THE number that decides where beauty renders run.
		env.sdfgi_enabled = true
		# Occlusion off and a coarser cell: the fine-cell + occlusion combo
		# produced light-leak blobs on flat ground at this scene scale.
		env.sdfgi_use_occlusion = false
		env.sdfgi_min_cell_size = 1.0
		env.sdfgi_cascades = 4
		env.sdfgi_bounce_feedback = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Grading for the game-clean daylight look: at exposure 1.25 every
	# mid-grey albedo (roofs, sidewalks) tone-mapped to near-white and the
	# whole aerial read as chalk. 0.95 puts a 0.35-albedo roof at mid-grey
	# where it belongs and lets the value spread between materials show.
	env.tonemap_white = 5.0
	env.tonemap_exposure = 0.95
	env.ssao_enabled = true
	env.ssao_intensity = 2.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

## Locate the sun baked into the panorama: the brightest texel of a reduced
## copy. Returns {azimuth_deg, elevation_deg} in this project's convention
## (azimuth 0 = north = -Z, clockwise), for an equirectangular panorama whose
## u=0.5 column faces -Z and whose v=0 row is the zenith.
##
## The convert() is load-bearing and was a silent bug: .hdr files load as
## FORMAT_RGBE9995, and Image.resize() on an RGBE image yields all-zero pixels
## without erroring — so this returned a constant rather than a measurement,
## and the sky was never actually aligned to the sun.
func _measure_hdri_sun(img: Image) -> Dictionary:
	var probe: Image = img.duplicate()
	probe.convert(Image.FORMAT_RGBF)
	probe.resize(256, 128, Image.INTERPOLATE_BILINEAR)
	var best := -1.0
	var best_x := 0
	var best_y := 0
	for y in range(128):
		for x in range(256):
			var c := probe.get_pixel(x, y)
			var lum := c.r + c.g + c.b
			if lum > best:
				best = lum
				best_x = x
				best_y = y
	assert(best > 0.0, "HDRI probe read no light — image format not decoded")
	return {
		"azimuth_deg": fposmod((float(best_x) / 256.0) * 360.0 + 180.0, 360.0),
		"elevation_deg": 90.0 - (float(best_y) + 0.5) / 128.0 * 180.0,
	}

## Solve for the afternoon/evening clock time at which the computed solar
## elevation matches the sky's baked sun. Afternoon branch by convention (a
## sunrise sky serves as an evening one mirrored about noon; the image cannot
## tell). Scans at 36 s steps — well under the tolerance.
func _solve_time_for_elevation(el_target: float) -> float:
	var best_t := 12.0
	var best_d := 999.0
	var t := 12.0
	while t <= 21.5:
		var sun := SunPosition.compute(params["year"], params["month"], params["day"],
				t, params["latitude"], params["longitude"], params["utc_offset"])
		var d: float = absf(sun["elevation_deg"] - el_target)
		if d < best_d:
			best_d = d
			best_t = t
		t += 0.01
	return best_t

## A panorama can be rotated to any azimuth but its sun elevation is baked in,
## so a sky and a computed sun can silently disagree about the time of day.
## Nothing else in the build would notice; this does.
func _check_sky_sun_agreement(baked: Dictionary, sun: Dictionary) -> void:
	sky_sun_delta_deg = absf(baked["elevation_deg"] - sun["elevation_deg"])
	if sky_sun_delta_deg > SKY_SUN_TOLERANCE_DEG:
		push_warning(("sky/sun disagree by %.1f deg: HDRI sun sits at %.1f deg "
				+ "elevation, computed sun at %.1f. Pick a time of day nearer the "
				+ "sky, or pin a sky nearer the time.") % [
				sky_sun_delta_deg, baked["elevation_deg"], sun["elevation_deg"]])

func _build_sun() -> void:
	var el: float = sun_info["elevation_deg"]
	var az: float = sun_info["azimuth_deg"]
	var light := DirectionalLight3D.new()
	add_child(light)
	var dir := SunPosition.sun_direction(az, el)
	light.look_at_from_position(dir * 500.0, Vector3.ZERO)
	# Direct solar illuminance falls with air mass as the sun drops (smooth
	# ramp standing in for the Kasten-Young curve). The 3.2 multiplier sets
	# the direct:diffuse ratio against the 0.55 sky ambient below — clear-sky
	# direct sun is roughly 5x diffuse skylight, and without that ratio the
	# scene reads shadowless under a bright sky (seen in CI at 48 deg sun).
	light.light_energy = clampf(sin(deg_to_rad(maxf(el, 0.0))) * 3.2, 0.0, 2.6)
	# Rayleigh scattering reddens low sun.
	var warm := clampf(1.0 - el / 35.0, 0.0, 1.0)
	light.light_color = Color(1.0, 1.0 - 0.25 * warm, 1.0 - 0.45 * warm)
	light.shadow_enabled = true
	# 500 m covers the hero block and first context ring from every band-1
	# camera position; the tighter range buys visibly crisper shadow edges
	# from the same 4k atlas.
	light.directional_shadow_max_distance = 500.0
	light.shadow_bias = 0.05

func _build_ground() -> void:
	# Streets: one asphalt surface under everything. With a plan, that
	# surface is the ISLAND — a radial fan following the lobed coastline,
	# with a skirt dropping below the waterline so the city stands out of
	# its harbor on a visible edge. The scan tiles at ~6 m so aggregate
	# reads as texture, not gravel, from the near band.
	var asphalt := _ground_material("asphalt", Color(0.21, 0.21, 0.215), 0.92, 6.0)
	if _plan == null:
		_slab(Vector2(-9000, -9000), Vector2(9000, 9000), 0.0, asphalt)
	else:
		_build_island(asphalt)
	# Sidewalks: a concrete apron around the block at curb height.
	var walk := _ground_material("sidewalk", Color(0.36, 0.35, 0.33), 0.8, 4.0)
	var hx := BlockGen.BLOCK_HALF_X
	var hz := BlockGen.BLOCK_HALF_Z
	_slab(Vector2(-hx - 4.5, -hz - 4.5), Vector2(hx + 4.5, hz + 4.5), 0.12, walk)
	# The far side of each street gets a facing sidewalk strip so the streets
	# read as streets rather than as a void.
	_slab(Vector2(-hx - 40, -hz - BlockGen.STREET_WIDTH - 9), Vector2(hx + 40, -hz - BlockGen.STREET_WIDTH - 4.5), 0.12, walk)
	_slab(Vector2(-hx - 40, hz + BlockGen.AVENUE_WIDTH + 4.5), Vector2(hx + 40, hz + BlockGen.AVENUE_WIDTH + 9), 0.12, walk)
	_slab(Vector2(-hx - BlockGen.CROSS_STREET_WIDTH - 9, -hz - 40), Vector2(-hx - BlockGen.CROSS_STREET_WIDTH - 4.5, hz + 40), 0.12, walk)
	_slab(Vector2(hx + BlockGen.CROSS_STREET_WIDTH + 4.5, -hz - 40), Vector2(hx + BlockGen.CROSS_STREET_WIDTH + 9, hz + 40), 0.12, walk)

## Parks and water from the city plan. A park is mown ground aligned to its
## domain's grid; water is one reflective plane covering the half-plane
## beyond the (angled) shoreline.
## Distant mainland: low landmasses across the water on seeded bearings,
## with sparse low massing on top. They exist for the HORIZON — an island
## city whose ocean runs empty to the sky edge reads as a diorama, and the
## fog turns these into exactly the hazy far shore a real harbor has.
func _build_mainland() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(params["seed"]) + "/mainland")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for arc in range(rng.randi_range(2, 4)):
		var b0 := rng.randf_range(0.0, TAU)
		var span := rng.randf_range(0.5, 1.3)
		var r := rng.randf_range(5200.0, 7500.0)
		# Overlapping segments make a CONTINUOUS shore; gaps read as rafts.
		var step_b := 300.0 / r
		var b := b0
		while b < b0 + span:
			var c := Vector2(cos(b), sin(b)) * (r + rng.randf_range(-150.0, 150.0))
			var h := rng.randf_range(10.0, 30.0)
			if rng.randf() < 0.1:
				h = rng.randf_range(40.0, 110.0)   # a far town's own towers
			# Land albedo, not concrete: dark enough to silhouette in haze.
			st.set_color(Color(0.16, 0.165, 0.16) * rng.randf_range(0.85, 1.15))
			_mainland_box(st, c, Vector2(rng.randf_range(500.0, 800.0),
					rng.randf_range(400.0, 900.0)), b + PI * 0.5, h)
			b += step_b
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	# Flat dark land albedo. Vertex colors reach the shader through an
	# sRGB conversion that brightened them (same lesson as the trees), and
	# per-box variation is invisible in haze anyway.
	m.albedo_color = Color(0.14, 0.15, 0.14)
	m.roughness = 1.0
	m.metallic_specular = 0.0
	mi.material_override = m
	add_child(mi)

func _mainland_box(st: SurfaceTool, c: Vector2, size: Vector2, ang: float, h: float) -> void:
	var u := Vector2(cos(ang), sin(ang)) * size.x * 0.5
	var v := Vector2(-sin(ang), cos(ang)) * size.y * 0.5
	var pts := [c - u - v, c + u - v, c + u + v, c - u + v]
	var top := []
	for p in pts:
		top.append(Vector3(p.x, h, p.y))
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(Vector2.ZERO)
		st.add_vertex(top[i])
	for i in range(4):
		var a: Vector3 = top[i]
		var b: Vector3 = top[(i + 1) % 4]
		var a0 := Vector3(a.x, -3.0, a.z)
		var b0 := Vector3(b.x, -3.0, b.z)
		for q in [b, a, a0, b, a0, b0]:
			st.set_uv(Vector2.ZERO)
			st.add_vertex(q)

## The island: a radial fan of ground following the coastline, its rim just
## past the esplanade, and a skirt dropping below the waterline so the city
## stands out of the harbor on a real edge. 2 deg steps keep the rim smooth
## against the lobed limit curve.
func _build_island(top_mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_land_fan(st, Vector2.ZERO, func(b: float) -> float:
		return _plan.city_limit(b) + 6.0, 180)
	for islet in _plan.islets:
		_land_fan(st, islet["center"] as Vector2, func(b: float) -> float:
			return _plan.islet_limit(islet, b) + 6.0, 72)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = top_mat
	add_child(mi)

## One land mass: radial ground fan + skirt down past the waterline.
func _land_fan(st: SurfaceTool, c: Vector2, limit_fn: Callable, steps: int) -> void:
	var center := Vector3(c.x, 0.0, c.y)
	for i in range(steps):
		var b0 := TAU * float(i) / float(steps)
		var b1 := TAU * float(i + 1) / float(steps)
		var r0: float = limit_fn.call(b0)
		var r1: float = limit_fn.call(b1)
		var p0 := center + Vector3(cos(b0) * r0, 0.0, sin(b0) * r0)
		var p1 := center + Vector3(cos(b1) * r1, 0.0, sin(b1) * r1)
		for q in [center, p0, p1]:
			st.set_uv(Vector2(q.x, q.z))
			st.add_vertex(q)
		# Skirt: rim down to -4 m; the strip above the waterline reads as
		# the seawall's wet concrete base.
		var d0 := p0 + Vector3(0, -4.0, 0)
		var d1 := p1 + Vector3(0, -4.0, 0)
		for q in [p1, p0, d0, p1, d0, d1]:
			st.set_uv(Vector2(q.x + q.z, q.y))
			st.add_vertex(q)

## Road paint: aged white thermoplastic, not pure white — fresh paint is
## ~0.75 reflectance and city paint weathers well below that.
func _paint_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.61, 0.58)
	m.roughness = 0.75
	return m

func _grass_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.37, 0.24)
	m.roughness = 1.0
	return m

func _build_plan_features(plan: CityPlan) -> void:
	var grass := _grass_material()
	for pk in plan.parks:
		_slab_rot(pk["center"], Vector2(float(pk["w"]) + 6.0, float(pk["d"]) + 6.0),
				float(pk["angle"]), 0.10, grass)
	# Harbor: water everywhere beyond the island, top at -1.5 m so the
	# island's skirt shows ~1.5 m of seawall base above the waterline.
	var water := ShaderMaterial.new()
	water.shader = preload("res://src/city/water.gdshader")
	var wmi := MeshInstance3D.new()
	var wbox := BoxMesh.new()
	wbox.size = Vector3(26000.0, 0.3, 26000.0)
	wmi.mesh = wbox
	wmi.material_override = water
	wmi.position = Vector3(0.0, -1.65, 0.0)
	add_child(wmi)
	_build_mainland()
	# The city meets its water on a built edge: an esplanade ring at curb
	# height with a seawall lip, segmented around the whole coastline.
	var walk := _ground_material("sidewalk", Color(0.36, 0.35, 0.33), 0.8, 4.0)
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.42, 0.40, 0.37)   # weathered harbor concrete
	wall.roughness = 0.9
	var steps := 120
	var prng := RandomNumberGenerator.new()
	prng.seed = hash(str(params["seed"]) + "/piers")
	var deck := StandardMaterial3D.new()
	deck.albedo_color = Color(0.16, 0.14, 0.12)   # tarred timber deck
	deck.roughness = 0.95
	for i in range(steps):
		var b := TAU * (float(i) + 0.5) / float(steps)
		var lim := plan.city_limit(b)
		var seg := lim * TAU / float(steps) + 4.0
		var tang := b + PI * 0.5
		var c := Vector2(cos(b), sin(b))
		_slab_rot(c * (lim - 14.0), Vector2(seg, 26.0), tang, 0.15, walk)
		_slab_rot(c * (lim - 1.0), Vector2(seg, 1.6), tang, 1.05, wall)
		# Piers: about a quarter of coastline segments grow one — a deck
		# running out into the harbor, sometimes with a transit shed. The
		# working edge a port city actually has.
		if prng.randf() < 0.28:  # main island only; islets stay residential
			var plen := prng.randf_range(60.0, 150.0)
			var pw := prng.randf_range(14.0, 30.0)
			var off := prng.randf_range(-0.3, 0.3) * seg
			var pc: Vector2 = c * (lim + plen * 0.5 - 4.0) \
					+ Vector2(cos(tang), sin(tang)) * off
			_slab_rot(pc, Vector2(pw, plen), b, 0.5, deck)
			if prng.randf() < 0.5:
				var shed := StandardMaterial3D.new()
				shed.albedo_color = Color(0.30, 0.28, 0.26) * prng.randf_range(0.8, 1.2)
				shed.roughness = 0.9
				_slab_rot(pc, Vector2(pw * 0.7, plen * prng.randf_range(0.4, 0.7)),
						b, prng.randf_range(5.0, 9.0), shed)
	for islet in plan.islets:
		var isteps := 48
		var ic: Vector2 = islet["center"]
		for i in range(isteps):
			var b := TAU * (float(i) + 0.5) / float(isteps)
			var lim: float = plan.islet_limit(islet, b)
			var seg := lim * TAU / float(isteps) + 3.0
			var tang := b + PI * 0.5
			var c := Vector2(cos(b), sin(b))
			_slab_rot(ic + c * (lim - 11.0), Vector2(seg, 20.0), tang, 0.15, walk)
			_slab_rot(ic + c * (lim - 1.0), Vector2(seg, 1.4), tang, 1.05, wall)

## A slab centered at `center` with plan-frame X size size.x / Z size size.y,
## turned by `angle` (the plan's rotation convention: local +X maps to world
## (cos angle, sin angle) in the XZ plane).
func _slab_rot(center: Vector2, size: Vector2, angle: float, top_y: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, maxf(top_y, 0.02), size.y)
	mi.mesh = box
	mi.material_override = mat
	mi.rotation.y = -angle
	mi.position = Vector3(center.x, maxf(top_y, 0.02) * 0.5 - 0.011, center.y)
	add_child(mi)

func _slab(a: Vector2, b: Vector2, top_y: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(b.x - a.x, maxf(top_y, 0.02), b.y - a.y)
	mi.mesh = box
	mi.material_override = mat
	mi.position = Vector3((a.x + b.x) * 0.5, maxf(top_y, 0.02) * 0.5 - 0.011, (a.y + b.y) * 0.5)
	add_child(mi)

func _build_block() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params["seed"])
	var lots := BlockGen.generate(rng)
	var only: String = str(params.get("only_lot", ""))
	if only != "":
		var filtered := []
		for l in lots:
			if l["id"] == only:
				filtered.append(l)
		lots = filtered
	var textures := _matlib
	var counts := {}
	for lot in lots:
		# Give each building its own RNG derived from the block seed and lot
		# id, so a change to one building's rules cannot reshuffle the others.
		var brng := RandomNumberGenerator.new()
		brng.seed = hash(str(params["seed"]) + "/" + lot["id"])
		var b := Grammar.build(lot, brng)
		add_child(MeshBuilder.building_node(b, textures))
		for prop in b["props"]:
			if prop["type"] == "plaza":
				var r: Dictionary = prop["rect"]
				_slab(Vector2(r["x0"], r["z0"]), Vector2(r["x1"], r["z1"]), 0.14,
						MeshBuilder.plaza_material())
		counts[lot["era"]] = counts.get(lot["era"], 0) + 1
	print("[plat] block: ", counts, " (", lots.size(), " buildings, seed ", params["seed"], ")")

## Assets have TWO homes: raw files on disk in the dev sandbox (fetched by
## tools/fetch-assets.sh, loadable only by absolute path) and imported
## resources inside the PCK of an exported build (loadable only through
## ResourceLoader). A packaged build that reads raw paths finds nothing —
## proven by running the first export, which came up with no materials and
## a flat fallback sky. These two helpers try the resource path first and
## fall back to the raw file, so one code path serves both.
static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			var tex := res as Texture2D
			# Godot imports images with mipmaps OFF by default, and the raw
			# path this replaced called generate_mipmaps() by hand. Without
			# them every facade aliases into sparkle at distance — a real
			# regression, caught by the perceptual gate (mean 5.57 vs 3.0)
			# rather than by anyone eyeballing a packaging change.
			var im := tex.get_image()
			if im != null and not im.has_mipmaps():
				im.generate_mipmaps()
				return ImageTexture.create_from_image(im)
			return tex
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	return null

static func _load_image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			return (res as Texture2D).get_image()
		if res is Image:
			return res as Image
	if FileAccess.file_exists(path):
		return Image.load_from_file(path)
	return null

## Load every fetched material set: materials/<slot>/{albedo,normal,ao[,roughness]}.
## A slot missing its core maps is dropped (callers fall back per-slot).
func _load_material_library() -> Dictionary:
	var lib := {}
	# res:// works in the editor AND inside an exported PCK; the globalized
	# path only works in the sandbox.
	var root_dir := DirAccess.open(ASSET_DIR + "/materials")
	if root_dir == null:
		push_warning("no material library — run tools/fetch-assets.sh")
		return lib
	for slot in root_dir.get_directories():
		var out := {}
		for key in ["albedo", "normal", "ao", "roughness"]:
			var path: String = ASSET_DIR + "/materials/" + slot + "/" + key + ".jpg"
			var tex := _load_texture(path)
			if tex != null:
				out[key] = tex
		if out.has("albedo") and out.has("normal") and out.has("ao"):
			lib[slot] = out
	if lib.is_empty():
		push_warning("material library empty — run tools/fetch-assets.sh")
	return lib

## Ground material: scan-textured when the slot exists (triplanar, world
## scale, so BoxMesh slabs need no UVs), flat color otherwise.
func _ground_material(slot: String, fallback: Color, rough: float, coverage_m: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex: Dictionary = _matlib.get(slot, {})
	if tex.has("albedo"):
		m.albedo_texture = tex["albedo"]
		# Scans are captured clean; street asphalt runs darker than a fresh
		# scan in every real aerial photo. Modulate rather than repaint.
		# Scans are captured clean and lit flat. Street asphalt runs darker
		# than a fresh scan in every real aerial photo, and city sidewalk
		# concrete sits near 0.35 albedo, not the ~0.55 of a clean scan —
		# undimmed, the walks blew out to white at the mid band.
		m.albedo_color = Color(0.55, 0.55, 0.57) if slot == "asphalt" \
				else (Color(0.62, 0.61, 0.59) if slot == "sidewalk" else Color.WHITE)
		m.normal_enabled = true
		m.normal_texture = tex["normal"]
		m.ao_enabled = true
		m.ao_texture = tex["ao"]
		if tex.has("roughness"):
			m.roughness_texture = tex["roughness"]
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE / coverage_m
		m.roughness = 1.0 if tex.has("roughness") else rough
	else:
		m.albedo_color = fallback
		m.roughness = rough
	return m

func describe() -> String:
	return "seed=%s date=%04d-%02d-%02d time=%05.2f sun_az=%.1f sun_el=%.1f sky_delta=%.1f %s" % [
		str(params["seed"]), params["year"], params["month"], params["day"],
		params["time"], sun_info["azimuth_deg"], sun_info["elevation_deg"],
		sky_sun_delta_deg, rig.describe()]
