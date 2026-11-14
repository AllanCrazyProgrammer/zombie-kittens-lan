class_name EmotePicker
extends Control
## Selector de reacciones (UX-08): una fila con las 6 bajo la barra superior. Tocar una la envía; tocar fuera lo cierra.

signal chosen(index: int)
signal closed

var buttons: Array[Button] = []
var _panel: PanelContainer


## `under`: rectángulo del botón que lo abre (coordenadas de la interfaz). Se coloca justo debajo y pegado a la derecha.
func setup(under: Rect2, screen: Vector2) -> EmotePicker:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = UIKit.panel(UIKit.C.panel, UIKit.C.toxic_dark, Vector2(12, 12))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := UIKit.hbox(6)
	for i in EmoteSet.COUNT:
		var b := UIKit.button(EmoteSet.word(i), "normal", 36)
		b.custom_minimum_size = Vector2(0, 112)
		for st: String in ["normal", "hover", "pressed", "disabled"]:
			var sb := b.get_theme_stylebox(st) as StyleBoxFlat
			sb.content_margin_left = 4
			sb.content_margin_right = 4
		for cn: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(cn, EmoteSet.color(i))
		var idx := i
		b.pressed.connect(func() -> void: chosen.emit(idx))
		row.add_child(b)
		buttons.append(b)
	_panel.add_child(row)
	add_child(_panel)
	var sz := _panel.get_combined_minimum_size()
	_panel.size = sz
	_panel.position = Vector2(clampf(under.end.x - sz.x, 8.0, maxf(8.0, screen.x - sz.x - 8.0)), under.end.y + 14.0)
	_panel.pivot_offset = Vector2(sz.x, 0)
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_panel, "modulate:a", 1.0, 0.1)
	return self


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		accept_event()
		closed.emit()
