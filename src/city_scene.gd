class_name CityScene
extends Node3D
## Assembles the whole world from a parameter dictionary: environment + HDRI
## sky, sun from real solar position, ground plane, the generated block, and
## the banded camera rig. Everything stochastic flows from params.seed —
## nothing in here is hand-placed.

const ASSET_DIR := "res://assets/downloaded"

var params: Dictionary
var rig: CameraRig
var sun_info: Dictionary

static func defaults() -> Dictionary:
	return {
		"seed": 1928,
		# Place and moment. NYC City Hall latitude; a June evening — low warm
		# sun from the west-northwest, matching the pinned low-sun sky HDRI.
		"latitude": 40.7128, "longitude": -74.0060, "utc_offset": -4.0,
		"year": 2026, "month": 6, "day": 21, "time": 18.75,
		"band": "near", "cam_azimuth": 222.0, "cam_height": 135.0, "cam_radius": 190.0,
	}

func _init(p: Dictionary = {}) -> void:
	params = defaults()
	params.merge(p, true)

func _ready() -> void:
	_build_environment()
	_build_sun()
	_build_ground()
	_build_block()
	rig = CameraRig.new()
	add_child(rig)
	rig.set_band(params["band"])
	rig.set_view(params["cam_azimuth"], params["cam_height"], params["cam_radius"])

func _build_environment() -> void:
	var env := Environment.new()
	var hdri_path := ASSET_DIR + "/sky/sky.hdr"
	var sun := SunPosition.compute(params["year"], params["month"], params["day"],
			params["time"], params["latitude"], params["longitude"], params["utc_offset"])
	sun_info = sun
	if FileAccess.file_exists(hdri_path):
		var img := Image.load_from_file(hdri_path)
		var sky_tex := ImageTexture.create_from_image(img)
		var sky_mat := PanoramaSkyMaterial.new()
		sky_mat.panorama = sky_tex
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		# Rotate the panorama so its baked sun sits at the computed azimuth.
		# The HDRI's own sun azimuth is measured from the image (brightest
		# texel), so this stays true for any sky the fetch script pins.
		var baked_az := _measure_hdri_sun_azimuth(img)
		env.sky_rotation = Vector3(0.0, deg_to_rad(baked_az - sun["azimuth_deg"]), 0.0)
	else:
		push_warning("HDRI missing — run tools/fetch-assets.sh. Falling back to flat sky.")
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.55, 0.70, 0.85)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.6, 0.7, 0.8)
		env.ambient_light_energy = 1.0
	# Distance haze: softens the HDRI horizon and gives the skyline depth.
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.78, 0.82)
	env.fog_density = 0.00012
	env.fog_sky_affect = 0.22
	env.fog_aerial_perspective = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_intensity = 2.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

## Find the brightest texel of the panorama at reduced resolution and return
## its azimuth in this project's convention (0 = north = -Z, clockwise),
## for a panorama u=0 at azimuth 180 (Godot maps u=0.5 to -Z).
func _measure_hdri_sun_azimuth(img: Image) -> float:
	var probe: Image = img.duplicate()
	probe.resize(256, 128, Image.INTERPOLATE_BILINEAR)
	var best := -1.0
	var best_x := 0
	for y in range(0, 64):  # sun is in the upper half
		for x in range(256):
			var c := probe.get_pixel(x, y)
			var lum := c.r + c.g + c.b
			if lum > best:
				best = lum
				best_x = x
	return fposmod((float(best_x) / 256.0) * 360.0 + 180.0, 360.0)

func _build_sun() -> void:
	var el: float = sun_info["elevation_deg"]
	var az: float = sun_info["azimuth_deg"]
	var light := DirectionalLight3D.new()
	add_child(light)
	var dir := SunPosition.sun_direction(az, el)
	light.look_at_from_position(dir * 500.0, Vector3.ZERO)
	# Direct solar illuminance falls with air mass as the sun drops; this
	# smooth ramp approximates the Kasten-Young air-mass curve well inside
	# the tonemapper's precision at aerial distances.
	light.light_energy = clampf(sin(deg_to_rad(maxf(el, 0.0))) * 1.6, 0.0, 1.5)
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
	var names := {"albedo": "albedo.jpg", "normal": "normal.jpg", "ao": "ao.jpg"}
	for key in names:
		var path: String = dir + "/" + names[key]
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			img.generate_mipmaps()
			out[key] = ImageTexture.create_from_image(img)
	if out.size() < 3:
		push_warning("brick PBR set incomplete — run tools/fetch-assets.sh")
		return {}
	return out

func describe() -> String:
	return "seed=%s date=%04d-%02d-%02d time=%05.2f sun_az=%.1f sun_el=%.1f %s" % [
		str(params["seed"]), params["year"], params["month"], params["day"],
		params["time"], sun_info["azimuth_deg"], sun_info["elevation_deg"],
		rig.describe()]
