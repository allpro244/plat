extends Node3D
## Interactive entry point — the playable viewer.
##
## The camera contract is not relaxed for interactive use: this drives the
## same CameraRig the headless shots use, so every orbit, zoom and band
## change is clamped by data/camera_bands.json. There is no free-fly, by
## construction (CLAUDE.md: the contract is load-bearing).
##
## Controls
## Movement is the Broadway-and-Wall map scheme (it was a MapLibre map):
##   left-drag ....... grab the ground and PAN — the city slides with you
##   right-drag ...... rotate (x) and tilt via height (y)
##   wheel ........... zoom toward the city (clamped to the band)
##   arrows .......... pan, like a map's keyboard controls
##   1 2 3 ........... near / mid / far band     C ....... re-centre downtown
##   T / G ........... time of day               N ....... new city
##   R rebuild   F preset views   H help   F12 screenshot   Esc quit
## Every move eases in (exponential approach), so it glides like easeTo
## instead of snapping — that glide was most of the old map's feel.
##
## Panning the TARGET is not free-fly: the camera still orbits that target
## inside its height band — a helicopter, not a noclip camera. Every band
## guarantee holds.
##
## Rebuilding a city is ~1-3 s of single-threaded generation, so the HUD
## says so and the frame is yielded before the work starts — otherwise the
## window looks hung.

const ROTATE_SENSITIVITY := 0.32   # deg per pixel, right-drag x
const TILT_SENSITIVITY := 0.9      # metres of height per pixel, right-drag y
const WHEEL_STEP := 0.1            # fraction of current radius per notch
const KEY_PAN := 0.5               # multiples of radius per second, arrows
## Exponential approach rate for the easeTo glide. ~8/s reaches 92% of a
## move in 300 ms — the pace of the old map's default ease.
const EASE := 8.0

var city: CityScene
var seed_value := 1928
var az := 225.0
var height := 120.0
var radius := 215.0
var band := "near"
var time_of_day := 15.5
var _hud: Label
var _help_visible := true
var _busy := false
var _panning := false
var _rotating := false
var _fps_accum := 0.0
var _fps_frames := 0
var _fps := 0.0
var _selftest := false
var _target := Vector2.ZERO      # orbit centre, world XZ (eased, applied)
# Goal state: inputs write here; _process eases the applied state toward it.
var _g_az := 225.0
var _g_height := 120.0
var _g_radius := 215.0
var _g_target := Vector2.ZERO

## Engine cities shipped inside the build: each is a whole island the
## economy generated (coast, parcels, classes, years, occupancy), rendered
## by plat. `E` cycles them; `N` returns to plat's own generator.
const ENGINE_CITIES := [
	"data/city-1928.json",   # Port Tarrstead — harbour bight, wedge park
	"data/city-777.json",    # Caldwich — twin parks, wide avenues
	"data/city-31337.json",  # Ashdon Island — headland tower cluster
	"data/city-8080.json",   # Salgate Island — broad, five parks
	"data/city-12345.json",  # Rookwich — dense old-town knot
	"data/city-222.json",    # Eskthorpe Reach — three parks down the spine
	"data/city-6060.json",   # New Presstone — Y-fork of diagonals
	"data/city-4711.json",   # Wendworth Point — one supertall over the park
	"data/city-90210.json",  # Eskley Point — rectangular central park
]
var _engine_pick := -1

var _city_file := ""       # a plat-city/1 export; when set, the viewer plays it
var _campaign_dir := ""    # a game-server campaign; when set, plat IS the game view
var _hud_game := {}        # firm/date/cash from the campaign's hud.json

func _ready() -> void:
	_selftest = "--selftest" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--city="):
			_city_file = a.substr(7)
		elif a.begins_with("--campaign="):
			_campaign_dir = a.substr(11).rstrip("/")
			_city_file = _campaign_dir + "/city.json"
			_load_game_hud()
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)
	_hud.text = "generating city..."
	await get_tree().process_frame
	_rebuild()

func _rebuild() -> void:
	_busy = true
	_hud.text = "generating city (seed %d)..." % seed_value
	# Let the HUD paint before the generation stalls the frame.
	await get_tree().process_frame
	await get_tree().process_frame
	if city:
		remove_child(city)
		city.queue_free()
	var t0 := Time.get_ticks_msec()
	# GI off in the INTERACTIVE viewer, on for stills. SDFGI accumulates
	# temporally — parked cameras converge to a clean image, but in flight
	# the cascades re-converge forever, which reads as a smeared, blotchy
	# distortion crawling over distant buildings (owner-reported). The
	# non-GI ambient path is calibrated for exactly this fallback.
	var params := {"seed": seed_value, "time": time_of_day, "gi": false}
	if _city_file != "":
		params["city"] = _city_file
	city = CityScene.new(params)
	add_child(city)
	city.rig.set_band(band)
	_snap()
	print("[plat] built seed %d in %d ms" % [seed_value, Time.get_ticks_msec() - t0])
	_busy = false
	if _selftest:
		await _run_selftest()

## Headless proof that the interactive path works: exercise every control,
## save a frame, quit. This is how an interactive scene gets the same
## "verified by render" treatment as the still pipeline.
func _run_selftest() -> void:
	# One run only: the campaign-advance step below rebuilds the city, and a
	# rebuild re-entering the selftest would loop forever.
	_selftest = false
	for step in [["pan", func() -> void: _pan_pixels(-400.0, 300.0)],
			["recentre", func() -> void: _g_target = city._plan.core_center \
					if city._plan != null else Vector2.ZERO],
			["orbit", func() -> void: _orbit(45.0)],
			["dolly", func() -> void: _dolly(30.0)],
			["height", func() -> void: _height(25.0)],
			["band mid", func() -> void: _set_band("mid")],
			["band far", func() -> void: _set_band("far")],
			["band near", func() -> void: _set_band("near")]]:
		(step[1] as Callable).call()
		_snap()
		await get_tree().process_frame
		print("[plat] selftest %s -> %s" % [step[0], city.rig.describe()])
	if _campaign_dir != "":
		# The game loop itself, once: sim advances in node, city rebuilds.
		var before := str(_hud_game.get("date", "?"))
		await _advance_campaign(3)
		while _busy:
			await get_tree().process_frame
		print("[plat] selftest campaign advance: %s -> %s" % [
				before, str(_hud_game.get("date", "?"))])
	for i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://renders/playable_selftest.png")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("[plat] selftest OK -> ", out)
	get_tree().quit(0)

# --- camera moves, all through the clamping rig --------------------------
# Inputs write GOALS; _process eases the applied state toward them, which
# is what turns every move into a glide.

func _orbit(d: float) -> void:
	_g_az += d

func _dolly(d: float) -> void:
	_g_radius += d

func _height(d: float) -> void:
	_g_height += d

func _set_band(b: String) -> void:
	band = b
	city.rig.set_band(b)
	_push()

## Snap applied state to goals instantly (rebuilds, selftest determinism).
func _snap() -> void:
	az = _g_az
	height = _g_height
	radius = _g_radius
	_target = _g_target
	_push()

func _push() -> void:
	if city and city.rig:
		city.rig.set_target_xz(_target.x, _target.y)
		city.rig.set_view(az, height, radius)

## Grab-the-ground pan: a drag of (dx, dy) screen pixels slides the city so
## the ground tracks the cursor. Metres-per-pixel comes from the current
## radius and the camera's vertical FOV over the viewport height.
func _pan_pixels(dx: float, dy: float) -> void:
	var vp_h := float(get_viewport().get_visible_rect().size.y)
	var mpp := 2.0 * radius * tan(deg_to_rad(37.5)) / maxf(vp_h, 1.0)
	var a := deg_to_rad(az)
	var fwd := Vector2(-sin(a), cos(a))     # inward, toward the target
	var right := Vector2(cos(a), sin(a))
	_g_target += (right * -dx + fwd * dy) * mpp
	var limit := 2600.0
	if city and city._plan != null:
		limit = city._plan.city_limit(atan2(_g_target.y, _g_target.x)) + 400.0
	elif city and city._import != null:
		limit = city._import.radius_max + 400.0
	if _g_target.length() > limit:
		_g_target = _g_target.normalized() * limit

func _process(delta: float) -> void:
	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum > 0.5:
		_fps = float(_fps_frames) / _fps_accum
		_fps_accum = 0.0
		_fps_frames = 0
	if _busy:
		return
	# Arrow keys pan, like a map's keyboard controls.
	var vp := get_viewport().get_visible_rect().size
	var px := KEY_PAN * vp.y * delta
	if Input.is_key_pressed(KEY_LEFT):
		_pan_pixels(-px, 0.0)
	if Input.is_key_pressed(KEY_RIGHT):
		_pan_pixels(px, 0.0)
	if Input.is_key_pressed(KEY_UP):
		_pan_pixels(0.0, -px)
	if Input.is_key_pressed(KEY_DOWN):
		_pan_pixels(0.0, px)
	if Input.is_key_pressed(KEY_PAGEUP):
		_height(90.0 * delta)
	if Input.is_key_pressed(KEY_PAGEDOWN):
		_height(-90.0 * delta)
	# The easeTo glide: applied state approaches the goal exponentially.
	var t := 1.0 - exp(-EASE * delta)
	az = lerpf(az, _g_az, t)
	height = lerpf(height, _g_height, t)
	radius = lerpf(radius, _g_radius, t)
	_target = _target.lerp(_g_target, t)
	_push()
	# The rig clamped what we pushed; pull the clamp back into the goals so
	# they cannot run away past a band edge while the user keeps dragging.
	_g_height = clampf(_g_height, height - 200.0, height + 200.0)
	_g_radius = clampf(_g_radius, radius - 400.0, radius + 400.0)
	_update_hud()

func _load_game_hud() -> void:
	var txt := FileAccess.get_file_as_string(_campaign_dir + "/hud.json")
	var doc: Variant = JSON.parse_string(txt) if not txt.is_empty() else null
	_hud_game = doc if doc is Dictionary else {}

## Advance the CAMPAIGN: the simulation runs in node (the engine repo's
## game-server), plat re-reads the files it wrote and rebuilds. The sim owns
## the quantities; this view never computes one.
func _advance_campaign(months: int) -> void:
	if _busy or _campaign_dir == "":
		return
	_busy = true
	_hud.text = "advancing %d months (simulation runs in node)..." % months
	await get_tree().process_frame
	await get_tree().process_frame
	var meta: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(_campaign_dir + "/campaign.json"))
	var runner := str((meta as Dictionary).get("runner", "")) if meta is Dictionary else ""
	var out := []
	var code := OS.execute("node", [runner, "advance", "--dir=" + _campaign_dir,
			"--months=%d" % months], out, true)
	_busy = false
	if code != 0 or runner == "":
		_hud.text = "advance FAILED (%d): %s" % [code, "".join(out).right(200)]
		return
	_load_game_hud()
	_rebuild()

func _update_hud() -> void:
	if city == null or city.rig == null:
		return
	var plan_line := ""
	if city._plan != null:
		plan_line = "\n%s" % city._plan.describe().replace("plan ", "")
	elif city._import != null:
		plan_line = "\n%s — engine city (%d buildings)" % [city._import.name,
				city._import.buildings.size()]
	var help := ""
	if _help_visible:
		if _campaign_dir != "":
			help = "\n\nSPACE advance a season (the simulation decides what changed)"
		help += ("\n\ndrag/arrows orbit   wheel/up-down dolly   PgUp/PgDn height"
				+ "\nleft-drag pan   right-drag rotate/tilt   wheel zoom"
				+ "\narrows pan   PgUp/PgDn height   C re-centre downtown"
				+ "\n1 2 3 band   T/G time   N new city   E engine city   F preset view"
				+ "\nH help   F12 screenshot   Esc quit")
	var game_line := ""
	if not _hud_game.is_empty():
		game_line = "\nPLAT — %s | %s | %s | cash $%.2fM | %d holdings%s" % [
				str(_hud_game.get("firm", "?")), str(_hud_game.get("city", "?")),
				str(_hud_game.get("date", "?")), float(_hud_game.get("cash", 0)) / 1e6,
				int(_hud_game.get("holdings", 0)),
				"" if _hud_game.get("occ") == null else " | occ %.0f%%" % (float(_hud_game.get("occ", 0)) * 100.0)]
	_hud.text = "plat — %.0f fps | %s | at (%.0f, %.0f) | %02d:%02d%s%s%s" % [
			_fps, city.rig.describe(), _target.x, _target.y, int(time_of_day),
			int(fposmod(time_of_day, 1.0) * 60.0), game_line, plan_line, help]

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_rotating = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dolly(-_g_radius * WHEEL_STEP)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dolly(_g_radius * WHEEL_STEP)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			_pan_pixels(mm.relative.x, mm.relative.y)
		elif _rotating:
			_orbit(mm.relative.x * ROTATE_SENSITIVITY)
			_height(-mm.relative.y * TILT_SENSITIVITY)
	elif event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_1: _set_band("near")
			KEY_2: _set_band("mid")
			KEY_3: _set_band("far")
			KEY_T:
				time_of_day = clampf(time_of_day + 0.5, 4.0, 22.0)
				_rebuild()
			KEY_G:
				time_of_day = clampf(time_of_day - 0.5, 4.0, 22.0)
				_rebuild()
			KEY_N:
				# A new city every time, and the seed is printed so any
				# city you like can be reproduced exactly. From an imported
				# city, N returns to plat's own generator — new ENGINE
				# cities are minted by the exporter, not a keypress.
				_city_file = ""
				_engine_pick = -1
				seed_value = randi() % 100000
				_rebuild()
			KEY_R:
				_rebuild()
			KEY_C:
				# Back to downtown — easy to get lost on a 5 km island.
				_g_target = Vector2.ZERO
				if city and city._plan != null:
					_g_target = city._plan.core_center
			KEY_F:
				_cycle_preset()
			KEY_H:
				_help_visible = not _help_visible
			KEY_F12:
				_screenshot()
			KEY_E:
				# Cycle the ENGINE cities shipped with the build: islands
				# the economy generated, with its parcels, classes, years
				# and occupancy. N stays plat's own generator.
				if _campaign_dir == "":
					_engine_pick = (_engine_pick + 1) % ENGINE_CITIES.size()
					_city_file = ENGINE_CITIES[_engine_pick]
					_g_target = Vector2.ZERO
					_snap()
					_rebuild()
			KEY_SPACE:
				# The game key: a season passes, the sim decides what
				# changed, the city rebuilds to show it.
				_advance_campaign(3)
			KEY_ESCAPE:
				get_tree().quit()

var _preset := 0

## Three framings worth looking at, one per band — the same views the
## reference renders use.
func _cycle_preset() -> void:
	_preset = (_preset + 1) % 3
	match _preset:
		0:
			band = "near"
			_g_az = 200.0
			_g_height = 140.0
			_g_radius = 240.0
		1:
			band = "mid"
			_g_az = 100.0
			_g_height = 420.0
			_g_radius = 880.0
		2:
			band = "far"
			_g_az = 20.0
			_g_height = 1150.0
			_g_radius = 1900.0
	city.rig.set_band(band)

func _screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "user://plat_%d_%s.png" % [seed_value, city.rig.band_name()]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[plat] screenshot -> ", ProjectSettings.globalize_path(path))
