class_name HistoryList
extends VBoxContainer
## Ventana «Historial» (UX-12): filtro «Todo / Solo lo mío» y, por entrada, el avatar de quien actuó y la
## miniatura de la carta implicada (solo si es conocida para este jugador). Las entradas son las que
## guarda la pantalla: {text, kind, player, target, mine, cards}; los encabezados de turno llevan kind «turn».

## Se emite al pulsar un filtro (true = «Solo lo mío»).
signal filter_changed(mine_only: bool)

const AVATAR := Vector2(46, 60)
const THUMB_H := 84

var _scroll: ScrollContainer
var _rows := 0
var _avatars := 0
var _thumbs := 0
var _list: VBoxContainer


## Cartas conocidas por este jugador que implica un evento (tipos). Los eventos privados solo llegan a quien los ve.
static func cards_of(e: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var src: Array = []
	match e.type:
		"play":
			src = [e.get("eff", "")]
		"got", "lost", "steal", "haunt":
			src = [e.get("card", "")]
		"nope":
			src = ["nope"]
		"boom":
			src = ["exploding"]
		"future", "peek":
			src = e.get("cards", [])
	for t: Variant in src:
		if str(t) != "" and CardDB.defs.has(str(t)):
			out.append(str(t))
	return out


## Bloques del historial según el filtro: [{title, head_mine, items}] con lo más reciente primero y, dentro de cada
## turno, en el orden en que pasó. Con el filtro solo quedan los turnos con entradas mías (o que son mi turno).
static func blocks(history: Array, mine_only: bool) -> Array:
	var all: Array = [{"title": "Inicio", "head_mine": false, "items": []}]
	for h: Dictionary in history:
		if h.kind == "turn":
			all.append({"title": h.text, "head_mine": bool(h.get("mine", false)), "items": []})
		elif not mine_only or bool(h.get("mine", false)):
			all[-1].items.append(h)
	var out: Array = []
	for bi in range(all.size() - 1, -1, -1):
		var b: Dictionary = all[bi]
		var keep: bool = not b.items.is_empty() or (b.head_mine if mine_only else bi == all.size() - 1)
		if keep:
			out.append(b)
	return out


## Cuántas entradas (sin contar encabezados) muestra el historial con ese filtro.
static func count(history: Array, mine_only: bool) -> int:
	var n := 0
	for b: Dictionary in blocks(history, mine_only):
		n += (b.items as Array).size()
	return n


## avatars: {id: índice de avatar}. max_h: alto de la lista desplazable.
func setup(history: Array, mine_only: bool, avatars: Dictionary, max_h: float) -> HistoryList:
	add_theme_constant_override("separation", 14)
	var filt := UIKit.hbox(12)
	filt.alignment = BoxContainer.ALIGNMENT_CENTER
	for f: Array in [["Todo", false], ["Solo lo mío", true]]:
		var b := UIKit.button(f[0], "primary" if mine_only == f[1] else "normal", 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val: bool = f[1]
		b.pressed.connect(func() -> void: filter_changed.emit(val))
		filt.add_child(b)
	add_child(filt)
	var hint := UIKit.label("Solo lo mío: lo que viste solo tú y lo que hiciste o te hicieron." if mine_only else "Los turnos más recientes arriba. En verde, lo que solo tú viste.", 26, UIKit.C.dim, false, true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, max_h)
	add_child(_scroll)
	var list := UIKit.vbox(8)
	_list = list
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list)
	var shown := blocks(history, mine_only)
	if history.is_empty() or (mine_only and count(history, true) == 0):
		var l := UIKit.label("Aún no pasa nada." if history.is_empty() else "Todavía no hay nada tuyo.", 32, UIKit.C.dim, false, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(l)
	for b: Dictionary in shown:
		var t := UIKit.label("— %s —" % b.title, 36, UIKit.C.gold, true)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(t)
		for h: Dictionary in b.items:
			list.add_child(_entry(h, avatars))
			_rows += 1
	_pass_touches(list)
	return self


func _entry(h: Dictionary, avatars: Dictionary) -> HBoxContainer:
	var row := UIKit.hbox(10)
	if h.get("player") != null and avatars.has(h.player):
		row.add_child(UIKit.avatar_icon(int(avatars[h.player]), AVATAR))
		_avatars += 1
	else:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(AVATAR.x, 0)
		row.add_child(gap)
	var cards: Array = h.get("cards", [])
	for t: Variant in cards:
		row.add_child(UIKit.card_image(str(t), THUMB_H))
		_thumbs += 1
	var l := UIKit.label(h.text, 30, Color("c8ff8a") if h.kind == "me" else UIKit.C.ink, false, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row


## Imágenes y paneles se quedan con el toque por defecto y el dedo no llegaría a la lista: se les deja pasar.
func _pass_touches(n: Node) -> void:
	if n is Control and n.mouse_filter == Control.MOUSE_FILTER_STOP:
		n.mouse_filter = Control.MOUSE_FILTER_PASS
	for c in n.get_children():
		_pass_touches(c)


## Entradas dibujadas (prueba).
func debug_rows() -> int:
	return _rows


## Prueba: avatares y miniaturas dibujados, y controles que se quedarían con el toque (impedirían desplazar con el dedo).
func debug_info() -> Dictionary:
	return {"avatars": _avatars, "thumbs": _thumbs, "blockers": _blockers(_list)}


func _blockers(n: Node) -> int:
	var k := 1 if (n is Control and n.mouse_filter == Control.MOUSE_FILTER_STOP) else 0
	for c in n.get_children():
		k += _blockers(c)
	return k
