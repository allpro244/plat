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
		# Camera azimuth sits ~115 deg off the evening sun so shadows rake
		# ACROSS the frame. A down-sun view hides every shadow behind its
		# caster — learned by chasing "broken" shadows that were merely
		# pointed away from the lens.
		"band": "near", "cam_azimuth": 155.0, "cam_height": 120.0, "cam_radius": 195.0,
		"gi": false,
	}

func _init(p: Dictionary = {}) -> void:
	params = defaults()
	params.merge(p, true)

func _ready() -> void:
	_build_environment()
	_build_sun()
	_build_ground()
	MeshBuilder.plain_materials = params.get("plain_mats", false)
	MeshBuilder.skip_windows = params.get("skip_windows", false)
	MeshBuilder.skip_props = params.get("skip_props", false)
	if not params.get("no_block", false):
		_build_block()
	if not params.get("no_context", false):
		add_child(ContextGen.build(int(params["seed"])))
	rig = CameraRig.new()
	add_child(rig)
	rig.set_band(params["band"])
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
	var img: Image = null
	if FileAccess.file_exists(hdri_path):
		img = Image.load_from_file(hdri_path)
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
	# The pinned sky is a rural field, so its ground half bounces green-brown
	# into every shadow — wrong context for a street canyon, where bounce
	# comes off masonry and asphalt. Blend the sky ambient toward neutral to
	# correct the cast; goes away entirely once an urban-horizon sky is pinned.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.72
	env.ambient_light_color = Color(0.72, 0.72, 0.74)
	env.ambient_light_energy = 0.55
	# Distance haze: softens the HDRI horizon and gives the skyline depth.
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.78, 0.82)
	env.fog_density = 0.00009
	env.fog_sky_affect = 0.22
	env.fog_aerial_perspective = 0.6
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
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.12
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
	light.directional_shadow_max_distance = 800.0
	light.shadow_bias = 0.05

func _build_ground() -> void:
	# Streets: one large asphalt plane under everything.
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.21, 0.21, 0.215)
	asphalt.roughness = 0.92
	_slab(Vector2(-800, -800), Vector2(800, 800), 0.0, asphalt)
	# Sidewalks: a concrete apron around the block at curb height.
	var walk := StandardMaterial3D.new()
	walk.albedo_color = Color(0.44, 0.43, 0.41)
	walk.roughness = 0.8
	var hx := BlockGen.BLOCK_HALF_X
	var hz := BlockGen.BLOCK_HALF_Z
	_slab(Vector2(-hx - 4.5, -hz - 4.5), Vector2(hx + 4.5, hz + 4.5), 0.12, walk)
	# The far side of each street gets a facing sidewalk strip so the streets
	# read as streets rather than as a void.
	_slab(Vector2(-hx - 40, -hz - BlockGen.STREET_WIDTH - 9), Vector2(hx + 40, -hz - BlockGen.STREET_WIDTH - 4.5), 0.12, walk)
	_slab(Vector2(-hx - 40, hz + BlockGen.AVENUE_WIDTH + 4.5), Vector2(hx + 40, hz + BlockGen.AVENUE_WIDTH + 9), 0.12, walk)
	_slab(Vector2(-hx - BlockGen.CROSS_STREET_WIDTH - 9, -hz - 40), Vector2(-hx - BlockGen.CROSS_STREET_WIDTH - 4.5, hz + 40), 0.12, walk)
	_slab(Vector2(hx + BlockGen.CROSS_STREET_WIDTH + 4.5, -hz - 40), Vector2(hx + BlockGen.CROSS_STREET_WIDTH + 9, hz + 40), 0.12, walk)

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
	var textures := _load_wall_textures()
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

func _load_wall_textures() -> Dictionary:
	var dir := ASSET_DIR + "/brick"
	var out := {}
	var names := {"albedo": "albedo.jpg", "normal": "normal.jpg", "ao": "ao.jpg",
			"roughness": "roughness.jpg"}
	for key in names:
		var path: String = dir + "/" + names[key]
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			img.generate_mipmaps()
			out[key] = ImageTexture.create_from_image(img)
	# roughness.jpg only exists in the primary profile; the mirror set uses a
	# scalar (matte brick). Only the three core maps are required.
	if not (out.has("albedo") and out.has("normal") and out.has("ao")):
		push_warning("brick PBR set incomplete — run tools/fetch-assets.sh")
		return {}
	return out

func describe() -> String:
	return "seed=%s date=%04d-%02d-%02d time=%05.2f sun_az=%.1f sun_el=%.1f sky_delta=%.1f %s" % [
		str(params["seed"]), params["year"], params["month"], params["day"],
		params["time"], sun_info["azimuth_deg"], sun_info["elevation_deg"],
		sky_sun_delta_deg, rig.describe()]
