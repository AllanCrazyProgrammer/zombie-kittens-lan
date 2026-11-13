class_name EmoteBubble
extends Control
## Globo de una reacción (UX-08): el gato de quien la envía y una palabra corta de color, con una cola que
## apunta al emisor. Aparece con un pequeño salto, se queda EmoteSet.SHOW_S segundos y se desvanece.
## Lo coloca la pantalla de juego cada cuadro con `place`.

const TAIL := 24.0

var player := ""
var index := 0
var _panel: PanelContainer
var _tail_x := 0.0
var _color := Color.WHITE
var _tween: Tween
var below := false     # true: el globo cuelga bajo el punto (cola hacia arriba); false: sobre el punto


func setup(p_player: String, avatar: int, p_index: int, p_below: bool = false) -> EmoteBubble:
	below = p_below
	player = p_player
	index = p_index
	_color = EmoteSet.color(index)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = UIKit.panel(UIKit.C.dark, _color, Vector2(14, 8))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UIKit.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UIKit.avatar_icon(avatar, Vector2(70, 92)))
	var l := UIKit.label(EmoteSet.word(index), 76, _color, true)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	_panel.add_child(row)
	add_child(_panel)
	var ps := _panel.get_combined_minimum_size()
	_panel.size = ps
	_panel.position = Vector2(0, TAIL if below else 0.0)
	custom_minimum_size = ps + Vector2(0, TAIL)
	size = custom_minimum_size
	pivot_offset = Vector2(size.x * 0.5, 0.0 if below else size.y)
	_tail_x = size.x * 0.5
	return self


## Anima la aparición, la espera y el desvanecido; al acabar se borra solo.
func play() -> void:
	scale = Vector2(0.25, 0.25)
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "modulate:a", 1.0, 0.12)
	_tween.tween_interval(EmoteSet.SHOW_S)
	_tween.tween_property(self, "modulate:a", 0.0, 0.35)
	_tween.tween_callback(queue_free)


## Pone el pie del globo en `anchor` (coordenadas de la interfaz) sin salirse de la pantalla.
func place(anchor: Vector2, screen: Vector2) -> void:
	var x := clampf(anchor.x - size.x * 0.5, 8.0, maxf(8.0, screen.x - size.x - 8.0))
	position = Vector2(x, anchor.y if below else anchor.y - size.y)
	var tx := clampf(anchor.x - x, 30.0, maxf(30.0, size.x - 30.0))
	if absf(tx - _tail_x) > 0.5:
		_tail_x = tx
		queue_redraw()
	pivot_offset = Vector2(_tail_x, 0.0 if below else size.y)


func _draw() -> void:
	var y := _panel.position.y
	var h := _panel.size.y
	var pts: PackedVector2Array
	var inner: PackedVector2Array
	if below:
		pts = PackedVector2Array([Vector2(_tail_x - 18.0, y + 4.0), Vector2(_tail_x + 18.0, y + 4.0), Vector2(_tail_x, 0.0)])
		inner = PackedVector2Array([Vector2(_tail_x - 11.0, y + 4.0), Vector2(_tail_x + 11.0, y + 4.0), Vector2(_tail_x, 8.0)])
	else:
		pts = PackedVector2Array([Vector2(_tail_x - 18.0, h - 4.0), Vector2(_tail_x + 18.0, h - 4.0), Vector2(_tail_x, h + TAIL)])
		inner = PackedVector2Array([Vector2(_tail_x - 11.0, h - 4.0), Vector2(_tail_x + 11.0, h - 4.0), Vector2(_tail_x, h + TAIL - 8.0)])
	draw_colored_polygon(pts, _color)
	draw_colored_polygon(inner, UIKit.C.dark)


## Prueba: ¿el globo sigue a la vista (no se está desvaneciendo del todo)?
func shown() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and modulate.a > 0.05
