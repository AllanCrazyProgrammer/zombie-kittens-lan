class_name ZKBots
extends RefCounted
## Jugadores controlados por la IA. Juegan solo con su mano y lo que han visto (no hacen trampa).
##   FÁCIL:   juega casi al azar.
##   NORMAL:  reacciona al riesgo y usa Ver el Futuro.
##   DIFÍCIL: recuerda el mazo, ataca, roba Gatitos Zombi y deja el explosivo arriba.
## Port de la IA de web/www/room.js.

const VALUE := {"zombie": 10, "nope": 7, "attack": 6, "attack_dead": 6, "super_skip": 6, "skip": 5, "see_future": 4, "shuffle": 4, "dig_deeper": 4, "clone": 4, "favor": 3, "clairvoyance": 2, "feed_dead": 2, "grave_robber": 2,
	"apocalypse": 6, "targeted_attack": 6, "bury": 5, "alter_future": 5, "draw_bottom": 5, "soul_swap": 4, "reverse": 4, "crow_eye": 3, "haunt": 3, "rotten": 6}
const EASY_PLAYS := ["attack", "skip", "super_skip", "see_future", "shuffle", "dig_deeper", "favor", "attack_dead", "grave_robber"]
## Cartas de La Cripta que el bot fácil añade a su lista (solo Plus)
const EASY_PLAYS_PLUS := ["targeted_attack", "reverse", "draw_bottom", "crow_eye", "apocalypse", "alter_future", "bury", "soul_swap"]

## Rasgos de personalidad (IA-03, solo Plus; el bot fácil los ignora)
const TRAIT_AGGRESSIVE := "aggressive"
const TRAIT_CAUTIOUS := "cautious"
const TRAIT_VENGEFUL := "vengeful"
## Nombres visibles para la interfaz
const TRAIT_LABELS := {"aggressive": "Agresivo", "cautious": "Prudente", "vengeful": "Vengativo"}
## Rasgo fijo de cada bot según su nombre
const TRAIT_BY_NAME := {"Bigotes": "aggressive", "Garritas": "cautious", "Pelusa": "vengeful", "Don Miau": "aggressive", "Ronroneo": "cautious", "Michi": "vengeful"}
## Cartas que perjudican a un jugador concreto (el objetivo es el perjudicado)
const HARM_EFFS := ["favor", "combo2", "combo3", "targeted_attack", "haunt", "soul_swap"]

var game: ZKGame
var levels: Dictionary          # id del jugador -> "easy" | "normal" | "hard"
var rnd: Callable
var _mem := {}                  # id -> {at: {profundidad: tipo}, len, shuf}
var _pending_ins := {}          # id -> posiciones elegidas al esconder explosivos
var _seq := 0
var plus := false               # Plus: heurísticas de las cartas de La Cripta y memoria del mazo con `tops`
# --- solo Plus
var _peek := {}                 # id del bot -> {id del rival: {cards: [tipos que sabe que tiene], scan: índice del descarte}}
var _rival_peek := {}           # un rival acaba de mirar el futuro: {by, draws}
var _hid_bottom := {}           # id -> valor de `shuf` en que escondió un explosivo al fondo del mazo
var _bury_card := {}            # id -> tipo de la carta que ve en su decisión de Entierro
var traits := {}                # id del bot -> rasgo ("aggressive" | "cautious" | "vengeful" | ""), solo Plus
var _grudge := {}               # id del bot vengativo -> id del último jugador que le perjudicó
var _grudge_seen := {}          # claves de jugadas de la pila ya anotadas


func _init(p_game: ZKGame, p_levels: Dictionary, p_rnd: Callable, p_plus: bool = false) -> void:
	game = p_game
	levels = p_levels
	rnd = p_rnd
	plus = p_plus


## Rasgo fijo para el nombre de un bot ("" si no tiene).
static func trait_for_name(bot_name: String) -> String:
	return TRAIT_BY_NAME.get(bot_name, "")


## Asigna los rasgos (id -> rasgo). Solo tienen efecto con plus = true y en normal o difícil.
func set_traits(t: Dictionary) -> void:
	traits = t.duplicate()


## Rasgo efectivo del bot: "" si no es Plus, si es fácil o si no tiene.
func _tr(id: String) -> String:
	if not plus or levels.get(id, "normal") == "easy":
		return ""
	return traits.get(id, "")


## Factor de los umbrales de riesgo: agresivo +20 %, prudente -20 %.
func _risk_f(id: String) -> float:
	var t := _tr(id)
	return 1.2 if t == TRAIT_AGGRESSIVE else (0.8 if t == TRAIT_CAUTIOUS else 1.0)


## Vengativo: si el último que le perjudicó es un objetivo válido (está en `cands`), va contra él; si no, `default`.
func _vt(id: String, cands: Array, default: String) -> String:
	if _tr(id) != TRAIT_VENGEFUL:
		return default
	var gr: String = _grudge.get(id, "")
	if gr == "":
		return default
	for o: ZKGame.Player in cands:
		if o.id == gr:
			return gr
	return default


static func val(t: String) -> int:
	return VALUE.get(t, 1)


## Profundidad final (desde arriba) de cada explosivo tras insertarlos uno tras otro.
static func _depths(pos: Array) -> Dictionary:
	var at := {}
	if pos.size() > 1:
		at[int(pos[0]) + (1 if int(pos[1]) <= int(pos[0]) else 0)] = "exploding"
		at[int(pos[1])] = "exploding"
	else:
		at[int(pos[0])] = "exploding"
	return at


## Registra el resultado de una acción del bot (para recordar dónde escondió los explosivos).
func note(id: String, action: Dictionary, err: String) -> void:
	if action.get("a") == "insert" and err == "":
		_pending_ins[id] = action["positions"]


## Lee los eventos nuevos del motor y actualiza lo que cada bot sabe del mazo.
func learn() -> void:
	if plus:
		_learn_prompt_plus()
	for e: Dictionary in game.events:
		if e.seq <= _seq:
			continue
		var to: String = e.get("to", "")
		if e.type == "future" and levels.has(to) and levels[to] != "easy":
			var at := {}
			for i in e.cards.size():
				at[i] = e.cards[i]
			_mem[to] = {"at": at, "len": e.len, "shuf": e.shuf, "tops": e.get("tops", 0)}
		elif e.type == "clair" and levels.get(to, "") == "hard":
			_mem[to] = {"at": _depths(e.positions), "len": e.len, "shuf": e.shuf, "tops": e.get("tops", 0)}
		elif e.type == "inserted":
			var pos: Variant = _pending_ins.get(e.player)
			_pending_ins.erase(e.player)
			if pos != null and levels.get(e.player, "") == "hard":
				_mem[e.player] = {"at": _depths(pos), "len": e.len, "shuf": e.shuf, "tops": e.get("tops", 0)}
				if plus and _depths(pos).has(int(e.len) - 1):
					_hid_bottom[e.player] = e.shuf
		if plus:
			_learn_event_plus(e)
	if plus:
		_scan_peeks()
		_scan_grudges()
	_seq = game.seq


## Plus: lo que el bot ve en sus propias decisiones (es información suya, no hace trampa).
func _learn_prompt_plus() -> void:
	var pr: Variant = game.prompt
	if pr != null and pr.type == "bury" and levels.has(pr.player):
		_bury_card[pr.player] = pr.card.type


## Plus: eventos públicos y privados dirigidos al bot que cambian lo que sabe.
func _learn_event_plus(e: Dictionary) -> void:
	var to: String = e.get("to", "")
	# Vengativo: eventos públicos en que otro jugador me quita una carta, me deja turnos o me espanta
	if e.type in ["steal", "attack", "haunt", "swap"] and e.get("player", "") != "":
		var victim: String = e.get("target", "")
		if _tr(victim) == TRAIT_VENGEFUL and e.player != victim:
			_grudge[victim] = e.player
	match e.type:
		"apocalypse":
			# Público: los N explosivos están arriba del mazo
			var at := {}
			for i in int(e.n):
				at[i] = "exploding"
			for id: String in levels:
				if levels[id] != "easy":
					_mem[id] = {"at": at.duplicate(), "len": game.draw.size(), "shuf": game.shuf, "tops": game.tops}
			_rival_peek = {}
		"buried":
			if levels.has(to) and levels[to] != "easy" and _bury_card.has(to):
				var card: String = _bury_card[to]
				_mem[to] = {"at": {int(e.pos): card}, "len": e.len, "shuf": e.shuf, "tops": 0}
				if card == "exploding" and int(e.pos) >= int(e.len) - 1:
					_hid_bottom[to] = e.shuf
		"peek":
			if levels.has(to) and levels[to] != "easy":
				if not _peek.has(to):
					_peek[to] = {}
				_peek[to][e.target] = {"cards": (e.cards as Array).duplicate(), "scan": game.discard.size()}
		"play":
			if e.get("eff", "") == "see_future" or e.get("eff", "") == "alter_future":
				_rival_peek = {"by": e.player, "draws": 0}
		"cancel":
			if e.get("eff", "") == "see_future" or e.get("eff", "") == "alter_future":
				_rival_peek = {}
		"shuffle", "inserted", "rot_placed":
			_rival_peek = {}
		"draw":
			if not _rival_peek.is_empty() and not e.get("bottom", false):
				_rival_peek["draws"] += 1
				if _rival_peek["draws"] >= 3:
					_rival_peek = {}
		"steal":
			for id: String in _peek:
				if _peek[id].has(e.target):
					if e.has("card"):
						_peek[id][e.target].cards.erase(e.card)
					else:
						_peek[id].erase(e.target)
		"gave":
			for id: String in _peek:
				_peek[id].erase(e.player)
		"swap":
			for id: String in _peek:
				_peek[id].erase(e.player)
				_peek[id].erase(e.target)


## Plus vengativo: jugadas públicas de la pila dirigidas a mí (Favor, pareja, trío, Ataque Dirigido, Espanto, Trueque)
## y quién anuló con Nop una jugada mía.
func _scan_grudges() -> void:
	for id: String in traits:
		if _tr(id) != TRAIT_VENGEFUL:
			continue
		for s: Dictionary in game.stack:
			if s.target == id and s.by != id and HARM_EFFS.has(s.eff):
				var k := "%d:%s" % [s.id, id]
				if not _grudge_seen.has(k):
					_grudge_seen[k] = 1
					_grudge[id] = s.by
			if s.by == id and s.nopes % 2 == 1 and s.last != id:
				var k2 := "%d:%d:%s" % [s.id, s.nopes, id]
				if not _grudge_seen.has(k2):
					_grudge_seen[k2] = 1
					_grudge[id] = s.last


## Plus: quita de lo que se sabe de una mano las cartas que su dueño ha descartado desde la última vez.
func _scan_peeks() -> void:
	var disc := game.discard
	for id: String in _peek:
		for tid: String in _peek[id].keys():
			var d: Dictionary = _peek[id][tid]
			for i in range(int(d.scan), disc.size()):
				if disc[i].by == tid:
					d.cards.erase(disc[i].card.type)
			d.scan = disc.size()


## Plus: tipos que el bot SABE que tiene el rival (lo vio con Ojo de Cuervo y no ha cambiado).
func _peek_cards(id: String, tid: String) -> Array:
	var d: Variant = _peek.get(id, {}).get(tid)
	if d == null:
		return []
	var p := game.P(tid)
	if p == null or d.cards.size() > p.hand.size():
		_peek[id].erase(tid)
		return []
	return d.cards


## Lo que el bot SABE de la carta a cierta profundidad del mazo (0 = la próxima), o "" si no lo sabe.
func known(id: String, depth: int = 0) -> String:
	var m: Variant = _mem.get(id)
	if m == null or m.shuf != game.shuf:
		return ""
	if plus:
		# Profundidad actual = la de entonces menos las cartas retiradas de ARRIBA desde entonces (robar del fondo no cuenta)
		var dp: int = depth + game.tops - int(m.get("tops", 0))
		if dp < 0 or dp >= game.draw.size():
			return ""
		return m.at.get(dp, "")
	var d: int = m.len - game.draw.size() + depth
	return m.at.get(d, "") if d >= 0 else ""


func _known_eks_below(id: String) -> int:
	var m: Variant = _mem.get(id)
	if m == null or m.shuf != game.shuf:
		return 0
	var off: int = (game.tops - int(m.get("tops", 0))) if plus else (m.len - game.draw.size())
	var n := 0
	for d: int in m.at:
		if d > off and m.at[d] == "exploding":
			n += 1
	return n


func _pick(a: Array) -> Variant:
	return a[int(floor(rnd.call() * a.size()))]


static func _play(c: ZKGame.Card, extra: Dictionary = {}) -> Dictionary:
	var a := {"a": "play", "cards": [c.id]}
	a.merge(extra)
	return a


## Decide la siguiente acción del bot `id`. Devuelve {} si no tiene nada que hacer ahora.
func decide(id: String) -> Dictionary:
	var g := game
	if g.over != null:
		return {}
	var me := g.P(id)
	if me == null:
		return {}
	var pr: Variant = g.prompt
	var level: String = levels.get(id, "normal")
	var easy := level == "easy"
	var hard := level == "hard"

	if pr != null:
		if pr.type == "explode" and pr.player == id:
			var z := me.find_type("zombie")
			if z == null:
				z = me.find_type("clone")
			return _play(z) if z != null else {"a": "die"}
		if pr.type == "zombie" and pr.player == id and pr.pendingPos == null:
			if pr.needRevive and pr.revived == null:
				var dead := g.dead()
				if hard:
					dead.sort_custom(func(x: ZKGame.Player, y: ZKGame.Player) -> bool: return x.hand.size() < y.hand.size())
					return {"a": "revive", "target": dead[0].id}
				return {"a": "revive", "target": _pick(dead).id}
			var n := g.draw.size()
			var positions: Array = []
			for i in pr.eks.size():
				if easy:
					positions.append(int(floor(rnd.call() * (n + i + 1))))
				elif hard:
					# Si el siguiente en robar es un rival, el explosivo va arriba; si vuelvo a robar yo, al fondo
					if g.turns_left > 1:
						positions.append(n + i)
					else:
						positions.append(0 if i == 0 else mini(n + i, 1 + int(floor(rnd.call() * 3))))
				else:
					positions.append(int(floor(rnd.call() * mini(5, n + i + 1))))
			return {"a": "insert", "positions": positions}
		if pr.type == "give" and pr.waiting.has(id):
			if easy:
				return {"a": "give", "card": _pick(me.hand).id}
			var worst: ZKGame.Card = me.hand[0]
			for c in me.hand:
				if val(c.type) < val(worst.type):
					worst = c
			return {"a": "give", "card": worst.id}
		if pr.type == "dig" and pr.player == id:
			return {"a": "dig", "keep": not _lethal(pr.card) or (easy and rnd.call() < 0.5)}
		if plus and pr.get("player") == id:
			if pr.type == "alter":
				return _alter_plus(id, level, pr)
			if pr.type == "bury":
				return _bury_plus(id, level, pr)
			if pr.type == "rot":
				return _rot_plus(id, level)
		if pr.type != "zombie":
			return {}
		if hard and pr.player != id and g.stack.is_empty():
			var cv := me.find_type("clairvoyance")
			if cv != null and not g.plan(id, [cv.id]).has("err"):
				return _play(cv)

	var s: Variant = g.top()
	if s != null:
		var nope := me.find_type("nope")
		if nope == null or s.last == id or s.passed.has(id):
			return {}
		var live: bool = s.nopes % 2 == 0
		var next_id := g.players[g.next_living_idx(g.cur)].id
		var hurts: bool = s.by != id and ((s.target == id and (s.eff == "favor" or s.eff == "combo2" or s.eff == "combo3")) or ((s.eff == "attack" or s.eff == "attack_dead") and next_id == id))
		if plus and not hurts:
			hurts = _hurts_plus(id, s, next_id)
		var want: bool = (live and hurts) or (not live and s.by == id)
		var tn := _tr(id)
		if tn == TRAIT_CAUTIOUS:
			want = live and hurts      # prudente: el Nop se guarda para lo que le perjudica directamente
		var pn := 0.15 if easy else (0.95 if hard else 0.75)
		if tn == TRAIT_AGGRESSIVE:
			pn = minf(1.0, pn + 0.1)
		return _play(nope) if want and rnd.call() < pn else {"a": "pass"}
	if plus and pr == null:
		var fr := _free_play_plus(id, me, level)
		if not fr.is_empty():
			return fr
	if pr != null or g.cur_p().id != id or not me.alive:
		return {}

	var others: Array = []
	for o in g.players:
		if o.id != id and o.alive and o.hand.size() > 0:
			others.append(o)
	var dead_n := g.dead().size()

	if easy:
		if rnd.call() < 0.15:
			var opts: Array = []
			for c in me.hand:
				if (EASY_PLAYS.has(c.type) or (plus and EASY_PLAYS_PLUS.has(c.type))) and not g.plan(id, [c.id]).has("err"):
					opts.append(c)
			if opts.size() > 0:
				var c: ZKGame.Card = _pick(opts)
				if plus:
					return _random_play_plus(id, c)
				return _play(c, {"target": _pick(others).id} if c.type == "favor" else {})
		return {"a": "draw"}

	if plus:
		return _turn_plus(id, me, hard, others, dead_n)

	var top := known(id, 0)
	var eks_in := g.living().size() - 1
	var danger: float
	if top != "":
		danger = 1.0 if top == "exploding" else 0.0
	else:
		var k := _known_eks_below(id) if hard else 0
		danger = float(maxi(0, eks_in - k)) / float(maxi(1, g.draw.size() - k))

	if not hard:
		if top == "" and danger > 0.18 and me.find_type("see_future") != null:
			return _play(me.find_type("see_future"))
		if danger > (0.5 if me.find_type("zombie") != null else 0.28):
			if g.turns_left > 1 and me.find_type("super_skip") != null:
				return _play(me.find_type("super_skip"))
			if me.find_type("attack") != null:
				return _play(me.find_type("attack"))
			if me.find_type("attack_dead") != null and dead_n > 0:
				return _play(me.find_type("attack_dead"))
			if me.find_type("skip") != null:
				return _play(me.find_type("skip"))
			if me.find_type("super_skip") != null:
				return _play(me.find_type("super_skip"))
			if me.find_type("shuffle") != null and top != "":
				return _play(me.find_type("shuffle"))
			if me.find_type("dig_deeper") != null and g.draw.size() > 1 and top != "":
				return _play(me.find_type("dig_deeper"))
		if others.size() > 0 and rnd.call() < 0.3:
			var pair := _best_group(me, 2, 4)
			if pair.size() >= 2:
				return {"a": "play", "cards": [pair[0].id, pair[1].id], "target": _pick(others).id}
			if me.find_type("favor") != null:
				return _play(me.find_type("favor"), {"target": _pick(others).id})
		if dead_n > 0 and me.find_type("grave_robber") != null and danger > 0.3 and rnd.call() < 0.5:
			return _play(me.find_type("grave_robber"))
		return {"a": "draw"}

	# ----- DIFÍCIL -----
	var zs := 0
	for c in me.hand:
		zs += 1 if c.type == "zombie" else 0
	# 1) Fortalecerse: conseguir Gatitos Zombi y cartas ajenas
	if others.size() > 0:
		var richest: ZKGame.Player = others[0]
		for o: ZKGame.Player in others:
			if o.hand.size() > richest.hand.size():
				richest = o
		var grp := _best_group(me, 2, 3)
		if grp.size() >= 3 and zs < 2:
			return {"a": "play", "cards": [grp[0].id, grp[1].id, grp[2].id], "target": richest.id, "named": "zombie"}
		if grp.size() >= 2:
			return {"a": "play", "cards": [grp[0].id, grp[1].id], "target": richest.id}
		if me.find_type("favor") != null:
			return _play(me.find_type("favor"), {"target": richest.id})
	# 2) Informarse antes de arriesgar
	if top == "" and danger >= 0.14 and me.find_type("see_future") != null:
		return _play(me.find_type("see_future"))
	# 3) Esquivar: con Zombi en mano tolera más riesgo
	if danger >= (0.34 if zs > 0 else 0.2):
		if g.turns_left > 1 and me.find_type("super_skip") != null:
			return _play(me.find_type("super_skip"))
		if me.find_type("attack") != null:
			return _play(me.find_type("attack"))
		if me.find_type("attack_dead") != null and dead_n > 0:
			return _play(me.find_type("attack_dead"))
		if me.find_type("skip") != null:
			return _play(me.find_type("skip"))
		if me.find_type("super_skip") != null:
			return _play(me.find_type("super_skip"))
		if me.find_type("dig_deeper") != null and g.draw.size() > 1 and known(id, 1) != "exploding":
			return _play(me.find_type("dig_deeper"))
		if top == "exploding" and me.find_type("shuffle") != null:
			return _play(me.find_type("shuffle"))
		if dead_n > 0 and me.find_type("grave_robber") != null and g.dead().any(func(o: ZKGame.Player) -> bool: return o.hand.size() > 0):
			return _play(me.find_type("grave_robber"))
	return {"a": "draw"}


## El grupo más grande de cartas iguales y poco valiosas (para parejas y tríos). Excluye Zombi, Nop y Clon.
func _best_group(me: ZKGame.Player, min_size: int, max_value: int) -> Array:
	var by_type := {}
	for c in me.hand:
		if c.type == "zombie" or c.type == "nope" or c.type == "clone" or val(c.type) > max_value:
			continue
		if not by_type.has(c.type):
			by_type[c.type] = []
		by_type[c.type].append(c)
	var best: Array = []
	for t: String in by_type:
		var grp: Array = by_type[t]
		if grp.size() < min_size:
			continue
		if best.is_empty() or grp.size() > best.size() or (grp.size() == best.size() and val(t) < val(best[0].type)):
			best = grp
	return best


# ================================================================ Plus: La Cripta y carencias de la IA
# Todo lo de abajo solo se alcanza con `plus = true`. Cada jugada se comprueba con game.plan() antes de devolverse.

## Jugada de una carta si el motor la admite ya (sin dejar objetivos por elegir). {} si no.
func _try(id: String, c: ZKGame.Card, target: Variant = null, named: Variant = null) -> Dictionary:
	if c == null:
		return {}
	var ids := [c.id]
	var pl := game.plan(id, ids, target, named)
	if pl.has("err") or pl.has("need"):
		return {}
	var a := {"a": "play", "cards": ids}
	if target != null:
		a["target"] = target
	if named != null:
		a["named"] = named
	return a


## Pareja o trío (las cartas deben ser jugables según el motor).
func _try_group(id: String, grp: Array, n: int, target: String, named: Variant = null) -> Dictionary:
	if grp.size() < n:
		return {}
	var ids: Array = []
	for i in n:
		ids.append(grp[i].id)
	var pl := game.plan(id, ids, target, named)
	if pl.has("err") or pl.has("need"):
		return {}
	var a := {"a": "play", "cards": ids, "target": target}
	if named != null:
		a["named"] = named
	return a


func _count_of(me: ZKGame.Player, t: String) -> int:
	var n := 0
	for c in me.hand:
		n += 1 if c.type == t else 0
	return n


func _rivals(id: String) -> Array:
	var out: Array = []
	for o in game.players:
		if o.id != id and o.alive:
			out.append(o)
	return out


func _richest(list: Array) -> ZKGame.Player:
	var best: ZKGame.Player = list[0]
	for o: ZKGame.Player in list:
		if o.hand.size() > best.hand.size():
			best = o
	return best


## Jugadores que el motor admite como objetivo para cada `need`.
func _targets(id: String, need: String) -> Array:
	var out: Array = []
	for o in game.players:
		if o.id == id:
			continue
		var ok := false
		match need:
			"living": ok = o.alive and o.hand.size() > 0
			"living_any": ok = o.alive
			"any_hand": ok = o.hand.size() > 0
			"dead": ok = not o.alive
			"dead_hand": ok = not o.alive and o.hand.size() > 0
		if ok:
			out.append(o)
	return out


## Fácil: juega una carta casi al azar, con un objetivo válido al azar.
func _random_play_plus(id: String, c: ZKGame.Card) -> Dictionary:
	var pl := game.plan(id, [c.id])
	if pl.has("err"):
		return {"a": "draw"}
	if pl.has("need"):
		var cand := _targets(id, pl.need)
		if cand.is_empty():
			return {"a": "draw"}
		return _play(c, {"target": _pick(cand).id})
	return _play(c)


## ¿La carta mata a quien la roba? Explosivo, o Putrefacto boca arriba (boca abajo no mata: abre la decisión `rot`).
static func _lethal(c: ZKGame.Card) -> bool:
	return c.type == "exploding" or (c.type == "rotten" and c.up)


## Lo que el bot sabe de la próxima carta. Con el Putrefacto boca arriba arriba (rotDepth = 0, público) es muerte segura:
## se trata como un explosivo conocido para que todas las salidas se activen.
func _top(id: String) -> String:
	if game.rot_depth() == 0:
		return "exploding"
	return known(id, 0)


## ¿La carta a cierta profundidad es un peligro conocido? Explosivo recordado o Putrefacto boca arriba (rotDepth).
func _bad_at(id: String, depth: int) -> bool:
	return known(id, depth) == "exploding" or game.rot_depth() == depth


## Decisión `rot`: fácil al azar; normal y difícil arriba si el siguiente en robar es un rival, al fondo si vuelvo a robar yo.
func _rot_plus(_id: String, level: String) -> Dictionary:
	var n := game.draw.size()
	if level == "easy":
		return {"a": "rot", "pos": int(floor(rnd.call() * (n + 1)))}
	return {"a": "rot", "pos": n if game.turns_left > 1 else 0}


## Probabilidad de que la próxima carta sea un explosivo, usando lo que el bot sabe del mazo.
func _danger_plus(id: String, top: String) -> float:
	if top != "":
		return 1.0 if top == "exploding" else 0.0
	var rd := game.rot_depth()
	if rd == 0:
		return 1.0   # Putrefacto boca arriba arriba del mazo: robar es muerte segura
	var m: Variant = _mem.get(id)
	var kn := 0
	var ke := 0
	if m != null and m.shuf == game.shuf:
		var off: int = game.tops - int(m.get("tops", 0))
		for d: int in m.at:
			var dd := d - off
			if dd > 0 and dd < game.draw.size():
				if rd >= 0 and m.at[d] == "rotten":
					continue   # el Putrefacto boca arriba se cuenta con rotDepth, no dos veces
				kn += 1
				ke += 1 if (m.at[d] == "exploding" or m.at[d] == "rotten") else 0
	if rd > 0 and rd < game.draw.size():
		kn += 1   # explosivo de posición conocida (el Putrefacto boca arriba)
		ke += 1
	var eks_in := game.living().size() - 1
	return float(maxi(0, eks_in - ke)) / float(maxi(1, game.draw.size() - kn))


func _bottom_hidden(id: String) -> bool:
	return _hid_bottom.get(id, -1) == game.shuf


## Nop: ¿esta jugada de otro me perjudica? (ampliación de la lógica clásica)
func _hurts_plus(id: String, s: Dictionary, next_id: String) -> bool:
	match s.eff:
		"targeted_attack", "haunt":
			return s.target == id
		"apocalypse":
			return next_id == id
		"soul_swap":
			var t := game.P(s.target)
			var by := game.P(s.by)
			if t == null or by == null:
				return false
			if t.id == id:
				return by.hand.size() + 3 <= t.hand.size()    # me quitarían una mano mucho mejor que la suya
			if _tr(id) == TRAIT_CAUTIOUS:
				return false    # prudente: solo lo que le perjudica directamente
			return t.hand.size() >= by.hand.size() + 3          # se llevaría una mano mucho mejor
	return false


## Objetivo de un Ataque Dirigido: normal al azar; difícil el rival con más cartas o, si sabe que arriba hay un explosivo,
## el que no tiene Zombi conocido (con Ojo de Cuervo).
func _attack_target(id: String, hard: bool, top: String) -> String:
	var rivals := _rivals(id)
	if rivals.is_empty():
		return ""
	if not hard:
		return _vt(id, rivals, _pick(rivals).id)
	if top == "exploding":
		var pool: Array = rivals.filter(func(o: ZKGame.Player) -> bool: return not _peek_cards(id, o.id).has("zombie"))
		if pool.is_empty():
			pool = rivals
		var best: ZKGame.Player = pool[0]
		for o: ZKGame.Player in pool:
			if o.hand.size() < best.hand.size():
				best = o
		return _vt(id, rivals, best.id)
	return _vt(id, rivals, _richest(rivals).id)


## Objetivo de un trío: quien se sabe que tiene un Zombi u otra carta valiosa; si no, el que más cartas tiene.
func _trio_target(id: String, others: Array) -> ZKGame.Player:
	var best: ZKGame.Player = _trio_target_base(id, others)
	var v := _vt(id, others, best.id)
	return best if v == best.id else game.P(v)


func _trio_target_base(id: String, others: Array) -> ZKGame.Player:
	var best: ZKGame.Player = others[0]
	var best_score := -1
	for o: ZKGame.Player in others:
		var known_cards := _peek_cards(id, o.id)
		var sc := o.hand.size()
		if known_cards.has("zombie"):
			sc += 1000
		else:
			for t: String in known_cards:
				if t != "exploding":
					sc = maxi(sc, 100 + val(t))
		if sc > best_score:
			best_score = sc
			best = o
	return best


## Carta que se pide en un trío: la mejor que se sabe que tiene; si no, un Gatito Zombi.
func _named_for(id: String, tid: String) -> String:
	var cards := _peek_cards(id, tid)
	var best := "zombie"
	var best_v := -1
	for t: String in cards:
		if t != "exploding" and game.deck_types.has(t) and val(t) > best_v:
			best = t
			best_v = val(t)
	if best == "zombie" or best_v >= 4:
		return best
	var p := game.P(tid)
	return best if p != null and cards.size() >= p.hand.size() else "zombie"


## Alterar el Futuro: pone el explosivo donde le tocará al siguiente rival (tras mis propios robos pendientes),
## o lo más abajo posible si voy a seguir robando. El difícil además se queda lo mejor para sí.
func _alter_plus(_id: String, level: String, pr: Dictionary) -> Dictionary:
	var cards: Array = pr.cards
	var m := cards.size()
	var ident: Array = []
	for i in m:
		ident.append(i)
	if level == "easy":
		return {"a": "reorder", "order": ident}
	var bombs: Array = []
	var safe: Array = []
	for i in m:
		(bombs if _lethal(cards[i]) else safe).append(i)
	if bombs.is_empty():
		return {"a": "reorder", "order": ident}
	if level == "hard":
		safe.sort_custom(func(x: int, y: int) -> bool:
			var vx := val(cards[x].type)
			var vy := val(cards[y].type)
			return vx > vy or (vx == vy and x < y))
	var mine := mini(game.turns_left, m)    # los robos que me quedan: los primeros puestos
	var out: Array = []
	for i in mine:
		out.append(safe.pop_front() if not safe.is_empty() else bombs.pop_front())
	out.append_array(bombs)
	out.append_array(safe)
	return {"a": "reorder", "order": out}


## Entierro: un explosivo va arriba para el siguiente rival (o al fondo si voy a robar otra vez); una carta segura,
## arriba si la voy a robar yo y al fondo si no.
func _bury_plus(id: String, level: String, pr: Dictionary) -> Dictionary:
	var n := game.draw.size()
	_bury_card[id] = pr.card.type
	if level == "easy":
		return {"a": "bury", "pos": int(floor(rnd.call() * (n + 1)))}
	var again := game.turns_left > 1
	var pos := 0
	if _lethal(pr.card):
		pos = n if again else 0
	else:
		pos = 0 if again else n
	return {"a": "bury", "pos": pos}


## Cartas que se juegan fuera de turno: los muertos espantan y alimentan; los vivos barajan si un rival acaba de mirar.
func _free_play_plus(id: String, me: ZKGame.Player, level: String) -> Dictionary:
	var g := game
	if not g.idle():
		return {}
	if not me.alive:
		var h := me.find_type("haunt")
		if h != null:
			var cands: Array = _targets(id, "living")
			if not cands.is_empty() and (level != "easy" or rnd.call() < 0.2):
				var r := _try(id, h, _vt(id, cands, _richest(cands).id))
				if not r.is_empty():
					return r
		var f := me.find_type("feed_dead")
		if f != null and level != "easy" and me.hand.size() <= (4 if level == "hard" else 3) and _targets(id, "living").size() >= 2:
			if level == "hard" or rnd.call() < 0.7:
				return _try(id, f, id)
		return {}
	if level == "easy" or _rival_peek.is_empty() or _rival_peek.by == id:
		return {}
	var sh := me.find_type("shuffle")
	if sh == null:
		return {}
	var top := _top(id)
	if top != "" and top != "exploding":
		return {}
	var danger := _danger_plus(id, top)
	var hard := level == "hard"
	var next_me := g.cur_p().id == id or g.players[g.next_living_idx(g.cur)].id == id
	if (next_me and danger >= (0.0 if hard else 0.1)) or danger >= (0.25 if hard else 0.3):
		if rnd.call() < (0.9 if hard else 0.6):
			return _try(id, sh)
	return {}


## Copia con el Clon un Ataque, Saltar o Súper Salto (o Marcha Atrás / Ataque Dirigido) del descarte.
func _clone_dodge(id: String, me: ZKGame.Player, hard: bool, top: String) -> Dictionary:
	var cl := me.find_type("clone")
	var td: Variant = game.top_discard()
	if cl == null or td == null:
		return {}
	var t: String = td.card.type
	if not ["attack", "skip", "super_skip", "reverse", "targeted_attack", "attack_dead"].has(t):
		return {}
	var pl := game.plan(id, [cl.id])
	if pl.has("err"):
		return {}
	if pl.has("need"):
		var tgt := _attack_target(id, hard, top)
		if tgt == "":
			return {}
		return _try(id, cl, tgt)
	return _try(id, cl)


## Esquivar el robo. Orden: lo que pasa el problema al rival, lo que termina el turno sin robar, lo que cambia la carta.
func _dodge_plus(id: String, me: ZKGame.Player, hard: bool, top: String, danger: float, dead_n: int) -> Dictionary:
	var g := game
	var r: Dictionary
	if g.turns_left > 1:
		r = _try(id, me.find_type("super_skip"))
		if not r.is_empty():
			return r
	if hard and me.find_type("targeted_attack") != null:
		var tg := _attack_target(id, true, top)
		if tg != "":
			r = _try(id, me.find_type("targeted_attack"), tg)
			if not r.is_empty():
				return r
	r = _try(id, me.find_type("attack"))
	if not r.is_empty():
		return r
	if not hard and me.find_type("targeted_attack") != null:
		var tn := _attack_target(id, false, top)
		if tn != "":
			r = _try(id, me.find_type("targeted_attack"), tn)
			if not r.is_empty():
				return r
	if dead_n > 0:
		r = _try(id, me.find_type("attack_dead"))
		if not r.is_empty():
			return r
	for t: String in ["skip", "super_skip", "reverse"]:
		r = _try(id, me.find_type(t))
		if not r.is_empty():
			return r
	if g.draw.size() > 0:
		r = _try(id, me.find_type("bury"))
		if not r.is_empty():
			return r
	var tcau := _tr(id) == TRAIT_CAUTIOUS
	if g.draw.size() > 1 and not _bottom_hidden(id) and g.rot_depth() != g.draw.size() - 1 and (top == "exploding" or (hard and danger >= 0.34 * _risk_f(id)) or (tcau and danger >= 0.2)):
		r = _try(id, me.find_type("draw_bottom"))
		if not r.is_empty():
			return r
	if g.rot_depth() == 0 and g.draw.size() >= 2:
		r = _try(id, me.find_type("alter_future"))   # Putrefacto boca arriba arriba: lo aparta de mi robo
		if not r.is_empty():
			return r
	if hard:
		if g.draw.size() > 1 and not _bad_at(id, 1):
			r = _try(id, me.find_type("dig_deeper"))
			if not r.is_empty():
				return r
		if top == "exploding":
			r = _try(id, me.find_type("shuffle"))
			if not r.is_empty():
				return r
		if dead_n > 0 and g.dead().any(func(o: ZKGame.Player) -> bool: return o.hand.size() > 0):
			r = _try(id, me.find_type("grave_robber"))
			if not r.is_empty():
				return r
	else:
		if top != "":
			r = _try(id, me.find_type("shuffle"))
			if not r.is_empty():
				return r
		if g.draw.size() > 1 and top != "":
			r = _try(id, me.find_type("dig_deeper"))
			if not r.is_empty():
				return r
	return _clone_dodge(id, me, hard, top)


## Trueque de Almas: difícil si el muerto tiene más cartas y yo no tengo Zombi; normal si tiene mucho más.
func _soul_swap_plus(id: String, me: ZKGame.Player, hard: bool, zs: int) -> Dictionary:
	var sw := me.find_type("soul_swap")
	if sw == null:
		return {}
	var cands := _targets(id, "dead_hand")
	if cands.is_empty():
		return {}
	var best := _richest(cands)
	var mine := me.hand.size() - 1
	var aggr := _tr(id) == TRAIT_AGGRESSIVE
	if hard:
		if best.hand.size() > mine and (zs == 0 or (aggr and best.hand.size() >= mine + 2)):
			return _try(id, sw, _vt(id, cands, best.id))
	elif best.hand.size() >= mine + (1 if aggr else 3) and rnd.call() < (0.8 if aggr else 0.5):
		return _try(id, sw, _vt(id, cands, best.id))
	return {}


## Alimenta a los Muertos jugado por un vivo: los demás vivos dan una carta al muerto. Sirve si yo tengo menos cartas
## que ellos (yo no doy).
func _feed_dead_living(id: String, me: ZKGame.Player, hard: bool) -> Dictionary:
	var f := me.find_type("feed_dead")
	if f == null:
		return {}
	var givers: Array = _targets(id, "living")
	var dead: Array = game.dead()
	if givers.size() < 2 or dead.is_empty():
		return {}
	var sum := 0
	for o: ZKGame.Player in givers:
		sum += o.hand.size()
	if float(sum) / givers.size() < me.hand.size() + 0.5:
		return {}
	if not hard and rnd.call() >= 0.5:
		return {}
	var tgt: ZKGame.Player = dead[0]
	for o: ZKGame.Player in dead:
		if o.hand.size() < tgt.hand.size():
			tgt = o
	return _try(id, f, tgt.id)


## Apocalipsis Zombi: los N explosivos pasan arriba. Solo si el siguiente en robar no soy yo y tengo reserva (Zombi o salto).
func _apocalypse_plus(id: String, me: ZKGame.Player, hard: bool, zs: int) -> Dictionary:
	var ap := me.find_type("apocalypse")
	if ap == null or game.living().size() < 3:
		return {}
	if game.players[game.next_living_idx(game.cur)].id == id:
		return {}
	var reserve := zs > 0
	for t: String in ["skip", "super_skip", "attack", "targeted_attack"]:
		reserve = reserve or me.find_type(t) != null
	if not reserve:
		return {}
	if not hard and (zs == 0 or rnd.call() >= 0.4):
		return {}
	return _try(id, ap)


## Turno de un bot normal o difícil en Plus. Copia el orden del clásico y añade La Cripta y las correcciones de IA-02.
func _turn_plus(id: String, me: ZKGame.Player, hard: bool, others: Array, dead_n: int) -> Dictionary:
	var g := game
	if g.draw.is_empty():
		return {"a": "draw"}
	var top := _top(id)
	var danger := _danger_plus(id, top)
	var zs := _count_of(me, "zombie")
	var r: Dictionary
	var tr := _tr(id)
	var rf := _risk_f(id)                              # umbrales de riesgo: agresivo +20 %, prudente -20 %
	var inf := rf * (0.6 if tr == TRAIT_CAUTIOUS else 1.0)   # el prudente se informa aún antes
	var aggr := tr == TRAIT_AGGRESSIVE

	if not hard:
		# Informarse
		if top == "" and danger > 0.18 * inf:
			for t: String in ["see_future", "alter_future"]:
				r = _try(id, me.find_type(t))
				if not r.is_empty():
					return r
		# Esquivar
		if danger > (0.5 if zs > 0 else 0.28) * rf:
			r = _dodge_plus(id, me, false, top, danger, dead_n)
			if not r.is_empty():
				return r
		if others.size() > 0:
			# IA-03: el agresivo ataca de forma dirigida sin esperar a tener riesgo
			if aggr and rnd.call() < 0.3:
				var tgt := _attack_target(id, false, top)
				if tgt != "":
					r = _try(id, me.find_type("targeted_attack"), tgt)
					if not r.is_empty():
						return r
			# IA-02d: tríos de cartas baratas pidiendo Gatito Zombi
			var trio := _best_group(me, 3, 4)
			if trio.size() >= 3 and rnd.call() < (0.8 if aggr else 0.5):
				r = _try_group(id, trio, 3, _vt(id, others, _pick(others).id), "zombie")
				if not r.is_empty():
					return r
			if rnd.call() < (0.55 if aggr else 0.3):
				var pair := _best_group(me, 2, 4)
				if pair.size() >= 2:
					r = _try_group(id, pair, 2, _vt(id, others, _pick(others).id))
					if not r.is_empty():
						return r
				r = _try(id, me.find_type("favor"), _vt(id, others, _pick(others).id))
				if not r.is_empty():
					return r
		if dead_n > 0 and me.find_type("grave_robber") != null and danger > 0.3 and rnd.call() < 0.5:
			r = _try(id, me.find_type("grave_robber"))
			if not r.is_empty():
				return r
		r = _soul_swap_plus(id, me, false, zs)
		if not r.is_empty():
			return r
		r = _apocalypse_plus(id, me, false, zs)
		if not r.is_empty():
			return r
		r = _feed_dead_living(id, me, false)
		if not r.is_empty():
			return r
		if others.size() > 0 and me.find_type("crow_eye") != null and rnd.call() < 0.1:
			return _try(id, me.find_type("crow_eye"), _vt(id, others, _pick(others).id))
		return {"a": "draw"}

	# ----- DIFÍCIL -----
	# 1) Fortalecerse
	r = _soul_swap_plus(id, me, true, zs)
	if not r.is_empty():
		return r
	if others.size() > 0:
		var richest := game.P(_vt(id, others, _richest(others).id))
		var grp := _best_group(me, 2, 4 if aggr else 3)
		if grp.size() >= 3 and zs < 2:
			var tt := _trio_target(id, others)
			var ce := me.find_type("crow_eye")
			if ce != null and _peek_cards(id, tt.id).is_empty():
				r = _try(id, ce, tt.id)
				if not r.is_empty():
					return r
			r = _try_group(id, grp, 3, tt.id, _named_for(id, tt.id))
			if not r.is_empty():
				return r
		if grp.size() >= 2:
			r = _try_group(id, grp, 2, richest.id)
			if not r.is_empty():
				return r
		r = _try(id, me.find_type("favor"), richest.id)
		if not r.is_empty():
			return r
	# IA-03: el agresivo ataca de forma dirigida sin esperar a tener riesgo
	if aggr and others.size() > 0 and rnd.call() < 0.3:
		var tgt := _attack_target(id, true, top)
		if tgt != "":
			r = _try(id, me.find_type("targeted_attack"), tgt)
			if not r.is_empty():
				return r
	# 2) Apocalipsis, si hay reserva
	r = _apocalypse_plus(id, me, true, zs)
	if not r.is_empty():
		return r
	# 3) Informarse antes de arriesgar
	if top == "" and danger >= 0.14 * inf:
		for t: String in ["alter_future", "see_future"]:
			r = _try(id, me.find_type(t))
			if not r.is_empty():
				return r
	# 4) Esquivar: con Zombi en mano tolera más riesgo
	if danger >= (0.34 if zs > 0 else 0.2) * rf:
		r = _dodge_plus(id, me, true, top, danger, dead_n)
		if not r.is_empty():
			return r
	# 5) Aprovechar cartas sueltas
	r = _feed_dead_living(id, me, true)
	if not r.is_empty():
		return r
	if others.size() > 0 and me.find_type("crow_eye") != null and rnd.call() < 0.3:
		var rc := game.P(_vt(id, others, _richest(others).id))
		if _peek_cards(id, rc.id).is_empty():
			r = _try(id, me.find_type("crow_eye"), rc.id)
			if not r.is_empty():
				return r
	return {"a": "draw"}
