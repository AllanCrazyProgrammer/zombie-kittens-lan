class_name ZKBots
extends RefCounted
## Jugadores controlados por la IA. Juegan solo con su mano y lo que han visto (no hacen trampa).
##   FÁCIL:   juega casi al azar.
##   NORMAL:  reacciona al riesgo y usa Ver el Futuro.
##   DIFÍCIL: recuerda el mazo, ataca, roba Gatitos Zombi y deja el explosivo arriba.
## Port de la IA de web/www/room.js.

const VALUE := {"zombie": 10, "nope": 7, "attack": 6, "attack_dead": 6, "super_skip": 6, "skip": 5, "see_future": 4, "shuffle": 4, "dig_deeper": 4, "clone": 4, "favor": 3, "clairvoyance": 2, "feed_dead": 2, "grave_robber": 2}
const EASY_PLAYS := ["attack", "skip", "super_skip", "see_future", "shuffle", "dig_deeper", "favor", "attack_dead", "grave_robber"]

var game: ZKGame
var levels: Dictionary          # id del jugador -> "easy" | "normal" | "hard"
var rnd: Callable
var _mem := {}                  # id -> {at: {profundidad: tipo}, len, shuf}
var _pending_ins := {}          # id -> posiciones elegidas al esconder explosivos
var _seq := 0
var plus := false               # Plus: se usará para las heurísticas nuevas (aún ninguna)


func _init(p_game: ZKGame, p_levels: Dictionary, p_rnd: Callable, p_plus: bool = false) -> void:
	game = p_game
	levels = p_levels
	rnd = p_rnd
	plus = p_plus


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
	for e: Dictionary in game.events:
		if e.seq <= _seq:
			continue
		var to: String = e.get("to", "")
		if e.type == "future" and levels.has(to) and levels[to] != "easy":
			var at := {}
			for i in e.cards.size():
				at[i] = e.cards[i]
			_mem[to] = {"at": at, "len": e.len, "shuf": e.shuf}
		elif e.type == "clair" and levels.get(to, "") == "hard":
			_mem[to] = {"at": _depths(e.positions), "len": e.len, "shuf": e.shuf}
		elif e.type == "inserted":
			var pos: Variant = _pending_ins.get(e.player)
			_pending_ins.erase(e.player)
			if pos != null and levels.get(e.player, "") == "hard":
				_mem[e.player] = {"at": _depths(pos), "len": e.len, "shuf": e.shuf}
	_seq = game.seq


## Lo que el bot SABE de la carta a cierta profundidad del mazo (0 = la próxima), o "" si no lo sabe.
func known(id: String, depth: int = 0) -> String:
	var m: Variant = _mem.get(id)
	if m == null or m.shuf != game.shuf:
		return ""
	var d: int = m.len - game.draw.size() + depth
	return m.at.get(d, "") if d >= 0 else ""


func _known_eks_below(id: String) -> int:
	var m: Variant = _mem.get(id)
	if m == null or m.shuf != game.shuf:
		return 0
	var off: int = m.len - game.draw.size()
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
			return {"a": "dig", "keep": pr.card.type != "exploding" or (easy and rnd.call() < 0.5)}
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
		var want: bool = (live and hurts) or (not live and s.by == id)
		return _play(nope) if want and rnd.call() < (0.15 if easy else (0.95 if hard else 0.75)) else {"a": "pass"}
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
				if EASY_PLAYS.has(c.type) and not g.plan(id, [c.id]).has("err"):
					opts.append(c)
			if opts.size() > 0:
				var c: ZKGame.Card = _pick(opts)
				return _play(c, {"target": _pick(others).id} if c.type == "favor" else {})
		return {"a": "draw"}

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
