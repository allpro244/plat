class_name CameraRig
extends Node3D
## Orbital camera constrained to the height bands defined in
## data/camera_bands.json. The bands are the contract (see CLAUDE.md): the rig
## exposes only (band, azimuth, height, radius) and clamps height and radius
## into the active band on every write, so the camera cannot leave its bands
## by construction. It always looks at the target point.

const BANDS_PATH := "res://data/camera_bands.json"

var _bands: Array = []
var _target := Vector3.ZERO
var _band_index := 0
var _azimuth_deg := 225.0
var _height_m := 100.0
var _radius_m := 200.0

var camera := Camera3D.new()

func _init() -> void:
	var f := FileAccess.open(BANDS_PATH, FileAccess.READ)
	assert(f != null, "camera bands file missing — the contract must exist as data")
	var cfg: Dictionary = JSON.parse_string(f.get_as_text())
	_bands = cfg["bands"]
	_target = Vector3(0.0, cfg["target_height_m"], 0.0)
	add_child(camera)
	camera.current = true
	camera.far = 6000.0
	_apply()

func set_band(band_name: String) -> void:
	for i in _bands.size():
		if _bands[i]["name"] == band_name:
			_band_index = i
			_apply()
			return
	push_error("unknown camera band: " + band_name)

func set_view(azimuth_deg: float, height_m: float, radius_m: float) -> void:
	_azimuth_deg = azimuth_deg
	_height_m = height_m
	_radius_m = radius_m
	_apply()

func set_target_xz(x: float, z: float) -> void:
	_target.x = x
	_target.z = z
	_apply()

func band_name() -> String:
	return _bands[_band_index]["name"]

func describe() -> String:
	return "band=%s az=%.1f h=%.1f r=%.1f" % [band_name(), _azimuth_deg, _height_m, _radius_m]

func _apply() -> void:
	var band: Dictionary = _bands[_band_index]
	# The clamp IS the contract. No caller can position the camera outside it.
	_height_m = clamp(_height_m, band["height_m"][0], band["height_m"][1])
	_radius_m = clamp(_radius_m, band["radius_m"][0], band["radius_m"][1])
	var az := deg_to_rad(_azimuth_deg)
	# Azimuth measured from north (-Z), clockwise, matching sun convention.
	var offset := Vector3(sin(az) * _radius_m, 0.0, -cos(az) * _radius_m)
	camera.position = _target + offset + Vector3(0.0, _height_m - _target.y, 0.0)
	if camera.is_inside_tree():
		camera.look_at(_target)
	else:
		camera.look_at_from_position(camera.position, _target)
