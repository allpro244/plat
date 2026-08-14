extends SceneTree
## Headless render entry point. Run via tools/shoot.sh, or directly:
##   godot --path . -s src/shoot.gd -- --seed=1928 --time=15.5 --out=renders/x.png
## Builds the city, lets the renderer settle, saves a PNG, prints the full
## parameter line (so every image is traceable to its inputs), and quits.

const SETTLE_FRAMES := 30

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var params := _parse_args()
	var out_path: String = params.get("out", "renders/shot.png")
	var city := CityScene.new(params)
	var tb := Time.get_ticks_msec()
	root.add_child(city)   # _ready() generates the whole city here
	print("[plat] build: %d ms (plan + all mesh generation, single-threaded CPU)" % [
			Time.get_ticks_msec() - tb])
	var t0 := Time.get_ticks_msec()
	for i in range(SETTLE_FRAMES):
		await process_frame
	await RenderingServer.frame_post_draw
	var settle_ms := Time.get_ticks_msec() - t0
	print("[plat] settle: %d frames in %d ms (%.0f ms/frame)" % [
			SETTLE_FRAMES, settle_ms, float(settle_ms) / SETTLE_FRAMES])
	var img := root.get_viewport().get_texture().get_image()
	var abs_out := ProjectSettings.globalize_path("res://" + out_path) \
			if not out_path.begins_with("/") else out_path
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	var err := img.save_png(abs_out)
	if err != OK:
		printerr("[plat] FAILED to save ", abs_out, " err=", err)
		quit(1)
		return
	# Hardware-independent cost numbers. These, not lavapipe milliseconds,
	# are what predict performance on a real GPU.
	print("[plat] scene: %d draw calls, %s prims, %.0f MB buffers, %.0f MB textures" % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			String.num_uint64(RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
			float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)) / 1048576.0,
			float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0])
	print("[plat] shot ", img.get_width(), "x", img.get_height(), " -> ", abs_out)
	print("[plat] ", city.describe())
	quit(0)

func _parse_args() -> Dictionary:
	var p := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var kv := arg.substr(2).split("=", true, 1)
		var key := kv[0]
		var val := kv[1]
		match key:
			"seed":
				p["seed"] = int(val)
			"time":
				p["time"] = float(val)
			"date":
				var d := val.split("-")
				p["year"] = int(d[0])
				p["month"] = int(d[1])
				p["day"] = int(d[2])
			"band":
				p["band"] = val
			"az":
				p["cam_azimuth"] = float(val)
			"height":
				p["cam_height"] = float(val)
			"radius":
				p["cam_radius"] = float(val)
			"out":
				p["out"] = val
			"gi":
				p["gi"] = val != "off"
			"context":
				p["no_context"] = val == "off"
			"env":
				p["env_plain"] = val == "plain"
			"block":
				p["no_block"] = val == "off"
			"mats":
				p["plain_mats"] = val == "plain"
			"fog":
				p["no_fog"] = val == "off"
			"only":
				p["only_lot"] = val
			"windows":
				p["skip_windows"] = val == "off"
			"props":
				p["skip_props"] = val == "off"
			"ground":
				p["skip_ground"] = val == "off"
			"city":
				p["city"] = val
			"tx":
				p["target_x"] = float(val)
			"tz":
				p["target_z"] = float(val)
			_:
				printerr("[plat] unknown arg --", key)
	return p
