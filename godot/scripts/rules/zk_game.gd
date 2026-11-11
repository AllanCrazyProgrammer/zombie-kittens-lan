class_name ZKGame
extends RefCounted
## Motor de reglas de Zombie Kittens (autoritativo). Port fiel de web/www/engine.js: mismas reglas, mismo
## orden de operaciones y mismo consumo de números aleatorios, para poder verificarlo jugada por jugada
## contra el motor original (ver tests/).
##
## No depende de nodos ni de la escena: recibe acciones (`act`), avanza con el reloj (`tick`) y expone
## el estado visible para cada jugador (`view`).

# [tipo, copias CON huella, copias SIN huella]  (24 con, 33 sin, + 4 explosivos = 61)
const DECK := [
	["zombie", 2, 3], ["attack", 2, 0], ["attack_dead", 0, 3], ["nope", 2, 3],
	["skip", 1, 2], ["super_skip", 1, 1], ["see_future", 2, 2], ["shuffle", 1, 1],
	["feed_dead", 0, 2], ["clone", 1, 2], ["grave_robber", 0, 1], ["favor", 1, 2],
	["dig_deeper", 2, 2], ["clairvoyance", 1, 1],
	["cat_a", 2, 2], ["cat_b", 2, 2], ["cat_c", 2, 2], ["cat_d", 2, 2],
]
## Cartas de packs (Plus). Mismo formato que DECK. «La Cripta»: falta la carta 10, `rotten` (otra tarea).
const DECK_CRYPT := [
	["targeted_attack", 0, 1], ["reverse", 0, 1], ["draw_bottom", 0, 1], ["crow_eye", 1, 1], ["apocalypse", 0, 1],
	["alter_future", 1, 1], ["bury", 0, 1], ["soul_swap", 0, 1], ["haunt", 0, 1],
]
## Respaldo de nombres de las cartas de packs (si la partida no recibe `names`, p. ej. en pruebas)
const NAMES_CRYPT := {
	"targeted_attack": "Ataque Dirigido", "reverse": "Marcha Atrás", "draw_bottom": "Robar del Fondo",
	"crow_eye": "Ojo de Cuervo", "apocalypse": "Apocalipsis Zombi", "alter_future": "Alterar el Futuro (3x)",
	"bury": "Entierro", "soul_swap": "Trueque de Almas", "haunt": "Espanto", "rotten": "Gatito Putrefacto",
}
const NAMES := {
	"exploding": "Gatito Explosivo", "zombie": "Gatito Zombi", "attack": "Ataque (2x)",
	"attack_dead": "Ataque de los Muertos", "nope": "Nop", "skip": "Saltar", "super_skip": "Súper Salto",
	"see_future": "Ver el Futuro (3x)", "shuffle": "Barajar", "feed_dead": "Alimenta a los Muertos",
	"clone": "Clon", "grave_robber": "Ladrón de Tumbas", "favor": "Favor", "dig_deeper": "Cava Más Hondo",
	"clairvoyance": "Clarividencia", "cat_a": "Gato Momia", "cat_b": "Vampigato", "cat_c": "Fantasmiau",
	"cat_d": "Esquelegato",
}
## Cartas ⚡: se pueden jugar fuera de turno e incluso estando muerto
const NOW := {"shuffle": true, "feed_dead": true, "clairvoyance": true}
## Cartas ⚡ añadidas por el modo Plus (el Espanto solo lo juega un muerto)
const NOW_PLUS := {"haunt": true}
const DEFAULT_CFG := {"NOPE_MS": 6500, "FAST_MS": 900, "PROMPT_MS": 40000, "GONE_MS": 6000, "CLAIR_MS": 4000, "HAND": 7}


class Card:
	extends RefCounted
	var id: String
	var type: String
	var paw: bool

	func _init(p_id: String, p_type: String, p_paw: bool) -> void:
		id = p_id
		type = p_type
		paw = p_paw


class Player:
	extends RefCounted
	var id: String
	var name: String
	var avatar: int = 0
	var bot: bool = false
	var hand: Array[Card] = []
	var alive: bool = true
	var ek: Card = null
	var connected: bool = true

	func find_type(t: String) -> Card:
		for c in hand:
			if c.type == t:
				return c
		return null

	func find_id(card_id: String) -> Card:
		for c in hand:
			if c.id == card_id:
				return c
		return null


var rnd: Callable
var _rng: RefCounted
var cfg: Dictionary
var players: Array[Player] = []
var draw: Array[Card] = []          # la última carta es la de arriba
var discard: Array[Dictionary] = [] # {card, by}
var stack: Array[Dictionary] = []   # jugadas esperando un posible Nop
var prompt: Variant = null          # decisión pendiente (Dictionary) o null
var over: Variant = null            # {winner} o null
var events: Array[Dictionary] = []
var seq: int = 0
var pid: int = 0
var mut: int = 0
var shuf: int = 0
var cur: int = 0
var turns_left: int = 1
var attacked: bool = false
var idle_since: int = 0
# --- Plus (con plus = false no se lee ni se cambia nada observable)
var plus: bool = false
var packs: Array = []
var rules: Dictionary = {}
var names: Dictionary = {}          # {tipo: nombre} de las cartas de packs (el motor no lee CardDB)
var dir: int = 1                    # sentido de juego (+1 / -1)
var tops: int = 0                   # cartas retiradas de ARRIBA del mazo desde el último cambio de `shuf`
var deck_types: Array[String] = []  # tipos presentes en esta partida (sin exploding)


## Nombre de una carta, también de packs. Las 19 cartas base salen siempre de NAMES (textos idénticos al clásico).
func _name(t: String) -> String:
	if NAMES.has(t):
		return NAMES[t]
	return str(names.get(t, NAMES_CRYPT.get(t, t)))


static func is_cat(t: String) -> bool:
	return t.begins_with("cat_")


static func shuffle_arr(a: Array, r: Callable) -> Array:
	for i in range(a.size() - 1, 0, -1):
		var j := int(floor(r.call() * (i + 1)))
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t
	return a


## opts: {players: [{id, name, avatar?, bot?}], deck_mode: "official"|"full", rng?: ZKRng, rnd?: Callable, cfg?: {}, now?: int}
func _init(opts: Dictionary) -> void:
	# "rng": objeto con next() (el motor lo mantiene vivo);  "rnd": Callable suelto;  sin nada: azar del sistema
	if opts.has("rng"):
		_rng = opts["rng"]
		rnd = _rng.next
	else:
		rnd = opts.get("rnd", func() -> float: return randf())
	cfg = DEFAULT_CFG.duplicate()
	cfg.merge(opts.get("cfg", {}), true)
	plus = bool(opts.get("plus", false))
	if plus:
		packs = (opts.get("packs", []) as Array).duplicate()
		rules = (opts.get("rules", {}) as Dictionary).duplicate()
		names = (opts.get("names", {}) as Dictionary).duplicate()
		if rules.has("hand"):
			cfg["HAND"] = clampi(int(rules["hand"]), 4, 8)   # M-04: mano inicial (solo Plus)
		elif packs.has("crypt") and not (opts.get("cfg", {}) as Dictionary).has("HAND"):
			cfg["HAND"] = 8   # Plus con La Cripta y sin mano explícita: 8 (equilibrio de duración)
	for d: Dictionary in opts["players"]:
		var p := Player.new()
		p.id = d["id"]
		p.name = d["name"]
		p.avatar = int(d.get("avatar", 0))
		p.bot = bool(d.get("bot", false))
		players.append(p)
	idle_since = int(opts.get("now", 0))
	_setup(opts.get("deck_mode", "official"))


## Filas de La Cripta de esta partida: DECK_CRYPT con `rules.crypt_copies` {tipo: [con_huella, sin_huella]} encima
## (palanca de pruebas/ajuste). Se ignoran tipos desconocidos y entradas que no sean [0-3, 0-3].
func _crypt_rows() -> Array:
	var over_rows: Variant = rules.get("crypt_copies", null)
	if not (over_rows is Dictionary):
		return DECK_CRYPT
	var out: Array = []
	for row: Array in DECK_CRYPT:
		var o: Variant = (over_rows as Dictionary).get(row[0], null)
		if o is Array and (o as Array).size() == 2 and _copies_ok(o[0]) and _copies_ok(o[1]):
			out.append([row[0], int(o[0]), int(o[1])])
		else:
			out.append(row)
	return out


static func _copies_ok(v: Variant) -> bool:
	return (v is int or (v is float and v == floorf(v))) and int(v) >= 0 and int(v) <= 3


func _setup(mode: String) -> void:
	var n := players.size()
	var next_id := 0
	var cards: Array[Card] = []
	var zombies: Array[Card] = []
	var eks: Array[Card] = []
	var rows: Array = DECK.duplicate()
	if plus and packs.has("crypt"):
		rows.append_array(_crypt_rows())
	for row: Array in rows:
		var type: String = row[0]
		var groups: Array = []
		if mode == "full" or n >= 4:
			groups = [[row[1], true], [row[2], false]]
		elif n == 2:
			groups = [[row[1], true]]
		else:
			groups = [[row[2], false]]
		for g: Array in groups:
			if int(g[0]) > 0 and not deck_types.has(type):
				deck_types.append(type)
			for _i in int(g[0]):
				next_id += 1
				var c := Card.new("c%d" % next_id, type, g[1])
				if type == "zombie":
					zombies.append(c)
				else:
					cards.append(c)
	for _i in 4:
		next_id += 1
		eks.append(Card.new("c%d" % next_id, "exploding", false))
	shuffle_arr(zombies, rnd)
	for p in players:
		if zombies.size() > 0:
			p.hand.append(zombies.pop_back())
	cards.append_array(zombies)
	shuffle_arr(cards, rnd)
	for _k in int(cfg["HAND"]):
		for p in players:
			if cards.size() > 0:
				p.hand.append(cards.pop_back())
	for _i in n - 1:
		cards.append(eks.pop_back())
	shuffle_arr(cards, rnd)
	draw = cards
	cur = int(floor(rnd.call() * n))
	emit("start", {"text": "¡Comienza la partida! Empieza " + cur_p().name + "."})


# ---------------------------------------------------------------- utilidades

func P(id: Variant) -> Player:
	if id == null:
		return null
	for p in players:
		if p.id == id:
			return p
	return null


func cur_p() -> Player:
	return players[cur]


func _where(list: Array, pred: Callable) -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in list:
		if pred.call(p):
			out.append(p)
	return out


func living() -> Array[Player]:
	return _where(players, func(p: Player) -> bool: return p.alive)


func dead() -> Array[Player]:
	return _where(players, func(p: Player) -> bool: return not p.alive)


func top() -> Variant:
	return stack[stack.size() - 1] if stack.size() > 0 else null


func top_discard() -> Variant:
	return discard[discard.size() - 1] if discard.size() > 0 else null


func idle() -> bool:
	return prompt == null and stack.is_empty() and over == null


func emit(type: String, data: Dictionary = {}, to: String = "") -> Dictionary:
	seq += 1
	var e := {"seq": seq, "type": type}
	e.merge(data)
	if plus and (type == "future" or type == "clair" or type == "inserted"):
		e["tops"] = tops
	if to != "":
		e["to"] = to
	events.append(e)
	while events.size() > 80:
		events.pop_front()
	return e


func shuffle_draw() -> void:
	shuffle_arr(draw, rnd)
	mut += 1
	shuf += 1
	tops = 0


func next_living_idx(from: int) -> int:
	var n := players.size()
	for k in range(1, n + 1):
		var i := posmod(from + k * dir, n)
		if players[i].alive:
			return i
	return from


func _dl(ids: Array, now: int, base: int = -1) -> int:
	var gone := true
	for id: String in ids:
		var p := P(id)
		if not (p != null and not p.bot and not p.connected):
			gone = false
			break
	return now + (int(cfg["GONE_MS"]) if gone else (base if base >= 0 else int(cfg["PROMPT_MS"])))


static func _none(v: Variant) -> bool:
	return v == null or (v is String and v == "")


# ---------------------------------------------------------------- validación de jugadas

## Devuelve {err} si la jugada no es válida, {need} si falta elegir objetivo, o el plan {kind, eff, cards, ...}.
func plan(player_id: String, ids: Variant, target: Variant = null, named: Variant = null) -> Dictionary:
	if over != null:
		return {"err": "La partida ya terminó."}
	var p := P(player_id)
	if p == null:
		return {"err": "Jugador desconocido."}
	if not (ids is Array) or ids.is_empty() or ids.size() > 3:
		return {"err": "Selección inválida."}
	var cards: Array[Card] = []
	for id: Variant in ids:
		var c := p.find_id(str(id))
		if c == null or cards.has(c):
			return {"err": "No tienes esa carta."}
		cards.append(c)
	var is_cur := cur_p().id == player_id
	var pr: Variant = prompt
	var dead_n := dead().size()

	if cards.size() == 1:
		var eff := cards[0].type
		if eff == "clone":
			if not p.alive or not is_cur:
				return {"err": "El Clon solo se juega en tu turno y estando vivo."}
			var td: Variant = top_discard()
			if td == null:
				return {"err": "No hay ninguna carta debajo para clonar."}
			if td.card.type == "clone":
				return {"err": "No puedes jugar un Clon sobre otro Clon."}
			eff = td.card.type
			if is_cat(eff) or eff == "exploding":
				return {"err": "Clonar esa carta sola no hace nada. Úsalo en pareja con otra carta."}
		if plus and eff == "haunt" and p.alive:
			return {"err": "Solo los muertos pueden espantar."}
		if eff == "zombie":
			if not (pr != null and pr.type == "explode" and pr.player == player_id):
				return {"err": "El Gatito Zombi se juega cuando sacas un Gatito Explosivo (o en combos)."}
			return {"kind": "zombie", "eff": eff, "cards": cards}
		if is_cat(eff):
			return {"err": "Las cartas de gato se juegan en pareja o en trío."}
		if eff == "nope":
			var t: Variant = top()
			if t == null or (pr != null and pr.type != "zombie"):
				return {"err": "No hay ninguna jugada que anular ahora."}
			if t.last == player_id:
				return {"err": "No puedes anular tu propia jugada."}
			return {"kind": "nope", "eff": eff, "cards": cards}
		if eff == "clairvoyance":
			if not (pr != null and pr.type == "zombie" and pr.player != player_id):
				return {"err": "Clarividencia se juega cuando OTRO jugador usa un Gatito Zombi."}
			if pr.watchers.has(player_id) or stack.any(func(s: Dictionary) -> bool: return s.eff == "clairvoyance" and s.by == player_id):
				return {"err": "Ya estás mirando."}
			return {"kind": "action", "eff": eff, "cards": cards}
		if pr != null:
			return {"err": "Espera a que termine la acción en curso."}
		if NOW.has(eff) or (plus and NOW_PLUS.has(eff)):
			if plus and eff == "haunt":
				if not players.any(func(o: Player) -> bool: return o.id != player_id and o.alive and o.hand.size() > 0):
					return {"err": "Nadie tiene cartas que espantar."}
				if _none(target):
					return {"need": "living", "eff": eff, "cards": cards}
				var th := P(target)
				if th == null or not th.alive or th.id == player_id or th.hand.is_empty():
					return {"err": "Elige a un jugador vivo con cartas."}
				return {"kind": "action", "eff": eff, "cards": cards, "target": target}
			if eff == "feed_dead":
				if dead_n == 0:
					return {"err": "No hay jugadores muertos."}
				if _none(target):
					return {"need": "dead", "eff": eff, "cards": cards}
				var t := P(target)
				if t == null or t.alive:
					return {"err": "Elige a un jugador muerto."}
			return {"kind": "action", "eff": eff, "cards": cards, "target": target if eff == "feed_dead" else null}
		if not is_cur or not p.alive:
			return {"err": "Solo puedes jugar esa carta en tu turno."}
		if not stack.is_empty():
			return {"err": "Espera a que se resuelva la jugada anterior."}
		if (eff == "attack_dead" or eff == "grave_robber") and dead_n == 0:
			return {"err": "No hay jugadores muertos: no puedes jugar esta carta."}
		if plus and eff == "soul_swap":
			if not players.any(func(o: Player) -> bool: return not o.alive and o.hand.size() > 0):
				return {"err": "Ningún jugador muerto tiene cartas."}
			if _none(target):
				return {"need": "dead_hand", "eff": eff, "cards": cards}
			var ts := P(target)
			if ts == null or ts.alive or ts.hand.is_empty():
				return {"err": "Elige a un jugador muerto con cartas."}
			return {"kind": "action", "eff": eff, "cards": cards, "target": target}
		if plus and (eff == "targeted_attack" or eff == "crow_eye"):
			var any_hand: bool = eff == "crow_eye"
			if not players.any(func(o: Player) -> bool: return o.id != player_id and (o.alive or any_hand) and (o.hand.size() > 0 or not any_hand)):
				return {"err": "Nadie tiene cartas que mirar." if any_hand else "No hay ningún rival vivo al que atacar."}
			if _none(target):
				return {"need": "any_hand" if any_hand else "living_any", "eff": eff, "cards": cards}
			var t := P(target)
			if t == null or t.id == player_id or (any_hand and t.hand.is_empty()) or (not any_hand and not t.alive):
				return {"err": "Elige a otro jugador con cartas." if any_hand else "Elige a un jugador vivo que no seas tú."}
			return {"kind": "action", "eff": eff, "cards": cards, "target": target}
		if eff == "favor":
			if not players.any(func(o: Player) -> bool: return o.id != player_id and o.alive and o.hand.size() > 0):
				return {"err": "Nadie tiene cartas para darte."}
			if _none(target):
				return {"need": "living", "eff": eff, "cards": cards}
			var t := P(target)
			if t == null or not t.alive or t.id == player_id or t.hand.is_empty():
				return {"err": "Elige a un jugador vivo con cartas."}
			return {"kind": "action", "eff": eff, "cards": cards, "target": target}
		return {"kind": "action", "eff": eff, "cards": cards, "target": null}

	# Combos especiales: dos o tres iguales (el Clon copia a la carta que acompaña)
	var real: Array[Card] = []
	for c in cards:
		if c.type != "clone":
			real.append(c)
	if real.is_empty():
		return {"err": "Un combo necesita al menos una carta que no sea Clon."}
	for c in real:
		if c.type != real[0].type:
			return {"err": "Las cartas del combo deben tener el mismo título."}
	if not is_cur or not p.alive:
		return {"err": "Los combos solo se juegan en tu turno."}
	if pr != null:
		return {"err": "Espera a que termine la acción en curso."}
	if not stack.is_empty():
		return {"err": "Espera a que se resuelva la jugada anterior."}
	if not players.any(func(o: Player) -> bool: return o.id != player_id and o.alive and o.hand.size() > 0):
		return {"err": "Ningún jugador vivo tiene cartas para robar."}
	var combo := "combo2" if cards.size() == 2 else "combo3"
	if _none(target):
		return {"need": "living", "eff": combo, "cards": cards, "of": real[0].type}
	var tp := P(target)
	if tp == null or not tp.alive or tp.id == player_id or tp.hand.is_empty():
		return {"err": "Elige a un jugador vivo con cartas."}
	if combo == "combo3":
		if _none(named):
			return {"need": "named", "eff": combo, "cards": cards, "target": target, "of": real[0].type}
		if (not deck_types.has(named) if plus else not NAMES.has(named)) or named == "exploding":
			return {"err": "Carta inválida."}
	return {"kind": "action", "eff": combo, "cards": cards, "target": target, "named": named if combo == "combo3" else null, "of": real[0].type}


# ---------------------------------------------------------------- entrada de acciones

## Aplica la acción de un jugador. Devuelve "" si se aceptó o el mensaje de error.
func act(player_id: String, a: Variant, now: int) -> String:
	if over != null:
		return "La partida ya terminó."
	var p := P(player_id)
	if p == null or not (a is Dictionary):
		return "Acción inválida."
	var err := ""
	match a.get("a", ""):
		"play": err = _do_play(p, a, now)
		"draw": err = _do_draw(p, now)
		"pass": err = _do_pass(p, now)
		"die": err = _do_die(p, now)
		"revive": err = _do_revive(p, a.get("target"), now)
		"insert": err = _do_insert(p, a.get("positions"), now)
		"reorder": err = _do_reorder(p, a.get("order"), now)
		"bury": err = _do_bury(p, a.get("pos"), now)
		"give": err = _do_give(p, a.get("card"), now)
		"dig": err = _do_dig(p, bool(a.get("keep", false)), now)
		_: err = "Acción desconocida."
	if err == "":
		idle_since = now
	return err


func _do_play(p: Player, a: Dictionary, now: int) -> String:
	var pl := plan(p.id, a.get("cards"), a.get("target"), a.get("named"))
	if pl.has("err"):
		return pl["err"]
	if pl.has("need"):
		return "Falta elegir un objetivo."
	var cards: Array[Card] = pl["cards"]
	for c in cards:
		p.hand.erase(c)
		discard.append({"card": c, "by": p.id})
	var eff: String = pl["eff"]
	var card_name: String = ("Clon (como " + _name(eff) + ")") if cards.size() == 1 and cards[0].type == "clone" else _name(cards[0].type)
	if pl["kind"] == "zombie":
		var pr: Dictionary = prompt
		var dead_p := dead()
		var clair := players.any(func(o: Player) -> bool: return o.id != p.id and o.find_type("clairvoyance") != null)
		prompt = {
			"type": "zombie", "player": p.id, "eks": [pr.card], "needRevive": dead_p.size() > 0, "revived": null,
			"watchers": [], "pendingPos": null, "minUntil": (now + int(cfg["CLAIR_MS"])) if clair else now,
			"start": now, "deadline": _dl([p.id], now, int(cfg["PROMPT_MS"]) + 15000),
		}
		emit("zombie", {"player": p.id, "text": p.name + " juega " + card_name + " y se salva de explotar."})
		if dead_p.size() == 1:
			_do_revive(p, dead_p[0].id, now)
		return ""
	if pl["kind"] == "nope":
		var t: Dictionary = top()
		t.nopes += 1
		t.last = p.id
		var yup: bool = t.nopes % 2 == 0
		emit("nope", {"player": p.id, "yup": yup, "text": p.name + (" responde con otro Nop: ¡la jugada vuelve a valer!" if yup else " dice ¡NOP! a " + P(t.by).name + ".")})
		_open_window(now)
		return ""
	pid += 1
	var s := {
		"id": pid, "eff": eff, "by": p.id, "last": p.id, "target": pl.get("target"), "named": pl.get("named"),
		"of": pl.get("of"), "n": cards.size(), "nopes": 0, "passed": {}, "deadline": 0, "total": 0,
	}
	if _none(s.target):
		s.target = null
	if _none(s.named):
		s.named = null
	var tn: String = P(s.target).name if s.target != null else ""
	var text: String
	if eff == "combo2":
		text = p.name + " juega una pareja de " + _name(s.of) + " contra " + tn + "."
	elif eff == "combo3":
		text = p.name + " juega un trío de " + _name(s.of) + " contra " + tn + " y pide: " + _name(s.named) + "."
	elif eff == "favor":
		text = p.name + " pide un Favor a " + tn + "."
	elif eff == "feed_dead":
		text = p.name + " juega Alimenta a los Muertos para " + tn + "."
	elif eff == "targeted_attack":
		text = p.name + " juega " + card_name + " contra " + tn + "."
	elif eff == "crow_eye":
		text = p.name + " mira la mano de " + tn + " con " + card_name + "."
	elif eff == "soul_swap":
		text = p.name + " juega " + card_name + " y quiere la mano de " + tn + "."
	elif eff == "haunt":
		text = p.name + " juega " + card_name + " desde el más allá contra " + tn + "."
	else:
		text = p.name + " juega " + card_name + "."
	emit("play", {"player": p.id, "eff": eff, "text": text})
	stack.append(s)
	_open_window(now)
	return ""


## Jugadores que podrían responder con un Nop a la jugada `s`.
func eligible(s: Dictionary) -> Array[Player]:
	return _where(players, func(o: Player) -> bool: return o.id != s.last and (o.bot or o.connected) and o.find_type("nope") != null)


func _open_window(now: int) -> void:
	var s: Variant = top()
	if s == null:
		return
	s.passed = {}
	s.total = int(cfg["NOPE_MS"]) if eligible(s).size() > 0 else int(cfg["FAST_MS"])
	s.deadline = now + s.total


func _do_pass(p: Player, now: int) -> String:
	var s: Variant = top()
	if s == null or (prompt != null and prompt.type != "zombie"):
		return "No hay nada que pasar."
	s.passed[p.id] = 1
	if eligible(s).all(func(o: Player) -> bool: return s.passed.has(o.id)):
		_resolve_top(now)
	return ""


func _resolve_top(now: int) -> void:
	if stack.is_empty():
		return
	var s: Dictionary = stack.pop_back()
	if s.nopes % 2 == 1:
		emit("cancel", {"eff": s.eff, "text": "La jugada de " + P(s.by).name + " fue anulada."})
	else:
		_apply(s, now)
	_settle(now)


func _settle(now: int) -> void:
	if over != null:
		return
	if prompt != null and prompt.type != "zombie":
		return
	if not stack.is_empty():
		_open_window(now)


# ---------------------------------------------------------------- efectos

func _apply(s: Dictionary, now: int) -> void:
	var p := P(s.by)
	var is_cur := cur_p().id == p.id
	match s.eff:
		"attack", "attack_dead":
			if not is_cur:
				return
			var add: int = 2 if s.eff == "attack" else 3 * dead().size()
			if add == 0:
				emit("info", {"text": "Ya no hay muertos: el Ataque de los Muertos no tiene efecto."})
				return
			var n: int = (turns_left if attacked else 0) + add
			_advance(n, true, now)
			emit("attack", {"player": p.id, "target": cur_p().id, "n": n, "text": cur_p().name + " debe jugar " + str(n) + " turnos seguidos."})
		"skip":
			if is_cur:
				emit("info", {"text": p.name + " termina su turno sin robar."})
				_end_turn(now)
		"super_skip":
			if is_cur:
				emit("info", {"text": p.name + " termina TODOS sus turnos sin robar."})
				_advance(1, false, now)
		"see_future":
			var cards: Array = []
			for i in range(draw.size() - 1, maxi(-1, draw.size() - 4), -1):
				cards.append(draw[i].type)
			emit("future", {"cards": cards, "mut": mut, "len": draw.size(), "shuf": shuf}, p.id)
		"shuffle":
			shuffle_draw()
			emit("shuffle", {"text": "El mazo fue barajado."})
		"feed_dead":
			var t := P(s.target)
			if t == null or t.alive:
				return
			var givers: Array[Player] = _where(living(), func(o: Player) -> bool: return o.id != p.id and o.hand.size() > 0)
			if givers.is_empty():
				return
			_start_give("feed", t.id, givers, now)
		"favor":
			var t := P(s.target)
			if t == null or not t.alive or t.hand.is_empty():
				return
			_start_give("favor", p.id, [t], now)
		"grave_robber":
			var givers: Array[Player] = _where(dead(), func(o: Player) -> bool: return o.hand.size() > 0)
			if givers.is_empty():
				emit("info", {"text": "Los muertos no tienen cartas que robar."})
				return
			_start_give("rob", null, givers, now)
		"dig_deeper":
			if not is_cur:
				return
			if draw.size() <= 1:
				emit("info", {"text": "Solo queda 1 carta en el mazo: Cava Más Hondo no tiene efecto."})
				return
			var card: Card = draw.pop_back()
			tops += 1
			mut += 1
			prompt = {"type": "dig", "player": p.id, "card": card, "start": now, "deadline": _dl([p.id], now)}
		"combo2":
			var t := P(s.target)
			if t == null or not t.alive or t.hand.is_empty():
				return
			var c: Card = t.hand.pop_at(int(floor(rnd.call() * t.hand.size())))
			p.hand.append(c)
			emit("steal", {"player": p.id, "target": t.id, "text": p.name + " le roba una carta al azar a " + t.name + "."})
			emit("got", {"card": c.type, "text": "Le robaste " + _name(c.type) + " a " + t.name + "."}, p.id)
			emit("lost", {"card": c.type, "text": p.name + " te robó " + _name(c.type) + "."}, t.id)
		"combo3":
			var t := P(s.target)
			if t == null or not t.alive:
				return
			var c := t.find_type(s.named)
			if c == null:
				emit("info", {"text": t.name + " no tiene " + _name(s.named) + ". " + p.name + " no consigue nada."})
				return
			t.hand.erase(c)
			p.hand.append(c)
			emit("steal", {"player": p.id, "target": t.id, "card": c.type, "text": p.name + " le quita " + _name(c.type) + " a " + t.name + "."})
		"clairvoyance":
			if prompt != null and prompt.type == "zombie" and not prompt.watchers.has(p.id):
				prompt.watchers.append(p.id)
		"targeted_attack":
			if not plus or not is_cur:
				return
			var t := P(s.target)
			var idx := players.find(t)
			if t == null or not t.alive:
				idx = next_living_idx(idx if idx >= 0 else cur)
				if players[idx].id == p.id:
					idx = next_living_idx(idx)   # nadie se ataca a sí mismo
			var n: int = (turns_left if attacked else 0) + 2
			cur = idx
			turns_left = n
			attacked = true
			idle_since = now
			emit("turn", {"player": cur_p().id})
			emit("attack", {"player": p.id, "target": cur_p().id, "n": n, "text": cur_p().name + " debe jugar " + str(n) + " turnos seguidos."})
		"reverse":
			if not plus or not is_cur:
				return
			dir = -dir
			emit("reverse", {"dir": dir, "text": "¡Marcha atrás! " + p.name + " invierte el sentido de juego."})
			_end_turn(now)
		"draw_bottom":
			if not plus or not is_cur or draw.is_empty():
				return
			var c: Card = draw.pop_front()
			mut += 1
			emit("draw", {"player": p.id, "bottom": true})
			_receive(p, c, now)
		"crow_eye":
			if not plus:
				return
			var t := P(s.target)
			if t == null or t.id == p.id:
				return
			var kinds: Array = []
			for c in t.hand:
				kinds.append(c.type)
			emit("info", {"text": p.name + " mira la mano de " + t.name + "."})
			emit("peek", {"target": t.id, "cards": kinds, "text": "Ves la mano de " + t.name + "."}, p.id)
		"apocalypse":
			if not plus:
				return
			var eks: Array[Card] = []
			var rest: Array[Card] = []
			for c in draw:
				if c.type == "exploding":
					eks.append(c)
				else:
					rest.append(c)
			shuffle_arr(rest, rnd)
			shuffle_arr(eks, rnd)
			draw.clear()
			draw.append_array(rest)
			draw.append_array(eks)
			mut += 1
			shuf += 1
			tops = 0
			emit("apocalypse", {"n": eks.size(), "text": "Los " + str(eks.size()) + " explosivos están arriba del mazo."})
			if is_cur:
				_advance(1, false, now)
		"alter_future":
			if not plus or not is_cur:
				return
			if draw.is_empty():
				emit("info", {"text": "El mazo está vacío: Alterar el Futuro no tiene efecto."})
				return
			var seen: Array[Card] = []
			for i in range(draw.size() - 1, maxi(-1, draw.size() - 4), -1):
				seen.append(draw[i])
			prompt = {"type": "alter", "player": p.id, "cards": seen, "start": now, "deadline": _dl([p.id], now)}
		"bury":
			if not plus or not is_cur:
				return
			if draw.is_empty():
				emit("info", {"text": "El mazo está vacío: Entierro no tiene efecto."})
				return
			var buried: Card = draw.pop_back()
			mut += 1
			tops += 1
			prompt = {"type": "bury", "player": p.id, "card": buried, "start": now, "deadline": _dl([p.id], now)}
		"soul_swap":
			if not plus:
				return
			var t := P(s.target)
			if t == null or t.alive or t.hand.is_empty():
				return
			var mine: Array[Card] = p.hand
			p.hand = t.hand
			t.hand = mine
			emit("swap", {"player": p.id, "target": t.id, "text": p.name + " intercambia su mano con la de " + t.name + "."})
			emit("got", {"n": p.hand.size(), "text": "Recibiste " + str(p.hand.size()) + " cartas de " + t.name + "."}, p.id)
			emit("got", {"n": t.hand.size(), "text": "Recibiste " + str(t.hand.size()) + " cartas de " + p.name + "."}, t.id)
		"haunt":
			if not plus:
				return
			var t := P(s.target)
			if t == null or not t.alive or t.hand.is_empty():
				return
			var c: Card = t.hand.pop_at(int(floor(rnd.call() * t.hand.size())))
			discard.append({"card": c, "by": t.id})
			emit("haunt", {"player": p.id, "target": t.id, "card": c.type, "text": p.name + " espanta a " + t.name + ": descarta " + _name(c.type) + "."})



func _start_give(reason: String, to: Variant, givers: Array, now: int) -> void:
	var waiting := {}
	var ids: Array = []
	for g: Player in givers:
		waiting[g.id] = 1
		ids.append(g.id)
	prompt = {"type": "give", "reason": reason, "to": to, "waiting": waiting, "pool": [], "start": now, "deadline": _dl(ids, now)}


func _do_give(p: Player, card_id: Variant, now: int) -> String:
	var pr: Variant = prompt
	if pr == null or pr.type != "give" or not pr.waiting.has(p.id):
		return "No tienes que dar ninguna carta."
	var c := p.find_id(str(card_id))
	if c == null:
		return "No tienes esa carta."
	p.hand.erase(c)
	pr.waiting.erase(p.id)
	if pr.reason == "rob":
		pr.pool.append(c)
		emit("info", {"text": p.name + " entrega una carta al mazo."})
	else:
		var t := P(pr.to)
		t.hand.append(c)
		emit("gave", {"player": p.id, "target": t.id, "text": p.name + " le da una carta a " + t.name + "."})
		emit("got", {"card": c.type, "text": p.name + " te dio " + _name(c.type) + "."}, t.id)
	if pr.waiting.is_empty():
		prompt = null
		if pr.reason == "rob":
			for pc: Card in pr.pool:
				draw.append(pc)
			shuffle_draw()
			emit("shuffle", {"text": "Las cartas de los muertos se barajan en el mazo."})
		_settle(now)
	return ""


# ---------------------------------------------------------------- robar / explotar / zombi

func _do_draw(p: Player, now: int) -> String:
	if cur_p().id != p.id or not p.alive:
		return "No es tu turno."
	if not idle():
		return "Espera a que termine la acción en curso."
	var c: Card = draw.pop_back()
	tops += 1
	mut += 1
	emit("draw", {"player": p.id})
	_receive(p, c, now)
	return ""


func _receive(p: Player, c: Card, now: int) -> void:
	if c.type == "exploding":
		var td: Variant = top_discard()
		var can_save: bool = p.find_type("zombie") != null or (p.find_type("clone") != null and td != null and td.card.type == "zombie")
		emit("boom", {"player": p.id, "text": "¡" + p.name + " sacó un GATITO EXPLOSIVO!"})
		if not can_save:
			_die(p, c, now)
			return
		prompt = {"type": "explode", "player": p.id, "card": c, "start": now, "deadline": _dl([p.id], now, 25000)}
		return
	p.hand.append(c)
	emit("got", {"card": c.type, "drawn": true, "text": "Robaste: " + _name(c.type) + "."}, p.id)
	_end_turn(now)


func _do_die(p: Player, now: int) -> String:
	var pr: Variant = prompt
	if pr == null or pr.type != "explode" or pr.player != p.id:
		return "No puedes hacer eso ahora."
	_die(p, pr.card, now)
	return ""


func _die(p: Player, card: Card, now: int) -> void:
	prompt = null
	p.alive = false
	p.ek = card
	emit("died", {"player": p.id, "text": "💥 " + p.name + " explotó y está MUERTO (por ahora)."})
	var alive := living()
	if alive.size() <= 1:
		over = {"winner": alive[0].id if alive.size() > 0 else null}
		stack.clear()
		emit("over", {"winner": over.winner, "text": "🏆 " + (alive[0].name if alive.size() > 0 else "Nadie") + " es el último gatito con vida. ¡Gana la partida!"})
		return
	_advance(1, false, now)


func _do_revive(p: Player, target: Variant, _now: int) -> String:
	var pr: Variant = prompt
	if pr == null or pr.type != "zombie" or pr.player != p.id:
		return "No puedes hacer eso ahora."
	if not pr.needRevive or pr.revived != null:
		return "No hay nadie a quien revivir."
	var t := P(target)
	if t == null or t.alive:
		return "Elige a un jugador muerto."
	t.alive = true
	pr.eks.append(t.ek)
	t.ek = null
	pr.revived = t.id
	emit("revived", {"player": p.id, "target": t.id, "text": "🧟 " + p.name + " revive a " + t.name + ". ¡Vuelve al juego!"})
	return ""


func _do_insert(p: Player, positions: Variant, now: int) -> String:
	var pr: Variant = prompt
	if pr == null or pr.type != "zombie" or pr.player != p.id:
		return "No puedes hacer eso ahora."
	if pr.needRevive and pr.revived == null:
		return "Primero elige a quién revivir."
	if not (positions is Array) or positions.size() != pr.eks.size():
		return "Posiciones inválidas."
	var pos: Array[int] = []
	for i in positions.size():
		var v: Variant = positions[i]
		if not (v is int or v is float) or float(v) != floor(float(v)) or v < 0 or v > draw.size() + i:
			return "Posición fuera del mazo."
		pos.append(int(v))
	pr.pendingPos = pos
	if stack.is_empty() and now >= pr.minUntil:
		_finish_insert(now)
	return ""


func _finish_insert(now: int) -> void:
	var pr: Dictionary = prompt
	var p := P(pr.player)
	for i in pr.pendingPos.size():
		draw.insert(maxi(0, draw.size() - pr.pendingPos[i]), pr.eks[i])
	mut += 1
	shuf += 1
	tops = 0
	for w: String in pr.watchers:
		emit("clair", {"positions": pr.pendingPos.duplicate(), "len": draw.size(), "shuf": shuf, "text": "Clarividencia: viste dónde quedó cada Gatito Explosivo."}, w)
	prompt = null
	var n: int = pr.eks.size()
	emit("inserted", {"player": p.id, "n": n, "len": draw.size(), "shuf": shuf, "text": p.name + " esconde " + (("los " + str(n) + " Gatitos Explosivos") if n > 1 else "el Gatito Explosivo") + " en el mazo."})
	_end_turn(now)
	_settle(now)


## Alterar el Futuro: `order` es una permutación de los índices de prompt.cards; order[0] será la próxima carta.
func _do_reorder(p: Player, order: Variant, now: int) -> String:
	var pr: Variant = prompt
	if pr == null or pr.type != "alter" or pr.player != p.id:
		return "No puedes hacer eso ahora."
	var cards: Array = pr.cards
	if not (order is Array) or order.size() != cards.size():
		return "Orden inválido."
	var idxs: Array[int] = []
	for v: Variant in order:
		if not (v is int or v is float) or float(v) != floor(float(v)) or v < 0 or v >= cards.size() or idxs.has(int(v)):
			return "Orden inválido."
		idxs.append(int(v))
	var kinds: Array = []
	for k in idxs.size():
		draw[draw.size() - 1 - k] = cards[idxs[k]]
		kinds.append(cards[idxs[k]].type)
	mut += 1
	shuf += 1
	tops = 0
	prompt = null
	emit("info", {"text": p.name + " reordena el futuro."})
	emit("future", {"cards": kinds, "mut": mut, "len": draw.size(), "shuf": shuf}, p.id)
	_settle(now)
	return ""


## Entierro: `pos` 0 = arriba del mazo … draw.size() = fondo.
func _do_bury(p: Player, pos: Variant, now: int) -> String:
	var pr: Variant = prompt
	if pr == null or pr.type != "bury" or pr.player != p.id:
		return "No puedes hacer eso ahora."
	if not (pos is int or pos is float) or float(pos) != floor(float(pos)) or pos < 0 or pos > draw.size():
		return "Posición fuera del mazo."
	var at: int = int(pos)
	draw.insert(draw.size() - at, pr.card)
	mut += 1
	shuf += 1
	tops = 0
	prompt = null
	emit("info", {"text": p.name + " entierra una carta en el mazo."})
	emit("buried", {"pos": at, "len": draw.size(), "shuf": shuf, "text": "Enterraste " + _name(pr.card.type) + " en la posición " + str(at + 1) + " del mazo."}, p.id)
	_end_turn(now)
	_settle(now)
	return ""


func _do_dig(p: Player, keep: bool, now: int) -> String:
	var pr: Variant = prompt
	if pr == null or pr.type != "dig" or pr.player != p.id:
		return "No puedes hacer eso ahora."
	prompt = null
	if keep:
		emit("info", {"text": p.name + " se queda con la primera carta."})
		_receive(p, pr.card, now)
	else:
		var second: Card = draw.pop_back()
		draw.append(pr.card)
		mut += 1
		shuf += 1
		tops = 0
		emit("info", {"text": p.name + " no quiso la primera carta… y roba la siguiente."})
		_receive(p, second, now)
	_settle(now)
	return ""


func _end_turn(now: int) -> void:
	turns_left -= 1
	if turns_left <= 0:
		_advance(1, false, now)
	else:
		idle_since = now


func _advance(n: int, was_attacked: bool, now: int) -> void:
	cur = next_living_idx(cur)
	turns_left = n
	attacked = was_attacked
	idle_since = now
	emit("turn", {"player": cur_p().id})


# ---------------------------------------------------------------- tiempo: plazos y acciones automáticas

func set_connected(player_id: String, on: bool, now: int) -> void:
	var p := P(player_id)
	if p == null:
		return
	p.connected = on
	var pr: Variant = prompt
	if not on and pr != null:
		var mine: bool = pr.get("player") == player_id or (pr.has("waiting") and pr.waiting.has(player_id))
		if mine:
			pr.deadline = mini(pr.deadline, now + int(cfg["GONE_MS"]))
	if not on:
		idle_since = maxi(idle_since, now)


## Próximo instante en que `tick` tendrá algo que hacer, o -1 si no hay nada pendiente.
func next_deadline() -> int:
	if over != null:
		return -1
	var pr: Variant = prompt
	var cands: Array[int] = []
	if not stack.is_empty() and (pr == null or pr.type == "zombie"):
		cands.append(top().deadline)
	if pr != null:
		cands.append(pr.deadline)
		if pr.type == "zombie" and pr.pendingPos != null:
			cands.append(pr.minUntil)
	var c := cur_p()
	if idle() and not c.bot and not c.connected:
		cands.append(idle_since + int(cfg["GONE_MS"]))
	return cands.min() if cands.size() > 0 else -1


func tick(now: int) -> void:
	var guard := 0
	while guard < 30 and over == null:
		guard += 1
		var pr: Variant = prompt
		if pr != null and pr.type == "zombie" and pr.pendingPos != null and stack.is_empty() and now >= pr.minUntil:
			_finish_insert(now)
			continue
		if not stack.is_empty() and (pr == null or pr.type == "zombie") and now >= top().deadline:
			_resolve_top(now)
			continue
		if pr != null and now >= pr.deadline:
			_auto_prompt(now)
			continue
		var c := cur_p()
		if idle() and not c.bot and not c.connected and now >= idle_since + int(cfg["GONE_MS"]):
			act(c.id, {"a": "draw"}, now)
			continue
		break


func _pick(arr: Array) -> Variant:
	return arr[int(floor(rnd.call() * arr.size()))]


func _auto_prompt(now: int) -> void:
	var pr: Dictionary = prompt
	match pr.type:
		"explode":
			var p := P(pr.player)
			var z := p.find_type("zombie")
			if z == null:
				z = p.find_type("clone")
			if z == null or act(p.id, {"a": "play", "cards": [z.id]}, now) != "":
				_die(p, pr.card, now)
		"zombie":
			var p := P(pr.player)
			if pr.needRevive and pr.revived == null:
				_do_revive(p, _pick(dead()).id, now)
			if pr.pendingPos == null:
				var pos: Array = []
				for i in pr.eks.size():
					pos.append(int(floor(rnd.call() * (draw.size() + i + 1))))
				_do_insert(p, pos, now)
			if prompt is Dictionary and is_same(prompt, pr):
				stack.clear()
				pr.minUntil = now
				_finish_insert(now)
		"give":
			for id: String in pr.waiting.keys():
				var p := P(id)
				_do_give(p, _pick(p.hand).id, now)
		"dig":
			_do_dig(P(pr.player), true, now)
		"alter":
			var ident: Array = []
			for i in pr.cards.size():
				ident.append(i)
			_do_reorder(P(pr.player), ident, now)
		"bury":
			_do_bury(P(pr.player), int(floor(rnd.call() * (draw.size() + 1))), now)


## Huella barata del estado: si cambia, hay algo nuevo que mostrar a los jugadores.
func signature() -> String:
	var s := "%d|%d|%d|%d|%d|%d|%s" % [seq, cur, turns_left, draw.size(), discard.size(), stack.size(), "o" if over != null else ""]
	var t: Variant = top()
	if t != null:
		s += "|%d/%d/%d" % [t.id, t.nopes, t.passed.size()]
	if prompt != null:
		s += "|" + prompt.type + str(prompt.get("revived")) + str(prompt.get("pendingPos") != null)
		if prompt.has("waiting"):
			s += str(prompt.waiting.size())
		if prompt.has("watchers"):
			s += str(prompt.watchers.size())
	for p in players:
		s += "1" if p.connected else "0"
	if plus:
		s += "|d%d" % dir
	return s


# ---------------------------------------------------------------- vista por jugador (oculta la información secreta)

func view(player_id: String, now: int) -> Dictionary:
	var me := P(player_id)
	var pr: Variant = prompt
	var t: Variant = top()
	var v := {
		"you": player_id,
		"players": players.map(func(p: Player) -> Dictionary: return {"id": p.id, "name": p.name, "avatar": p.avatar, "bot": p.bot, "alive": p.alive, "connected": p.connected, "count": p.hand.size()}),
		"hand": me.hand.map(func(c: Card) -> Dictionary: return {"id": c.id, "type": c.type, "paw": c.paw}) if me != null else [],
		"playable": {},
		"draw": draw.size(), "discardN": discard.size(),
		"discard": discard.slice(maxi(0, discard.size() - 5)).map(func(d: Dictionary) -> Dictionary: return {"id": d.card.id, "type": d.card.type, "by": d.by}),
		"cur": cur_p().id, "turnsLeft": turns_left, "attacked": attacked,
		"deadN": dead().size(),
		"stack": stack.map(func(s: Dictionary) -> Dictionary: return {"id": s.id, "eff": s.eff, "of": s.of, "by": s.by, "target": s.target, "named": s.named, "nopes": s.nopes, "last": s.last}),
		"win": null, "prompt": null, "over": over,
		"events": events.filter(func(e: Dictionary) -> bool: return not e.has("to") or e.to == player_id),
	}
	if plus:
		v["plus"] = true
		v["packs"] = packs.duplicate()
		v["dir"] = dir
		v["deckTypes"] = deck_types.duplicate()
		v["tops"] = tops
		v["shuf"] = shuf
		v["rules"] = rules.duplicate()
		v["discard"] = discard.slice(maxi(0, discard.size() - 20)).map(func(d: Dictionary) -> Dictionary: return {"id": d.card.id, "type": d.card.type, "by": d.by})
	if me != null:
		for c in me.hand:
			var pl := plan(player_id, [c.id])
			if not pl.has("err"):
				v.playable[c.id] = pl.get("need", 1)
	if t != null and (pr == null or pr.type == "zombie"):
		v.win = {
			"remain": maxi(0, t.deadline - now), "total": t.total,
			"canNope": me != null and t.last != player_id and me.find_type("nope") != null,
			"passed": t.passed.has(player_id),
		}
	if pr != null:
		var o := {"type": pr.type, "remain": maxi(0, pr.deadline - now), "total": pr.deadline - pr.start}
		match pr.type:
			"explode":
				o.player = pr.player
				o.mine = pr.player == player_id
			"zombie":
				o.player = pr.player
				o.mine = pr.player == player_id
				o.needRevive = pr.needRevive
				o.revived = pr.revived
				o.eks = pr.eks.size()
				o.waiting = pr.pendingPos != null
				o.watching = pr.watchers.has(player_id)
			"give":
				o.reason = pr.reason
				o.to = pr.to
				o.waiting = pr.waiting.keys()
				o.mine = pr.waiting.has(player_id)
			"dig":
				o.player = pr.player
				o.mine = pr.player == player_id
				o.card = pr.card.type if o.mine else null
			"alter":
				o.player = pr.player
				o.mine = pr.player == player_id
				if o.mine:
					o.cards = pr.cards.map(func(c: Card) -> String: return c.type)
			"bury":
				o.player = pr.player
				o.mine = pr.player == player_id
				if o.mine:
					o.card = pr.card.type
		v.prompt = o
	return v
