class_name MatchStats
extends RefCounted
## Resumen de fin de partida (UX-09). Acumula contadores por jugador a partir de los eventos públicos
## (`feed`, una vez por evento, en orden de `seq`) y dibuja la tabla compacta de la ventana final.
## Solo cuenta lo que la vista conserva: el motor guarda los últimos 80 eventos.

const COLS: Array[Array] = [["Explotó", "boom"], ["Revivido", "revived"], ["Nops", "nopes"], ["Robos", "steals"], ["Turnos", "turns"]]
const NUM_W := 128

var _last_seq := 0
var _d := {}
var _rows: Array[Dictionary] = []    # última tabla dibujada (prueba)


func _row(id: Variant) -> Dictionary:
	var k := str(id)
	if not _d.has(k):
		_d[k] = {"boom": 0, "revived": 0, "nopes": 0, "steals": 0, "turns": 0}
	return _d[k]


func _add(id: Variant, key: String, n: int = 1) -> void:
	if id != null:
		_row(id)[key] += n


## Contadores de un jugador: boom (veces que explotó), revived (veces que lo revivieron), nopes (Nops jugados),
## steals (cartas robadas a otros: parejas, tríos y favores recibidos) y turns (turnos que le tocaron).
func of(id: Variant) -> Dictionary:
	return _row(id).duplicate()


## Suma un evento público. Los ya vistos (seq repetido o anterior) se ignoran. `players` es la lista de la vista.
func feed(e: Dictionary, players: Array) -> void:
	var seq := int(e.get("seq", 0))
	if seq <= _last_seq:
		return
	_last_seq = seq
	match e.type:
		"start":
			for p: Dictionary in players:
				if str(e.get("text", "")).ends_with("Empieza %s." % p.name):
					_add(p.id, "turns")
		"turn":
			_add(e.player, "turns")
		"attack":
			_add(e.target, "turns", maxi(0, int(e.n) - 1))     # el evento «turn» ya contó el primero
		"died":
			_add(e.player, "boom")
		"revived":
			_add(e.target, "revived")
		"nope":
			_add(e.player, "nopes")
		"steal":
			_add(e.player, "steals")
		"gave":
			_add(e.target, "steals")


## Tabla compacta: una fila por jugador (avatar pequeño + nombre) con los contadores; el ganador resaltado.
## `scores` opcional {id: victorias} añade una columna «Victorias» (marcador de sala, otra tarea).
func build_table(view: Dictionary, scores: Dictionary = {}) -> VBoxContainer:
	_rows = []
	var winner: Variant = view.over.winner if view.over != null else null
	var cols: Array[Array] = COLS.duplicate()
	if not scores.is_empty():
		cols.append(["Victorias", "wins"])
	var table := UIKit.vbox(6)
	var head := UIKit.hbox(6)
	head.add_child(_cell("", 24, UIKit.C.dim, 0))
	for c: Array in cols:
		head.add_child(_cell(c[0], 22, UIKit.C.dim, NUM_W if cols.size() <= 5 else 104))
	var head_m := MarginContainer.new()      # mismo margen que el panel de cada fila (borde + relleno)
	head_m.add_theme_constant_override("margin_left", 15)
	head_m.add_theme_constant_override("margin_right", 15)
	head_m.add_child(head)
	table.add_child(head_m)
	for p: Dictionary in view.players:
		var won: bool = p.id == winner
		var stats := of(p.id)
		stats["wins"] = int(scores.get(p.id, 0))
		var panel := UIKit.panel(Color("3a2a05") if won else Color(0.11, 0.06, 0.24), UIKit.C.gold if won else UIKit.C.line, Vector2(10, 6))
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
		var h := UIKit.hbox(6)
		panel.add_child(h)
		var who := UIKit.hbox(10)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.add_child(UIKit.avatar_icon(int(p.avatar), Vector2(46, 60)))
		var nm := UIKit.label(str(p.name) + ("  ★" if won else ""), 30, UIKit.C.gold if won else UIKit.C.ink, true)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		who.add_child(nm)
		h.add_child(who)
		var values: Array = []
		for c: Array in cols:
			var val := int(stats[c[1]])
			values.append(val)
			h.add_child(_cell(str(val), 34, UIKit.C.gold if won else UIKit.C.ink, NUM_W if cols.size() <= 5 else 104))
		table.add_child(panel)
		_rows.append({"id": p.id, "winner": won, "values": values, "panel": panel})
	return table


func _cell(text: String, size: int, color: Color, w: int) -> Label:
	var l := UIKit.label(text, size, color, size >= 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(w, 0)
	if w == 0:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Filas de la última tabla dibujada: [{id, winner, values: [explotó, revivido, nops, robos, turnos(, victorias)]}] (prueba).
func debug_rows() -> Array:
	return _rows.map(func(r: Dictionary) -> Dictionary: return {"id": r.id, "winner": r.winner, "values": r.values, "border": (r.panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color})
