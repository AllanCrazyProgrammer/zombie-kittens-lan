class_name NopWindow
extends RefCounted
## Ventana de Nop (UX-05): qué se le ofrece al jugador mientras hay una jugada en la pila, y el ajuste
## local «Dejar pasar lo que no me afecta». Solo lee la vista del jugador; no toca el motor.

const SETTINGS := "user://settings.cfg"
const SECTION := "plus"
const KEY := "auto_pass"
const ATTACKS: Array[String] = ["attack", "attack_dead", "targeted_attack"]


## Cuántos Nop tiene el jugador en la mano.
static func nop_count(v: Dictionary) -> int:
	var n := 0
	for c: Dictionary in v.hand:
		if c.type == "nope":
			n += 1
	return n


## ¿Puede el jugador responder ahora a la jugada de la pila? (si no, solo ve el texto y la barra de tiempo)
static func can_respond(v: Dictionary) -> bool:
	return v.win != null and v.win.canNope and not v.win.passed


## Texto del botón: «¡NOP!» con un solo Nop y «¡NOP! ×N» con más.
static func button_text(v: Dictionary) -> String:
	var n := nop_count(v)
	return "¡NOP! ×%d" % n if n > 1 else "¡NOP!"


## Ids de los Nop de la mano que conviene resaltar (vacío si no puede responder).
static func nop_ids(v: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not can_respond(v):
		return out
	for c: Dictionary in v.hand:
		if c.type == "nope":
			out.append(c.id)
	return out


## Siguiente jugador vivo después de `from`, según el sentido de juego de la vista ("" si no hay).
static func next_after(v: Dictionary, from: String) -> String:
	var players: Array = v.players
	var idx := -1
	for i in players.size():
		if players[i].id == from:
			idx = i
	if idx < 0:
		return ""
	var step: int = int(v.get("dir", 1))
	for k in range(1, players.size() + 1):
		var p: Dictionary = players[posmod(idx + k * step, players.size())]
		if p.alive:
			return p.id
	return ""


## ¿La jugada de arriba de la pila afecta al jugador? Objetivo de la jugada, ataque que le tocaría recibir,
## Apocalipsis si él roba el siguiente, o un Nop que anuló una jugada suya.
static func affects(v: Dictionary) -> bool:
	if v.stack.is_empty():
		return false
	var me: String = v.you
	var t: Dictionary = v.stack[v.stack.size() - 1]
	if t.target == me:
		return true
	if int(t.nopes) % 2 == 1 and t.by == me:
		return true
	if t.eff in ATTACKS:
		return next_after(v, t.by) == me
	if t.eff == "apocalypse":
		var drawer: String = t.by if int(v.turnsLeft) > 1 and v.cur == t.by else next_after(v, t.by)
		return drawer == me
	return false


## ¿Debe enviarse «pasar» sola? Hay una jugada ajena que puedo responder, aún no pasé y no me afecta.
static func should_auto_pass(v: Dictionary) -> bool:
	if v.over != null or not can_respond(v) or v.stack.is_empty():
		return false
	var t: Dictionary = v.stack[v.stack.size() - 1]
	return t.by != v.you and not affects(v)


## Huella de la jugada de arriba (para no enviar «pasar» dos veces sobre la misma).
static func signature(v: Dictionary) -> String:
	if v.stack.is_empty():
		return ""
	var t: Dictionary = v.stack[v.stack.size() - 1]
	return "%s/%s" % [str(t.id), str(t.nopes)]


static func load_auto_pass() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return bool(cfg.get_value(SECTION, KEY, false))


static func save_auto_pass(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value(SECTION, KEY, on)
	cfg.save(SETTINGS)
