class_name BwTheme
extends RefCounted
## Broadway & Wall design tokens for native Godot chrome.
## Ported from plat-econ/src/index.css — parchment cards, ink type, gold accents.

const PAPER := Color("#f6f1e2")
const PAPER_DEEP := Color("#ebe3cf")
const INK := Color("#2b251a")
const INK_DIM := Color("#7a7260")
const GOLD := Color("#b07f1e")
const TEAL := Color("#2f7a72")
const DANGER := Color("#a8402e")
const SUCCESS := Color("#3a7d46")
const CARD_LINE := Color(0.573, 0.431, 0.157, 0.4)

const CLASS_COLORS := {
	"office": Color("#4a6fa5"),
	"retail": Color("#8a6b4a"),
	"industrial": Color("#6a6a72"),
	"multifamily": Color("#7a5f9e"),
	"mix": Color("#5a7a6a"),
	"land": Color("#8a7a5a"),
	"hotel": Color("#9a6a5a"),
}

static var _serif: Font
static var _mono: Font
static var _sans: Font


static func serif() -> Font:
	_ensure_fonts()
	return _serif


static func mono() -> Font:
	_ensure_fonts()
	return _mono


static func sans() -> Font:
	_ensure_fonts()
	return _sans


static func _ensure_fonts() -> void:
	if _serif != null:
		return
	var s := SystemFont.new()
	s.font_names = PackedStringArray([
		"Iowan Old Style", "Palatino Linotype", "Palatino", "Georgia", "Times New Roman", "serif"])
	s.font_weight = 600
	_serif = s
	var m := SystemFont.new()
	m.font_names = PackedStringArray([
		"ui-monospace", "SF Mono", "Cascadia Mono", "Consolas", "Menlo", "monospace"])
	m.font_weight = 400
	_mono = m
	var u := SystemFont.new()
	u.font_names = PackedStringArray([
		"system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"])
	u.font_weight = 400
	_sans = u


## Godot StyleBoxFlat has one shadow. These sizes are the ambient half of
## `--lift-1/2/3` in plat-econ/src/index.css (tight contact + wide wash).
## The top-edge hairline is drawn as a ColorRect on the page sheet.
static func _lift(s: StyleBoxFlat, level: int) -> void:
	var ink := Color(48.0 / 255.0, 38.0 / 255.0, 16.0 / 255.0, 1.0)
	match level:
		1:
			s.shadow_color = Color(ink.r, ink.g, ink.b, 0.16)
			s.shadow_size = 8
			s.shadow_offset = Vector2(0, 2)
		2:
			s.shadow_color = Color(ink.r, ink.g, ink.b, 0.20)
			s.shadow_size = 18
			s.shadow_offset = Vector2(0, 6)
		_:
			s.shadow_color = Color(ink.r, ink.g, ink.b, 0.28)
			s.shadow_size = 36
			s.shadow_offset = Vector2(0, 14)


static func panel_bg(alpha: float = 0.94) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(PAPER.r, PAPER.g, PAPER.b, alpha)
	s.border_color = CARD_LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	_lift(s, 2)
	return s


static func topbar_bg() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.973, 0.957, 0.910, 0.90)
	s.border_color = Color(0.471, 0.361, 0.149, 0.22)
	s.border_width_bottom = 1
	_lift(s, 1)
	return s


static func chip_bg(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(10)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


static func chip_muted() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(INK.r, INK.g, INK.b, 0.08)
	s.set_corner_radius_all(10)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


static func lens_btn(on: bool = false, teal: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(5)
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_width_left = 1
	s.border_width_right = 1
	if on and teal:
		s.bg_color = Color("#2a6d66")
		s.border_color = Color("#1f544f")
	elif on:
		s.bg_color = Color("#c2862a")
		s.border_color = Color("#97531a")
	else:
		s.bg_color = Color(1.0, 0.992, 0.965, 0.82)
		s.border_color = Color(0.376, 0.298, 0.133, 0.22)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func advance_btn() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#241e14")
	s.border_color = Color("#191509")
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.shadow_color = Color(0.188, 0.149, 0.063, 0.20)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s


static func buy_btn() -> StyleBoxFlat:
	return advance_btn()


static func class_color(cls: String) -> Color:
	return CLASS_COLORS.get(cls, Color("#5c5348"))


static func page_sheet() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.976, 0.961, 0.922, 0.97)
	s.border_color = CARD_LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	_lift(s, 3)
	return s


const HAIRLINE := Color(1.0, 0.988, 0.949, 0.75)


static func start_opt(on: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(5)
	s.set_border_width_all(1)
	if on:
		s.bg_color = Color(0.93, 0.86, 0.68, 0.96)
		s.border_color = GOLD
	else:
		s.bg_color = Color(1.0, 0.992, 0.965, 0.94)
		s.border_color = Color(0.376, 0.298, 0.133, 0.22)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func style_label(node: Label, size: int, use_mono: bool = false, dim: bool = false) -> void:
	node.add_theme_font_override("font", BwTheme.mono() if use_mono else BwTheme.sans())
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", INK_DIM if dim else INK)
