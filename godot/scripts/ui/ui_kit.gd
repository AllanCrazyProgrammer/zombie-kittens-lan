class_name UIKit
extends RefCounted
## Piezas de interfaz con el estilo del juego (botones, paneles, textos). Todo se crea por código.

const TITLE_FONT := preload("res://assets/fonts/Bangers-Regular.ttf")
const BODY_FONT := preload("res://assets/fonts/Nunito.ttf")
const C := {
	"night": Color("170c33"), "panel": Color("2b1c5c"), "panel2": Color("382673"), "line": Color("4d3a94"),
	"ink": Color("f4efff"), "dim": Color("b3a6dc"), "toxic": Color("b6f23a"), "toxic_dark": Color("4e7a10"),
	"red": Color("ff4055"), "gold": Color("ffd23a"), "cream": Color("fbf5e6"), "dark": Color("150a22"),
}
static var _bold: FontVariation
static var _grabber: Texture2D


static func bold() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = BODY_FONT
		_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	return _bold


static func box(bg: Color, border: Color, radius: int = 28, bw: int = 5, pad: Vector2 = Vector2(28, 16)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	return s


static func label(text: String, size: int = 40, color: Color = C.ink, title: bool = false, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", TITLE_FONT if title else bold())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if title:
		l.add_theme_color_override("font_outline_color", C.dark)
		l.add_theme_constant_override("outline_size", maxi(6, size / 5))
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## kind: normal | primary | danger | ghost | on
static func button(text: String, kind: String = "normal", size: int = 46) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", TITLE_FONT)
	b.add_theme_font_size_override("font_size", size)
	var bg: Color = C.panel2
	var border: Color = C.line
	var fg: Color = C.ink
	match kind:
		"primary", "on":
			bg = Color("a6e62e"); border = Color("dcff8a"); fg = Color("16250a")
		"danger":
			bg = Color("e0283f"); border = Color("ffa5b0"); fg = Color.WHITE
		"ghost":
			bg = Color(1, 1, 1, 0.06); border = Color(1, 1, 1, 0.3)
	var normal := box(bg, border)
	normal.shadow_color = Color(0, 0, 0, 0.45)
	normal.shadow_size = 2
	normal.shadow_offset = Vector2(0, 7)
	var pressed := box(bg.darkened(0.18), border)
	var disabled := box(Color("3a3550"), Color("555066"))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fg)
	b.add_theme_color_override("font_disabled_color", Color("8a86a0"))
	b.custom_minimum_size = Vector2(0, size * 2.1)
	b.pressed.connect(func() -> void: Sfx.play("tap", -6.0))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


static func panel(bg: Color = C.panel, border: Color = C.line, pad: Vector2 = Vector2(30, 24)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, 30, 5, pad))
	return p


static func vbox(sep: int = 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func timer_bar() -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 18)
	p.add_theme_stylebox_override("background", box(Color("150a30"), Color("150a30"), 9, 0, Vector2.ZERO))
	p.add_theme_stylebox_override("fill", box(C.gold, C.gold, 9, 0, Vector2.ZERO))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func slider(max_value: int, value: int) -> HSlider:
	if _grabber == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.78, 0.8, 0.98, 1.0])
		g.colors = PackedColorArray([C.toxic, C.toxic, Color("16250a"), Color("16250a"), Color(0, 0, 0, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 84
		t.height = 84
		_grabber = t
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = max_value
	s.step = 1
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(0, 96)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
		s.add_theme_icon_override(n, _grabber)
	var track := box(Color("150a30"), C.line, 12, 3, Vector2.ZERO)
	track.content_margin_top = 12
	track.content_margin_bottom = 12
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", box(C.red, C.red, 12, 0, Vector2.ZERO))
	s.add_theme_stylebox_override("grabber_area_highlight", box(C.red, C.red, 12, 0, Vector2.ZERO))
	return s


static func card_image(type: String, height: int = 420) -> TextureRect:
	var t := TextureRect.new()
	t.texture = CardDB.texture(type)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(height * 5.0 / 7.0, height)
	return t
