extends Node3D
## Interactive entry point — the playable viewer.
##
## Camera is free-flow (owner override, 2026-08). The height-band clamp is
## gone. Map mode is the Broadway-and-Wall / MapLibre scheme; V toggles a
## WASD free-fly that can go anywhere. Street-level fidelity is not a goal.
##
## Controls (map mode — MapLibre defaults)
##   left-drag ........... grab the ground and PAN
##   right-drag .......... rotate bearing (x) and tilt pitch (y)
##   ctrl+left-drag ...... same as right-drag
##   wheel ............... zoom toward the cursor
##   double-click ........ zoom in toward the click
##   arrows .............. pan
##   shift+arrows ........ rotate / tilt
##   compass (bottom-right) reset bearing to north; +/− zoom
##   1 2 3 ............... optional near / mid / far presets (not a clamp)
##   V ................... free-fly (WASD + RMB look + Q/E vertical)
##   C ................... re-centre downtown
##   T / G ............... time of day               N ....... new city
##   R rebuild   F preset views   H help   F12 screenshot   Esc quit
## Every move eases in (exponential approach), so it glides like easeTo
## instead of snapping — that glide was most of the old map's feel.

const ROTATE_SENSITIVITY := 0.32   # deg per pixel, right-drag x
const PITCH_SENSITIVITY := 0.22    # deg per pixel, right-drag y (MapLibre tilt)
const WHEEL_STEP := 0.12           # fraction of current distance per notch
const KEY_PAN := 0.5               # multiples of viewport per second, arrows
const KEY_TURN := 70.0             # deg/s, shift+arrows
const KEY_TILT := 40.0             # deg/s, shift+up/down
const FLY_LOOK := 0.12             # deg per pixel in free-fly
## Exponential approach rate for the easeTo glide. ~8/s reaches 92% of a
## move in 300 ms — the pace of the old map's default ease.
const EASE := 8.0

var city: CityScene
var seed_value := 1928
var bearing := 225.0
var pitch := 60.8
var distance := 246.0
var time_of_day := 15.5
var _ui: GameUi
var _compass: Button
var _press_pos := Vector2.ZERO   # to tell a click from a drag
var _selected: Dictionary = {}   # the building on the card
var _listing_pick := -1          # TAB cycles the for-sale tape
var _help_visible := false
var _busy := false
var _panning := false
var _rotating := false
var _grab: Variant = null        # ground point under cursor at pan-press
var _fps_accum := 0.0
var _fps_frames := 0
var _fps := 0.0
var _selftest := false
var _uishot := false
var _startshot := false
var _target := Vector2.ZERO      # orbit centre, world XZ (eased, applied)
# Goal state: inputs write here; _process eases the applied state toward it.
var _g_bearing := 225.0
var _g_pitch := 60.8
var _g_distance := 246.0
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
var _market_rows: Array = []
var _portfolio: Dictionary = {}
var _news: Dictionary = {}
var _economy: Dictionary = {}
var _debt: Dictionary = {}
var _books: Dictionary = {}

func _ready() -> void:
	_selftest = "--selftest" in OS.get_cmdline_user_args()
	_uishot = "--uishot" in OS.get_cmdline_user_args()
	_startshot = "--startshot" in OS.get_cmdline_user_args()
	# The game OPENS in an engine city: parcels, records, clickable
	# buildings. Launching into the renderer's own seeded testbed made
	# every click a no-op — the first thing the owner tried. N still
	# reaches the plat generator; --seed= forces it from the CLI.
	_engine_pick = 0
	_city_file = ENGINE_CITIES[0]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			_city_file = ""
			_engine_pick = -1
			seed_value = int(a.substr(7))
		elif a.begins_with("--city="):
			_city_file = a.substr(7)
		elif a.begins_with("--campaign="):
			_campaign_dir = a.substr(11).rstrip("/")
			_city_file = _campaign_dir + "/city.json"
			_load_game_hud()
	# Acceptance: `godot -- --selftest` must exercise the deal loop, not
	# just the viewer. Found a firm on seed 1928 when the caller did not
	# already pass --campaign=.
	if (_selftest or _uishot) and _campaign_dir == "" and not _startshot:
		_bootstrap_selftest_campaign()
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = GameUi.new()
	layer.add_child(_ui)
	_ui.advance_pressed.connect(func() -> void: _advance_campaign(1, false))
	_ui.year_pressed.connect(func() -> void: _advance_campaign(12, true))
	_ui.skip_pressed.connect(func() -> void: _advance_campaign(36, true))
	_ui.buy_pressed.connect(_buy_selected)
	_ui.listing_chosen.connect(_focus_listing)
	_ui.page_opened.connect(_on_page_opened)
	_ui.break_ground_pressed.connect(_break_ground_opts)
	_ui.continue_pressed.connect(_continue_campaign)
	_ui.close_parcel_pressed.connect(func() -> void:
		_selected = {}
		_ui.hide_parcel())
	_ui.lens_pressed.connect(_on_lens)
	_ui.attention_opened.connect(_on_attention)
	_build_nav_widget(layer)
	_ui.set_status("generating city...")
	await get_tree().process_frame
	await _rebuild()
	_refresh_resume()
	if _campaign_dir != "":
		_ui.set_playing(true)
		_load_desks()
	else:
		_ui.set_playing(false)

## MapLibre NavigationControl analogue: compass resets bearing; +/− zoom.
func _build_nav_widget(layer: CanvasLayer) -> void:
	var box := VBoxContainer.new()
	var vp := get_viewport().get_visible_rect().size
	box.position = Vector2(vp.x - 88, vp.y - 168)
	box.add_theme_constant_override("separation", 4)
	layer.add_child(box)
	_compass = Button.new()
	_compass.text = "N"
	_compass.tooltip_text = "Reset bearing to north"
	_compass.custom_minimum_size = Vector2(72, 48)
	_compass.add_theme_stylebox_override("normal", BwTheme.lens_btn())
	_compass.add_theme_stylebox_override("hover", BwTheme.lens_btn())
	_compass.add_theme_color_override("font_color", BwTheme.INK_DIM)
	_compass.add_theme_font_override("font", BwTheme.sans())
	_compass.pressed.connect(_reset_bearing)
	box.add_child(_compass)
	var zoom_in := Button.new()
	zoom_in.text = "+"
	zoom_in.tooltip_text = "Zoom in"
	zoom_in.custom_minimum_size = Vector2(72, 32)
	zoom_in.add_theme_stylebox_override("normal", BwTheme.lens_btn())
	zoom_in.add_theme_stylebox_override("hover", BwTheme.lens_btn())
	zoom_in.add_theme_color_override("font_color", BwTheme.INK_DIM)
	zoom_in.pressed.connect(func() -> void: _g_distance *= (1.0 - WHEEL_STEP * 2.0))
	box.add_child(zoom_in)
	var zoom_out := Button.new()
	zoom_out.text = "−"
	zoom_out.tooltip_text = "Zoom out"
	zoom_out.custom_minimum_size = Vector2(72, 32)
	zoom_out.add_theme_stylebox_override("normal", BwTheme.lens_btn())
	zoom_out.add_theme_stylebox_override("hover", BwTheme.lens_btn())
	zoom_out.add_theme_color_override("font_color", BwTheme.INK_DIM)
	zoom_out.pressed.connect(func() -> void: _g_distance *= (1.0 + WHEEL_STEP * 2.0))
	box.add_child(zoom_out)

func _reset_bearing() -> void:
	_g_bearing = 0.0
	if city and city.rig and city.rig.is_fly():
		city.rig.exit_fly()

func _rebuild() -> void:
	_busy = true
	_ui.set_status("generating city (seed %d)..." % seed_value)
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
	_snap()
	print("[plat] built seed %d in %d ms" % [seed_value, Time.get_ticks_msec() - t0])
	# A rebuild replaces every imported record. Re-bind the card to the same
	# BBL so a buy shows ★ YOURS instead of a stale FOR SALE line.
	var keep := str(_selected.get("bbl", ""))
	if keep != "" and city._import != null:
		var found := false
		for b in city._import.buildings:
			if str(b.get("bbl", "")) == keep:
				_show_card(b)
				found = true
				break
		if not found:
			_ui.hide_parcel()
	_busy = false
	if _selftest:
		await _run_selftest()
	elif _uishot:
		await _run_uishot()
	elif _startshot:
		await _run_startshot()

## Headless proof that the interactive path works: exercise the free-flow
## camera, the parcel card, a campaign advance and a buy, save frames, quit.
func _run_selftest() -> void:
	# One run only: the campaign-advance step below rebuilds the city, and a
	# rebuild re-entering the selftest would loop forever.
	_selftest = false
	# Camera proof: two framings the old band clamp would have rejected.
	# Street — closer than the old near floor (70 m / 130 m), aimed at the
	# downtown core so the frame is buildings, not the origin park.
	if city._import != null:
		_g_target = city._import.core
	_g_bearing = 200.0
	_g_pitch = 72.0
	_g_distance = 48.0
	_snap()
	for i in range(8):
		await get_tree().process_frame
	print("[plat] selftest camera street -> %s" % city.rig.describe())
	await _save_frame("renders/camera_street.png")
	# Aerial — past the old far ceiling (1200 m / 2600 m).
	_g_bearing = 40.0
	_g_pitch = 36.0
	_g_distance = 4200.0
	_snap()
	for i in range(8):
		await get_tree().process_frame
	print("[plat] selftest camera aerial -> %s" % city.rig.describe())
	await _save_frame("renders/camera_aerial.png")
	# Free-fly: leave the orbit, move, come back. Prints the fly pose.
	city.rig.enter_fly()
	city.rig.fly_input(Vector3(0.4, 0.3, -1.0), 180.0)
	print("[plat] selftest camera fly -> %s" % city.rig.describe())
	city.rig.exit_fly()
	# Back to a playable downtown framing for the card / deal loop.
	_g_bearing = 225.0
	_g_pitch = 58.0
	_g_distance = 280.0
	_g_target = Vector2.ZERO
	if city._import != null:
		_g_target = city._import.core
	_snap()
	await get_tree().process_frame
	print("[plat] selftest map -> %s" % city.rig.describe())
	if city._import != null and not city._import.buildings.is_empty():
		# Prove the parcel card: pick a real building through the camera.
		var cam := get_viewport().get_camera_3d()
		for b in city._import.buildings:
			if b["deco"] or float(b["z1"]) < 8.0 or not b["sqft"] > 0.0:
				continue
			var bb: Rect2 = b["bbox"]
			var c := bb.get_center()
			var world := Vector3(c.x, float(b["z1"]) * 0.5, c.y)
			if cam.is_position_behind(world):
				continue
			_pick_building(cam.unproject_position(world))
			if _ui.is_parcel_visible():
				print("[plat] selftest pick: ", _ui.parcel_debug_text())
				break
		if not _ui.is_parcel_visible():
			printerr("[plat] selftest pick FAILED: no building card")
	if _campaign_dir != "":
		# The game loop itself, once: sim advances in node, city rebuilds.
		var before := str(_hud_game.get("date", "?"))
		var cash_a := float(_hud_game.get("cash", 0))
		await _advance_campaign(1, false)
		while _busy:
			await get_tree().process_frame
		print("[plat] selftest campaign advance: %s $%.2fM -> %s $%.2fM" % [
				before, cash_a / 1e6,
				str(_hud_game.get("date", "?")), float(_hud_game.get("cash", 0)) / 1e6])
		# And a DEAL: buy the cheapest listed lot cash covers. Owners
		# overlay on so the bought lot's gold marker is in the frame.
		var cash0 := float(_hud_game.get("cash", 0))
		_pick_affordable_listing()
		if not _selected.is_empty():
			print("[plat] selftest listing: ", _ui.parcel_debug_text())
			ContextGen.overlay = "owners"
			await _buy_selected()
			while _busy:
				await get_tree().process_frame
			print("[plat] selftest buy: cash $%.2fM -> $%.2fM, holdings %d" % [
					cash0 / 1e6, float(_hud_game.get("cash", 0)) / 1e6,
					int(_hud_game.get("holdings", 0))])
			if _ui.is_parcel_visible():
				print("[plat] selftest owned card: ", _ui.parcel_debug_text())
			_ui.open_page("portfolio")
			_on_page_opened("portfolio")
			var port_n := 0
			var tot: Variant = _portfolio.get("totals", {})
			if tot is Dictionary:
				port_n = int((tot as Dictionary).get("n", 0))
			print("[plat] selftest portfolio: %d holdings" % port_n)
			for i in range(10):
				await get_tree().process_frame
			await _save_frame("renders/ui_portfolio.png")
			_ui.open_page("economy")
			_on_page_opened("economy")
			print("[plat] selftest economy: %s" % str(_economy.get("phase", "?")))
			for i in range(8):
				await get_tree().process_frame
			await _save_frame("renders/ui_economy.png")
			_ui.open_page("news")
			_on_page_opened("news")
			print("[plat] selftest news: %d items" % int((_news.get("items", []) as Array).size()))
			for i in range(8):
				await get_tree().process_frame
			await _save_frame("renders/ui_news.png")
		else:
			printerr("[plat] selftest buy FAILED: no affordable listing")
	else:
		printerr("[plat] selftest campaign SKIPPED: no runner / campaign dir")
	for i in range(20):
		await get_tree().process_frame
	await _save_frame("renders/ui_proof.png")
	await _save_frame("renders/playable_selftest.png")
	print("[plat] selftest OK -> ", ProjectSettings.globalize_path(
			"res://renders/playable_selftest.png"))
	get_tree().quit(0)

## Honest current-chrome frame for docs/UI-PLAN.md. Downtown, listing on
## the card, vitals populated. Not a claim that the desk is done.
func _run_uishot() -> void:
	_uishot = false
	_help_visible = false
	if city._import != null:
		_g_target = city._import.core
	_g_bearing = 210.0
	_g_pitch = 56.0
	_g_distance = 320.0
	_snap()
	for i in range(8):
		await get_tree().process_frame
	_ui.set_playing(true)
	_load_desks()
	_pick_affordable_listing()
	if not _ui.is_parcel_visible() and city._import != null:
		for b in city._import.buildings:
			if b.get("listed", false) and not b.get("deco", false):
				_show_card(b)
				break
	_ui.open_page("market")
	_on_page_opened("market")
	_update_hud()
	for i in range(12):
		await get_tree().process_frame
	await _save_frame("renders/ui_current.png")
	print("[plat] uishot OK -> ", ProjectSettings.globalize_path(
			"res://renders/ui_current.png"))
	get_tree().quit(0)


func _run_startshot() -> void:
	_startshot = false
	_ui.set_playing(false)
	_refresh_resume()
	for i in range(10):
		await get_tree().process_frame
	await _save_frame("renders/ui_start.png")
	print("[plat] startshot OK -> ", ProjectSettings.globalize_path(
			"res://renders/ui_start.png"))
	get_tree().quit(0)


func _save_frame(rel: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://" + rel)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("[plat] frame -> ", out)

func _bootstrap_selftest_campaign() -> void:
	var runner := _resolve_runner()
	if runner == "":
		printerr("[plat] selftest: no simulation runner at ",
				"/workspace/plat-econ/tools/game-server.mjs")
		return
	var dir := ProjectSettings.globalize_path("user://campaigns/selftest")
	var out := []
	var ran: Array = _run_sim(PackedStringArray([runner, "new", "--dir=" + dir,
			"--seed=1928"]))
	var code: int = ran[0]
	out = ran[1]
	print("[plat] selftest campaign new: code=%d %s" % [code, "".join(out).right(400)])
	if code != 0:
		return
	_campaign_dir = dir
	_city_file = dir + "/city.json"
	_engine_pick = -1
	_load_game_hud()

# --- camera moves --------------------------------------------------------
# Inputs write GOALS; _process eases the applied state toward them, which
# is what turns every move into a glide. Nothing here writes a band clamp.

func _orbit(d: float) -> void:
	_g_bearing += d

func _tilt(d: float) -> void:
	_g_pitch = clampf(_g_pitch + d, CameraRig.MIN_PITCH, CameraRig.MAX_PITCH)

func _dolly_frac(frac: float) -> void:
	_g_distance = clampf(_g_distance * (1.0 + frac),
			CameraRig.MIN_DISTANCE, CameraRig.MAX_DISTANCE)

func _apply_preset(name: String) -> void:
	if city and city.rig:
		city.rig.apply_preset(name)
		# Pull the preset into goals so ease / HUD stay in sync — still not
		# a lock; the next wheel notch leaves it.
		_g_bearing = city.rig.bearing()
		_g_pitch = city.rig.pitch()
		_g_distance = city.rig.distance()
		_snap()

## Snap applied state to goals instantly (rebuilds, selftest determinism).
func _snap() -> void:
	bearing = _g_bearing
	pitch = _g_pitch
	distance = _g_distance
	_target = _g_target
	_push()

func _push() -> void:
	if city and city.rig:
		if city.rig.is_fly():
			return
		city.rig.set_target_xz(_target.x, _target.y)
		city.rig.set_orbit(bearing, pitch, distance)

func _ground_under(screen: Vector2) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 1e-5:
		return null
	var t := -from.y / dir.y
	if t < 0.0:
		return null
	return from + dir * t

## Grab-the-ground pan: the world point under the cursor stays under it.
func _pan_grab(screen: Vector2) -> void:
	var now: Variant = _ground_under(screen)
	if _grab == null or now == null:
		return
	var g: Vector3 = _grab
	var p: Vector3 = now
	var d := Vector2(g.x - p.x, g.z - p.z)
	_g_target += d
	_target += d
	_push()

## Keyboard / approximate pan (eased). Metres-per-pixel from current
## distance and the camera's vertical FOV over the viewport height.
func _pan_pixels(dx: float, dy: float) -> void:
	var vp_h := float(get_viewport().get_visible_rect().size.y)
	var mpp := 2.0 * distance * tan(deg_to_rad(37.5)) / maxf(vp_h, 1.0)
	var a := deg_to_rad(bearing)
	var fwd := Vector2(-sin(a), cos(a))
	var right := Vector2(cos(a), sin(a))
	_g_target += (right * -dx + fwd * dy) * mpp

## Zoom so the ground under `screen` stays under the cursor (MapLibre).
func _zoom_toward(screen: Vector2, factor: float) -> void:
	var g: Variant = _ground_under(screen)
	var old := _g_distance
	_g_distance = clampf(_g_distance * factor, CameraRig.MIN_DISTANCE, CameraRig.MAX_DISTANCE)
	if g != null and old > 0.1:
		var gp := Vector2((g as Vector3).x, (g as Vector3).z)
		var k := _g_distance / old
		_g_target = gp + (_g_target - gp) * k

func _toggle_fly() -> void:
	if city == null or city.rig == null:
		return
	if city.rig.is_fly():
		city.rig.exit_fly()
		_g_bearing = city.rig.bearing()
		_g_pitch = city.rig.pitch()
		_g_distance = city.rig.distance()
		_g_target = city.rig.target_xz()
		_snap()
	else:
		_push()
		city.rig.enter_fly()

func _process(delta: float) -> void:
	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum > 0.5:
		_fps = float(_fps_frames) / _fps_accum
		_fps_accum = 0.0
		_fps_frames = 0
	if _busy:
		return
	if city and city.rig and city.rig.is_fly():
		_fly_process(delta)
		_update_hud()
		return
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var vp := get_viewport().get_visible_rect().size
	if shift:
		if Input.is_key_pressed(KEY_LEFT):
			_orbit(-KEY_TURN * delta)
		if Input.is_key_pressed(KEY_RIGHT):
			_orbit(KEY_TURN * delta)
		if Input.is_key_pressed(KEY_UP):
			_tilt(KEY_TILT * delta)
		if Input.is_key_pressed(KEY_DOWN):
			_tilt(-KEY_TILT * delta)
	else:
		var px := KEY_PAN * vp.y * delta
		if Input.is_key_pressed(KEY_LEFT):
			_pan_pixels(-px, 0.0)
		if Input.is_key_pressed(KEY_RIGHT):
			_pan_pixels(px, 0.0)
		if Input.is_key_pressed(KEY_UP):
			_pan_pixels(0.0, -px)
		if Input.is_key_pressed(KEY_DOWN):
			_pan_pixels(0.0, px)
	# The easeTo glide: applied state approaches the goal exponentially.
	var t := 1.0 - exp(-EASE * delta)
	bearing = rad_to_deg(lerp_angle(deg_to_rad(bearing), deg_to_rad(_g_bearing), t))
	pitch = lerpf(pitch, _g_pitch, t)
	distance = lerpf(distance, _g_distance, t)
	_target = _target.lerp(_g_target, t)
	_g_pitch = clampf(_g_pitch, CameraRig.MIN_PITCH, CameraRig.MAX_PITCH)
	_g_distance = clampf(_g_distance, CameraRig.MIN_DISTANCE, CameraRig.MAX_DISTANCE)
	_push()
	_update_hud()

func _fly_process(delta: float) -> void:
	var sprint := 2.8 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	var speed := 90.0 * sprint
	var v := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		v.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		v.z += 1.0
	if Input.is_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		v.x += 1.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_PAGEUP):
		v.y += 1.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_PAGEDOWN):
		v.y -= 1.0
	if v != Vector3.ZERO:
		city.rig.fly_input(v.normalized(), speed * delta)

func _load_game_hud() -> void:
	var txt := FileAccess.get_file_as_string(_campaign_dir + "/hud.json")
	var doc: Variant = JSON.parse_string(txt) if not txt.is_empty() else null
	_hud_game = doc if doc is Dictionary else {}
	_load_desks()

## Advance the CAMPAIGN: the simulation runs in node (the engine repo's
## game-server), plat re-reads the files it wrote and rebuilds. The sim owns
## the quantities; this view never computes one.
func _advance_campaign(months: int, until_attention: bool = false) -> void:
	if _busy or _campaign_dir == "":
		return
	_busy = true
	_ui.set_status("advancing %d months (simulation runs in node)..." % months)
	await get_tree().process_frame
	await get_tree().process_frame
	var meta: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(_campaign_dir + "/campaign.json"))
	var runner := str((meta as Dictionary).get("runner", "")) if meta is Dictionary else ""
	if runner == "" or not FileAccess.file_exists(runner):
		runner = _resolve_runner()
	var args := PackedStringArray([runner, "advance", "--dir=" + _campaign_dir,
			"--months=%d" % months])
	if until_attention:
		args.append("--until=attention")
	var out := []
	var ran: Array = _run_sim(args)
	var code: int = ran[0]
	out = ran[1]
	_busy = false
	if code != 0 or runner == "":
		_ui.set_status("advance FAILED (%d): %s" % [code, "".join(out).right(200)])
		return
	_load_game_hud()
	_rebuild()

## Pick the building under a screen point: ray against each imported
## building's extruded footprint box, nearest hit wins, refined by
## point-in-polygon at the hit so neighbouring boxes cannot steal a click.
## No physics bodies — the city is batched meshes, and 1,400 AABB tests
## per click is nothing.
func _pick_building(screen: Vector2) -> void:
	if city == null or city._import == null:
		_ui.hide_parcel()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var best_t := 1e18
	var best: Dictionary = {}
	for b in city._import.buildings:
		if b["deco"]:
			continue
		var bb: Rect2 = b["bbox"]
		var top: float = maxf(float(b["z1"]), 4.0)   # vacant lots stay clickable
		var aabb := AABB(Vector3(bb.position.x, -0.5, bb.position.y),
				Vector3(bb.size.x, top + 0.5, bb.size.y))
		var hit: Variant = aabb.intersects_ray(from, dir)
		if hit == null:
			continue
		var t := (hit as Vector3).distance_to(from)
		if t >= best_t:
			continue
		# Refine: the ray must actually cross the footprint, not just the box.
		var p := hit as Vector3
		var inside := Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), b["ring"])
		if not inside:
			# Facade hits land on the box wall; test the ground-projected walk
			# of the ray a few metres further in.
			var q := p + dir * 3.0
			inside = Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), b["ring"])
		if inside:
			best_t = t
			best = b
	if best.is_empty():
		_ui.hide_parcel()
		return
	_show_card(best)

func _show_card(b: Dictionary) -> void:
	_selected = b
	_ui.show_parcel(_enrich(b), _campaign_dir != "")


## Where the simulation lives: the plat-sim sidecar next to the executable,
## plat-econ shipped beside the exe, PLAT_SIM, a dev checkout, or nothing.
func _sim_bin() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	if OS.get_name() == "Windows":
		for rel in ["node.exe", "node/node.exe"]:
			var p := exe_dir.path_join(rel)
			if FileAccess.file_exists(p):
				return p
	else:
		for rel in ["node", "node/bin/node"]:
			var p := exe_dir.path_join(rel)
			if FileAccess.file_exists(p):
				return p
	return "node"

func _run_sim(args: PackedStringArray) -> Array:
	var out := []
	var code := OS.execute(_sim_bin(), args, out, true)
	return [code, out]

func _resolve_runner() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var beside_sim := exe_dir.path_join("plat-sim.mjs")
	if FileAccess.file_exists(beside_sim):
		return beside_sim
	var bundled := exe_dir.path_join("plat-econ/tools/game-server.mjs")
	if FileAccess.file_exists(bundled):
		return bundled
	var env := OS.get_environment("PLAT_SIM")
	if env != "" and FileAccess.file_exists(env):
		return env
	var root := ProjectSettings.globalize_path("res://")
	for rel in [
			"../plat-econ/tools/game-server.mjs",
			"plat-econ/tools/game-server.mjs",
	]:
		var p := root.path_join(rel).simplify_path()
		if FileAccess.file_exists(p):
			return p
	var dev := "/workspace/plat-econ/tools/game-server.mjs"
	return dev if FileAccess.file_exists(dev) else ""

func _break_ground() -> void:
	await _break_ground_opts("city", "village", 2500000)


func _break_ground_opts(size: String, density: String, cash: int) -> void:
	if _busy:
		return
	var runner := _resolve_runner()
	if runner == "":
		_ui.show_error("No simulation", "plat-sim.mjs beside the executable, or set PLAT_SIM")
		return
	_busy = true
	_ui.set_status("breaking ground (generating island, founding firm)...")
	await get_tree().process_frame
	await get_tree().process_frame
	var dir := ProjectSettings.globalize_path("user://campaigns/c%d" % (randi() % 1000000))
	var ran: Array = _run_sim(PackedStringArray([runner, "new", "--dir=" + dir,
			"--seed=%d" % (randi() % 100000),
			"--size=" + size, "--density=" + density, "--cash=%d" % cash]))
	var code: int = ran[0]
	var out: Array = ran[1]
	_busy = false
	if code != 0:
		_ui.show_error("Break ground failed", "".join(out).right(200))
		return
	_open_campaign(dir)


func _continue_campaign(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path.path_join("city.json")):
		return
	_open_campaign(path)


func _open_campaign(dir: String) -> void:
	_campaign_dir = dir
	_city_file = dir + "/city.json"
	_engine_pick = -1
	_load_game_hud()
	_ui.set_playing(true)
	_g_target = Vector2.ZERO
	_snap()
	_rebuild()


func _load_desks() -> void:
	if _campaign_dir == "" or _ui == null:
		return
	_market_rows = _desk_file("market").get("rows", [])
	_portfolio = _desk_file("portfolio")
	_news = _desk_file("news")
	_economy = _desk_file("economy")
	_debt = _desk_file("debt")
	_books = _desk_file("books")


func _desk_file(name: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(_campaign_dir + "/desks/" + name + ".json")
	var doc: Variant = JSON.parse_string(txt) if not txt.is_empty() else null
	return doc if doc is Dictionary else {}


func _holding_row(bbl: String) -> Dictionary:
	for r in _portfolio.get("rows", []):
		if r is Dictionary and str(r.get("bbl", "")) == bbl:
			return r
	return {}


func _enrich(b: Dictionary) -> Dictionary:
	var out := b.duplicate()
	var row := _holding_row(str(b.get("bbl", "")))
	if row.is_empty():
		return out
	out["held"] = true
	if row.get("noi") != null:
		out["noi"] = row["noi"]
	if row.get("basis") != null:
		out["basis"] = row["basis"]
	if row.get("debt") != null:
		out["debt"] = row["debt"]
	if row.get("value") != null:
		out["value"] = row["value"]
	if row.get("occ") != null:
		out["occ"] = row["occ"]
	return out


func _on_page_opened(page: String) -> void:
	match page:
		"market":
			_ui.set_market_rows(_market_rows)
		"portfolio":
			_ui.set_portfolio(_portfolio)
		"news":
			_ui.set_news(_news)
		"economy":
			_ui.set_economy(_economy)
		"debt":
			_ui.set_debt(_debt)
		"books":
			_ui.set_books(_books)
		"property":
			_ui.set_property_overview(_enrich(_selected) if not _selected.is_empty() else {})
		_:
			_ui.set_page_note("This desk is next. The engine already has the numbers; the export is not wired yet.")


func _on_lens(name: String, on: bool) -> void:
	if name == "owners":
		ContextGen.overlay = "owners" if on else ""
	elif name == "listings":
		ContextGen.overlay = "listings" if on else ""
	else:
		return
	_rebuild()


func _on_attention(item: Dictionary) -> void:
	var bbl := str(item.get("bbl", ""))
	if bbl != "":
		_focus_listing(bbl)


func _focus_listing(bbl: String) -> void:
	if city == null or city._import == null or bbl == "":
		return
	for b in city._import.buildings:
		if str(b.get("bbl", "")) == bbl:
			var c := (b["bbox"] as Rect2).get_center()
			_g_target = c
			_show_card(b)
			return


func _refresh_resume() -> void:
	if _ui == null:
		return
	var root := ProjectSettings.globalize_path("user://campaigns")
	var best := ""
	var best_label := ""
	var d := DirAccess.open(root)
	if d:
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			if d.current_is_dir() and not name.begins_with("."):
				var hud_path := root.path_join(name).path_join("hud.json")
				if FileAccess.file_exists(hud_path):
					var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(hud_path))
					if doc is Dictionary:
						best = root.path_join(name)
						best_label = "%s · %s · %s" % [
								str(doc.get("city", name)), str(doc.get("date", "")),
								"$%.2fM" % (float(doc.get("cash", 0)) / 1e6)]
			name = d.get_next()
	_ui.set_resume(best, best_label)

## BUY the selected parcel at ask (docs/GAME-PLAN.md 3.2). The engine
## decides; its error string is shown verbatim — plat never re-prices.
func _buy_selected() -> void:
	if _busy or _campaign_dir == "" or _selected.is_empty():
		return
	if not _selected.get("listed", false) or _selected.get("held", false):
		return
	var bbl := str(_selected.get("bbl", ""))
	_busy = true
	_ui.set_status("buying %s..." % bbl)
	await get_tree().process_frame
	await get_tree().process_frame
	var meta: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(_campaign_dir + "/campaign.json"))
	var runner := str((meta as Dictionary).get("runner", "")) if meta is Dictionary else ""
	if runner == "" or not FileAccess.file_exists(runner):
		runner = _resolve_runner()
	var out := []
	var ran: Array = _run_sim(PackedStringArray([runner, "buy", "--dir=" + _campaign_dir,
			"--bbl=" + bbl]))
	var code: int = ran[0]
	out = ran[1]
	_busy = false
	if code != 0:
		var res: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(_campaign_dir + "/result.json"))
		_ui.show_error("Buy failed", str((res as Dictionary).get("err", "?")) \
				if res is Dictionary else "unknown error")
		return
	_load_game_hud()
	_rebuild()

## TAB walks the for-sale tape: camera flies to each listing, card shows it.
func _cycle_listing() -> void:
	if city == null or city._import == null:
		return
	var listed: Array = []
	for b in city._import.buildings:
		if b.get("listed", false) and not b.get("deco", false):
			listed.append(b)
	if listed.is_empty():
		return
	_listing_pick = (_listing_pick + 1) % listed.size()
	var b: Dictionary = listed[_listing_pick]
	var c := (b["bbox"] as Rect2).get_center()
	_g_target = c
	_show_card(b)

## Cheapest listed lot the firm can actually pay for — the selftest deal.
func _pick_affordable_listing() -> void:
	if city == null or city._import == null:
		return
	var cash := float(_hud_game.get("cash", 0))
	var best: Dictionary = {}
	var best_ask := 1e18
	for b in city._import.buildings:
		if not b.get("listed", false) or b.get("held", false) or b.get("deco", false):
			continue
		var ask := float(b.get("ask", 0.0))
		if ask > 0.0 and ask <= cash and ask < best_ask:
			best = b
			best_ask = ask
	if best.is_empty():
		_selected = {}
		return
	var c := (best["bbox"] as Rect2).get_center()
	_g_target = c
	_target = c
	_push()
	_show_card(best)

func _update_hud() -> void:
	if city == null or city.rig == null or _ui == null:
		return
	_ui.set_fps(_fps)
	_ui.refresh_vitals(_hud_game, _campaign_dir != "")
	var status := ""
	if city._import != null:
		status = "%s · %d buildings · %s" % [
				city._import.name, city._import.buildings.size(), city.rig.describe()]
	elif city._plan != null:
		status = city._plan.describe().replace("plan ", "")
	if _busy:
		pass  # status text set by the operation in flight
	else:
		_ui.set_status(status)
	var help := ""
	if _help_visible:
		if _campaign_dir != "":
			help = ("Advance · Buy · Listings (Tab) · Owners lens\n"
					+ "Space advance season · B buy · Tab cycle listings · M owners overlay")
		else:
			help = "F1 or Break ground — found a firm on a fresh island"
		help += ("\n\nPan: left-drag · Rotate/tilt: right-drag · Zoom: wheel at cursor"
				+ "\nV free-fly · C downtown · H toggle help · Esc quit")
	_ui.set_help(help, _help_visible)
	_ui.set_owners_lens(ContextGen.overlay == "owners")
	_ui.set_listings_lens(ContextGen.overlay == "listings")
	if _compass:
		var br := city.rig.bearing()
		_compass.text = "N\n%03d°" % int(fposmod(br, 360.0))

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.double_click and mb.pressed:
				_zoom_toward(mb.position, 0.5)
				return
			if mb.pressed:
				_press_pos = mb.position
				if mb.ctrl_pressed:
					_rotating = true
					_panning = false
					_grab = null
				else:
					_panning = true
					_rotating = false
					_grab = _ground_under(mb.position)
			else:
				if _press_pos.distance_to(mb.position) < 6.0:
					# A press that never moved is a CLICK: pick the parcel.
					_pick_building(mb.position)
				_panning = false
				_rotating = false
				_grab = null
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_rotating = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_toward(mb.position, 1.0 - WHEEL_STEP)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_toward(mb.position, 1.0 + WHEEL_STEP)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if city and city.rig and city.rig.is_fly() and _rotating:
			city.rig.fly_look(mm.relative.x * FLY_LOOK, mm.relative.y * FLY_LOOK)
		elif _panning and not mm.ctrl_pressed:
			_pan_grab(mm.position)
		elif _rotating or (_panning and mm.ctrl_pressed):
			_orbit(mm.relative.x * ROTATE_SENSITIVITY)
			_tilt(-mm.relative.y * PITCH_SENSITIVITY)
	elif event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_1: _apply_preset("near")
			KEY_2: _apply_preset("mid")
			KEY_3: _apply_preset("far")
			KEY_V:
				_toggle_fly()
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
				elif city and city._import != null:
					_g_target = city._import.core
			KEY_F:
				_cycle_preset()
			KEY_H:
				_help_visible = not _help_visible
			KEY_F12:
				_screenshot()
			KEY_E:
				if city and city.rig and city.rig.is_fly():
					return
				# Cycle the ENGINE cities shipped with the build: islands
				# the economy generated, with its parcels, classes, years
				# and occupancy. N stays plat's own generator.
				if _campaign_dir == "":
					_engine_pick = (_engine_pick + 1) % ENGINE_CITIES.size()
					_city_file = ENGINE_CITIES[_engine_pick]
					_g_target = Vector2.ZERO
					_snap()
					_rebuild()
			KEY_F1:
				_break_ground()
			KEY_M:
				# Owners overlay: your deeds gold, the for-sale tape green.
				ContextGen.overlay = "" if ContextGen.overlay == "owners" else "owners"
				_rebuild()
			KEY_B:
				_buy_selected()
			KEY_TAB:
				_cycle_listing()
			KEY_SPACE:
				# The game key: a season passes, the sim decides what
				# changed, the city rebuilds to show it.
				_advance_campaign(1, false)
			KEY_ESCAPE:
				get_tree().quit()

var _preset := 0

## Three optional framings — the old band midpoints, now just views.
func _cycle_preset() -> void:
	_preset = (_preset + 1) % 3
	match _preset:
		0:
			_g_bearing = 200.0
			_g_pitch = 60.0
			_g_distance = 246.0
		1:
			_g_bearing = 100.0
			_g_pitch = 64.0
			_g_distance = 975.0
		2:
			_g_bearing = 20.0
			_g_pitch = 59.0
			_g_distance = 2220.0

func _screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "user://plat_%d.png" % seed_value
	img.save_png(ProjectSettings.globalize_path(path))
	print("[plat] screenshot -> ", ProjectSettings.globalize_path(path))
