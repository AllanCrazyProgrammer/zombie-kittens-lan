class_name DeckMemory
extends RefCounted
## Recordatorio del futuro (UX-02): lo que ESTE jugador sabe de posiciones concretas del mazo.
##
## Aplica la misma vigencia que `ZKBots` (`learn` / `known`): lo sabido vale mientras `shuf` no cambie
## y se desplaza con `tops` (cartas retiradas de ARRIBA). Robar del fondo no desplaza nada. Se alimenta
## de los eventos de la vista: `future`, `clair`, `inserted` (propio), `buried` (propio) y `apocalypse`.

var _shuf := -1
var _abs := {}            # posición absoluta (profundidad + tops cuando se aprendió) -> tipo de carta
var _seq := 0             # último evento procesado
var bury_card := ""       # tipo de la carta que estoy enterrando (se lee de la decisión `bury` abierta)
var pending_insert: Array = []   # posiciones que envié al esconder explosivos (el evento `inserted` no las trae)


## Profundidades de los explosivos escondidos con estas posiciones (mismo cálculo que `ZKBots._depths`).
static func depths_of(pos: Array) -> Dictionary:
	var at := {}
	if pos.size() > 1:
		at[int(pos[0]) + (1 if int(pos[1]) <= int(pos[0]) else 0)] = "exploding"
		at[int(pos[1])] = "exploding"
	elif pos.size() == 1:
		at[int(pos[0])] = "exploding"
	return at


## Olvida todo (p. ej. al empezar otra partida).
func clear() -> void:
	_abs.clear()
	_shuf = -1


## Aprende `at` (profundidad -> tipo) tal como estaba el mazo con esos `shuf` y `tops`.
func learn(shuf: int, tops: int, at: Dictionary) -> void:
	if shuf < _shuf:
		return
	if shuf != _shuf:
		_abs.clear()
		_shuf = shuf
	for d: Variant in at:
		_abs[int(d) + tops] = str(at[d])


## Anota las posiciones que el jugador acaba de enviar al esconder sus explosivos.
func note_insert(positions: Array) -> void:
	pending_insert = positions.duplicate()


## Procesa los eventos nuevos de la vista (los ya vistos se saltan) y la decisión `bury` propia.
func feed(v: Dictionary) -> void:
	var pr: Variant = v.get("prompt")
	if pr != null and pr.get("mine", false) and pr.type == "bury":
		bury_card = str(pr.get("card", ""))
	var evs: Array = v.get("events", [])
	for i in evs.size():
		var e: Dictionary = evs[i]
		if e.seq <= _seq:
			continue
		_seq = e.seq
		_on_event(e, v, evs, i)


func _on_event(e: Dictionary, v: Dictionary, evs: Array, idx: int) -> void:
	match e.type:
		"future":
			var at := {}
			var cards: Array = e.cards
			for k in cards.size():
				at[k] = cards[k]
			learn(int(e.shuf), int(e.get("tops", 0)), at)
		"clair":
			learn(int(e.shuf), int(e.get("tops", 0)), depths_of(e.positions))
		"inserted":
			if e.player == v.you and not pending_insert.is_empty():
				learn(int(e.shuf), int(e.get("tops", 0)), depths_of(pending_insert))
			if e.player == v.you:
				pending_insert = []
		"buried":
			if bury_card != "":
				learn(int(e.shuf), int(e.get("tops", 0)), {int(e.pos): bury_card})
			bury_card = ""
		"apocalypse":
			# Público y sin `shuf`: vale el de la vista, salvo que después haya habido otro cambio del mazo
			# (en ese caso no se aprende nada: no se sabría con qué `shuf` encajarlo).
			var later_robs := 0
			for j in range(idx + 1, evs.size()):
				var f: Dictionary = evs[j]
				if _changes_deck(f):
					return
				if f.type == "draw" and not f.get("bottom", false):
					later_robs += 1
			var at := {}
			for k in int(e.n):
				at[k] = "exploding"
			learn(int(v.get("shuf", 0)), int(v.get("tops", 0)) - later_robs, at)


## ¿Este evento cambia el orden del mazo (sube `shuf`)?
static func _changes_deck(f: Dictionary) -> bool:
	if f.type in ["shuffle", "inserted", "buried", "apocalypse"]:
		return true
	var txt := str(f.get("text", ""))
	return txt.contains("reordena el futuro") or txt.contains("no quiso la primera") or txt.contains("entierra una carta")


## Lo que se sabe y sigue vigente: [{depth, type}] ordenado de arriba abajo (depth 0 = la próxima carta).
func known(v: Dictionary) -> Array:
	var out: Array = []
	if _shuf < 0 or int(v.get("shuf", -1)) != _shuf:
		if _shuf >= 0 and int(v.get("shuf", -1)) > _shuf:
			clear()
		return out
	var tops := int(v.get("tops", 0))
	var n := int(v.get("draw", 0))
	var keys := _abs.keys()
	keys.sort()
	for k: int in keys:
		var d := k - tops
		if d < 0 or d >= n:
			_abs.erase(k)       # ya se robó (de arriba o del fondo): no vuelve
			continue
		out.append({"depth": d, "type": _abs[k]})
	return out


## Tira para junto al mazo: hasta `max_cards` cartas conocidas con huecos «?» (depth -1) entre medias
## y `bomb`: profundidad del primer explosivo conocido que no sale en la tira (-1 si ninguno).
func strip(v: Dictionary, max_cards: int = 3) -> Dictionary:
	var kn := known(v)
	var items: Array = []
	var next_depth := 0
	var shown := 0
	var shown_depths: Array = []
	for k: Dictionary in kn:
		if shown >= max_cards:
			break
		if int(k.depth) > next_depth:
			items.append({"depth": -1, "type": "", "gap": int(k.depth) - next_depth})
		items.append(k)
		shown_depths.append(int(k.depth))
		next_depth = int(k.depth) + 1
		shown += 1
	var bomb := -1
	for k: Dictionary in kn:
		if k.type == "exploding" and not shown_depths.has(int(k.depth)):
			bomb = int(k.depth)
			break
	return {"items": items, "bomb": bomb, "count": kn.size()}
