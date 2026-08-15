class_name GameUi
extends Control
## Broadway & Wall chrome: start room, full-width bar, glance card,
## marketplace desk, inbox. Data from main.gd; this file paints.

signal advance_pressed
signal year_pressed
signal skip_pressed
signal buy_pressed
signal list_pressed
signal delist_pressed
signal accept_offer_pressed
signal develop_pressed(use: String, floors: int)
signal draw_pressed
signal repay_pressed
signal refi_pressed(product: String)
signal listing_chosen(bbl: String)
signal page_opened(page: String)
signal break_ground_pressed(size: String, density: String, cash: int)
signal continue_pressed(path: String)
signal close_parcel_pressed
signal lens_pressed(name: String, on: bool)
signal map_filter_pressed(name: String)
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
var _list_btn: Button
var _delist_btn: Button
var _accept_btn: Button
var _build_btn: Button
var _full_btn: Button

var _inbox: Panel
var _inbox_body: VBoxContainer
var _map_hud: Panel
var _map_hud_body: VBoxContainer
var _map_filter := "city"
var _parcel_kept := false

var _page: Control
var _page_kicker: Label
var _page_title: Label
var _page_sub: Label
var _page_scroll: ScrollContainer
var _page_body: VBoxContainer

var _parcel_data: Dictionary = {}
var _campaign := false
var _page_name := ""
var _lenses: Dictionary = {}
var _market_rows: Array = []
var _market_cls := "all"
var _prop_tab := "overview"
var _prop_building: Dictionary = {}
var _prop_options: Array = []
var _prop_quotes: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_topbar()
	_build_inbox()
	_build_map_hud()
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
	if _map_hud:
		_map_hud.visible = on
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
	_fps_label.visible = false
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

	var map_btn := _lens("Map", false)
	map_btn.pressed.connect(hide_page)
	row2.add_child(map_btn)

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


func _build_map_hud() -> void:
	_map_hud = Panel.new()
	_map_hud.set_anchors_preset(PRESET_TOP_LEFT)
	_map_hud.offset_left = 14
	_map_hud.offset_top = 232
	_map_hud.offset_right = 360
	_map_hud.offset_bottom = 360
	_map_hud.add_theme_stylebox_override("panel", BwTheme.panel_bg(0.94))
	_map_hud.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_map_hud)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	_map_hud.add_child(pad)
	_map_hud_body = VBoxContainer.new()
	_map_hud_body.add_theme_constant_override("separation", 6)
	pad.add_child(_map_hud_body)


func _build_parcel() -> void:
	_parcel = Panel.new()
	_parcel.visible = false
	_parcel.set_anchors_preset(PRESET_TOP_RIGHT)
	_parcel.offset_left = -344
	_parcel.offset_top = 108
	_parcel.offset_right = -14
	_parcel.offset_bottom = 580
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
	_list_btn = _lens("List at appraisal", false)
	_list_btn.visible = false
	_list_btn.pressed.connect(func() -> void: list_pressed.emit())
	body.add_child(_list_btn)
	_delist_btn = _lens("Delist", false)
	_delist_btn.visible = false
	_delist_btn.pressed.connect(func() -> void: delist_pressed.emit())
	body.add_child(_delist_btn)
	_accept_btn = Button.new()
	_accept_btn.visible = false
	_accept_btn.text = "Accept offer"
	_accept_btn.add_theme_stylebox_override("normal", BwTheme.buy_btn())
	_accept_btn.add_theme_stylebox_override("hover", BwTheme.buy_btn())
	_accept_btn.add_theme_stylebox_override("pressed", BwTheme.buy_btn())
	_accept_btn.add_theme_color_override("font_color", Color("#f6efdc"))
	_accept_btn.pressed.connect(func() -> void: accept_offer_pressed.emit())
	body.add_child(_accept_btn)
	_build_btn = _lens("Build…", false)
	_build_btn.visible = false
	_build_btn.pressed.connect(func() -> void: open_page("property", "build"))
	body.add_child(_build_btn)
	_full_btn = _lens("Full view", false)
	_full_btn.pressed.connect(func() -> void: open_page("property", "overview"))
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
	sheet.offset_left = -540
	sheet.offset_right = 540
	sheet.offset_top = -340
	sheet.offset_bottom = 340
	sheet.add_theme_stylebox_override("panel", BwTheme.page_sheet())
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_page.add_child(sheet)
	var hair := ColorRect.new()
	hair.color = BwTheme.HAIRLINE
	hair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hair.set_anchors_preset(PRESET_TOP_WIDE)
	hair.offset_left = 10
	hair.offset_right = -10
	hair.offset_top = 1
	hair.offset_bottom = 2
	sheet.add_child(hair)
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
	_page_scroll = ScrollContainer.new()
	_page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_page_scroll)
	_page_body = VBoxContainer.new()
	_page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_body.add_theme_constant_override("separation", 6)
	_page_scroll.add_child(_page_body)


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
	var nxt: Variant = hud.get("next", {})
	set_inbox(items, bool(hud.get("yearOne", false)), int(hud.get("monthsLeft", 0)),
			nxt if nxt is Dictionary else {})


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


func set_inbox(items: Array, year_one: bool = false, months_left: int = 0, next: Dictionary = {}) -> void:
	_clear(_inbox_body)
	var kick := Label.new()
	if year_one:
		kick.text = "YEAR ONE · %d MO LEFT" % months_left
	elif not items.is_empty():
		kick.text = "ON YOUR DESK · %d" % items.size()
	else:
		kick.text = "ON YOUR DESK"
	kick.add_theme_font_override("font", BwTheme.mono())
	kick.add_theme_font_size_override("font_size", 9)
	kick.add_theme_color_override("font_color", BwTheme.GOLD)
	_inbox_body.add_child(kick)
	if items.is_empty():
		var hint := Label.new()
		var nxt_label := str(next.get("label", "")) if not next.is_empty() else ""
		hint.text = nxt_label if nxt_label != "" else "Keep the city in view — buy, lease, or build."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		BwTheme.style_label(hint, 12, false, true)
		_inbox_body.add_child(hint)
		var page := str(next.get("page", "market")) if not next.is_empty() else "market"
		var go := _lens("Acquire" if page == "market" else "Open", false)
		go.pressed.connect(func() -> void: open_page(page))
		_inbox_body.add_child(go)
		_inbox.offset_bottom = 232
		_place_map_hud()
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
	_inbox.offset_bottom = 108 + 48 + items.size() * 40
	_place_map_hud()


func _place_map_hud() -> void:
	if _map_hud == null:
		return
	_map_hud.offset_top = _inbox.offset_bottom + 8


func set_map_hud(doc: Dictionary) -> void:
	_clear(_map_hud_body)
	var kick := Label.new()
	kick.text = "CITY"
	kick.add_theme_font_override("font", BwTheme.mono())
	kick.add_theme_font_size_override("font_size", 9)
	kick.add_theme_color_override("font_color", BwTheme.GOLD)
	_map_hud_body.add_child(kick)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	_map_hud_body.add_child(filters)
	for pair in [["city", "City"], ["book", "Book"], ["cranes", "Cranes"]]:
		var id: String = str(pair[0])
		var b := _lens(str(pair[1]), _map_filter == id)
		b.pressed.connect(func() -> void:
			_map_filter = id
			map_filter_pressed.emit(id)
			set_map_hud(doc))
		filters.add_child(b)
	var deliveries: Array = doc.get("deliveries", [])
	if not deliveries.is_empty():
		var h := Label.new()
		h.text = "UNDER CONSTRUCTION"
		BwTheme.style_label(h, 10, false, true)
		_map_hud_body.add_child(h)
		for d in deliveries:
			_hud_row(str(d.get("label", d.get("address", "?"))), str(d.get("bbl", "")), "")
	var balloons: Array = doc.get("balloons", [])
	if not balloons.is_empty():
		var h := Label.new()
		h.text = "BALLOONS · 18 MO"
		BwTheme.style_label(h, 10, false, true)
		_map_hud_body.add_child(h)
		for d in balloons:
			_hud_row(str(d.get("label", d.get("address", "?"))), str(d.get("bbl", "")), "debt")
	var built := float(doc.get("deliveredSf", 0))
	if built > 0.0:
		_note_in(_map_hud_body, "Your deliveries · %s sf" % _fmt_sf(built))
	var rows := 2 + deliveries.size() + balloons.size()
	_map_hud.offset_bottom = _map_hud.offset_top + 56 + rows * 28
	_place_map_hud()


func _hud_row(text: String, bbl: String, page: String) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_stylebox_override("normal", BwTheme.start_opt(false))
	b.add_theme_stylebox_override("hover", BwTheme.start_opt(true))
	b.add_theme_color_override("font_color", BwTheme.INK)
	b.add_theme_font_override("font", BwTheme.sans())
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(func() -> void:
		if bbl != "" and bbl != "<null>":
			listing_chosen.emit(bbl)
		if page != "":
			open_page(page)
		else:
			hide_page())
	_map_hud_body.add_child(b)


func _note_in(parent: Node, text: String) -> void:
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BwTheme.style_label(lab, 12, true, true)
	parent.add_child(lab)


func show_parcel(b: Dictionary, campaign: bool) -> void:
	_parcel_data = b
	_campaign = campaign
	_parcel_kept = true
	_parcel.visible = not _page.visible
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
	if b.get("listed", false) and b.get("held", false):
		_add_chip("ON THE MARKET", BwTheme.TEAL)
	elif b.get("listed", false):
		_add_chip("FOR SALE", BwTheme.TEAL)
	if b.get("developing", false):
		_add_chip("UNDER CONSTRUCTION", BwTheme.GOLD)
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
	if float(b.get("noi", -1.0)) >= 0.0:
		_grid_row("NOI / yr", _usd(float(b["noi"])))
	if float(b.get("basis", -1.0)) > 0.0:
		_grid_row("Basis", _usd(float(b["basis"])))
	if float(b.get("debt", -1.0)) > 0.0:
		_grid_row("Debt", _usd(float(b["debt"])))
	var ours: bool = bool(b.get("held", false))
	var our_list: bool = ours and bool(b.get("listed", false))
	var offer := float(b.get("offer", -1.0))
	var land: bool = str(b.get("cls", "")) == "land"
	_buy_btn.visible = false
	_list_btn.visible = false
	_delist_btn.visible = false
	_accept_btn.visible = false
	_build_btn.visible = false
	if listed:
		_deal_head.text = "For sale"
		_deal_note.text = "Ask %s%s" % [_usd(float(b.get("ask", 0.0))),
				" — motivated seller" if b.get("distress", false) else ""]
		_buy_btn.visible = campaign
	elif ours and offer > 0.0:
		_deal_head.text = "Offer in hand"
		_deal_note.text = "They will pay %s." % _usd(offer)
		_accept_btn.visible = campaign
		_delist_btn.visible = campaign
	elif our_list:
		_deal_head.text = "On the market"
		_deal_note.text = "Ask %s — waiting for the phone." % _usd(float(b.get("ask", 0.0)))
		_delist_btn.visible = campaign
	elif ours:
		_deal_head.text = "Your holding"
		_deal_note.text = "This deed is on your balance sheet."
		_list_btn.visible = campaign and float(b.get("listAsk", b.get("value", 0.0))) > 0.0
		if _list_btn.visible:
			_list_btn.text = "List at %s" % _usd(float(b.get("listAsk", b.get("value", 0.0))))
		_build_btn.visible = campaign and land and not bool(b.get("developing", false))
	elif has_ask:
		_deal_head.text = "Off-market"
		_deal_note.text = "Indicative ask %s" % _usd(float(b["ask"]))
	else:
		_deal_head.text = ""
		_deal_note.text = ""


func hide_parcel() -> void:
	_parcel.visible = false
	_parcel_kept = false
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
	_list_btn.visible = false
	_delist_btn.visible = false
	_accept_btn.visible = false
	_build_btn.visible = false


func open_page(page: String, tab: String = "") -> void:
	if page == "property":
		if tab != "":
			_prop_tab = tab
		elif _page_name != "property":
			_prop_tab = "overview"
	_page_name = page
	_page.visible = true
	_inbox.visible = false
	if _map_hud:
		_map_hud.visible = false
	_parcel_kept = _parcel.visible or _parcel_kept
	_parcel.visible = false
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
	if _campaign:
		_inbox.visible = true
		if _map_hud:
			_map_hud.visible = true
		_parcel.visible = _parcel_kept


func current_page() -> String:
	return _page_name


func set_market_rows(rows: Array) -> void:
	_market_rows = rows
	_paint_market()


func _paint_market() -> void:
	_clear(_page_body)
	_add_room_nav("market")
	if _market_rows.is_empty():
		_note("No listings on the tape this month.")
		return
	var motivated := 0
	var classes: Dictionary = {}
	for r in _market_rows:
		if int(r.get("distress", 0)) == 1:
			motivated += 1
		var c := str(r.get("cls", ""))
		classes[c] = int(classes.get(c, 0)) + 1
	_stat_strip([
		["On the market", str(_market_rows.size())],
		["Motivated", str(motivated)],
	])
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	_page_body.add_child(filters)
	var all_b := _lens("All · %d" % _market_rows.size(), _market_cls == "all")
	all_b.pressed.connect(func() -> void:
		_market_cls = "all"
		_paint_market())
	filters.add_child(all_b)
	for c in ["land", "office", "retail", "multifamily", "industrial"]:
		if not classes.has(c):
			continue
		var id: String = str(c)
		var b := _lens("%s · %d" % [id, int(classes[id])], _market_cls == id)
		b.pressed.connect(func() -> void:
			_market_cls = id
			_paint_market())
		filters.add_child(b)
	var hl := _lens("Highlight on map", bool(_lenses.get("listings", false)))
	hl.pressed.connect(func() -> void:
		var on := not bool(_lenses.get("listings", false))
		_lenses["listings"] = on
		if _lens_btns.has("listings"):
			_style_btn(_lens_btns["listings"], on, false)
		lens_pressed.emit("listings", on)
		_paint_market())
	filters.add_child(hl)
	_note("On-market listings. Click a row to put it on the card.")
	_sheet_head([
		["Address", 0, false], ["Class", 110, false], ["Sf", 80, true],
		["Ask", 88, true], ["Occ", 56, true],
	])
	var shown := 0
	for r in _market_rows:
		var cls := str(r.get("cls", ""))
		if _market_cls != "all" and cls != _market_cls:
			continue
		shown += 1
		var occ = r.get("occ")
		var occ_s := "—" if occ == null else "%.0f%%" % (float(occ) * 100.0)
		_sheet_row([
			[str(r.get("address", r.get("bbl", "?"))), 0, false],
			[cls, 110, false],
			[_fmt_sf(float(r.get("sf", 0))), 80, true],
			[_usd(float(r.get("ask", 0))), 88, true],
			[occ_s, 56, true],
		], str(r.get("bbl", "")), true)
	if shown == 0:
		_note("Nothing in that class this month.")


func set_portfolio(doc: Dictionary) -> void:
	_clear(_page_body)
	_add_room_nav("portfolio")
	var rows: Array = doc.get("rows", [])
	var tot: Dictionary = doc.get("totals", {})
	if rows.is_empty():
		_note("Your book is empty. Start on the public tape — compare a rent roll, agree a price, then choose the debt.")
		var go := _lens("Acquire →", false)
		go.pressed.connect(func() -> void: open_page("market"))
		_page_body.add_child(go)
		return
	_stat_strip([
		["Holdings", str(int(tot.get("n", rows.size())))],
		["Value", _usd(float(tot.get("value", 0)))],
		["NOI / yr", _usd(float(tot.get("noi", 0)))],
		["Debt", _usd(float(tot.get("debt", 0)))],
		["Equity", _usd(float(tot.get("equity", 0)))],
	])
	_sheet_head([
		["Address", 0, false], ["Class", 110, false], ["Sf", 80, true],
		["Occ", 56, true], ["NOI", 88, true], ["Value", 88, true],
	])
	for r in rows:
		var occ = r.get("occ")
		var occ_s := "—" if occ == null else "%.0f%%" % (float(occ) * 100.0)
		_sheet_row([
			[str(r.get("address", r.get("bbl", "?"))), 0, false],
			[str(r.get("cls", "")), 110, false],
			[_fmt_sf(float(r.get("sf", 0))), 80, true],
			[occ_s, 56, true],
			[_usd(float(r.get("noi", 0))), 88, true],
			[_usd(float(r.get("value", 0))), 88, true],
		], str(r.get("bbl", "")), false)


func set_news(doc: Dictionary) -> void:
	_clear(_page_body)
	_add_room_nav("news")
	var items: Array = doc.get("items", [])
	if items.is_empty():
		_note("Nothing on the wire yet. Advance a month.")
		return
	_note("The last %d items, newest first. A row with a parcel opens it on the map." % items.size())
	var last_when := ""
	for n in items:
		var when := str(n.get("when", ""))
		if when != last_when:
			last_when = when
			var head := Label.new()
			head.text = when.to_upper()
			BwTheme.style_label(head, 10, false, true)
			_page_body.add_child(head)
		var text := str(n.get("text", ""))
		var bbl := str(n.get("bbl", ""))
		var kind := str(n.get("kind", "info"))
		if bbl != "" and bbl != "<null>":
			_row_btn(text + "  ✈", bbl, true)
		else:
			var lab := Label.new()
			lab.text = text
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lab.add_theme_font_override("font", BwTheme.sans())
			lab.add_theme_font_size_override("font_size", 13)
			lab.add_theme_color_override("font_color",
					BwTheme.DANGER if kind == "warn" else BwTheme.INK)
			_page_body.add_child(lab)


func set_economy(doc: Dictionary) -> void:
	_clear(_page_body)
	_add_room_nav("economy")
	var phase := str(doc.get("phase", "—"))
	_stat_strip([
		["Cycle", phase.capitalize()],
		["Base rate", _pct(doc.get("indexRate"), 2)],
		["Credit", _pct_idx(doc.get("creditIdx"))],
		["Employment", _pct_idx(doc.get("employIdx"))],
		["Build costs", _pct_idx(doc.get("costIdx"))],
		["Land", _pct_idx(doc.get("landIdx"))],
	])
	var blurb := _phase_blurb(phase)
	var rumor = doc.get("rumoredPhase")
	if rumor != null and str(rumor) != "" and str(rumor) != "<null>":
		blurb += " Word on the street: %s is coming." % str(rumor)
	_note(blurb)
	var sec := Label.new()
	sec.text = "WHERE THE CITY STANDS"
	BwTheme.style_label(sec, 10, false, true)
	_page_body.add_child(sec)
	_kv("Population", _commify(doc.get("population")))
	_kv("Jobs", _commify(doc.get("jobs")))
	if doc.get("jobsYr") != null:
		_kv("Jobs this year", "%s%.1f%%" % ["+" if float(doc["jobsYr"]) >= 0.0 else "", float(doc["jobsYr"])])
	_kv("Unemployment", _pct(doc.get("unemployment"), 1, true))
	var classes: Dictionary = doc.get("classes", {})
	if not classes.is_empty():
		var ch := Label.new()
		ch.text = "SPACE MARKETS"
		BwTheme.style_label(ch, 10, false, true)
		_page_body.add_child(ch)
		_sheet_head([
			["Class", 0, false], ["Vacancy", 88, true],
			["Rent idx", 88, true], ["Cap", 72, true],
		])
		for k in ["office", "retail", "multifamily", "industrial"]:
			if not classes.has(k):
				continue
			var c: Dictionary = classes[k]
			_sheet_row([
				[k, 0, false],
				[_pct(c.get("vac"), 1, true), 88, true],
				[_num(c.get("rent"), 2), 88, true],
				[_pct(c.get("cap"), 2), 72, true],
			])


func set_debt(doc: Dictionary) -> void:
	_clear(_page_body)
	_add_room_nav("debt")
	var loc: Dictionary = doc.get("loc", {})
	var tot: Dictionary = doc.get("totals", {})
	_stat_strip([
		["Line", _usd(float(loc.get("limit", 0)))],
		["Drawn", _usd(float(loc.get("drawn", 0)))],
		["Available", _usd(float(loc.get("available", 0)))],
		["Coupon", _pct(loc.get("rate"), 2)],
		["Book debt", _usd(float(tot.get("total", 0)))],
	])
	var draw_amt := float(loc.get("drawAmt", loc.get("available", 0)))
	var repay_amt := float(loc.get("repayAmt", 0))
	_note("The line covers a shortfall before the run dies. Idle cash above $250k pays it back.")
	if draw_amt > 0.0:
		var draw := Button.new()
		draw.text = "Draw %s" % _usd(draw_amt)
		draw.add_theme_stylebox_override("normal", BwTheme.buy_btn())
		draw.add_theme_stylebox_override("hover", BwTheme.buy_btn())
		draw.add_theme_stylebox_override("pressed", BwTheme.buy_btn())
		draw.add_theme_color_override("font_color", Color("#f6efdc"))
		draw.pressed.connect(func() -> void: draw_pressed.emit())
		_page_body.add_child(draw)
	if repay_amt > 0.0:
		var repay := _lens("Repay %s" % _usd(repay_amt), false)
		repay.pressed.connect(func() -> void: repay_pressed.emit())
		_page_body.add_child(repay)
	var loans: Array = doc.get("loans", [])
	if loans.is_empty():
		_note("No mortgages on the book. The line is the only paper.")
		return
	_sheet_head([
		["Address", 0, false], ["Kind", 88, false], ["Balance", 88, true],
		["Rate", 64, true], ["Due", 88, false],
	])
	for r in loans:
		var rate = r.get("rate")
		_sheet_row([
			[str(r.get("address", "—")), 0, false],
			[str(r.get("kind", "")), 88, false],
			[_usd(float(r.get("balance", 0))), 88, true],
			["—" if rate == null else "%.2f%%" % float(rate), 64, true],
			[str(r.get("maturity", "—")), 88, false],
		], str(r.get("bbl", "")), false)


func set_books(doc: Dictionary) -> void:
	_clear(_page_body)
	_add_room_nav("books")
	_stat_strip([
		["Cash", _usd(float(doc.get("cash", 0)))],
		["Net worth", _usd(float(doc.get("nw", 0))) if doc.get("nw") != null else "—"],
		["CF / mo", _usd(float(doc.get("cf", 0))) if doc.get("cf") != null else "—"],
		["Taxes paid", _usd(float(doc.get("taxesPaid", 0)))],
		["Exits", str(int(doc.get("exits", 0)))],
	])
	var years: Array = doc.get("years", [])
	if years.is_empty():
		_note("The ledger is empty. Buy something, then Advance.")
		return
	_sheet_head([
		["Year", 72, false], ["NOI", 88, true], ["Debt svc", 88, true],
		["Bought", 88, true], ["Sold", 88, true], ["Tax", 72, true],
	])
	for y in years:
		_sheet_row([
			[str(y.get("when", y.get("yr", "?"))), 72, false],
			[_usd(float(y.get("noi", 0))), 88, true],
			[_usd(float(y.get("debtSvc", 0))), 88, true],
			[_usd(float(y.get("bought", 0))), 88, true],
			[_usd(float(y.get("sold", 0))), 88, true],
			[_usd(float(y.get("taxes", 0))), 72, true],
		])


func set_property_overview(b: Dictionary, options: Array = [], quotes: Array = []) -> void:
	_prop_building = b
	_prop_options = options
	_prop_quotes = quotes
	_paint_property()


func _paint_property() -> void:
	_clear(_page_body)
	_add_room_nav("property")
	var b := _prop_building
	if b.is_empty():
		_note("Click a building on the map, then open Full view.")
		return
	var held: bool = bool(b.get("held", false))
	var listed: bool = bool(b.get("listed", false))
	var land: bool = str(b.get("cls", "")) == "land"
	var developing: bool = bool(b.get("developing", false))
	var tabs: Array = [["overview", "Overview"]]
	tabs.append(["sell" if held else "acquire", "Sell" if held else "Acquire"])
	if held and land and not listed:
		tabs.append(["build", "Build"])
	if held:
		tabs.append(["refi", "Refinance"])
	var ids: Array = []
	for t in tabs:
		ids.append(t[0])
	if not ids.has(_prop_tab):
		_prop_tab = "overview"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_page_body.add_child(row)
	for t in tabs:
		var id: String = str(t[0])
		var btn := _lens(str(t[1]), id == _prop_tab)
		btn.pressed.connect(func() -> void:
			_prop_tab = id
			_paint_property())
		row.add_child(btn)
	var addr := str(b.get("address", "")).strip_edges()
	var title := Label.new()
	title.text = addr if addr != "" else _class_title(str(b.get("cls", "?")))
	title.add_theme_font_override("font", BwTheme.serif())
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", BwTheme.INK)
	_page_body.add_child(title)
	_note("Parcel %s · %s" % [str(b.get("bbl", "?")), str(b.get("district", "")).to_upper()])
	match _prop_tab:
		"acquire", "sell":
			_paint_prop_deal(b, held, listed)
		"build":
			_paint_prop_build(b, developing)
		"refi":
			_paint_prop_refi()
		_:
			_paint_prop_overview(b)
	var map := _lens("Show on the map", false)
	map.pressed.connect(hide_page)
	_page_body.add_child(map)


func _paint_prop_overview(b: Dictionary) -> void:
	_stat_strip([
		["Appraised", _usd(float(b.get("value", 0))) if float(b.get("value", 0)) > 0.0 else "—"],
		["NOI / yr", _usd(float(b.get("noi", 0))) if float(b.get("noi", -1)) >= 0.0 else "—"],
		["Occupancy", ("%.0f%%" % (float(b["occ"]) * 100.0)) if float(b.get("occ", -1)) >= 0.0 else "—"],
		["Equity", _usd(float(b.get("value", 0)) - float(b.get("debt", 0))) if float(b.get("value", 0)) > 0.0 else "—"],
	])
	_kv("Use", _class_title(str(b.get("cls", "?"))))
	_kv("Building", _fmt_sf(float(b.get("sqft", b.get("sf", 0)))) + " sf")
	_kv("Lot", _fmt_sf(float(b.get("lot_sqft", b.get("lotSf", 0)))) + " sf")
	_kv("Floors", str(int(b.get("floors", 0))))
	_kv("Built", str(int(b.get("year", 0))))
	if float(b.get("basis", -1.0)) > 0.0:
		_kv("Basis", _usd(float(b["basis"])))
	if float(b.get("debt", -1.0)) > 0.0:
		_kv("Debt", _usd(float(b["debt"])))


func _paint_prop_deal(b: Dictionary, held: bool, listed: bool) -> void:
	var offer := float(b.get("offer", -1.0))
	if listed and not held and float(b.get("ask", 0)) > 0.0:
		_kv("Ask", _usd(float(b["ask"])))
		var buy := Button.new()
		buy.text = "Buy at ask"
		buy.add_theme_stylebox_override("normal", BwTheme.buy_btn())
		buy.add_theme_stylebox_override("hover", BwTheme.buy_btn())
		buy.add_theme_stylebox_override("pressed", BwTheme.buy_btn())
		buy.add_theme_color_override("font_color", Color("#f6efdc"))
		buy.pressed.connect(func() -> void:
			hide_page()
			buy_pressed.emit())
		_page_body.add_child(buy)
	elif held and offer > 0.0:
		_kv("Offer", _usd(offer))
		var acc := Button.new()
		acc.text = "Accept offer"
		acc.add_theme_stylebox_override("normal", BwTheme.buy_btn())
		acc.add_theme_stylebox_override("hover", BwTheme.buy_btn())
		acc.add_theme_stylebox_override("pressed", BwTheme.buy_btn())
		acc.add_theme_color_override("font_color", Color("#f6efdc"))
		acc.pressed.connect(func() -> void:
			hide_page()
			accept_offer_pressed.emit())
		_page_body.add_child(acc)
		var pull := _lens("Delist", false)
		pull.pressed.connect(func() -> void: delist_pressed.emit())
		_page_body.add_child(pull)
	elif held and listed:
		_kv("Your ask", _usd(float(b.get("ask", 0))))
		_note("On the market. The engine will bring offers; you do not invent a buyer.")
		var pull := _lens("Delist", false)
		pull.pressed.connect(func() -> void: delist_pressed.emit())
		_page_body.add_child(pull)
	elif held:
		var ask := float(b.get("listAsk", b.get("value", 0.0)))
		if ask > 0.0:
			var list := _lens("List quietly at %s" % _usd(ask), false)
			list.pressed.connect(func() -> void: list_pressed.emit())
			_page_body.add_child(list)
		else:
			_note("No appraisal to list against.")
	else:
		_note("This lot is not for sale.")


func _paint_prop_build(b: Dictionary, developing: bool) -> void:
	if developing:
		_note("Cranes on site: %s, %s floors." % [
				str(b.get("jobUse", "building")), str(b.get("jobFloors", "?"))])
		return
	if _prop_options.is_empty():
		_note("No programmes underwritten on this lot.")
		return
	_note("The engine underwrote these. A row that does not pencil still runs — the error is the engine's.")
	_sheet_head([
		["Use", 110, false], ["Fl", 40, true], ["Sf", 80, true],
		["Cost", 88, true], ["Verdict", 0, false],
	])
	for o in _prop_options:
		var use := str(o.get("use", ""))
		var floors := int(o.get("floors", 0))
		var why = o.get("why")
		var mark := "pencils" if bool(o.get("clears", false)) else (
				str(why) if why != null and str(why) != "<null>" else "does not pencil")
		var u := use
		var f := floors
		_sheet_row([
			[use, 110, false],
			[str(floors), 40, true],
			[_fmt_sf(float(o.get("sf", 0))), 80, true],
			[_usd(float(o.get("cost", 0))), 88, true],
			[mark, 0, false],
		], "", false, func() -> void: develop_pressed.emit(u, f), bool(o.get("clears", false)))


func _paint_prop_refi() -> void:
	_note("Desks that will write against this deed. Proceeds and the coupon are the engine's.")
	if _prop_quotes.is_empty():
		_note("No desk will quote against this today.")
		return
	_sheet_head([
		["Desk", 0, false], ["Proceeds", 88, true], ["Rate", 64, true],
	])
	var any := false
	for q in _prop_quotes:
		if not bool(q.get("available", false)):
			continue
		any = true
		var pid := str(q.get("id", ""))
		_sheet_row([
			[str(q.get("label", pid)), 0, false],
			[_usd(float(q.get("proceeds", 0))), 88, true],
			["—" if q.get("rate") == null else "%.2f%%" % float(q["rate"]), 64, true],
		], "", false, func() -> void: refi_pressed.emit(pid))
	if not any:
		_note("No desk will quote against this today.")
		for q in _prop_quotes:
			var why = q.get("why")
			if why == null or str(why) == "<null>" or str(why) == "":
				continue
			_note("%s — %s" % [str(q.get("label", q.get("id", "?"))), str(why)])


func scroll_page(frac: float = 1.0) -> void:
	if _page_scroll == null:
		return
	var mb := _page_body.get_combined_minimum_size().y
	var vh := _page_scroll.size.y
	_page_scroll.scroll_vertical = int(maxf(0.0, mb - vh) * clampf(frac, 0.0, 1.0))


func set_page_note(text: String) -> void:
	_clear(_page_body)
	_add_room_nav(_page_name)
	_note(text)


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
				"Your deeds. Click a row to open the file."])
		"property": return PackedStringArray(["Assets", "Property",
				"The complete file. Tabs for the desks this deed has."])
		"debt": return PackedStringArray(["Capital", "Debt",
				"The line and every loan the engine has written."])
		"books": return PackedStringArray(["Capital", "The Books",
				"Cash, net worth, and the yearly ledger."])
		"news": return PackedStringArray(["World", "The Tape",
				"What the city wrote. Newest first."])
		"economy": return PackedStringArray(["Economy", "Economy",
				"The cycle and the four space markets."])
		_: return PackedStringArray(["Desk", page.capitalize(), "Coming."])


func _add_room_nav(page: String) -> void:
	var siblings := _siblings_of(page)
	if siblings.size() <= 1:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for s in siblings:
		var id: String = str(s[0])
		var b := _lens(str(s[1]), id == page)
		b.pressed.connect(func() -> void: open_page(id))
		row.add_child(b)
	_page_body.add_child(row)


func _siblings_of(page: String) -> Array:
	match _job_of(page):
		"acquire":
			return [["market", "Marketplace"], ["deals", "Deals"], ["notes", "Notes"]]
		"assets":
			return [["portfolio", "Portfolio"], ["property", "Property"]]
		"capital":
			return [["debt", "Debt"], ["books", "Books"]]
		"world":
			return [["news", "News"]]
		_:
			return []


func _note(text: String) -> void:
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BwTheme.style_label(lab, 13, false, true)
	_page_body.add_child(lab)


func _sheet_head(cells: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for c in cells:
		row.add_child(_sheet_cell(str(c[0]).to_upper(), int(c[1]), bool(c[2]), true))
	_page_body.add_child(row)


func _sheet_row(cells: Array, bbl: String = "", close: bool = false, extra: Callable = Callable(), on: bool = false) -> void:
	var clickable := extra.is_valid() or (bbl != "" and bbl != "<null>")
	if not clickable:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		for c in cells:
			row.add_child(_sheet_cell(str(c[0]), int(c[1]), bool(c[2]), false))
		_page_body.add_child(row)
		return
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 28
	b.add_theme_stylebox_override("normal", BwTheme.start_opt(on))
	b.add_theme_stylebox_override("hover", BwTheme.start_opt(true))
	b.add_theme_stylebox_override("pressed", BwTheme.start_opt(true))
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 10)
	hb.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	hb.offset_left = 10
	hb.offset_right = -10
	for c in cells:
		var lab := _sheet_cell(str(c[0]), int(c[1]), bool(c[2]), false)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(lab)
	b.add_child(hb)
	if extra.is_valid():
		b.pressed.connect(extra)
	else:
		b.pressed.connect(func() -> void:
			listing_chosen.emit(bbl)
			if close:
				hide_page()
			else:
				open_page("property"))
	_page_body.add_child(b)


func _sheet_cell(text: String, width: int, numeric: bool, header: bool) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.clip_text = true
	if width > 0:
		lab.custom_minimum_size.x = width
	else:
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if numeric:
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	BwTheme.style_label(lab, 10 if header else 12, true, header)
	return lab


func _table_head(cols: Array) -> void:
	var head := HBoxContainer.new()
	for t in cols:
		var h := Label.new()
		h.text = str(t).to_upper()
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		BwTheme.style_label(h, 10, false, true)
		head.add_child(h)
	_page_body.add_child(head)


func _row_btn(text: String, bbl: String, close: bool) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_stylebox_override("normal", BwTheme.start_opt(false))
	b.add_theme_stylebox_override("hover", BwTheme.start_opt(true))
	b.add_theme_color_override("font_color", BwTheme.INK)
	b.add_theme_font_override("font", BwTheme.mono())
	b.add_theme_font_size_override("font_size", 12)
	if bbl != "" and bbl != "<null>":
		b.pressed.connect(func() -> void:
			listing_chosen.emit(bbl)
			if close:
				hide_page()
			else:
				open_page("property"))
	_page_body.add_child(b)


func _stat_strip(items: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	for it in items:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		var k := Label.new()
		k.text = str(it[0]).to_upper()
		BwTheme.style_label(k, 9, false, true)
		box.add_child(k)
		var v := Label.new()
		v.text = str(it[1])
		BwTheme.style_label(v, 14, true)
		box.add_child(v)
		row.add_child(box)
	_page_body.add_child(row)


func _kv(key: String, value: String) -> void:
	var row := HBoxContainer.new()
	var k := Label.new()
	k.text = key
	k.custom_minimum_size.x = 140
	BwTheme.style_label(k, 13, false, true)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BwTheme.style_label(v, 13, true)
	row.add_child(v)
	_page_body.add_child(row)


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


static func _phase_blurb(phase: String) -> String:
	match phase:
		"expansion":
			return "Tenants expand, capital chases, rents push. Enjoy it — peaks are born here."
		"peak":
			return "Priced to perfection. Every deal works on paper and none has margin for the turn."
		"recession":
			return "Tenants retrench and lenders retreat. Cheap buildings and expensive money."
		"recovery":
			return "The bleeding has stopped. Concessions burn off before face rents move."
		"depression":
			return "Empty space is still winning. This is not healing — it is a glut that has not cleared."
		_:
			return "The cycle the four space markets are living in."


static func _pct(v, places: int = 1, fraction: bool = false) -> String:
	if v == null:
		return "—"
	var n := float(v)
	if fraction:
		n *= 100.0
	if places <= 0:
		return "%.0f%%" % n
	if places == 1:
		return "%.1f%%" % n
	return "%.2f%%" % n


static func _pct_idx(v) -> String:
	if v == null:
		return "—"
	return "%.0f" % (float(v) * 100.0)


static func _num(v, _places: int = 2) -> String:
	if v == null:
		return "—"
	return "%.2f" % float(v)


static func _commify(v) -> String:
	if v == null:
		return "—"
	var s := str(int(roundf(float(v))))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


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
