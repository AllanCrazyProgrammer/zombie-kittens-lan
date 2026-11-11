class_name DiscardList
extends VBoxContainer
## Lista desplazable de las cartas jugadas (UX-03): la más reciente arriba, con miniatura, nombre y
## quién la jugó. El descarte es información pública (`view.discard`, últimas 20 entradas).

var _scroll: ScrollContainer
var _ids: Array[String] = []


## view: vista de la partida. max_h: alto máximo de la lista. scroll: posición a restaurar.
func setup(view: Dictionary, max_h: float, scroll: int = 0) -> DiscardList:
	add_theme_constant_override("separation", 12)
	var names := {}
	for p: Dictionary in view.players:
		names[p.id] = p.name
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, max_h)
	add_child(_scroll)
	var list := UIKit.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list)
	var entries: Array = view.discard
	if entries.is_empty():
		var l := UIKit.label("Aún no se ha jugado ninguna carta.", 32, UIKit.C.dim, false, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(l)
	for i in range(entries.size() - 1, -1, -1):
		var d: Dictionary = entries[i]
		_ids.append(str(d.id))
		var row := UIKit.panel(Color(0.11, 0.06, 0.24), UIKit.C.line, Vector2(14, 10))
		var h := UIKit.hbox(18)
		row.add_child(h)
		h.add_child(UIKit.card_image(d.type, 150))
		var v := UIKit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(v)
		v.add_child(UIKit.label(CardDB.display_name(d.type), 40, UIKit.C.ink, true, true))
		var by := "Tú" if d.by == view.you else str(names.get(d.by, "?"))
		v.add_child(UIKit.label("Jugó: " + by, 30, UIKit.C.gold if d.by == view.you else UIKit.C.dim))
		if i == entries.size() - 1:
			v.add_child(UIKit.label("Arriba del descarte", 26, UIKit.C.toxic))
		list.add_child(row)
	_pass_touches(list)
	if scroll > 0:
		_restore.call_deferred(scroll)
	return self


## Paneles e imágenes se quedan con el toque por defecto y el dedo no llegaría a la lista: se les deja pasar.
func _pass_touches(n: Node) -> void:
	if n is Control and n.mouse_filter == Control.MOUSE_FILTER_STOP:
		n.mouse_filter = Control.MOUSE_FILTER_PASS
	for c in n.get_children():
		_pass_touches(c)


func _restore(v: int) -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = v


## Posición actual de la lista (para conservarla si la ventana se reconstruye).
func scroll_value() -> int:
	return _scroll.scroll_vertical if is_instance_valid(_scroll) else 0


## Ids de las cartas listadas, la más reciente primero (prueba).
func debug_ids() -> Array[String]:
	return _ids
