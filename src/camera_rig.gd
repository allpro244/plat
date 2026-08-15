class_name CameraRig
extends Node3D
## Free-flow camera. Two modes:
##
##   MAP  — Broadway & Wall / MapLibre scheme: orbit a ground target with
##          continuous bearing, pitch (0 = nadir, 89 ≈ horizon) and distance.
##          No height-band clamp. camera_bands.json is optional presets only.
##   FLY  — position + look direction; WASD / Q-E / mouse-look go anywhere,
##          including street level and off the island.
##
## Owner override (2026-08): the orbital band contract in CLAUDE.md / BRIEF.md
## is revoked. Street-level fidelity is not a goal; freedom of movement is.

const BANDS_PATH := "res://data/camera_bands.json"
const MIN_DISTANCE := 6.0
const MAX_DISTANCE := 12000.0
const MIN_PITCH := 0.0
const MAX_PITCH := 89.0
const MIN_HEIGHT := 1.5

enum Mode { MAP, FLY }

var _presets: Array = []
var _preset_name := "near"
var _target := Vector3.ZERO
var _bearing_deg := 225.0
var _pitch_deg := 60.8
var _distance_m := 246.0
var _mode := Mode.MAP

var _fly_pos := Vector3(0.0, 120.0, 200.0)
var _fly_yaw := 225.0
var _fly_pitch := -25.0

var camera := Camera3D.new()

func _init() -> void:
	var f := FileAccess.open(BANDS_PATH, FileAccess.READ)
	if f != null:
		var cfg: Dictionary = JSON.parse_string(f.get_as_text())
		_presets = cfg.get("bands", [])
		_target = Vector3(0.0, float(cfg.get("target_height_m", 0.0)), 0.0)
	add_child(camera)
	camera.current = true
	camera.far = 12000.0
	_apply()

## Optional framing preset (near/mid/far). Does NOT lock the camera — the
## next set_view / set_orbit / zoom is free to leave the old band.
func set_band(band_name: String) -> void:
	apply_preset(band_name)

func apply_preset(preset_name: String) -> void:
	for i in _presets.size():
		if _presets[i]["name"] == preset_name:
			_preset_name = preset_name
			var h: Array = _presets[i]["height_m"]
			var r: Array = _presets[i]["radius_m"]
			var height := (float(h[0]) + float(h[1])) * 0.5
			var radius := (float(r[0]) + float(r[1])) * 0.5
			_set_from_height_radius(height, radius)
			_apply()
			return
	push_error("unknown camera preset: " + preset_name)

## Compatibility with shoot.gd / CityScene: azimuth + height + ground radius.
## Height and radius are NOT clamped into a band.
func set_view(azimuth_deg: float, height_m: float, radius_m: float) -> void:
	_bearing_deg = azimuth_deg
	_set_from_height_radius(height_m, radius_m)
	_apply()

func set_orbit(bearing_deg: float, pitch_deg: float, distance_m: float) -> void:
	_bearing_deg = bearing_deg
	_pitch_deg = clampf(pitch_deg, MIN_PITCH, MAX_PITCH)
	_distance_m = clampf(distance_m, MIN_DISTANCE, MAX_DISTANCE)
	_apply()

func set_target_xz(x: float, z: float) -> void:
	_target.x = x
	_target.z = z
	_apply()

func band_name() -> String:
	return _preset_name

func is_fly() -> bool:
	return _mode == Mode.FLY

func bearing() -> float:
	return _bearing_deg if _mode == Mode.MAP else _fly_yaw

func pitch() -> float:
	return _pitch_deg

func distance() -> float:
	return _distance_m

func target_xz() -> Vector2:
	return Vector2(_target.x, _target.z)

func describe() -> String:
	if _mode == Mode.FLY:
		return "fly pos=(%.0f, %.0f, %.0f) yaw=%.1f look=%.1f" % [
				_fly_pos.x, _fly_pos.y, _fly_pos.z, _fly_yaw, _fly_pitch]
	return "map bearing=%.1f pitch=%.1f dist=%.1f" % [
			_bearing_deg, _pitch_deg, _distance_m]

func enter_fly() -> void:
	_fly_pos = camera.global_position
	var look := -camera.global_transform.basis.z
	_fly_yaw = rad_to_deg(atan2(look.x, -look.z))
	_fly_pitch = rad_to_deg(asin(clampf(look.y, -1.0, 1.0)))
	_mode = Mode.FLY
	_apply()

func exit_fly() -> void:
	if _mode != Mode.FLY:
		return
	var look := _fly_look_dir()
	if look.y < -0.05:
		var t := -_fly_pos.y / look.y
		var hit := _fly_pos + look * t
		_target = Vector3(hit.x, _target.y, hit.z)
	else:
		_target = Vector3(_fly_pos.x, _target.y, _fly_pos.z)
	_bearing_deg = _fly_yaw
	var horiz := Vector2(_fly_pos.x - _target.x, _fly_pos.z - _target.z).length()
	_distance_m = clampf(_fly_pos.distance_to(_target), MIN_DISTANCE, MAX_DISTANCE)
	_pitch_deg = clampf(rad_to_deg(atan2(horiz, maxf(_fly_pos.y - _target.y, 0.01))),
			MIN_PITCH, MAX_PITCH)
	_mode = Mode.MAP
	_apply()

## local_move: +x right, +y up, −z forward (Godot camera local).
func fly_input(local_move: Vector3, metres: float) -> void:
	if _mode != Mode.FLY:
		return
	var yaw := deg_to_rad(_fly_yaw)
	var fwd := Vector3(sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, sin(yaw))
	_fly_pos += (right * local_move.x + Vector3.UP * local_move.y - fwd * local_move.z) * metres
	_apply()

func fly_look(dx_deg: float, dy_deg: float) -> void:
	if _mode != Mode.FLY:
		return
	_fly_yaw += dx_deg
	_fly_pitch = clampf(_fly_pitch - dy_deg, -89.0, 89.0)
	_apply()

func _set_from_height_radius(height_m: float, radius_m: float) -> void:
	var h := maxf(height_m, 0.01)
	var r := maxf(radius_m, 0.0)
	_distance_m = clampf(sqrt(h * h + r * r), MIN_DISTANCE, MAX_DISTANCE)
	_pitch_deg = clampf(rad_to_deg(atan2(r, h)), MIN_PITCH, MAX_PITCH)

func _fly_look_dir() -> Vector3:
	var yaw := deg_to_rad(_fly_yaw)
	var pit := deg_to_rad(_fly_pitch)
	var cp := cos(pit)
	return Vector3(sin(yaw) * cp, sin(pit), -cos(yaw) * cp).normalized()

func _apply() -> void:
	if _mode == Mode.FLY:
		camera.position = _fly_pos
		var dest := camera.position + _fly_look_dir()
		if camera.is_inside_tree():
			camera.look_at(dest)
		else:
			camera.look_at_from_position(camera.position, dest)
		return
	# MAP: continuous orbit. Soft physical limits only — not a band.
	_pitch_deg = clampf(_pitch_deg, MIN_PITCH, MAX_PITCH)
	_distance_m = clampf(_distance_m, MIN_DISTANCE, MAX_DISTANCE)
	var pr := deg_to_rad(_pitch_deg)
	var br := deg_to_rad(_bearing_deg)
	var horiz := _distance_m * sin(pr)
	var vert := _distance_m * cos(pr)
	if vert < MIN_HEIGHT:
		vert = MIN_HEIGHT
	var offset := Vector3(sin(br) * horiz, vert, -cos(br) * horiz)
	camera.position = _target + offset
	if camera.is_inside_tree():
		camera.look_at(_target)
	else:
		camera.look_at_from_position(camera.position, _target)
