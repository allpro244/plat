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
var _card: Label
var _press_pos := Vector2.ZERO   # to tell a click from a drag
var _selected: Dictionary = {}   # the building on the card
var _listing_pick := -1          # TAB cycles the for-sale tape
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
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)
	# The parcel card: what a clicked building IS, by the record — the same
	# numbers the acquisition desk prices off.
	_card = Label.new()
	_card.add_theme_color_override("font_color", Color(1, 1, 1))
	_card.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_card.add_theme_constant_override("outline_size", 7)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Plain absolute placement: anchor presets make `position` an offset
	# from the anchored edge, which put the first card 1,180 px past the
	# right border — an invisible card, caught by the selftest frame.
	_card.position = Vector2(get_viewport().get_visible_rect().size.x - 420, 12)
	_card.visible = false
	layer.add_child(_card)
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
			if _card.visible:
				print("[plat] selftest pick: ", _card.text.replace("\n", " | "))
				break
		if not _card.visible:
			printerr("[plat] selftest pick FAILED: no building card")
	if _campaign_dir != "":
		# The game loop itself, once: sim advances in node, city rebuilds.
		var before := str(_hud_game.get("date", "?"))
		await _advance_campaign(3)
		while _busy:
			await get_tree().process_frame
		print("[plat] selftest campaign advance: %s -> %s" % [
				before, str(_hud_game.get("date", "?"))])
		# And a DEAL: walk the tape, buy the first listing, prove the money
		# moved and the deed came back marked.
		var cash0 := float(_hud_game.get("cash", 0))
		_cycle_listing()
		if not _selected.is_empty():
			await _buy_selected()
			while _busy:
				await get_tree().process_frame
			print("[plat] selftest buy: cash $%.2fM -> $%.2fM, holdings %d" % [
					cash0 / 1e6, float(_hud_game.get("cash", 0)) / 1e6,
					int(_hud_game.get("holdings", 0))])
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
	if runner == "" or not FileAccess.file_exists(runner):
		runner = _resolve_runner()
	var out := []
	var code := OS.execute("node", [runner, "advance", "--dir=" + _campaign_dir,
			"--months=%d" % months], out, true)
	_busy = false
	if code != 0 or runner == "":
		_hud.text = "advance FAILED (%d): %s" % [code, "".join(out).right(200)]
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
		_card.visible = false
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
		_card.visible = false
		return
	_show_card(best)

func _show_card(b: Dictionary) -> void:
	_selected = b
	var par: Dictionary = b
	var occ_line := "—"
	if float(par.get("occ", -1.0)) >= 0.0:
		occ_line = "%.0f%% occupied" % (float(par["occ"]) * 100.0)
	var lines := [
		"BBL %s%s" % [str(par.get("bbl", "?")), "   ★ YOURS" if par.get("held", false) else ""],
		"%s · %s" % [str(par.get("cls", "?")).to_upper(), str(par.get("district", "?"))],
		"%s sf building · %s sf lot" % [_fmt_sf(float(par.get("sqft", 0.0))),
				_fmt_sf(float(par.get("lot_sqft", 0.0)))],
		"%d floors · built %d" % [int(par.get("floors", 0)), int(par.get("year", 0))],
		occ_line,
	]
	# The money lines: the record becomes an investment memo.
	if float(par.get("value", -1.0)) > 0.0:
		lines.append("appraised $%.2fM" % (float(par["value"]) / 1e6))
	if par.get("listed", false):
		lines.append("FOR SALE — ask $%.2fM%s" % [float(par.get("ask", 0.0)) / 1e6,
				"  (DISTRESS)" if par.get("distress", false) else ""])
		if _campaign_dir != "" and not par.get("held", false):
			lines.append("[B] buy at ask")
	elif float(par.get("ask", -1.0)) > 0.0:
		lines.append("off-market ask $%.2fM" % (float(par["ask"]) / 1e6))
	_card.text = "\n".join(lines)
	_card.visible = true

static func _fmt_sf(v: float) -> String:
	var s := str(int(roundf(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out

## Where the simulation lives: the plat-sim sidecar next to the executable,
## a PLAT_SIM env override, or the dev repo. Empty string = no sim available.
func _resolve_runner() -> String:
	var beside := OS.get_executable_path().get_base_dir() + "/plat-sim.mjs"
	if FileAccess.file_exists(beside):
		return beside
	var env := OS.get_environment("PLAT_SIM")
	if env != "" and FileAccess.file_exists(env):
		return env
	var dev := "/workspace/plat-econ/tools/game-server.mjs"
	return dev if FileAccess.file_exists(dev) else ""

## BREAK GROUND (docs/GAME-PLAN.md phase 2, first cut): F1 founds a firm on
## a fresh island and opens it as the live campaign.
func _break_ground() -> void:
	if _busy:
		return
	var runner := _resolve_runner()
	if runner == "":
		_card.text = "no simulation found\n(plat-sim.mjs beside the executable,\nor set PLAT_SIM)"
		_card.visible = true
		return
	_busy = true
	_hud.text = "breaking ground (generating island, founding firm)..."
	await get_tree().process_frame
	await get_tree().process_frame
	var dir := ProjectSettings.globalize_path("user://campaigns/c%d" % (randi() % 1000000))
	var out := []
	var code := OS.execute("node", [runner, "new", "--dir=" + dir,
			"--seed=%d" % (randi() % 100000)], out, true)
	_busy = false
	if code != 0:
		_card.text = "break ground FAILED\n" + "".join(out).right(200)
		_card.visible = true
		return
	_campaign_dir = dir
	_city_file = dir + "/city.json"
	_engine_pick = -1
	_load_game_hud()
	_g_target = Vector2.ZERO
	_snap()
	_rebuild()

## BUY the selected parcel at ask (docs/GAME-PLAN.md 3.2). The engine
## decides; its error string is shown verbatim — plat never re-prices.
func _buy_selected() -> void:
	if _busy or _campaign_dir == "" or _selected.is_empty():
		return
	if not _selected.get("listed", false) or _selected.get("held", false):
		return
	var bbl := str(_selected.get("bbl", ""))
	_busy = true
	_hud.text = "buying %s..." % bbl
	await get_tree().process_frame
	await get_tree().process_frame
	var meta: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(_campaign_dir + "/campaign.json"))
	var runner := str((meta as Dictionary).get("runner", "")) if meta is Dictionary else ""
	if runner == "" or not FileAccess.file_exists(runner):
		runner = _resolve_runner()
	var out := []
	var code := OS.execute("node", [runner, "buy", "--dir=" + _campaign_dir,
			"--bbl=" + bbl], out, true)
	_busy = false
	if code != 0:
		var res: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(_campaign_dir + "/result.json"))
		_card.text = "BUY FAILED\n%s" % str((res as Dictionary).get("err", "?")) \
				if res is Dictionary else "BUY FAILED"
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
			help = "\n\nSPACE advance a season   B buy selected   TAB for-sale tape   M owners overlay"
		if _campaign_dir == "":
			help = "\n\nF1 BREAK GROUND — found a firm on a fresh island"
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
		game_line += " | %d for sale (TAB)" % int(_hud_game.get("listings", 0))
		var att: Array = _hud_game.get("attention", [])
		if not att.is_empty():
			game_line += "\n! " + " · ".join(PackedStringArray(att))
	_hud.text = "plat — %.0f fps | %s | at (%.0f, %.0f) | %02d:%02d%s%s%s" % [
			_fps, city.rig.describe(), _target.x, _target.y, int(time_of_day),
			int(fposmod(time_of_day, 1.0) * 60.0), game_line, plan_line, help]

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_pos = mb.position
			elif _press_pos.distance_to(mb.position) < 6.0:
				# A press that never moved is a CLICK: pick the parcel.
				_pick_building(mb.position)
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
