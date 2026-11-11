class_name FutureArranger
extends HBoxContainer
## Alterar el Futuro: las (hasta) 3 cartas de arriba en grande, con las etiquetas fijas PRÓXIMA /
## SEGUNDA / TERCERA. Se reordenan arrastrando una carta sobre otra o, más sencillo, tocando dos
## cartas para intercambiarlas. `order[k]` es el índice (dentro de las cartas recibidas) de la carta
## que quedará en el lugar k; es justo lo que espera la acción `reorder`.

signal order_changed(order: Array)

const LABELS := ["PRÓXIMA", "SEGUNDA", "TERCERA"]
const IDLE_BORDER := Color("5b3da8")

var _types: Array = []
var _order: Array[int] = []
var _pics: Array[TextureRect] = []
var _cells: Array[PanelContainer] = []
var _picked := -1        # lugar tocado, a la espera de otro para intercambiarse
var _press := -1         # lugar donde empezó el dedo
var _over := -1          # lugar bajo el dedo mientras se arrastra


## types: tipos de las cartas, la primera es la próxima. card_h: alto de cada carta.
## order: orden inicial (permutación); si no vale, el original.
func setup(types: Array, card_h: int, order: Array = []) -> FutureArranger:
	_types = types.duplicate()
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 14)
	_order = []
	var ok := order.size() == types.size()
	for k in order.size():
		if int(order[k]) < 0 or int(order[k]) >= types.size() or _order.has(int(order[k])):
			ok = false
			break
		_order.append(int(order[k]))
	if not ok:
		_order = []
		for i in types.size():
			_order.append(i)
	for slot in _types.size():
		var col := UIKit.vbox(8)
		var l := UIKit.label(LABELS[mini(slot, 2)], 38, UIKit.C.gold, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		var cell := UIKit.panel(Color(0.11, 0.06, 0.24), IDLE_BORDER, Vector2(6, 6))
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.gui_input.connect(_on_cell_input.bind(slot))
		var pic := UIKit.card_image(_types[_order[slot]], card_h)
		pic.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_child(pic)
		col.add_child(cell)
		add_child(col)
		_pics.append(pic)
		_cells.append(cell)
	_paint()
	return self


## Orden actual: el índice (de las cartas recibidas) que ocupa cada lugar.
func order() -> Array:
	return _order.duplicate()


## Tipos en el orden actual (el primero es la próxima carta).
func current_types() -> Array:
	return _order.map(func(i: int) -> String: return _types[i])


func _paint() -> void:
	for slot in _cells.size():
		_pics[slot].texture = CardDB.texture(_types[_order[slot]])
		var hot := slot == _picked or (slot == _over and _press >= 0 and _over != _press)
		_cells[slot].add_theme_stylebox_override("panel", UIKit.box(Color(0.11, 0.06, 0.24), UIKit.C.toxic if hot else IDLE_BORDER, 18, 8 if hot else 4, Vector2(6, 6)))
		_cells[slot].modulate = Color(1.15, 1.2, 1.0) if slot == _picked else Color.WHITE


func _swap(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= _order.size() or b >= _order.size():
		return
	var t := _order[a]
	_order[a] = _order[b]
	_order[b] = t
	_picked = -1
	_paint()
	order_changed.emit(order())


func _slot_at(global_pos: Vector2) -> int:
	for slot in _cells.size():
		if _cells[slot].get_global_rect().has_point(global_pos):
			return slot
	return -1


func _on_cell_input(event: InputEvent, slot: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press = slot
			_over = slot
		else:
			var at := _slot_at(_global_of(event, slot))
			var from := _press
			_press = -1
			_over = -1
			if from < 0:
				return
			if at >= 0 and at != from:
				_swap(from, at)         # arrastrada sobre otra carta
			else:
				_tap(from)
	elif event is InputEventMouseMotion and _press >= 0:
		var at2 := _slot_at(_global_of(event, slot))
		if at2 != _over:
			_over = at2
			_paint()


## Posición del evento en coordenadas globales (no depende de dónde crea el motor que está el ratón).
func _global_of(event: InputEvent, slot: int) -> Vector2:
	return _cells[slot].get_global_transform() * (event as InputEventMouse).position


func _tap(slot: int) -> void:
	if _picked < 0:
		_picked = slot
		_paint()
	elif _picked == slot:
		_picked = -1
		_paint()
	else:
		_swap(_picked, slot)


## Prueba: la carta (control) de un lugar, para tocarla o arrastrarla de verdad.
func debug_cell(slot: int) -> Control:
	return _cells[slot]


## Prueba: toca un lugar (primer toque elige, segundo intercambia).
func debug_tap(slot: int) -> void:
	_tap(slot)


## Prueba: intercambia dos lugares como si se arrastrara una carta sobre otra.
func debug_swap(a: int, b: int) -> void:
	_swap(a, b)
