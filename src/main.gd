extends Node3D
## Interactive entry: builds the default city and orbits with the keys below.
## The rig still clamps to its bands — interactive use gets no special camera.
##   arrows: orbit / zoom   page up/down: height   1/2/3: band   T/G: time of day

var city: CityScene
var az := 225.0
var height := 105.0
var radius := 215.0
var time_of_day := 15.5

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if city:
		city.queue_free()
	city = CityScene.new({"time": time_of_day})
	add_child(city)

func _process(delta: float) -> void:
	var changed := false
	if Input.is_key_pressed(KEY_LEFT):
		az -= 40.0 * delta
		changed = true
	if Input.is_key_pressed(KEY_RIGHT):
		az += 40.0 * delta
		changed = true
	if Input.is_key_pressed(KEY_UP):
		radius -= 80.0 * delta
		changed = true
	if Input.is_key_pressed(KEY_DOWN):
		radius += 80.0 * delta
		changed = true
	if Input.is_key_pressed(KEY_PAGEUP):
		height += 60.0 * delta
		changed = true
	if Input.is_key_pressed(KEY_PAGEDOWN):
		height -= 60.0 * delta
		changed = true
	if changed and city.rig:
		city.rig.set_view(az, height, radius)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: city.rig.set_band("near")
			KEY_2: city.rig.set_band("mid")
			KEY_3: city.rig.set_band("far")
			KEY_T:
				time_of_day = clampf(time_of_day + 0.5, 4.0, 22.0)
				_rebuild()
			KEY_G:
				time_of_day = clampf(time_of_day - 0.5, 4.0, 22.0)
				_rebuild()
