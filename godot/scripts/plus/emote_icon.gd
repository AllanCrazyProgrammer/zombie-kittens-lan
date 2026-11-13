class_name EmoteIcon
extends Control
## Icono del botón de reacciones (UX-08): un globo de diálogo con tres puntos, dibujado (sin emoji ni fuente).
## Durante el enfriamiento oscurece el botón de arriba abajo y muestra los segundos que faltan.

var _frac := 0.0      # fracción de enfriamiento que queda (0 = listo)
var _secs := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## frac 0 = listo; 1 = recién enviado. secs = segundos que faltan (se redondea hacia arriba).
func set_cooldown(frac: float, secs: int) -> void:
	if absf(frac - _frac) > 0.004 or secs != _secs:
		_frac = frac
		_secs = secs
		queue_redraw()


func cooling() -> bool:
	return _frac > 0.0


func _draw() -> void:
	var c := size * 0.5
	var tint := Color(0.62, 0.6, 0.72) if _frac > 0.0 else UIKit.C.cream
	var body := Rect2(c.x - 30, c.y - 22, 60, 38)
	draw_style_box(UIKit.box(tint, UIKit.C.dark, 14, 3, Vector2.ZERO), body)
	draw_colored_polygon(PackedVector2Array([Vector2(c.x - 14, c.y + 13), Vector2(c.x + 4, c.y + 13), Vector2(c.x - 18, c.y + 30)]), tint)
	for i in 3:
		draw_circle(Vector2(c.x - 15 + 15 * i, c.y - 3), 4.5, UIKit.C.dark)
	if _frac > 0.0:
		var r := Rect2(6, 6, size.x - 12, (size.y - 12) * _frac)
		draw_rect(r, Color(0.08, 0.04, 0.16, 0.55))
		var f: Font = UIKit.TITLE_FONT
		var s := str(maxi(1, _secs))
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
		draw_string_outline(f, Vector2(c.x - w * 0.5, c.y + 15), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, 8, UIKit.C.dark)
		draw_string(f, Vector2(c.x - w * 0.5, c.y + 15), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, UIKit.C.gold)
