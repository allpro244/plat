class_name GameUi
extends Control
## Broadway & Wall chrome: start room, full-width bar, glance card,
## marketplace desk, inbox. Data from main.gd; this file paints.

signal advance_pressed
signal year_pressed
signal skip_pressed
signal buy_pressed
signal listing_chosen(bbl: String)
signal page_opened(page: String)
signal break_ground_pressed(size: String, density: String, cash: int)
signal continue_pressed(path: String)
signal close_parcel_pressed
signal lens_pressed(name: String, on: bool)
signal attention_opened(item: Dictionary)

var start: StartMenu

var _topbar: Panel
var _brand: Label
var _firm_line: Label
var _city_line: Label
var _vitals: HBoxContainer
var _vitals_map: Dictionary = {}
var _job_btns: Dictionary = {}
var _lens_btns: Dictionary = {}
var _advance_btn: Button
var _year_btn: Button
var _fps_label: Label

var _parcel: Panel
var _parcel_address: Label
var _parcel_bbl: Label
var _chip_row: HBoxContainer
var _grid: GridContainer
var _deal_head: Label
var _deal_note: Label
var _buy_btn: Button
var _full_btn: Button

var _inbox: Panel
var _inbox_body: VBoxContainer

var _page: Control
var _page_kicker: Label
var _page_title: Label
var _page_sub: Label
var _page_body: VBoxContainer

var _parcel_data: Dictionary = {}
var _campaign := false
var _page_name := ""
var _lenses: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_topbar()
	_build_inbox()
	_build_parcel()
	_build_page()
	start = StartMenu.new()
	add_child(start)
	start.break_ground_pressed.connect(func(s: String, d: String, c: int) -> void:
		break_ground_pressed.emit(s, d, c))
	start.continue_pressed.connect(func(p: String) -> void:
		continue_pressed.emit(p))
	set_playing(false)


func set_playing(on: bool) -> void:
	_campaign = on
	start.visible = not on
	_topbar.visible = on
	_inbox.visible = on
	if not on:
		_parcel.visible = false
		_page.visible = false


func set_resume(path: String, label: String) -> void:
	start.set_resume(path, label)


func _build_topbar() -> void:
	_topbar = Panel.new()
	_topbar.set_anchors_preset(PRESET_TOP_WIDE)
	_topbar.offset_bottom = 96
	_topbar.offset_right = 0
	_topbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_topbar.add_theme_stylebox_override("panel", BwTheme.topbar_bg())
	_topbar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_topbar)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	_topbar.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	pad.add_child(col)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 16)
	col.add_child(row1)

	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	row1.add_child(brand)
	_brand = Label.new()
	_brand.text = "Broadway & Wall"
	_brand.add_theme_font_override("font", BwTheme.serif())
	_brand.add_theme_font_size_override("font_size", 20)
	_brand.add_theme_color_override("font_color", BwTheme.INK)
	brand.add_child(_brand)
	_firm_line = Label.new()
	BwTheme.style_label(_firm_line, 12)
	brand.add_child(_firm_line)
	_city_line = Label.new()
	BwTheme.style_label(_city_line, 10, false, true)
	brand.add_child(_city_line)

	_vitals = HBoxContainer.new()
	_vitals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vitals.add_theme_constant_override("separation", 14)
	row1.add_child(_vitals)
	_stat("Date", "date", 88)
	_stat("Cash", "cash", 80)
	_stat("Line", "line", 80)
	_stat("CF / yr", "cf", 80)
	_stat("Occupancy", "occ", 72)
	_stat("Book", "book", 72)
	_stat("For sale", "listings", 64)

	_fps_label = Label.new()
	BwTheme.style_label(_fps_label, 11, true, true)
	row1.add_child(_fps_label)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	col.add_child(row2)
	for job in [["acquire", "Acquire"], ["assets", "Assets"], ["capital", "Capital"],
			["world", "World"], ["economy", "Economy"]]:
		var b := _lens(job[1], false)
		var id: String = job[0]
		b.pressed.connect(func() -> void: _open_job(id))
		row2.add_child(b)
		_job_btns[id] = b
	var sep := Label.new()
	sep.text = " "
	row2.add_child(sep)
	for lens in [["listings", "◉ Market"], ["owners", "◫ Owners"]]:
		var b := _lens(lens[1], false)
		var id: String = lens[0]
		b.pressed.connect(func() -> void:
			var on := not bool(_lenses.get(id, false))
			_lenses[id] = on
			_style_btn(b, on, id == "owners")
			lens_pressed.emit(id, on))
		row2.add_child(b)
		_lens_btns[id] = b

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(spacer)

	_advance_btn = Button.new()
	_advance_btn.text = "Advance ▸"
	_advance_btn.add_theme_stylebox_override("normal", BwTheme.advance_btn())
	_advance_btn.add_theme_stylebox_override("hover", BwTheme.advance_btn())
	_advance_btn.add_theme_stylebox_override("pressed", BwTheme.advance_btn())
	_advance_btn.add_theme_color_override("font_color", Color("#f6efdc"))
	_advance_btn.add_theme_font_override("font", BwTheme.serif())
	_advance_btn.add_theme_font_size_override("font_size", 15)
	_advance_btn.pressed.connect(func() -> void: advance_pressed.emit())
	row2.add_child(_advance_btn)
	_year_btn = _lens("Year ▸▸", false)
	_year_btn.pressed.connect(func() -> void: year_pressed.emit())
	row2.add_child(_year_btn)
	var skip := _lens("Skip", false)
	skip.pressed.connect(func() -> void: skip_pressed.emit())
	row2.add_child(skip)


func _stat(label: String, key: String, width: int) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size.x = width
	var lab := Label.new()
	lab.text = label.to_upper()
	BwTheme.style_label(lab, 9, false, true)
	box.add_child(lab)
	var val := Label.new()
	BwTheme.style_label(val, 13, true)
	box.add_child(val)
	_vitals.add_child(box)
	_vitals_map[key] = val


func _lens(text: String, on: bool) -> Button:
	var b := Button.new()
	b.text = text
	_style_btn(b, on, false)
	return b


func _style_btn(b: Button, on: bool, teal: bool) -> void:
	var sb := BwTheme.lens_btn(on, teal)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", Color("#fffaef") if on else BwTheme.INK_DIM)
	b.add_theme_font_override("font", BwTheme.sans())
	b.add_theme_font_size_override("font_size", 12)


func _build_inbox() -> void:
	_inbox = Panel.new()
	_inbox.set_anchors_preset(PRESET_TOP_LEFT)
	_inbox.offset_left = 14
	_inbox.offset_top = 108
	_inbox.offset_right = 360
	_inbox.offset_bottom = 250
	_inbox.add_theme_stylebox_override("panel", BwTheme.panel_bg(0.94))
	_inbox.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_inbox)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	_inbox.add_child(pad)
	_inbox_body = VBoxContainer.new()
	_inbox_body.add_theme_constant_override("separation", 6)
	pad.add_child(_inbox_body)


func _build_parcel() -> void:
	_parcel = Panel.new()
	_parcel.visible = false
	_parcel.set_anchors_preset(PRESET_TOP_RIGHT)
	_parcel.offset_left = -344
	_parcel.offset_top = 108
	_parcel.offset_right = -14
	_parcel.offset_bottom = 520
	_parcel.add_theme_stylebox_override("panel", BwTheme.panel_bg())
	_parcel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_parcel)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 15)
	pad.add_theme_constant_override("margin_right", 15)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	_parcel.add_child(pad)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	pad.add_child(body)

	var head := HBoxContainer.new()
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
	BwTheme.style_label(_parcel_bbl, 11, true, true)
	titles.add_child(_parcel_bbl)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.add_theme_color_override("font_color", BwTheme.INK_DIM)
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(func() -> void:
		hide_parcel()
		close_parcel_pressed.emit())
	head.add_child(close)

	_chip_row = HBoxContainer.new()
	_chip_row.add_theme_constant_override("separation", 6)
	body.add_child(_chip_row)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 5)
	body.add_child(_grid)
	_deal_head = Label.new()
	_deal_head.add_theme_font_override("font", BwTheme.serif())
	_deal_head.add_theme_font_size_override("font_size", 14)
	_deal_head.add_theme_color_override("font_color", BwTheme.INK)
	body.add_child(_deal_head)
	_deal_note = Label.new()
	_deal_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BwTheme.style_label(_deal_note, 12, false, true)
	body.add_child(_deal_note)
	_buy_btn = Button.new()
	_buy_btn.text = "Buy at ask"
	_buy_btn.add_theme_stylebox_override("normal", BwTheme.buy_btn())
	_buy_btn.add_theme_stylebox_override("hover", BwTheme.buy_btn())
	_buy_btn.add_theme_stylebox_override("pressed", BwTheme.buy_btn())
	_buy_btn.add_theme_color_override("font_color", Color("#f6efdc"))
	_buy_btn.add_theme_font_override("font", BwTheme.sans())
	_buy_btn.pressed.connect(func() -> void: buy_pressed.emit())
	body.add_child(_buy_btn)
	_full_btn = _lens("Full view", false)
	_full_btn.pressed.connect(func() -> void: open_page("property"))
	body.add_child(_full_btn)


func _build_page() -> void:
	_page = Control.new()
	_page.visible = false
	_page.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_page.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_page)
	var wash := ColorRect.new()
	wash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	wash.color = Color(0.09, 0.08, 0.05, 0.48)
	wash.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			hide_page())
	_page.add_child(wash)
	var sheet := Panel.new()
	sheet.set_anchors_preset(PRESET_CENTER)
	sheet.offset_left = -520
	sheet.offset_right = 520
	sheet.offset_top = -320
	sheet.offset_bottom = 320
	sheet.add_theme_stylebox_override("panel", BwTheme.page_sheet())
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_page.add_child(sheet)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 28)
	pad.add_theme_constant_override("margin_right", 28)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	sheet.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	_page_kicker = Label.new()
	BwTheme.style_label(_page_kicker, 10, false, true)
	titles.add_child(_page_kicker)
	_page_title = Label.new()
	_page_title.add_theme_font_override("font", BwTheme.serif())
	_page_title.add_theme_font_size_override("font_size", 28)
	_page_title.add_theme_color_override("font_color", BwTheme.INK)
	titles.add_child(_page_title)
	_page_sub = Label.new()
	BwTheme.style_label(_page_sub, 13, false, true)
	titles.add_child(_page_sub)
	var x := Button.new()
	x.text = "×"
	x.flat = true
	x.add_theme_font_size_override("font_size", 22)
	x.add_theme_color_override("font_color", BwTheme.INK_DIM)
	x.pressed.connect(hide_page)
	head.add_child(x)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_page_body = VBoxContainer.new()
	_page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_page_body)


func refresh_vitals(hud: Dictionary, campaign: bool) -> void:
	_campaign = campaign
	if not campaign:
		return
	_firm_line.text = str(hud.get("firm", "your firm"))
	_city_line.text = str(hud.get("city", "")).to_upper()
	_set_stat("date", "%s  ·  Yr %s" % [str(hud.get("date", "—")), str(hud.get("year", 1))])
	var cash := float(hud.get("cash", 0))
	_set_stat("cash", _usd(cash), cash < 0)
	var line := float(hud.get("line", 0))
	var drawn := float(hud.get("lineDrawn", 0))
	_set_stat("line", _usd(drawn) + " / " + _usd(line) if drawn > 0 else (_usd(line) if line > 0 else "—"), drawn > 0)
	var cf := float(hud.get("cf", 0))
	_set_stat("cf", _usd(cf * 12.0) if hud.get("cf") != null else "—", cf < 0)
	var occ = hud.get("occ")
	_set_stat("occ", "%.0f%%" % (float(occ) * 100.0) if occ != null else "—")
	_set_stat("book", str(hud.get("book", "—")), bool(hud.get("bookBad", false)))
	_set_stat("listings", str(int(hud.get("listings", 0))))
	var items: Array = hud.get("attentionItems", [])
	if items.is_empty():
		for s in hud.get("attention", []):
			items.append({"label": str(s), "page": "market", "bbl": ""})
	set_inbox(items)


func _set_stat(key: String, value: String, bad: bool = false) -> void:
	if not _vitals_map.has(key):
		return
	var lab: Label = _vitals_map[key]
	lab.text = value
	lab.add_theme_color_override("font_color", BwTheme.DANGER if bad else BwTheme.INK)


func set_fps(fps: float) -> void:
	_fps_label.text = "%.0f fps" % fps
	_fps_label.add_theme_color_override("font_color",
			BwTheme.SUCCESS if fps >= 55 else (Color("#9a7a1c") if fps >= 30 else BwTheme.DANGER))


func set_status(_text: String) -> void:
	pass


func set_help(_text: String, _visible: bool) -> void:
	pass


func set_owners_lens(on: bool) -> void:
	_lenses["owners"] = on
	if _lens_btns.has("owners"):
		_style_btn(_lens_btns["owners"], on, true)


func set_listings_lens(on: bool) -> void:
	_lenses["listings"] = on
	if _lens_btns.has("listings"):
		_style_btn(_lens_btns["listings"], on, false)


func set_inbox(items: Array) -> void:
	_clear(_inbox_body)
	var kick := Label.new()
	kick.text = "ON YOUR DESK" if not items.is_empty() else "YEAR ONE"
	kick.add_theme_font_override("font", BwTheme.mono())
	kick.add_theme_font_size_override("font_size", 9)
	kick.add_theme_color_override("font_color", BwTheme.GOLD)
	_inbox_body.add_child(kick)
	if items.is_empty():
		var hint := Label.new()
		hint.text = "Nothing waiting. Open Acquire to read the tape."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		BwTheme.style_label(hint, 12, false, true)
		_inbox_body.add_child(hint)
		var go := _lens("Acquire", false)
		go.pressed.connect(func() -> void: open_page("market"))
		_inbox_body.add_child(go)
		_inbox.offset_bottom = 220
		return
	for it in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lab := Label.new()
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.text = str(it.get("label", it) if it is Dictionary else it)
		BwTheme.style_label(lab, 12)
		row.add_child(lab)
		var open := _lens("Open", false)
		var captured: Dictionary = it if it is Dictionary else {"label": str(it), "page": "market"}
		open.pressed.connect(func() -> void:
			attention_opened.emit(captured)
			open_page(str(captured.get("page", "market"))))
		row.add_child(open)
		_inbox_body.add_child(row)
	_inbox.offset_bottom = 108 + 36 + items.size() * 36


func show_parcel(b: Dictionary, campaign: bool) -> void:
	_parcel_data = b
	_campaign = campaign
	_parcel.visible = true
	var addr := str(b.get("address", "")).strip_edges()
	var cls := str(b.get("cls", "?"))
	_parcel_address.text = addr if addr != "" else _class_title(cls)
	_parcel_bbl.text = "Parcel %s · %s" % [str(b.get("bbl", "?")), str(b.get("district", "")).to_upper()]
	_clear(_chip_row)
	_add_chip(_class_title(cls), BwTheme.class_color(cls))
	if str(b.get("district", "")) != "":
		_add_chip(str(b.get("district", "")).to_upper(), BwTheme.INK_DIM, true)
	if b.get("held", false):
		_add_chip("OWNED", BwTheme.GOLD)
	if b.get("listed", false) and not b.get("held", false):
		_add_chip("FOR SALE", BwTheme.TEAL)
	if b.get("distress", false):
		_add_chip("MOTIVATED", BwTheme.DANGER)
	_clear(_grid)
	_grid_row("Building", _fmt_sf(float(b.get("sqft", 0.0))) + " sf")
	_grid_row("Lot", _fmt_sf(float(b.get("lot_sqft", 0.0))) + " sf")
	_grid_row("Floors", str(int(b.get("floors", 0))))
	_grid_row("Built", str(int(b.get("year", 0))))
	if float(b.get("occ", -1.0)) >= 0.0:
		_grid_row("Occupancy", "%.0f%%" % (float(b["occ"]) * 100.0))
	if float(b.get("value", -1.0)) > 0.0:
		_grid_row("Appraised", _usd(float(b["value"])))
	var listed: bool = bool(b.get("listed", false)) and not bool(b.get("held", false))
	var has_ask: bool = float(b.get("ask", -1.0)) > 0.0
	if listed:
		_deal_head.text = "For sale"
		_deal_note.text = "Ask %s%s" % [_usd(float(b.get("ask", 0.0))),
				" — motivated seller" if b.get("distress", false) else ""]
		_buy_btn.visible = campaign
	elif has_ask:
		_deal_head.text = "Off-market"
		_deal_note.text = "Indicative ask %s" % _usd(float(b["ask"]))
		_buy_btn.visible = false
	elif b.get("held", false):
		_deal_head.text = "Your holding"
		_deal_note.text = "This deed is on your balance sheet."
		_buy_btn.visible = false
	else:
		_deal_head.text = ""
		_deal_note.text = ""
		_buy_btn.visible = false


func hide_parcel() -> void:
	_parcel.visible = false
	_parcel_data = {}


func is_parcel_visible() -> bool:
	return _parcel.visible


func parcel_debug_text() -> String:
	if _parcel_data.is_empty():
		return ""
	return "%s | %s | %s" % [_parcel_bbl.text, _parcel_address.text, _deal_note.text]


func show_error(title: String, detail: String) -> void:
	_parcel.visible = true
	_parcel_address.text = title
	_parcel_bbl.text = ""
	_clear(_chip_row)
	_clear(_grid)
	_deal_head.text = ""
	_deal_note.text = detail
	_buy_btn.visible = false


func open_page(page: String) -> void:
	_page_name = page
	_page.visible = true
	var meta := _page_meta(page)
	_page_kicker.text = meta[0]
	_page_title.text = meta[1]
	_page_sub.text = meta[2]
	for id in _job_btns:
		_style_btn(_job_btns[id], _job_of(page) == id, false)
	page_opened.emit(page)


func hide_page() -> void:
	_page.visible = false
	_page_name = ""
	for id in _job_btns:
		_style_btn(_job_btns[id], false, false)


func current_page() -> String:
	return _page_name


func set_market_rows(rows: Array) -> void:
	_clear(_page_body)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "No listings on the tape this month."
		BwTheme.style_label(empty, 13, false, true)
		_page_body.add_child(empty)
		return
	var head := HBoxContainer.new()
	for t in ["Address", "Class", "Sf", "Ask", "Occ"]:
		var h := Label.new()
		h.text = t.to_upper()
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		BwTheme.style_label(h, 10, false, true)
		head.add_child(h)
	_page_body.add_child(head)
	for r in rows:
		var b := Button.new()
		var addr := str(r.get("address", r.get("bbl", "?")))
		var ask := _usd(float(r.get("ask", 0)))
		var occ = r.get("occ")
		var occ_s := "—" if occ == null else "%.0f%%" % (float(occ) * 100.0)
		b.text = "%s    %s    %s    %s    %s" % [
				addr, str(r.get("cls", "")), _fmt_sf(float(r.get("sf", 0))), ask, occ_s]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_stylebox_override("normal", BwTheme.start_opt(false))
		b.add_theme_stylebox_override("hover", BwTheme.start_opt(true))
		b.add_theme_color_override("font_color", BwTheme.INK)
		b.add_theme_font_override("font", BwTheme.mono())
		b.add_theme_font_size_override("font_size", 12)
		var bbl := str(r.get("bbl", ""))
		b.pressed.connect(func() -> void:
			listing_chosen.emit(bbl)
			hide_page())
		_page_body.add_child(b)


func set_page_note(text: String) -> void:
	_clear(_page_body)
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BwTheme.style_label(lab, 14, false, true)
	_page_body.add_child(lab)


func _open_job(job: String) -> void:
	match job:
		"acquire": open_page("market")
		"assets": open_page("portfolio")
		"capital": open_page("debt")
		"world": open_page("news")
		"economy": open_page("economy")


func _job_of(page: String) -> String:
	match page:
		"market", "deals", "notes": return "acquire"
		"portfolio", "leasing", "staff", "property": return "assets"
		"debt", "books": return "capital"
		"news", "research": return "world"
		"economy": return "economy"
		_: return ""


func _page_meta(page: String) -> PackedStringArray:
	match page:
		"market": return PackedStringArray(["Acquire", "The Marketplace",
				"On-market listings. Click a row to put it on the card."])
		"deals": return PackedStringArray(["Acquire", "The Deals Desk",
				"Live negotiations — export not wired yet."])
		"notes": return PackedStringArray(["Acquire", "The Note Desk",
				"Distressed paper — export not wired yet."])
		"portfolio": return PackedStringArray(["Assets", "Portfolio",
				"Holdings and income — export not wired yet."])
		"property": return PackedStringArray(["Assets", "Property",
				"The complete file. Overview is the glance card; more tabs follow."])
		"debt": return PackedStringArray(["Capital", "Debt",
				"Loans and the line — export not wired yet."])
		"books": return PackedStringArray(["Capital", "The Books",
				"Cash movement — export not wired yet."])
		"news": return PackedStringArray(["World", "The Tape",
				"What the city wrote this month — export not wired yet."])
		"economy": return PackedStringArray(["Economy", "Economy",
				"Cycle and space markets — export not wired yet."])
		_: return PackedStringArray(["Desk", page.capitalize(), "Coming."])


func _add_chip(text: String, bg: Color, muted: bool = false) -> void:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", BwTheme.chip_muted() if muted else BwTheme.chip_bg(bg))
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_override("font", BwTheme.sans())
	lab.add_theme_font_size_override("font_size", 11)
	lab.add_theme_color_override("font_color", BwTheme.INK_DIM if muted else Color("#fdfbf4"))
	chip.add_child(lab)
	_chip_row.add_child(chip)


func _grid_row(key: String, value: String) -> void:
	var k := Label.new()
	k.text = key
	BwTheme.style_label(k, 13, false, true)
	_grid.add_child(k)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BwTheme.style_label(v, 13, true)
	_grid.add_child(v)


static func _class_title(cls: String) -> String:
	match cls:
		"office": return "Office"
		"retail": return "Retail"
		"industrial": return "Industrial"
		"multifamily": return "Multifamily"
		"mix": return "Mixed use"
		"land": return "Vacant lot"
		_: return cls.capitalize()


static func _usd(v: float) -> String:
	if absf(v) >= 1e6:
		return "$%.2fM" % (v / 1e6)
	if absf(v) >= 1000.0:
		return "$%.0fk" % (v / 1000.0)
	return "$%.0f" % v


static func _fmt_sf(v: float) -> String:
	var s := str(int(roundf(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


static func _clear(node: Node) -> void:
	while node.get_child_count() > 0:
		var c := node.get_child(0)
		node.remove_child(c)
		c.free()
