class_name DeckMemoryStrip
extends PanelContainer
## Recordatorio del futuro (UX-02), vista: tira compacta junto al mazo con las PRÓXIMAS cartas conocidas
## (hasta 3 miniaturas, hueco «?» para las posiciones no conocidas entre medias) y la marca «💣 en N»
## si se conoce un explosivo más abajo. Solo el rectángulo de la tira recibe toques: tocarla emite `tapped`.

signal tapped

const THUMB_H := 112

var _row: HBoxContainer
var _items := 0
var _bomb := -1
var _sig := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("panel", UIKit.box(Color(0.08, 0.04, 0.16, 0.82), UIKit.C.gold, 18, 3, Vector2(10, 6)))
	_row = UIKit.hbox(8)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	visible = false


## Redibuja con el resultado de `DeckMemory.strip()`. Se oculta si no se sabe nada.
func update(info: Dictionary) -> void:
	var items: Array = info.get("items", [])
	var bomb: int = int(info.get("bomb", -1))
	var sig := str(items) + "|" + str(bomb)
	visible = not items.is_empty() or bomb >= 0
	if sig == _sig:
		return
	_sig = sig
	_items = items.size()
	_bomb = bomb
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	for it: Dictionary in items:
		_row.add_child(_slot(it))
	if bomb >= 0:
		var b := UIKit.label("💣 en %d" % (bomb + 1), 30, UIKit.C.gold, true)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(b)
	reset_size()


func _slot(it: Dictionary) -> Control:
	var col := UIKit.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var depth: int = int(it.depth)
	if depth < 0:
		var q := PanelContainer.new()
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		q.custom_minimum_size = Vector2(46, THUMB_H)
		q.add_theme_stylebox_override("panel", UIKit.box(Color(0.17, 0.11, 0.36, 0.7), UIKit.C.line, 10, 2, Vector2(0, 0)))
		var ql := UIKit.label("?", 44, UIKit.C.dim, true)
		ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ql.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ql.mouse_filter = Control.MOUSE_FILTER_IGNORE
		q.add_child(ql)
		col.add_child(q)
		var gl := UIKit.label("+%d" % int(it.get("gap", 1)), 22, UIKit.C.dim)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(gl)
		return col
	var pic := UIKit.card_image(str(it.type), THUMB_H)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	var cap := UIKit.label(position_name(depth), 22, UIKit.C.gold, true)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cap)
	return col


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		tapped.emit()
		accept_event()
	elif event is InputEventScreenTouch and not event.pressed:
		tapped.emit()
		accept_event()


## Cuántas miniaturas «?» y cartas hay dibujadas (prueba).
func debug_items() -> Array:
	var out: Array = []
	for c in _row.get_children():
		if c is VBoxContainer:
			out.append("?" if (c.get_child(0) is PanelContainer) else "carta")
	return out


## Marca de explosivo más abajo (posición 1-based, 0 si no hay) (prueba).
func debug_bomb() -> int:
	return _bomb + 1 if _bomb >= 0 else 0


## «Próxima», «2.ª», «3.ª»… según la profundidad (0 = la próxima).
static func position_name(depth: int) -> String:
	return "Próxima" if depth <= 0 else "%d.ª" % (depth + 1)


## Rellena la ventana del recordatorio con todo lo conocido, en orden (3 por fila).
static func fill_window(box: VBoxContainer, known: Array, deck_n: int) -> void:
	var intro := UIKit.label("Mazo de %d cartas. Solo tú lo ves." % deck_n, 30, UIKit.C.ink, false, true)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(intro)
	if known.is_empty():
		var none := UIKit.label("Ya no recuerdas nada: el mazo cambió.", 34, UIKit.C.gold, false, true)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(none)
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	var cc := CenterContainer.new()
	cc.add_child(grid)
	box.add_child(cc)
	for k: Dictionary in known:
		var col := UIKit.vbox(4)
		var d: int = int(k.depth)
		var l := UIKit.label(position_name(d) if d <= 0 else "Posición %d" % (d + 1), 30, UIKit.C.gold, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		col.add_child(UIKit.card_image(str(k.type), 330 if known.size() <= 3 else 270))
		var sub := UIKit.label(("debajo de %d carta%s" % [d, "s" if d > 1 else ""]) if d > 0 else "la próxima en robarse", 24, UIKit.C.dim)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub)
		grid.add_child(col)
