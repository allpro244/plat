class_name GameUi
extends Control
## Native Broadway & Wall chrome over the 3D city — parchment panels, vitals
## strip, parcel glance card, command rail. Data comes from main.gd; this
## file owns layout and paint only.

signal advance_pressed
signal buy_pressed
signal listings_pressed
signal break_ground_pressed
signal close_parcel_pressed
signal owners_lens_pressed(on: bool)

var _topbar: PanelContainer
var _brand: Label
var _firm_line: Label
var _city_line: Label
var _vitals: HBoxContainer
var _vitals_map: Dictionary = {}
var _actions: HBoxContainer
var _status: Label
var _help: Label
var _fps_label: Label

var _parcel_panel: PanelContainer
var _parcel_address: Label
var _parcel_bbl: Label
var _chip_row: HBoxContainer
var _grid: GridContainer
var _deal_box: VBoxContainer
var _deal_head: Label
var _deal_note: Label
var _buy_btn: Button
var _close_btn: Button

var _rail: PanelContainer
var _advance_btn: Button
var _listings_btn: Button
var _owners_btn: Button
var _break_btn: Button
var _buy_rail_btn: Button

var _owners_on := false
var _parcel_data: Dictionary = {}
var _campaign_active := false


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_topbar()
	_build_parcel_panel()
	_build_rail()
	_build_footer()


func _build_topbar() -> void:
	_topbar = PanelContainer.new()
	_topbar.set_anchors_preset(PRESET_TOP_WIDE)
	_topbar.offset_bottom = 72
	_topbar.add_theme_stylebox_override("panel", BwTheme.topbar_bg())
	_topbar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_topbar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.set_anchors_preset(PRESET_FULL_RECT)
	row.offset_left = 18
	row.offset_right = -18
	row.offset_top = 10
	row.offset_bottom = -10
	_topbar.add_child(row)

	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 2)
	row.add_child(brand)
	_brand = Label.new()
	_brand.text = "plat"
	_brand.add_theme_font_override("font", BwTheme.serif())
	_brand.add_theme_font_size_override("font_size", 23)
	_brand.add_theme_color_override("font_color", BwTheme.INK)
	brand.add_child(_brand)
	_firm_line = Label.new()
	_firm_line.add_theme_font_override("font", BwTheme.sans())
	_firm_line.add_theme_font_size_override("font_size", 13)
	_firm_line.add_theme_color_override("font_color", BwTheme.INK)
	brand.add_child(_firm_line)
	_city_line = Label.new()
	_city_line.add_theme_font_override("font", BwTheme.sans())
	_city_line.add_theme_font_size_override("font_size", 11)
	_city_line.add_theme_color_override("font_color", BwTheme.INK_DIM)
	brand.add_child(_city_line)

	_vitals = HBoxContainer.new()
	_vitals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vitals.add_theme_constant_override("separation", 14)
	_vitals.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_vitals)

	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	row.add_child(_actions)
	_fps_label = Label.new()
	_fps_label.add_theme_font_override("font", BwTheme.mono())
	_fps_label.add_theme_font_size_override("font_size", 12)
	_fps_label.add_theme_color_override("font_color", BwTheme.SUCCESS)
	_actions.add_child(_fps_label)


func _build_parcel_panel() -> void:
	_parcel_panel = PanelContainer.new()
	_parcel_panel.visible = false
	_parcel_panel.custom_minimum_size = Vector2(330, 0)
	_parcel_panel.set_anchors_preset(PRESET_TOP_RIGHT)
	_parcel_panel.offset_left = -344
	_parcel_panel.offset_top = 82
	_parcel_panel.offset_right = -14
	_parcel_panel.offset_bottom = -80
	_parcel_panel.add_theme_stylebox_override("panel", BwTheme.panel_bg())
	_parcel_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_parcel_panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.offset_left = 15
	scroll.offset_top = 14
	scroll.offset_right = -15
	scroll.offset_bottom = -14
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_parcel_panel.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	body.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	_parcel_address = Label.new()
	_parcel_address.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_parcel_address.add_theme_font_override("font", BwTheme.serif())
	_parcel_address.add_theme_font_size_override("font_size", 20)
	_parcel_address.add_theme_color_override("font_color", BwTheme.INK)
	titles.add_child(_parcel_address)
	_parcel_bbl = Label.new()
	_parcel_bbl.add_theme_font_override("font", BwTheme.mono())
	_parcel_bbl.add_theme_font_size_override("font_size", 11)
	_parcel_bbl.add_theme_color_override("font_color", BwTheme.INK_DIM)
	titles.add_child(_parcel_bbl)
	_close_btn = Button.new()
	_close_btn.text = "×"
	_close_btn.flat = true
	_close_btn.add_theme_color_override("font_color", BwTheme.INK_DIM)
	_close_btn.add_theme_font_override("font", BwTheme.sans())
	_close_btn.add_theme_font_size_override("font_size", 20)
	_close_btn.pressed.connect(func() -> void:
		hide_parcel()
		close_parcel_pressed.emit())
	head.add_child(_close_btn)

	_chip_row = HBoxContainer.new()
	_chip_row.add_theme_constant_override("separation", 6)
	body.add_child(_chip_row)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 5)
	body.add_child(_grid)

	_deal_box = VBoxContainer.new()
	_deal_box.add_theme_constant_override("separation", 6)
	body.add_child(_deal_box)
	_deal_head = Label.new()
	_deal_head.add_theme_font_override("font", BwTheme.serif())
	_deal_head.add_theme_font_size_override("font_size", 14)
	_deal_head.add_theme_color_override("font_color", BwTheme.INK)
	_deal_box.add_child(_deal_head)
	_deal_note = Label.new()
	_deal_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deal_note.add_theme_font_override("font", BwTheme.sans())
	_deal_note.add_theme_font_size_override("font_size", 12)
	_deal_note.add_theme_color_override("font_color", BwTheme.INK_DIM)
	_deal_box.add_child(_deal_note)
	_buy_btn = Button.new()
	_buy_btn.text = "Buy at ask"
	_buy_btn.add_theme_stylebox_override("normal", BwTheme.buy_btn())
	_buy_btn.add_theme_stylebox_override("hover", BwTheme.buy_btn())
	_buy_btn.add_theme_stylebox_override("pressed", BwTheme.buy_btn())
	_buy_btn.add_theme_color_override("font_color", Color("#f6efdc"))
	_buy_btn.add_theme_font_override("font", BwTheme.sans())
	_buy_btn.add_theme_font_size_override("font_size", 12)
	_buy_btn.pressed.connect(func() -> void: buy_pressed.emit())
	_deal_box.add_child(_buy_btn)


func _build_rail() -> void:
	_rail = PanelContainer.new()
	_rail.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_rail.offset_top = -56
	_rail.offset_bottom = -12
	_rail.add_theme_stylebox_override("panel", BwTheme.panel_bg(0.92))
	_rail.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rail)
	var row := HBoxContainer.new()
	row.set_anchors_preset(PRESET_CENTER)
	row.offset_left = -280
	row.offset_right = 280
	row.offset_top = -22
	row.offset_bottom = 22
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_rail.add_child(row)

	_break_btn = _make_lens_btn("Break ground")
	_break_btn.pressed.connect(func() -> void: break_ground_pressed.emit())
	row.add_child(_break_btn)

	_advance_btn = Button.new()
	_advance_btn.text = "Advance ▸"
	_advance_btn.add_theme_stylebox_override("normal", BwTheme.advance_btn())
	_advance_btn.add_theme_stylebox_override("hover", BwTheme.advance_btn())
	_advance_btn.add_theme_stylebox_override("pressed", BwTheme.advance_btn())
	_advance_btn.add_theme_color_override("font_color", Color("#f6efdc"))
	_advance_btn.add_theme_font_override("font", BwTheme.serif())
	_advance_btn.add_theme_font_size_override("font_size", 15)
	_advance_btn.pressed.connect(func() -> void: advance_pressed.emit())
	row.add_child(_advance_btn)

	_buy_rail_btn = Button.new()
	_buy_rail_btn.text = "Buy"
	_buy_rail_btn.add_theme_stylebox_override("normal", BwTheme.lens_btn())
	_buy_rail_btn.add_theme_stylebox_override("hover", BwTheme.lens_btn())
	_buy_rail_btn.add_theme_color_override("font_color", BwTheme.INK)
	_buy_rail_btn.pressed.connect(func() -> void: buy_pressed.emit())
	row.add_child(_buy_rail_btn)

	_listings_btn = _make_lens_btn("Listings (Tab)")
	_listings_btn.pressed.connect(func() -> void: listings_pressed.emit())
	row.add_child(_listings_btn)

	_owners_btn = _make_lens_btn("◫ Owners")
	_owners_btn.pressed.connect(func() -> void:
		_owners_on = not _owners_on
		_style_lens(_owners_btn, _owners_on, true)
		owners_lens_pressed.emit(_owners_on))
	row.add_child(_owners_btn)


func _build_footer() -> void:
	_status = Label.new()
	_status.set_anchors_preset(PRESET_BOTTOM_LEFT)
	_status.offset_left = 16
	_status.offset_top = -36
	_status.offset_bottom = -60
	_status.add_theme_font_override("font", BwTheme.sans())
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", BwTheme.INK_DIM)
	add_child(_status)

	_help = Label.new()
	_help.set_anchors_preset(PRESET_BOTTOM_LEFT)
	_help.offset_left = 16
	_help.offset_top = -120
	_help.offset_right = 520
	_help.offset_bottom = -64
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.add_theme_font_override("font", BwTheme.sans())
	_help.add_theme_font_size_override("font_size", 10)
	_help.add_theme_color_override("font_color", Color(BwTheme.INK_DIM.r, BwTheme.INK_DIM.g, BwTheme.INK_DIM.b, 0.85))
	add_child(_help)


func _make_lens_btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	_style_lens(b, false, false)
	return b


func _style_lens(b: Button, on: bool, teal: bool) -> void:
	var sb := BwTheme.lens_btn(on, teal)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", Color("#fffaef") if on else BwTheme.INK_DIM)
	b.add_theme_font_override("font", BwTheme.sans())
	b.add_theme_font_size_override("font_size", 12)


func _stat(label: String, key: String, width: int = 0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	if width > 0:
		box.custom_minimum_size.x = width
	var lab := Label.new()
	lab.text = label.to_upper()
	lab.add_theme_font_override("font", BwTheme.sans())
	lab.add_theme_font_size_override("font_size", 10)
	lab.add_theme_color_override("font_color", BwTheme.INK_DIM)
	box.add_child(lab)
	var val := Label.new()
	val.name = "Value"
	val.add_theme_font_override("font", BwTheme.mono())
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", BwTheme.INK)
	box.add_child(val)
	_vitals.add_child(box)
	_vitals_map[key] = val
	return box


func refresh_vitals(hud_game: Dictionary, campaign: bool) -> void:
	_campaign_active = campaign
	if _vitals_map.is_empty():
		_stat("Date", "date", 96)
		_stat("Cash", "cash", 88)
		_stat("Holdings", "holdings", 72)
		_stat("Occupancy", "occ", 72)
		_stat("For sale", "listings", 72)

	if campaign and not hud_game.is_empty():
		_firm_line.text = str(hud_game.get("firm", "your firm"))
		_city_line.text = str(hud_game.get("city", "?")).to_upper()
		_set_stat("date", str(hud_game.get("date", "—")))
		var cash := float(hud_game.get("cash", 0))
		_set_stat("cash", "$%.2fM" % (cash / 1e6), cash < 0)
		_set_stat("holdings", str(int(hud_game.get("holdings", 0))))
		var occ = hud_game.get("occ")
		if occ != null:
			_set_stat("occ", "%.0f%%" % (float(occ) * 100.0))
		else:
			_set_stat("occ", "—")
		_set_stat("listings", str(int(hud_game.get("listings", 0))))
		_break_btn.visible = false
		_advance_btn.visible = true
		_buy_rail_btn.visible = true
	else:
		_firm_line.text = "3D city renderer"
		_city_line.text = "F1 TO FOUND A FIRM AND PLAY"
		for k in ["date", "cash", "holdings", "occ", "listings"]:
			if _vitals_map.has(k):
				_set_stat(k, "—")
		_break_btn.visible = true
		_advance_btn.visible = false
		_buy_rail_btn.visible = false

	var att: Array = hud_game.get("attention", [])
	if not att.is_empty():
		_city_line.text += "  ·  ! " + " · ".join(PackedStringArray(att))


func _set_stat(key: String, value: String, bad: bool = false) -> void:
	if not _vitals_map.has(key):
		return
	var lab: Label = _vitals_map[key]
	lab.text = value
	lab.add_theme_color_override("font_color", BwTheme.DANGER if bad else BwTheme.INK)


func set_fps(fps: float) -> void:
	var col := BwTheme.SUCCESS if fps >= 55 else (Color("#9a7a1c") if fps >= 30 else BwTheme.DANGER)
	_fps_label.text = "%.0f fps" % fps
	_fps_label.add_theme_color_override("font_color", col)


func set_status(text: String) -> void:
	_status.text = text


func set_help(text: String, visible: bool) -> void:
	_help.text = text
	_help.visible = visible


func set_camera_hint(desc: String) -> void:
	if desc.is_empty():
		return
	_status.text = desc if _status.text.is_empty() else _status.text


func set_owners_lens(on: bool) -> void:
	_owners_on = on
	_style_lens(_owners_btn, on, true)


func show_parcel(b: Dictionary, campaign: bool) -> void:
	_parcel_data = b
	_campaign_active = campaign
	_parcel_panel.visible = true
	var cls := str(b.get("cls", "?"))
	var district := str(b.get("district", "?"))
	_parcel_address.text = _class_title(cls)
	_parcel_bbl.text = "Parcel %s · %s" % [str(b.get("bbl", "?")), district.to_upper()]

	_clear_children(_chip_row)
	_add_chip(_class_title(cls), BwTheme.class_color(cls))
	_add_chip(district.to_upper(), BwTheme.INK_DIM, true)
	if b.get("held", false):
		_add_chip("OWNED", BwTheme.GOLD)
	if b.get("listed", false) and not b.get("held", false):
		_add_chip("FOR SALE", BwTheme.TEAL)
	if b.get("distress", false):
		_add_chip("MOTIVATED", BwTheme.DANGER)

	_clear_children(_grid)
	_grid_row("Building", _fmt_sf(float(b.get("sqft", 0.0))) + " sf")
	_grid_row("Lot", _fmt_sf(float(b.get("lot_sqft", 0.0))) + " sf")
	_grid_row("Floors", str(int(b.get("floors", 0))))
	_grid_row("Built", str(int(b.get("year", 0))))
	if float(b.get("occ", -1.0)) >= 0.0:
		_grid_row("Occupancy", "%.0f%%" % (float(b["occ"]) * 100.0))
	if float(b.get("value", -1.0)) > 0.0:
		_grid_row("Appraised", "$%.2fM" % (float(b["value"]) / 1e6))

	var listed: bool = bool(b.get("listed", false)) and not bool(b.get("held", false))
	var has_ask: bool = float(b.get("ask", -1.0)) > 0.0
	_deal_box.visible = listed or has_ask or b.get("held", false)
	if listed:
		_deal_head.text = "For sale"
		var ask := float(b.get("ask", 0.0))
		_deal_note.text = "Ask $%.2fM%s" % [ask / 1e6,
				" — motivated seller" if b.get("distress", false) else ""]
		_buy_btn.visible = campaign
		_buy_btn.disabled = not campaign
	elif has_ask:
		_deal_head.text = "Off-market"
		_deal_note.text = "Indicative ask $%.2fM" % (float(b["ask"]) / 1e6)
		_buy_btn.visible = false
	elif b.get("held", false):
		_deal_head.text = "Your holding"
		_deal_note.text = "This deed is on your balance sheet."
		_buy_btn.visible = false
	else:
		_deal_box.visible = false


func is_parcel_visible() -> bool:
	return _parcel_panel.visible


func hide_parcel() -> void:
	_parcel_panel.visible = false
	_parcel_data = {}


func parcel_debug_text() -> String:
	if _parcel_data.is_empty():
		return ""
	var lines: PackedStringArray = [
		_parcel_bbl.text,
		_parcel_address.text,
	]
	for c in _chip_row.get_children():
		if c is Label:
			lines.append((c as Label).text)
	for i in range(0, _grid.get_child_count(), 2):
		if i + 1 < _grid.get_child_count():
			var k: Label = _grid.get_child(i) as Label
			var v: Label = _grid.get_child(i + 1) as Label
			lines.append("%s: %s" % [k.text, v.text])
	if _deal_box.visible:
		lines.append(_deal_head.text + " — " + _deal_note.text)
	return " | ".join(lines)


func show_error(title: String, detail: String) -> void:
	show_parcel({}, false)
	_parcel_panel.visible = true
	_parcel_address.text = title
	_parcel_bbl.text = ""
	_clear_children(_chip_row)
	_clear_children(_grid)
	_deal_box.visible = true
	_deal_head.text = ""
	_deal_note.text = detail
	_buy_btn.visible = false


static func _class_title(cls: String) -> String:
	match cls:
		"office": return "Office"
		"retail": return "Retail"
		"industrial": return "Industrial"
		"multifamily": return "Multifamily"
		"mix": return "Mixed use"
		"land": return "Vacant lot"
		"hotel": return "Hotel"
		_: return cls.capitalize()


func _add_chip(text: String, bg: Color, muted: bool = false) -> void:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", BwTheme.chip_muted() if muted else BwTheme.chip_bg(bg))
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_override("font", BwTheme.sans())
	lab.add_theme_font_size_override("font_size", 11)
	if muted:
		lab.add_theme_color_override("font_color", BwTheme.INK_DIM)
	else:
		lab.add_theme_color_override("font_color", Color("#fdfbf4"))
	chip.add_child(lab)
	_chip_row.add_child(chip)


func _grid_row(key: String, value: String) -> void:
	var k := Label.new()
	k.text = key
	k.add_theme_font_override("font", BwTheme.sans())
	k.add_theme_font_size_override("font_size", 13)
	k.add_theme_color_override("font_color", BwTheme.INK_DIM)
	_grid.add_child(k)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_font_override("font", BwTheme.mono())
	v.add_theme_font_size_override("font_size", 13)
	v.add_theme_color_override("font_color", BwTheme.INK)
	_grid.add_child(v)


static func _fmt_sf(v: float) -> String:
	var s := str(int(roundf(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


static func _clear_children(node: Node) -> void:
	while node.get_child_count() > 0:
		var c := node.get_child(0)
		node.remove_child(c)
		c.free()
