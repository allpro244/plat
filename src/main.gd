extends Node3D
## Interactive entry point — the playable viewer.
##
## The camera contract is not relaxed for interactive use: this drives the
## same CameraRig the headless shots use, so every orbit, zoom and band
## change is clamped by data/camera_bands.json. There is no free-fly, by
## construction (CLAUDE.md: the contract is load-bearing).
##
## Controls
##   drag / arrows ... orbit          wheel / up-down ... dolly (clamped)
##   PgUp / PgDn ..... height          1 2 3 ............ near / mid / far band
##   T / G ........... time of day     N ................ new city (random seed)
##   R ............... rebuild         F ................ cycle preset views
##   H ............... toggle help     F12 .............. save a screenshot
##   Esc ............. quit
##
## Rebuilding a city is ~1-3 s of single-threaded generation, so the HUD
## says so and the frame is yielded before the work starts — otherwise the
## window looks hung.

const ORBIT_SPEED := 40.0        # deg/sec on arrows
const DRAG_SENSITIVITY := 0.32   # deg per pixel
const DOLLY_SPEED := 90.0        # m/sec on arrows
const WHEEL_STEP := 0.06         # fraction of current radius per notch

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
var _dragging := false
var _fps_accum := 0.0
var _fps_frames := 0
var _fps := 0.0
var _selftest := false

func _ready() -> void:
	_selftest = "--selftest" in OS.get_cmdline_user_args()
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
	city = CityScene.new({"seed": seed_value, "time": time_of_day})
	add_child(city)
	city.rig.set_band(band)
	city.rig.set_view(az, height, radius)
	print("[plat] built seed %d in %d ms" % [seed_value, Time.get_ticks_msec() - t0])
	_busy = false
	if _selftest:
		await _run_selftest()

## Headless proof that the interactive path works: exercise every control,
## save a frame, quit. This is how an interactive scene gets the same
## "verified by render" treatment as the still pipeline.
func _run_selftest() -> void:
	for step in [["orbit", func() -> void: _orbit(45.0)],
			["dolly", func() -> void: _dolly(30.0)],
			["height", func() -> void: _height(25.0)],
			["band mid", func() -> void: _set_band("mid")],
			["band far", func() -> void: _set_band("far")],
			["band near", func() -> void: _set_band("near")]]:
		(step[1] as Callable).call()
		await get_tree().process_frame
		print("[plat] selftest %s -> %s" % [step[0], city.rig.describe()])
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

func _orbit(d: float) -> void:
	az = fposmod(az + d, 360.0)
	_push()

func _dolly(d: float) -> void:
	radius += d
	_push()

func _height(d: float) -> void:
	height += d
	_push()

func _set_band(b: String) -> void:
	band = b
	city.rig.set_band(b)
	# Re-push so the rig re-clamps our numbers into the new band's range.
	_push()

func _push() -> void:
	if city and city.rig:
		city.rig.set_view(az, height, radius)

func _process(delta: float) -> void:
	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum > 0.5:
		_fps = float(_fps_frames) / _fps_accum
		_fps_accum = 0.0
		_fps_frames = 0
	if _busy:
		return
	if Input.is_key_pressed(KEY_LEFT):
		_orbit(-ORBIT_SPEED * delta)
	if Input.is_key_pressed(KEY_RIGHT):
		_orbit(ORBIT_SPEED * delta)
	if Input.is_key_pressed(KEY_UP):
		_dolly(-DOLLY_SPEED * delta)
	if Input.is_key_pressed(KEY_DOWN):
		_dolly(DOLLY_SPEED * delta)
	if Input.is_key_pressed(KEY_PAGEUP):
		_height(60.0 * delta)
	if Input.is_key_pressed(KEY_PAGEDOWN):
		_height(-60.0 * delta)
	_update_hud()

func _update_hud() -> void:
	if city == null or city.rig == null:
		return
	var plan_line := ""
	if city._plan != null:
		plan_line = "\n%s" % city._plan.describe().replace("plan ", "")
	var help := ""
	if _help_visible:
		help = ("\n\ndrag/arrows orbit   wheel/up-down dolly   PgUp/PgDn height"
				+ "\n1 2 3 band   T/G time   N new city   F preset view"
				+ "\nH help   F12 screenshot   Esc quit")
	_hud.text = "plat — %.0f fps | %s | %02d:%02d%s%s" % [
			_fps, city.rig.describe(), int(time_of_day),
			int(fposmod(time_of_day, 1.0) * 60.0), plan_line, help]

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dolly(-radius * WHEEL_STEP)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dolly(radius * WHEEL_STEP)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_orbit(mm.relative.x * DRAG_SENSITIVITY)
		_height(-mm.relative.y * DRAG_SENSITIVITY * 2.0)
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
				# city you like can be reproduced exactly.
				seed_value = randi() % 100000
				_rebuild()
			KEY_R:
				_rebuild()
			KEY_F:
				_cycle_preset()
			KEY_H:
				_help_visible = not _help_visible
			KEY_F12:
				_screenshot()
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
			az = 200.0
			height = 140.0
			radius = 240.0
		1:
			band = "mid"
			az = 100.0
			height = 420.0
			radius = 880.0
		2:
			band = "far"
			az = 20.0
			height = 1150.0
			radius = 1900.0
	city.rig.set_band(band)
	_push()

func _screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "user://plat_%d_%s.png" % [seed_value, city.rig.band_name()]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[plat] screenshot -> ", ProjectSettings.globalize_path(path))
