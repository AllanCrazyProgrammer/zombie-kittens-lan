class_name CardPickGrid
extends ScrollContainer
## Cuadrícula desplazable de miniaturas de carta, 3 columnas (UX-04). Un toque corto sobre una
## miniatura emite `picked`; arrastrar para desplazar la lista no elige nada.

signal picked(type: String)

const COLUMNS := 3
const TAP_SLOP := 24.0

var _types: Array[String] = []
var _down := Vector2.ZERO


## types: tipos que se ofrecen, en este orden. max_h: alto máximo de la zona desplazable.
func setup(types: Array, max_h: float) -> CardPickGrid:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	custom_minimum_size = Vector2(0, max_h)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	add_child(grid)
	for t: String in types:
		_types.append(t)
		var cell := UIKit.panel(Color(0.11, 0.06, 0.24), UIKit.C.line, Vector2(8, 8))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.gui_input.connect(_on_cell_input.bind(t))
		var v := UIKit.vbox(4)
		cell.add_child(v)
		var pic := UIKit.card_image(t, 250)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(pic)
		var l := UIKit.label(CardDB.display_name(t), 26, UIKit.C.ink, false, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(0, 66)
		v.add_child(l)
		grid.add_child(cell)
	return self


func _on_cell_input(event: InputEvent, type: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = event.global_position
		elif event.global_position.distance_to(_down) <= TAP_SLOP:
			picked.emit(type)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_down = event.position
		elif event.position.distance_to(_down) <= TAP_SLOP:
			picked.emit(type)


## Tipos ofrecidos, en orden (prueba).
func debug_types() -> Array[String]:
	return _types


## Simula el toque sobre una miniatura (prueba).
func debug_pick(type: String) -> void:
	if _types.has(type):
		picked.emit(type)
