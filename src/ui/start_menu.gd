class_name StartMenu
extends Control
## Broadway & Wall start room: Continue, three dials, Break ground.
## Labels match plat-econ citygen lists. Numbers come from the runner.

signal break_ground_pressed(size: String, density: String, cash: int)
signal continue_pressed(path: String)

const SIZES := [
	["hamlet", "Hamlet", "A few hundred lots — same cheque, small pond."],
	["town", "Town", "Half the standard map. Every mistake is visible."],
	["city", "City", "The standard island — about fourteen hundred lots."],
	["metro", "Metropolis", "Twice the land. Same cheque, deeper pond."],
	["giant", "Great City", "Four times the land. You are a minnow."],
]
const DEVS := [
	["landing", "Landing", "Two thirds still grass. You watch a city start."],
	["village", "Young town", "The standard opening. Two fifths unbuilt."],
	["town1900", "Working town", "Filled in around the harbour. A third vacant."],
	["harbour", "Established", "A real skyline. 27% vacant, towers to forty."],
	["metropolis", "Metropolis", "14% vacant. A game about buying what exists."],
]
const CASH := [
	[1000000, "Age 28 · $1.0M", "One small building outright, almost no reserve."],
	[2500000, "Age 35 · $2.5M", "The standard opening. Room to be wrong once."],
	[5000000, "Age 42 · $5.0M", "A real first book."],
	[10000000, "Age 48 · $10M", "A small institutional platform."],
	[20000000, "Age 52 · $20M", "A serious acquisition book."],
]

var _size := "city"
var _density := "village"
var _cash := 2500000
var _resume_path := ""
var _continue_btn: Button
var _size_btns: Dictionary = {}
var _dev_btns: Dictionary = {}
var _cash_btns: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var wash := ColorRect.new()
	wash.set_anchors_preset(PRESET_FULL_RECT)
	wash.color = Color(0.07, 0.12, 0.16, 0.72)
	add_child(wash)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Broadway & Wall"
	title.add_theme_font_override("font", BwTheme.serif())
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#f4ead2"))
	col.add_child(title)
	var sub := Label.new()
	sub.text = "A hundred years of somebody else’s city, and whatever you can hold of it."
	sub.add_theme_font_override("font", BwTheme.sans())
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color("#93aab6"))
	col.add_child(sub)

	_continue_btn = Button.new()
	_continue_btn.visible = false
	_continue_btn.add_theme_stylebox_override("normal", BwTheme.start_opt(true))
	_continue_btn.add_theme_stylebox_override("hover", BwTheme.start_opt(true))
	_continue_btn.add_theme_color_override("font_color", BwTheme.INK)
	_continue_btn.add_theme_font_override("font", BwTheme.serif())
	_continue_btn.add_theme_font_size_override("font_size", 18)
	_continue_btn.pressed.connect(func() -> void:
		if _resume_path != "":
			continue_pressed.emit(_resume_path))
	col.add_child(_continue_btn)

	var or_line := Label.new()
	or_line.text = "CUT A TOWN AND BREAK GROUND"
	or_line.add_theme_font_override("font", BwTheme.sans())
	or_line.add_theme_font_size_override("font_size", 11)
	or_line.add_theme_color_override("font_color", Color("#93aab6"))
	col.add_child(or_line)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	scroll.add_child(cols)
	_size_btns = _opt_col(cols, "how big", SIZES, func(id: String) -> void:
		_size = id
		_paint_opts(_size_btns, _size))
	_dev_btns = _opt_col(cols, "how built up", DEVS, func(id: String) -> void:
		_density = id
		_paint_opts(_dev_btns, _density))
	var cash_rows: Array = []
	for c in CASH:
		cash_rows.append([str(c[0]), str(c[1]), str(c[2])])
	_cash_btns = _opt_col(cols, "age · capital", cash_rows, func(id: String) -> void:
		_cash = int(id)
		_paint_opts(_cash_btns, id))
	_paint_opts(_size_btns, _size)
	_paint_opts(_dev_btns, _density)
	_paint_opts(_cash_btns, str(_cash))

	var ground := Button.new()
	ground.text = "Break ground"
	ground.add_theme_stylebox_override("normal", BwTheme.advance_btn())
	ground.add_theme_stylebox_override("hover", BwTheme.advance_btn())
	ground.add_theme_stylebox_override("pressed", BwTheme.advance_btn())
	ground.add_theme_color_override("font_color", Color("#f6efdc"))
	ground.add_theme_font_override("font", BwTheme.serif())
	ground.add_theme_font_size_override("font_size", 18)
	ground.custom_minimum_size = Vector2(0, 48)
	ground.pressed.connect(func() -> void:
		break_ground_pressed.emit(_size, _density, _cash))
	col.add_child(ground)


func set_resume(path: String, label: String) -> void:
	_resume_path = path
	_continue_btn.visible = path != ""
	_continue_btn.text = "Continue  ·  " + label + "   Resume ▸" if path != "" else ""


func _opt_col(parent: HBoxContainer, head: String, rows: Array, pick: Callable) -> Dictionary:
	var sheet := PanelContainer.new()
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.add_theme_stylebox_override("panel", BwTheme.panel_bg(0.96))
	parent.add_child(sheet)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	sheet.add_child(box)
	var h := Label.new()
	h.text = head.to_upper()
	BwTheme.style_label(h, 10, false, true)
	box.add_child(h)
	var btns := {}
	for row in rows:
		var b := Button.new()
		b.text = "%s\n%s" % [row[1], row[2]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", BwTheme.sans())
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", BwTheme.INK)
		var id := str(row[0])
		b.pressed.connect(func() -> void: pick.call(id))
		box.add_child(b)
		btns[id] = b
	return btns


func _paint_opts(btns: Dictionary, on_id: String) -> void:
	for id in btns:
		var b: Button = btns[id]
		var sb := BwTheme.start_opt(id == on_id)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
