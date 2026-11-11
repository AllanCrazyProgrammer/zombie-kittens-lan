extends SceneTree
## Pruebas del motor de reglas en Godot. Uso:
##   godot --headless --path godot -s tests/run_tests.gd
## 1) Reproduce partidas grabadas del motor original (JavaScript) y compara el estado tras CADA paso.
## 2) Simula partidas completas con la IA y comprueba que no se pierden cartas ni se atasca nada.
## 3) Enfrenta las dificultades entre sí.

const Game := preload("res://scripts/rules/zk_game.gd")
const Rng := preload("res://scripts/rules/zk_rng.gd")
const Bots := preload("res://scripts/ai/zk_bots.gd")

var _fails := 0


## Se arranca en _initialize (no en _init): así ya existen los autoloads (Net, CardDB) que usan las salas y sesiones.
func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	if "--record-guard" in OS.get_cmdline_user_args():
		_record_guard()
		quit(1 if _fails > 0 else 0)
		return
	if "--balance" in OS.get_cmdline_user_args():
		_balance(OS.get_cmdline_user_args())
		quit(0)
		return
	_test_versions()
	_test_rng_and_setup()
	_test_traces()
	_test_simulations()
	_test_classic_guard()
	_test_plus_engine()
	_test_plus_levers()
	_test_crypt_cards_1()
	_test_crypt_cards_2()
	_test_plus_network()
	_test_difficulty()
	_test_plus_bots()
	print("\n%s  (%d ms)" % ["TODO OK" if _fails == 0 else "%d FALLOS" % _fails, Time.get_ticks_msec() - t0])
	quit(1 if _fails > 0 else 0)


func _check(cond: bool, what: String) -> bool:
	if not cond:
		_fails += 1
		printerr("  ✗ " + what)
	return cond


func _ok(what: String) -> void:
	print("  ✓ " + what)


static func _ids(a: Array) -> String:
	var out: PackedStringArray = []
	for c: Variant in a:
		out.append(c.id)
	return ",".join(out)


static func _or_dash(v: Variant) -> String:
	return "-" if v == null or (v is String and v == "") else str(v)


## Huella textual del estado completo. Debe coincidir carácter a carácter con digest() de tools/godot/gen-traces.js
static func digest(g: Game) -> String:
	var s := "D:" + _ids(g.draw) + "|X:"
	var parts: PackedStringArray = []
	for d: Dictionary in g.discard:
		parts.append(d.card.id + "/" + d.by)
	s += ",".join(parts) + "|H:"
	parts = []
	for p in g.players:
		parts.append(p.id + "=" + _ids(p.hand) + "/" + ("1" if p.alive else "0") + "/" + (p.ek.id if p.ek != null else "-") + "/" + ("1" if p.connected else "0"))
	s += ";".join(parts) + "|C:%d/%d/%d|S:" % [g.cur, g.turns_left, 1 if g.attacked else 0]
	parts = []
	for x: Dictionary in g.stack:
		parts.append("/".join(PackedStringArray([x.eff, x.by, str(x.nopes), x.last, _or_dash(x.target), _or_dash(x.named), str(x.deadline), "+".join(PackedStringArray(x.passed.keys()))])))
	s += ";".join(parts) + "|P:"
	if g.prompt != null:
		var pr: Dictionary = g.prompt
		s += "%s/%d" % [pr.type, pr.deadline]
		if pr.has("player"):
			s += "/pl=" + pr.player
		if pr.has("card"):
			s += "/c=" + pr.card.id
		if pr.has("eks"):
			var pp := "-"
			if pr.pendingPos != null:
				var q: PackedStringArray = []
				for v: int in pr.pendingPos:
					q.append(str(v))
				pp = "+".join(q)
			s += "/e=" + _ids(pr.eks) + "/r=" + _or_dash(pr.revived) + "/pp=" + pp + "/w=" + "+".join(PackedStringArray(pr.watchers)) + "/m=%d" % pr.minUntil
		if pr.has("waiting"):
			s += "/wt=" + "+".join(PackedStringArray(pr.waiting.keys())) + "/to=" + _or_dash(pr.to) + "/rs=" + pr.reason + "/pool=" + _ids(pr.pool)
	var last_type: String = g.events[g.events.size() - 1].type if g.events.size() > 0 else ""
	s += "|O:" + ((_or_dash(g.over.winner)) if g.over != null else "") + "|E:%d/%s|M:%d/%d/%d" % [g.seq, last_type, g.mut, g.shuf, g.idle_since]
	return s


static func _mk(n: int, seed_value: int, mode: String = "official", rng: Rng = null, plus: bool = false, packs: Array = []) -> Game:
	var players: Array = []
	for i in n:
		players.append({"id": "b%d" % i, "name": "B%d" % i, "bot": true})
	var opts := {"players": players, "deck_mode": mode, "rng": rng if rng != null else Rng.new(seed_value), "now": 0}
	if plus:
		opts["plus"] = true
		opts["packs"] = packs
	return Game.new(opts)


static func _count(g: Game) -> int:
	var n := g.draw.size() + g.discard.size()
	for p in g.players:
		n += p.hand.size() + (1 if p.ek != null else 0)
	if g.prompt != null:
		n += (1 if g.prompt.has("card") else 0) + (g.prompt.eks.size() if g.prompt.has("eks") else 0) + (g.prompt.pool.size() if g.prompt.has("pool") else 0)
	return n


func _test_versions() -> void:
	print("Versiones")
	var U := preload("res://scripts/autoload/updater.gd")
	var cases := [["2.1.0", "2.0.0", true], ["v2.1.0", "2.0.0", true], ["1.10.0", "1.9.3", true], ["2.0.0", "2.0.0", false],
		["2.0", "2.0.0", false], ["1.1.0", "2.0.0", false], ["v3.0.0-beta", "2.9", true], ["2.0.0", "2.0.1", false]]
	var bad := 0
	for c: Array in cases:
		if not _check(U.is_newer(c[0], c[1]) == c[2], "%s > %s debería ser %s" % c):
			bad += 1
	if bad == 0:
		_ok("comparación de versiones (%d casos)" % cases.size())


func _test_rng_and_setup() -> void:
	print("Preparación")
	for row: Array in [[2, 9, 25], [3, 11, 35], [4, 28, 60], [5, 21, 61]]:
		var g := _mk(row[0], 7)
		_check(g.draw.size() == row[1], "%d jugadores: mazo de %d (salió %d)" % [row[0], row[1], g.draw.size()])
		_check(_count(g) == row[2], "%d jugadores: %d cartas en total" % [row[0], row[2]])
		var eks := 0
		for c in g.draw:
			eks += 1 if c.type == "exploding" else 0
		_check(eks == row[0] - 1, "%d jugadores: %d explosivos" % [row[0], row[0] - 1])
		for p in g.players:
			_check(p.hand.size() == 8 and p.find_type("zombie") != null, "mano inicial de 8 con Gatito Zombi")
	_ok("mazos y manos iniciales para 2, 3, 4 y 5 jugadores")


func _test_traces() -> void:
	print("Comparación con el motor original")
	var f := FileAccess.open("res://tests/traces.json", FileAccess.READ)
	if not _check(f != null, "no se encontró tests/traces.json (genera con: node tools/godot/gen-traces.js)"):
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var r := Rng.new(12345)
	var same := true
	for v: float in data.rng:
		same = same and absf(r.next() - v) < 1e-12   # el lector de JSON de Godot no conserva todos los decimales
	_check(same, "generador aleatorio idéntico al de JavaScript")
	_check(Rng.fnv("D:c1,c2|X:") == int(data.fnv), "función de huella idéntica")
	var steps := 0
	var bad := 0
	for gi in data.games.size():
		var t: Dictionary = data.games[gi]
		var g := _mk(int(t.n), 0, t.mode, Rng.new(int(t.seed)))
		for i: Variant in t.gone:
			g.players[int(i)].bot = false
			g.set_connected("b%d" % int(i), false, 0)
		g.tick(0)
		if Rng.fnv(digest(g)) != int(t.init):
			bad += 1
			printerr("  ✗ partida %d: el reparto inicial difiere\n    %s" % [gi, digest(g)])
			continue
		for si in t.steps.size():
			var st: Array = t.steps[si]
			var now := int(st[1])
			if int(st[0]) == 0:
				var a: Dictionary = st[3]
				var err := g.act("b%d" % int(st[2]), a, now)
				if (err != "") != (int(st[4]) == 1):
					bad += 1
					printerr("  ✗ partida %d paso %d: el error difiere (%s) acción %s" % [gi, si, err, a])
					break
			else:
				g.tick(now)
			steps += 1
			if Rng.fnv(digest(g)) != int(st[5]):
				bad += 1
				printerr("  ✗ partida %d paso %d: el estado difiere tras %s\n    %s" % [gi, si, st, digest(g)])
				break
		if bad == 0 and si_winner(g) != _or_dash(t.winner):
			bad += 1
			printerr("  ✗ partida %d: ganador distinto" % gi)
		if bad >= 3:
			break
	if _check(bad == 0, "%d partidas difieren del motor original" % bad):
		_ok("%d partidas / %d pasos idénticos al motor original, paso a paso" % [data.games.size(), steps])


static func si_winner(g: Game) -> String:
	return _or_dash(g.over.winner) if g.over != null else "?"


## Juega una partida completa solo con bots. Devuelve el id del ganador ("" si falló alguna comprobación).
func _simulate(n: int, seed_value: int, mode: String, levels: Array, plus: bool = false) -> String:
	var rng := Rng.new(seed_value)
	var g := _mk(n, 0, mode, rng, plus)
	var lv := {}
	for i in n:
		lv["b%d" % i] = levels[i % levels.size()]
	var bots := Bots.new(g, lv, rng.next, plus)
	var total := _count(g)
	var now := 0
	var steps := 0
	var first := 0
	while g.over == null:
		steps += 1
		if not _check(steps < 20000, "partida interminable (semilla %d)" % seed_value):
			return ""
		g.tick(now)
		bots.learn()
		var acted := false
		for k in n:
			var id := "b%d" % ((first + k) % n)
			var a := bots.decide(id)
			if a.is_empty():
				continue
			var err := g.act(id, a, now)
			bots.note(id, a, err)
			bots.learn()
			acted = true
			first = (first + k + 1) % n
			break
		if acted:
			now += 400
		else:
			var d := g.next_deadline()
			if g.over != null:
				break   # la partida pudo terminar dentro de tick(): no es un atasco
			if not _check(d >= 0, "partida atascada (semilla %d)" % seed_value):
				return ""
			now = maxi(now + 1, d)
		if not _check(_count(g) == total, "se perdieron o duplicaron cartas (semilla %d)" % seed_value):
			return ""
		if g.over == null:
			var eks := 0
			for c in g.draw:
				eks += 1 if c.type == "exploding" else 0
			if g.prompt != null:
				eks += (1 if g.prompt.has("card") and g.prompt.card.type == "exploding" else 0) + (g.prompt.eks.size() if g.prompt.has("eks") else 0)
			if not _check(eks == g.living().size() - 1, "explosivos en juego != vivos - 1 (semilla %d)" % seed_value):
				return ""
	return g.over.winner


func _test_simulations() -> void:
	print("Simulaciones con IA")
	var games := 0
	for lv: String in ["easy", "normal", "hard"]:
		for s in 150:
			for n in [2, 3, 4, 5]:
				if _simulate(n, s * 31 + n + lv.length() * 1000, "full" if s % 5 == 0 else "official", [lv]) == "":
					return
				games += 1
	_ok("%d partidas completas sin atascos ni cartas perdidas" % games)


func _duel(a: String, b: String, n: int) -> int:
	var w := 0
	for i in n:
		var levels := [a, b] if i % 2 == 1 else [b, a]
		var winner := _simulate(2, 9000 + i, "official", levels)
		if winner == ("b0" if i % 2 == 1 else "b1"):
			w += 1
	return int(round(100.0 * w / n))


func _test_difficulty() -> void:
	print("Dificultades")
	var hn := _duel("hard", "normal", 400)
	var ne := _duel("normal", "easy", 400)
	var he := _duel("hard", "easy", 400)
	print("    difícil vs normal: %d%%   normal vs fácil: %d%%   difícil vs fácil: %d%%" % [hn, ne, he])
	if _check(hn > 52 and ne > 52 and he > 60, "las dificultades no están ordenadas"):
		_ok("la IA difícil vence a la normal, y la normal a la fácil")


# ---------------------------------------------------------------- guardia del clásico
# Graba (con el motor clásico, antes de añadir Plus) una huella de ~40 partidas deterministas:
# acciones de los bots, eventos y, cada GUARD_EVERY pasos, las claves y el contenido de view() de cada jugador.
# La prueba vuelve a jugarlas con plus = false y exige huellas idénticas. Regrabar solo a propósito:
#   godot --headless --path godot -s tests/run_tests.gd -- --record-guard

const GUARD_FILE := "res://tests/classic_guard.json"
const GUARD_EVERY := 7
const GUARD_GAMES := 40


static func _guard_cases() -> Array:
	var mixes := [["easy", "normal", "hard"], ["hard"], ["normal", "hard", "easy"], ["easy"], ["normal"], ["hard", "normal"]]
	var out: Array = []
	for i in GUARD_GAMES:
		out.append({"n": 2 + i % 4, "seed": 4001 + i * 37, "mode": "full" if i % 3 == 0 else "official", "levels": mixes[(i / 4 + i) % mixes.size()]})
	return out


static func _h(s: String) -> String:
	return s.sha256_text()


## Juega una partida con reloj simulado y devuelve sus huellas.
func _guard_play(c: Dictionary) -> Dictionary:
	var n: int = c.n
	var rng := Rng.new(int(c.seed))
	var g := _mk(n, 0, c.mode, rng)
	var lv := {}
	for i in n:
		lv["b%d" % i] = c.levels[i % c.levels.size()]
	var bots := Bots.new(g, lv, rng.next)
	var acts := ""
	var evs := ""
	var views := ""
	var seen := 0
	var now := 0
	var steps := 0
	var first := 0
	while g.over == null and steps < 20000:
		steps += 1
		g.tick(now)
		bots.learn()
		var acted := false
		for k in n:
			var id := "b%d" % ((first + k) % n)
			var a := bots.decide(id)
			if a.is_empty():
				continue
			var err := g.act(id, a, now)
			bots.note(id, a, err)
			bots.learn()
			acts += "%s:%s:%s\n" % [id, JSON.stringify(a, "", true), err]
			acted = true
			first = (first + k + 1) % n
			break
		for e: Dictionary in g.events:
			if e.seq > seen:
				evs += "%d|%s|%s|%s\n" % [e.seq, e.type, e.get("text", ""), e.get("to", "")]
				seen = e.seq
		if steps % GUARD_EVERY == 0:
			for p in g.players:
				var v := g.view(p.id, now)
				var ks: Array = v.keys()
				ks.sort()
				views += p.id + ":" + ",".join(PackedStringArray(ks)) + ":" + JSON.stringify(v, "", true) + "\n"
		if acted:
			now += 400
		else:
			var d := g.next_deadline()
			if d < 0:
				break
			now = maxi(now + 1, d)
	return {"steps": steps, "winner": si_winner(g), "actions": _h(acts), "events": _h(evs), "views": _h(views)}


func _record_guard() -> void:
	var games: Array = []
	for c: Dictionary in _guard_cases():
		var r := _guard_play(c)
		r.merge(c)
		games.append(r)
	var f := FileAccess.open(GUARD_FILE, FileAccess.WRITE)
	if not _check(f != null, "no se pudo escribir " + GUARD_FILE):
		return
	f.store_string(JSON.stringify({"every": GUARD_EVERY, "games": games}, "\t", true))
	f.close()
	print("Guardia del clásico grabada: %d partidas en %s" % [games.size(), GUARD_FILE])


func _test_classic_guard() -> void:
	print("Guardia del clásico")
	var f := FileAccess.open(GUARD_FILE, FileAccess.READ)
	if not _check(f != null, "falta tests/classic_guard.json (grábalo con -- --record-guard)"):
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var cases := _guard_cases()
	if not _check(data.games.size() == cases.size(), "la guardia tiene %d partidas y se esperaban %d" % [data.games.size(), cases.size()]):
		return
	var bad := 0
	for i in cases.size():
		var rec: Dictionary = data.games[i]
		var r := _guard_play(cases[i])
		for k: String in ["steps", "winner", "actions", "events", "views"]:
			if str(r[k]) != (str(int(rec[k])) if k == "steps" else str(rec[k])):
				bad += 1
				printerr("  ✗ guardia: partida %d (n=%d, semilla %d, %s): difiere «%s»" % [i, cases[i].n, cases[i].seed, cases[i].mode, k])
				break
	if _check(bad == 0, "%d partidas del clásico cambiaron respecto a la grabación" % bad):
		_ok("%d partidas del clásico idénticas a la grabación (acciones, eventos y vistas)" % cases.size())


# ---------------------------------------------------------------- Plus (T05): interruptor, vista, sentido, red

func _test_plus_engine() -> void:
	print("Plus: motor")
	var c := _mk(3, 5)
	var v := c.view("b0", 0)
	var extra := true
	for k: String in ["plus", "packs", "dir", "deckTypes", "tops", "shuf", "rules"]:
		extra = extra and not v.has(k)
	_check(extra and not c.plus and c.dir == 1 and c.tops == 0, "clásico: la vista no lleva claves de Plus")
	var g := _mk(4, 5, "official", null, true)
	v = g.view("b0", 0)
	var ok := true
	for k: String in ["plus", "packs", "dir", "deckTypes", "tops", "shuf", "rules", "discard"]:
		ok = _check(v.has(k), "view(plus) debe tener la clave «%s»" % k) and ok
	if ok:
		_check(v.plus == true and v.dir == 1 and v.tops == 0 and v.packs == [] and v.deckTypes.has("zombie") and not v.deckTypes.has("exploding"), "valores iniciales de las claves de Plus")
	_check(g.signature().contains("|d1"), "la firma incluye el sentido solo en Plus")
	# tops: cuenta lo que sale de arriba y vuelve a 0 al barajar
	g.cur = 0
	g.turns_left = 1
	var before := g.draw.size()
	g.tick(0)
	var first := "b%d" % g.cur
	g.act(first, {"a": "draw"}, 0)
	_check(g.draw.size() == before - 1 and g.tops == 1, "tops sube al robar de arriba (tops=%d)" % g.tops)
	g.shuffle_draw()
	_check(g.tops == 0, "tops vuelve a 0 al cambiar shuf")
	# next_living_idx con dir = -1
	var h := _mk(4, 3, "official", null, true)
	_check(h.next_living_idx(0) == 1 and h.next_living_idx(3) == 0, "dir = 1: siguiente vivo hacia delante")
	h.dir = -1
	_check(h.next_living_idx(0) == 3 and h.next_living_idx(2) == 1, "dir = -1: siguiente vivo hacia atrás (con vuelta)")
	h.players[3].alive = false
	_check(h.next_living_idx(0) == 2, "dir = -1 salta a los muertos")
	h.players[2].alive = false
	h.players[1].alive = false
	_check(h.next_living_idx(0) == 0, "dir = -1 sin otros vivos devuelve el mismo asiento")
	# Simulaciones con plus = true sin cartas nuevas: deben terminar sin perder cartas
	var done := 0
	for s_i in 12:
		for n in [2, 3, 4, 5]:
			if _simulate(n, 700 + s_i * 13 + n, "full" if s_i % 3 == 0 else "official", ["easy", "normal", "hard"], true) == "":
				return
			done += 1
	_ok("vista, tops, sentido de juego y %d partidas con plus = true sin cartas nuevas" % done)


## Palancas de ajuste de Plus: rules.hand y rules.crypt_copies (solo con plus = true)
func _test_plus_levers() -> void:
	var f0 := _fails
	var ps: Array = []
	for i in 3:
		ps.append({"id": "b%d" % i, "name": "B%d" % i, "bot": true})
	var mk := func(plus: bool, rules: Dictionary) -> Game:
		return Game.new({"players": ps, "deck_mode": "official", "rng": Rng.new(77), "now": 0, "plus": plus, "packs": ["crypt"], "rules": rules})
	for h: int in [4, 5, 6, 7, 8]:
		var g: Game = mk.call(true, {"hand": h})
		_check(g.players[0].hand.size() == h + 1 and g.players[2].hand.size() == h + 1, "rules.hand = %d reparte %d cartas (+ zombi)" % [h, h + 1])
	_check((mk.call(true, {}) as Game).players[0].hand.size() == 8, "sin rules.hand la mano sigue siendo 7 (+ zombi)")
	_check((mk.call(true, {"hand": 99}) as Game).players[0].hand.size() == 9 and (mk.call(true, {"hand": 1}) as Game).players[0].hand.size() == 5, "rules.hand se limita a 4-8")
	_check((mk.call(false, {"hand": 5}) as Game).players[0].hand.size() == 8, "con plus = false rules.hand se ignora")
	var base: Game = mk.call(true, {})
	var same: Game = mk.call(false, {"hand": 5})
	var cl: Game = Game.new({"players": ps, "deck_mode": "official", "rng": Rng.new(77), "now": 0})
	_check(same.signature() == cl.signature() and base.deck_types.has("bury"), "plus = false con rules sigue idéntico al clásico")
	# crypt_copies (3 jugadores = grupo «sin huella»; base: draw_bottom 2, bury 1, haunt 2)
	_check(_count_type(base, "draw_bottom") == 2 and _count_type(base, "bury") == 1 and _count_type(base, "haunt") == 2, "base: copias de La Cripta sin huella")
	var g2: Game = mk.call(true, {"crypt_copies": {"draw_bottom": [1, 1], "bury": [0, 0], "haunt": [3, 3], "nada": [1, 1], "reverse": [4, 1], "crow_eye": [1]}})
	_check(_count_type(g2, "draw_bottom") == 1 and _count_type(g2, "bury") == 0 and _count_type(g2, "haunt") == 3, "crypt_copies sobrescribe las copias")
	_check(not g2.deck_types.has("bury") and _count_type(g2, "reverse") == 2 and _count_type(g2, "crow_eye") == 1 and not g2.deck_types.has("nada"), "crypt_copies ignora tipos desconocidos y valores fuera de 0-3 o mal formados")
	var g3: Game = mk.call(false, {"crypt_copies": {"draw_bottom": [3, 3]}})
	_check(g3.signature() == cl.signature() and _count_type(g3, "draw_bottom") == 0, "con plus = false crypt_copies se ignora")
	var tot := _count(g2)
	_check(tot == _count(_mk(3, 77, "official", null, true, ["crypt"])) - 2 + 1, "crypt_copies: el total de cartas cuadra")
	if _fails == f0:
		_ok("palancas hand y crypt_copies: límites, sobrescritura e inocuas con plus = false")


## Sala de pruebas: recoge los mensajes en lugar de enviarlos por la red. Se crea al vuelo con load() porque
## las salas usan autoloads (Net, CardDB), que no existen cuando se compila este archivo.
func _test_room() -> Node:
	var sc := GDScript.new()
	sc.source_code = "extends \"res://scripts/net/room_host.gd\"\nvar out: Array = []\nfunc send(peer: int, m: Dictionary) -> void:\n\tout.append([peer, m])\n"
	sc.reload()
	return sc.new()


func _test_plus_network() -> void:
	print("Plus: red")
	_check(preload("res://scripts/autoload/net.gd").PROTO == 3, "Net.PROTO = 3")
	var db: Node = root.get_node("CardDB")
	if db.defs.is_empty():
		db._ready()   # en _initialize los autoloads aún no han recibido _ready
	_check(db.types_for([]).size() == db.types().size() and db.types_for(["crypt"]).size() >= db.types().size() and db.types().size() == 19, "CardDB.types_for([]) == CardDB.types() (19 cartas)")
	# Sala Plus: rechaza hello sin proto (o con proto < 3) y acepta proto 3
	var plus_room = _test_room()
	plus_room.configure(true)
	plus_room.on_msg(7, {"t": "hello", "name": "Viejo", "token": "x1"})
	var rejected: bool = plus_room.out.size() == 1 and plus_room.out[0][1].t == "full" and plus_room.out[0][1].msg == "Esta sala es de Zombie Kittens Plus. Actualiza el juego para entrar."
	_check(rejected and plus_room.players.is_empty(), "sala Plus rechaza hello sin proto con el mensaje del contrato")
	plus_room.out.clear()
	plus_room.on_msg(7, {"t": "hello", "name": "Viejo", "token": "x1", "proto": 2})
	_check(plus_room.out.size() == 1 and plus_room.out[0][1].t == "full" and plus_room.players.is_empty(), "sala Plus rechaza proto 2")
	plus_room.out.clear()
	plus_room.on_msg(7, {"t": "hello", "name": "Nuevo", "token": "x2", "proto": 3})
	_check(plus_room.players.size() == 1 and plus_room.out[0][1].t == "welcome", "sala Plus acepta proto 3")
	var lobby: Dictionary = plus_room.out[1][1]
	_check(lobby.t == "lobby" and lobby.settings.plus == true and lobby.settings.deck_mode == "official" and lobby.settings.packs == [] and lobby.settings.rules == {}, "lobby.settings = {deck_mode, plus, packs, rules}")
	var beacon: Dictionary = plus_room.beacon_info()
	_check(beacon.plus == true and beacon.proto == 3 and beacon.has("name") and beacon.has("players") and beacon.has("started"), "la baliza añade plus y proto y conserva sus claves")
	plus_room.configure(false)
	_check(plus_room.settings.plus == true, "el modo de la sala no cambia una vez creada")
	plus_room.free()
	# Sala clásica: no comprueba proto (clientes 2.x) y sus mensajes conservan las claves de siempre
	var room = _test_room()
	room.on_msg(7, {"t": "hello", "name": "Viejo", "avatar": 1, "token": "y1"})
	_check(room.players.size() == 1 and room.out[0][1].t == "welcome" and room.out[0][1].keys().size() == 3, "sala clásica acepta hello sin proto; welcome intacto")
	var cl: Dictionary = room.out[1][1]
	var keep := true
	for k: String in ["t", "settings", "started", "players"]:
		keep = keep and cl.has(k)
	_check(keep and cl.settings.has("deck_mode") and cl.settings.plus == false and cl.settings.packs == [] and cl.settings.rules == {}, "lobby clásico: claves existentes + plus=false, packs=[], rules={}")
	room.on_msg(1, {"t": "hello", "name": "Anfitrion", "token": "y0", "proto": 3})
	room.on_msg(1, {"t": "settings", "packs": ["crypt"], "rules": {"hand": 9}})
	_check(room.settings.packs == [] and room.settings.rules == {}, "sala clásica rechaza cambiar packs y reglas")
	_check(room.beacon_info().plus == false and room.beacon_info().proto == 3, "baliza clásica: plus=false")
	room.free()
	var cs: Node = load("res://scripts/net/client_session.gd").new()
	_check(not cs.is_plus(), "ClientSession.is_plus() es false sin sala")
	cs.lobby = {"settings": {"plus": true}}
	_check(cs.is_plus(), "ClientSession.is_plus() lee lobby.settings.plus")
	cs.free()
	var lm: Node = load("res://scripts/match/local_match.gd").new()
	lm.start({"rivals": 1, "plus": true, "seed": 3})
	_check(lm.is_plus() and lm.game.plus and lm.bots.plus and lm.view().has("plus"), "LocalMatch con opts.plus = true")
	lm.start({"rivals": 1, "seed": 3})
	_check(not lm.is_plus() and not lm.game.plus and not lm.view().has("plus"), "LocalMatch clásico por defecto")
	lm.free()
	_ok("PROTO, hello/proto, salas Plus y clásica, baliza y sesiones")


# ---------------------------------------------------------------- Plus (T23): La Cripta, cartas 1-5

const CRYPT_1 := ["targeted_attack", "reverse", "draw_bottom", "crow_eye", "apocalypse"]
const CRYPT_2 := ["alter_future", "bury", "soul_swap", "haunt"]

var _clk := 0
var _tid := 0


## Partida Plus con el pack La Cripta, sin cartas en las manos, turno de b0 (para montar cada situación a mano).
func _cg(n: int, seed_value: int = 1) -> Game:
	var g := _mk(n, seed_value, "full", null, true, ["crypt"])
	for p in g.players:
		p.hand.clear()
	g.cur = 0
	g.turns_left = 1
	g.attacked = false
	g.events.clear()
	_clk = 0
	return g


func _card(type: String) -> Game.Card:
	_tid += 1
	return Game.Card.new("t%d" % _tid, type, false)


func _give(g: Game, i: int, type: String) -> Game.Card:
	var c := _card(type)
	g.players[i].hand.append(c)
	return c


func _play(g: Game, who: String, cards: Variant, target: Variant = null) -> String:
	var ids: Array = []
	for c: Game.Card in (cards if cards is Array else [cards]):
		ids.append(c.id)
	return g.act(who, {"a": "play", "cards": ids, "target": target}, _clk)


## Deja pasar la ventana de Nop y lo que venga detrás.
func _resolve(g: Game) -> void:
	_clk += 10000
	g.tick(_clk)


func _evs(g: Game, type: String) -> Array:
	return g.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _in_discard(g: Game, c: Game.Card) -> bool:
	return g.discard.any(func(d: Dictionary) -> bool: return d.card.id == c.id)


func _count_type(g: Game, type: String) -> int:
	var n := 0
	for c in g.draw:
		n += 1 if c.type == type else 0
	for p in g.players:
		for c in p.hand:
			n += 1 if c.type == type else 0
	return n


func _test_crypt_cards_1() -> void:
	print("Plus: La Cripta (cartas 1-5)")
	var f0 := _fails
	_crypt_deal()
	_crypt_targeted_attack()
	_crypt_reverse()
	_crypt_draw_bottom()
	_crypt_crow_eye()
	_crypt_apocalypse()
	_crypt_simulation()
	if _fails == f0:
		_ok("Ataque Dirigido, Marcha Atrás, Robar del Fondo, Ojo de Cuervo y Apocalipsis Zombi: reparto, casos y simulación")


func _crypt_deal() -> void:
	var want := {2: [0, 0, 1, 1, 0], 3: [2, 2, 2, 1, 1], 4: [2, 2, 3, 2, 1], 5: [2, 2, 3, 2, 1]}
	var extra := {2: 4, 3: 13, 4: 17, 5: 17}   # con las cartas 1-9 del pack
	for n: int in [2, 3, 4, 5]:
		var g := _mk(n, 7, "official", null, true, ["crypt"])
		var base := _mk(n, 7, "official", null, true)
		for i in CRYPT_1.size():
			var got := _count_type(g, CRYPT_1[i])
			_check(got == want[n][i], "%d jugadores: %d copias de %s (salieron %d)" % [n, want[n][i], CRYPT_1[i], got])
			_check((got > 0) == g.deck_types.has(CRYPT_1[i]), "%d jugadores: deck_types coherente con %s" % [n, CRYPT_1[i]])
		_check(_count(g) == _count(base) + extra[n], "%d jugadores: %d cartas más que sin pack (hay %d)" % [n, extra[n], _count(g) - _count(base)])
		for t: String in CRYPT_1:
			_check(_count_type(base, t) == 0 and not base.deck_types.has(t), "%d jugadores, plus sin packs: no aparece %s" % [n, t])
		_check(g.view("b0", 0).packs == ["crypt"] and base.view("b0", 0).packs == [], "view.packs refleja los packs activos")


func _crypt_targeted_attack() -> void:
	var g := _cg(4)
	var ta := _give(g, 0, "targeted_attack")
	_check(g.plan("b0", [ta.id]).get("need") == "living_any", "Ataque Dirigido: plan pide objetivo living_any")
	_check(g.view("b0", 0).playable.get(ta.id) == "living_any", "Ataque Dirigido: view.playable devuelve need living_any")
	_check(g.plan("b0", [ta.id], "b0").has("err"), "Ataque Dirigido: no puedes elegirte")
	_check(g.plan("b0", [ta.id], "zz").has("err"), "Ataque Dirigido: objetivo desconocido rechazado")
	g.players[3].alive = false
	_check(g.plan("b0", [ta.id], "b3").has("err"), "Ataque Dirigido: objetivo muerto rechazado")
	g.players[3].alive = true
	_check(g.plan("b0", [ta.id], "b2").get("kind") == "action", "Ataque Dirigido: vale un objetivo vivo sin cartas")
	var tb := _give(g, 1, "targeted_attack")
	_check(g.plan("b1", [tb.id], "b2").has("err"), "Ataque Dirigido: fuera de turno rechazado")
	g.players[0].alive = false
	_check(g.plan("b0", [ta.id], "b2").has("err"), "Ataque Dirigido: un muerto no puede jugarlo")
	g.players[0].alive = true
	_check(_play(g, "b0", ta, "b0") != "" and _play(g, "b0", ta) != "", "Ataque Dirigido: act rechaza objetivo inválido o ausente")
	# caso normal
	_check(_play(g, "b0", ta, "b2") == "", "Ataque Dirigido: se juega")
	_check(_evs(g, "play")[0].text == "B0 juega Ataque Dirigido contra B2.", "Ataque Dirigido: texto del evento play")
	_resolve(g)
	var v := g.view("b1", _clk)
	_check(v.cur == "b2" and v.turnsLeft == 2 and v.attacked, "Ataque Dirigido: cur = objetivo, turnsLeft = 2, attacked")
	var at := _evs(g, "attack")
	_check(at.size() == 1 and at[0].n == 2 and at[0].target == "b2" and at[0].player == "b0" and _in_discard(g, ta), "Ataque Dirigido: evento attack {player, target, n} y carta al descarte")
	# apilado sobre un ataque previo: b2 tiene 2 turnos pendientes y juega otro dirigido contra b3
	var t2 := _give(g, 2, "targeted_attack")
	g.events.clear()
	_check(_play(g, "b2", t2, "b3") == "", "Ataque Dirigido: se juega sobre un ataque")
	_resolve(g)
	_check(g.cur == 3 and g.turns_left == 4 and g.attacked and _evs(g, "attack")[0].n == 4, "Ataque Dirigido apilado: pendientes (2) + 2 = 4")
	# anulada con Nop
	g = _cg(3)
	ta = _give(g, 0, "targeted_attack")
	var nope := _give(g, 1, "nope")
	_play(g, "b0", ta, "b2")
	_check(g.act("b1", {"a": "play", "cards": [nope.id]}, _clk) == "", "Ataque Dirigido: b1 dice Nop")
	_resolve(g)
	_check(g.cur == 0 and g.turns_left == 1 and not g.attacked and _evs(g, "attack").is_empty() and _evs(g, "cancel").size() == 1, "Ataque Dirigido anulado: sin efecto")
	_check(_in_discard(g, ta) and g.players[0].find_id(ta.id) == null, "Ataque Dirigido anulado: la carta se pierde")
	# jugada con Clon
	g = _cg(3)
	g.discard.append({"card": _card("targeted_attack"), "by": "b2"})
	var cl := _give(g, 0, "clone")
	_check(g.plan("b0", [cl.id]).get("need") == "living_any", "Clon de Ataque Dirigido: pide objetivo living_any")
	_check(g.plan("b0", [cl.id], "b0").has("err"), "Clon de Ataque Dirigido: objetivo inválido rechazado")
	_check(_play(g, "b0", cl, "b1") == "", "Clon de Ataque Dirigido: se juega")
	_check(_evs(g, "play")[0].text == "B0 juega Clon (como Ataque Dirigido) contra B1.", "Clon de Ataque Dirigido: texto")
	_resolve(g)
	_check(g.cur == 1 and g.turns_left == 2 and g.attacked, "Clon de Ataque Dirigido: efecto de ataque dirigido")
	# el objetivo muere antes de resolverse
	g = _cg(4)
	ta = _give(g, 0, "targeted_attack")
	_play(g, "b0", ta, "b2")
	g.players[2].alive = false
	_resolve(g)
	_check(g.cur == 3 and g.turns_left == 2 and g.attacked, "Ataque Dirigido: si el objetivo murió, pasa al siguiente vivo")
	g = _cg(4)
	g.dir = -1
	ta = _give(g, 0, "targeted_attack")
	_play(g, "b0", ta, "b2")
	g.players[2].alive = false
	_resolve(g)
	_check(g.cur == 1 and g.turns_left == 2, "Ataque Dirigido: con dir = -1 el siguiente vivo va hacia atrás")
	# si ya no es mi turno al resolverse: nada
	g = _cg(3)
	ta = _give(g, 0, "targeted_attack")
	_play(g, "b0", ta, "b2")
	g.cur = 1
	_resolve(g)
	_check(g.cur == 1 and g.turns_left == 1 and not g.attacked, "Ataque Dirigido: sin efecto si dejó de ser mi turno")
	# en pareja se ignora su texto
	g = _cg(3)
	var pa := _give(g, 0, "targeted_attack")
	var pb := _give(g, 0, "targeted_attack")
	_give(g, 1, "skip")
	_check(_play(g, "b0", [pa, pb], "b1") == "", "Ataque Dirigido en pareja: se juega como combo")
	_resolve(g)
	_check(g.cur == 0 and not g.attacked and g.players[0].hand.size() == 1 and _evs(g, "steal").size() == 1, "Ataque Dirigido en pareja: roba una carta y no ataca")


func _crypt_reverse() -> void:
	var g := _cg(4)
	g.cur = 1
	var r := _give(g, 1, "reverse")
	var r0 := _give(g, 0, "reverse")
	_check(g.plan("b1", [r.id]).get("kind") == "action", "Marcha Atrás: se juega en mi turno sin objetivo")
	_check(g.view("b1", 0).playable.get(r.id) == 1, "Marcha Atrás: view.playable lo marca jugable")
	_check(g.plan("b0", [r0.id]).has("err"), "Marcha Atrás: fuera de turno rechazada")
	g.players[1].alive = false
	_check(g.plan("b1", [r.id]).has("err"), "Marcha Atrás: un muerto no puede jugarla")
	g.players[1].alive = true
	_play(g, "b1", r)
	_resolve(g)
	_check(g.dir == -1 and g.cur == 0 and g.turns_left == 1, "Marcha Atrás con 4 jugadores: si B la juega, el siguiente es A")
	var ev := _evs(g, "reverse")
	_check(ev.size() == 1 and ev[0].dir == -1 and g.next_living_idx(0) == 3, "Marcha Atrás: evento reverse y el orden sigue A→D→C→B")
	_check(g.view("b2", _clk).dir == -1 and g.signature().contains("|d-1"), "Marcha Atrás: view.dir y firma con el sentido nuevo")
	# termina UN turno: si me atacaron solo quita uno
	g = _cg(4)
	g.cur = 1
	g.turns_left = 2
	g.attacked = true
	r = _give(g, 1, "reverse")
	_play(g, "b1", r)
	_resolve(g)
	_check(g.dir == -1 and g.cur == 1 and g.turns_left == 1, "Marcha Atrás atacado: solo termina uno de los dos turnos")
	# anulada con Nop
	g = _cg(4)
	g.cur = 1
	r = _give(g, 1, "reverse")
	var nope := _give(g, 2, "nope")
	_play(g, "b1", r)
	g.act("b2", {"a": "play", "cards": [nope.id]}, _clk)
	_resolve(g)
	_check(g.dir == 1 and g.cur == 1 and _evs(g, "reverse").is_empty() and _in_discard(g, r), "Marcha Atrás anulada: sin efecto y la carta se pierde")
	# con Clon
	g = _cg(4)
	g.cur = 2
	g.discard.append({"card": _card("reverse"), "by": "b0"})
	var cl := _give(g, 2, "clone")
	_check(g.plan("b2", [cl.id]).get("kind") == "action", "Clon de Marcha Atrás: jugable")
	_play(g, "b2", cl)
	_check(_evs(g, "play")[0].text == "B2 juega Clon (como Marcha Atrás).", "Clon de Marcha Atrás: texto")
	_resolve(g)
	_check(g.dir == -1 and g.cur == 1, "Clon de Marcha Atrás: invierte y pasa al anterior")
	# 2 jugadores equivale a Saltar
	g = _cg(2)
	r = _give(g, 0, "reverse")
	_play(g, "b0", r)
	_resolve(g)
	_check(g.cur == 1 and g.dir == -1, "Marcha Atrás con 2 jugadores equivale a Saltar")
	# ya no es mi turno al resolverse
	g = _cg(3)
	r = _give(g, 0, "reverse")
	_play(g, "b0", r)
	g.cur = 2
	_resolve(g)
	_check(g.dir == 1 and g.cur == 2, "Marcha Atrás: sin efecto si dejó de ser mi turno")


func _crypt_draw_bottom() -> void:
	var g := _cg(3)
	var db := _give(g, 0, "draw_bottom")
	var bot := Game.Card.new("d1", "cat_a", false)
	var mid := Game.Card.new("d2", "cat_b", false)
	var top := Game.Card.new("d3", "cat_c", false)
	g.draw.clear()
	g.draw.append_array([bot, mid, top])
	g.tops = 5
	var m0 := g.mut
	_check(g.plan("b0", [db.id]).get("kind") == "action" and g.view("b0", 0).playable.get(db.id) == 1, "Robar del Fondo: jugable sin objetivo")
	_check(g.plan("b1", [_give(g, 1, "draw_bottom").id]).has("err"), "Robar del Fondo: fuera de turno rechazado")
	_play(g, "b0", db)
	_resolve(g)
	_check(g.draw.size() == 2 and g.draw[0] == mid and g.draw[1] == top, "Robar del Fondo: el mazo pierde draw[0]")
	_check(g.players[0].find_id("d1") != null and g.tops == 5 and g.mut == m0 + 1, "Robar del Fondo: la carta va a la mano, no toca tops y mut + 1")
	var d := _evs(g, "draw")
	_check(d.size() == 1 and d[0].player == "b0" and d[0].get("bottom", false) == true, "Robar del Fondo: evento draw con bottom")
	_check(g.cur == 1 and g.turns_left == 1, "Robar del Fondo: termina el turno")
	# explosivo del fondo: se abre la decisión explode
	g = _cg(3)
	db = _give(g, 0, "draw_bottom")
	_give(g, 0, "zombie")
	var ek := Game.Card.new("e1", "exploding", false)
	g.draw.clear()
	g.draw.append_array([ek, mid, top])
	_play(g, "b0", db)
	_resolve(g)
	_check(g.prompt != null and g.prompt.type == "explode" and g.prompt.player == "b0" and g.prompt.card == ek and g.draw.size() == 2, "Robar del Fondo: explosivo abre la decisión explode")
	_check(g.view("b0", _clk).prompt.type == "explode" and g.view("b0", _clk).prompt.mine, "Robar del Fondo: la vista muestra la decisión explode")
	# explosivo sin Zombi: muere
	g = _cg(3)
	db = _give(g, 0, "draw_bottom")
	g.draw.clear()
	g.draw.append_array([ek, mid, top])
	_play(g, "b0", db)
	_resolve(g)
	_check(not g.players[0].alive and g.prompt == null and g.cur == 1, "Robar del Fondo: explosivo sin Zombi mata a quien lo roba")
	# atacado: gasta un turno de los dos
	g = _cg(3)
	g.turns_left = 2
	g.attacked = true
	db = _give(g, 0, "draw_bottom")
	g.draw.clear()
	g.draw.append_array([bot, mid, top])
	_play(g, "b0", db)
	_resolve(g)
	_check(g.cur == 0 and g.turns_left == 1, "Robar del Fondo atacado: roba un turno de los dos")
	# anulada con Nop
	g = _cg(3)
	db = _give(g, 0, "draw_bottom")
	var nope := _give(g, 1, "nope")
	g.draw.clear()
	g.draw.append_array([bot, mid, top])
	_play(g, "b0", db)
	g.act("b1", {"a": "play", "cards": [nope.id]}, _clk)
	_resolve(g)
	_check(g.draw.size() == 3 and g.draw[0] == bot and g.cur == 0 and _in_discard(g, db) and g.players[0].hand.is_empty(), "Robar del Fondo anulado: no roba y la carta se pierde")
	# con Clon
	g = _cg(3)
	g.discard.append({"card": _card("draw_bottom"), "by": "b2"})
	var cl := _give(g, 0, "clone")
	g.draw.clear()
	g.draw.append_array([bot, mid, top])
	_play(g, "b0", cl)
	_resolve(g)
	_check(g.draw.size() == 2 and g.players[0].find_id("d1") != null and g.cur == 1, "Clon de Robar del Fondo: roba del fondo")
	# ya no es mi turno al resolverse
	g = _cg(3)
	db = _give(g, 0, "draw_bottom")
	g.draw.clear()
	g.draw.append_array([bot, mid, top])
	_play(g, "b0", db)
	g.cur = 2
	_resolve(g)
	_check(g.draw.size() == 3 and g.players[0].hand.is_empty(), "Robar del Fondo: sin efecto si dejó de ser mi turno")


func _crypt_crow_eye() -> void:
	var g := _cg(4)
	var ce := _give(g, 0, "crow_eye")
	_give(g, 1, "zombie")
	_give(g, 1, "cat_a")
	_give(g, 3, "skip")
	g.players[3].alive = false
	_check(g.plan("b0", [ce.id]).get("need") == "any_hand" and g.view("b0", 0).playable.get(ce.id) == "any_hand", "Ojo de Cuervo: need any_hand (en plan y en view)")
	_check(g.plan("b0", [ce.id], "b2").has("err"), "Ojo de Cuervo: objetivo sin cartas rechazado")
	_check(g.plan("b0", [ce.id], "b0").has("err"), "Ojo de Cuervo: no puedes mirarte")
	_check(g.plan("b0", [ce.id], "b3").get("kind") == "action", "Ojo de Cuervo: vale un muerto con cartas")
	_check(_play(g, "b0", ce, "b2") != "" and _play(g, "b0", ce) != "", "Ojo de Cuervo: act rechaza objetivo inválido o ausente")
	var tb := _give(g, 1, "crow_eye")
	_check(g.plan("b1", [tb.id], "b0").has("err"), "Ojo de Cuervo: fuera de turno rechazado")
	g.players[1].hand.erase(tb)
	_check(_play(g, "b0", ce, "b1") == "", "Ojo de Cuervo: se juega")
	_check(_evs(g, "play")[0].text == "B0 mira la mano de B1 con Ojo de Cuervo.", "Ojo de Cuervo: texto del evento play")
	_resolve(g)
	var pk := _evs(g, "peek")
	_check(pk.size() == 1 and pk[0].to == "b0" and pk[0].target == "b1" and pk[0].cards == ["zombie", "cat_a"], "Ojo de Cuervo: peek con las cartas correctas, para quien juega")
	var seen := {}
	for p in g.players:
		seen[p.id] = g.view(p.id, _clk).events.filter(func(e: Dictionary) -> bool: return e.type == "peek").size()
	_check(seen == {"b0": 1, "b1": 0, "b2": 0, "b3": 0}, "Ojo de Cuervo: peek SOLO llega a quien juega")
	var pub := _evs(g, "info").filter(func(e: Dictionary) -> bool: return not e.has("to"))
	_check(pub.size() == 1 and pub[0].text == "B0 mira la mano de B1.", "Ojo de Cuervo: info público «X mira la mano de Y»")
	_check(g.cur == 0 and g.turns_left == 1 and _in_discard(g, ce), "Ojo de Cuervo: no termina el turno")
	# mano de un muerto
	var ce2 := _give(g, 0, "crow_eye")
	g.events.clear()
	_play(g, "b0", ce2, "b3")
	_resolve(g)
	_check(_evs(g, "peek").size() == 1 and _evs(g, "peek")[0].cards == ["skip"], "Ojo de Cuervo: mira la mano de un muerto")
	# anulada con Nop
	g = _cg(3)
	ce = _give(g, 0, "crow_eye")
	_give(g, 2, "cat_b")
	var nope := _give(g, 1, "nope")
	_play(g, "b0", ce, "b2")
	g.act("b1", {"a": "play", "cards": [nope.id]}, _clk)
	_resolve(g)
	_check(_evs(g, "peek").is_empty() and _in_discard(g, ce), "Ojo de Cuervo anulado: nadie ve nada y la carta se pierde")
	# con Clon
	g = _cg(3)
	g.discard.append({"card": _card("crow_eye"), "by": "b2"})
	var cl := _give(g, 0, "clone")
	_give(g, 2, "cat_b")
	_check(g.plan("b0", [cl.id]).get("need") == "any_hand", "Clon de Ojo de Cuervo: pide objetivo any_hand")
	_check(g.plan("b0", [cl.id], "b1").has("err"), "Clon de Ojo de Cuervo: objetivo sin cartas rechazado")
	_play(g, "b0", cl, "b2")
	_resolve(g)
	_check(_evs(g, "peek").size() == 1 and _evs(g, "peek")[0].cards == ["cat_b"], "Clon de Ojo de Cuervo: ve la mano")
	# nadie tiene cartas
	g = _cg(3)
	ce = _give(g, 0, "crow_eye")
	_check(g.plan("b0", [ce.id]).has("err"), "Ojo de Cuervo: sin cartas que mirar es un error")


func _crypt_apocalypse() -> void:
	var g := _cg(4)
	var ap := _give(g, 0, "apocalypse")
	var cards: Array[Game.Card] = []
	for i in 12:
		cards.append(Game.Card.new("a%d" % i, "exploding" if i % 4 == 1 else "cat_a", false))
	g.draw.clear()
	g.draw.append_array(cards)
	g.tops = 4
	g.turns_left = 3
	g.attacked = true
	var s0 := g.shuf
	var m0 := g.mut
	var ids0: Array = g.draw.map(func(c: Game.Card) -> String: return c.id)
	ids0.sort()
	_check(g.plan("b0", [ap.id]).get("kind") == "action" and g.view("b0", 0).playable.get(ap.id) == 1, "Apocalipsis: jugable sin objetivo")
	_check(g.plan("b1", [_give(g, 1, "apocalypse").id]).has("err"), "Apocalipsis: fuera de turno rechazado")
	_play(g, "b0", ap)
	_resolve(g)
	var n := g.draw.size()
	var top3 := g.draw[n - 1].type == "exploding" and g.draw[n - 2].type == "exploding" and g.draw[n - 3].type == "exploding"
	_check(n == 12 and top3 and g.draw[n - 4].type != "exploding", "Apocalipsis: los 3 explosivos quedan arriba")
	var ids1: Array = g.draw.map(func(c: Game.Card) -> String: return c.id)
	ids1.sort()
	_check(ids0 == ids1, "Apocalipsis: no se pierde ni se duplica ninguna carta")
	_check(g.shuf == s0 + 1 and g.mut == m0 + 1 and g.tops == 0, "Apocalipsis: shuf + 1, mut + 1 y tops a 0")
	var ev := _evs(g, "apocalypse")
	_check(ev.size() == 1 and ev[0].n == 3 and ev[0].text == "Los 3 explosivos están arriba del mazo.", "Apocalipsis: evento apocalypse {n}")
	_check(g.cur == 1 and g.turns_left == 1 and not g.attacked, "Apocalipsis: termina TODOS los turnos")
	# anulado con Nop
	g = _cg(4)
	ap = _give(g, 0, "apocalypse")
	var nope := _give(g, 2, "nope")
	g.draw.clear()
	g.draw.append_array(cards)
	var order := _ids(g.draw)
	_play(g, "b0", ap)
	g.act("b2", {"a": "play", "cards": [nope.id]}, _clk)
	_resolve(g)
	_check(_ids(g.draw) == order and g.cur == 0 and _evs(g, "apocalypse").is_empty() and _in_discard(g, ap), "Apocalipsis anulado: sin efecto y la carta se pierde")
	# con Clon
	g = _cg(3)
	g.discard.append({"card": _card("apocalypse"), "by": "b1"})
	var cl := _give(g, 0, "clone")
	g.draw.clear()
	g.draw.append_array(cards)
	_play(g, "b0", cl)
	_resolve(g)
	_check(g.draw[g.draw.size() - 1].type == "exploding" and g.cur == 1 and g.shuf == 1, "Clon de Apocalipsis: reordena y termina el turno")
	# ya no es mi turno al resolverse: se baraja pero no se avanza
	g = _cg(4)
	ap = _give(g, 0, "apocalypse")
	g.draw.clear()
	g.draw.append_array(cards)
	_play(g, "b0", ap)
	g.cur = 2
	_resolve(g)
	_check(g.cur == 2 and g.draw[g.draw.size() - 1].type == "exploding", "Apocalipsis: si dejó de ser mi turno, reordena pero no avanza")
	# sin explosivos
	g = _cg(3)
	ap = _give(g, 0, "apocalypse")
	g.draw.clear()
	g.draw.append_array([Game.Card.new("z1", "cat_a", false), Game.Card.new("z2", "cat_b", false)])
	_play(g, "b0", ap)
	_resolve(g)
	_check(_evs(g, "apocalypse")[0].n == 0 and g.draw.size() == 2 and g.cur == 1, "Apocalipsis sin explosivos en el mazo: n = 0")


## Simulación: bots (que aún no conocen las cartas nuevas) + un «jugador de pruebas» que juega al azar las cartas nuevas.
func _crypt_sim_game(n: int, seed_value: int, mode: String, levels: Array, stats: Dictionary) -> String:
	var rng := Rng.new(seed_value)
	var g := _mk(n, 0, mode, rng, true, ["crypt"])
	var tp := Rng.new(seed_value * 7 + 1)
	var lv := {}
	for i in n:
		lv["b%d" % i] = levels[i % levels.size()]
	var bots := Bots.new(g, lv, rng.next, true)
	var total := _count(g)
	var now := 0
	var steps := 0
	var first := 0
	while g.over == null:
		steps += 1
		if not _check(steps < 20000, "partida interminable con La Cripta (semilla %d)" % seed_value):
			return ""
		g.tick(now)
		bots.learn()
		var acted := false
		var c := g.cur_p()
		# decisiones alter / bury: a veces se responde (a veces mal), a veces se deja vencer el plazo
		if g.prompt != null and (g.prompt.type == "alter" or g.prompt.type == "bury"):
			var pr: Dictionary = g.prompt
			var r := tp.next()
			var who: String = pr.player
			if pr.type == "alter":
				var m: int = pr.cards.size()
				var order: Array = []
				for i in m:
					order.append(i)
				if r < 0.5:
					for i in range(m - 1, 0, -1):
						var j := int(tp.next() * (i + 1))
						var t: Variant = order[i]
						order[i] = order[j]
						order[j] = t
					if _check(g.act(who, {"a": "reorder", "order": order}, now) == "", "reorder válido rechazado (semilla %d)" % seed_value):
						stats["resp_alter"] = int(stats.get("resp_alter", 0)) + 1
						acted = true
				elif r < 0.6:
					var before := g.signature()
					_check(g.act(who, {"a": "reorder", "order": order + [m]}, now) != "" and g.signature() == before, "reorder inválido aceptado (semilla %d)" % seed_value)
			else:
				if r < 0.5:
					var pos := int(tp.next() * (g.draw.size() + 1))
					if _check(g.act(who, {"a": "bury", "pos": pos}, now) == "", "bury válido rechazado (semilla %d)" % seed_value):
						stats["resp_bury"] = int(stats.get("resp_bury", 0)) + 1
						acted = true
				elif r < 0.6:
					var before2 := g.signature()
					_check(g.act(who, {"a": "bury", "pos": g.draw.size() + 1}, now) != "" and g.signature() == before2, "bury inválido aceptado (semilla %d)" % seed_value)
		# jugadores muertos que espantan
		if not acted and g.over == null and tp.next() < 0.3:
			for dp in g.players:
				var hc: Game.Card = dp.find_type("haunt") if not dp.alive else null
				if hc == null:
					continue
				var plh := g.plan(dp.id, [hc.id])
				if plh.has("err"):
					continue
				var cands: Array = g.players.filter(func(o: Game.Player) -> bool: return o.alive and o.hand.size() > 0)
				if cands.is_empty():
					continue
				var errh := g.act(dp.id, {"a": "play", "cards": [hc.id], "target": cands[int(tp.next() * cands.size())].id}, now)
				if _check(errh == "", "el muerto no pudo espantar: %s" % errh):
					stats["dead_haunt"] = int(stats.get("dead_haunt", 0)) + 1
					stats["haunt"] = int(stats.get("haunt", 0)) + 1
					acted = true
				break
		if not acted and c.alive and g.idle() and tp.next() < 0.4:
			var opts: Array = c.hand.filter(func(x: Game.Card) -> bool: return x.type == "clone" or CRYPT_1.has(x.type) or CRYPT_2.has(x.type))
			if not opts.is_empty():
				var card: Game.Card = opts[int(tp.next() * opts.size())]
				var pl := g.plan(c.id, [card.id])
				if not pl.has("err"):
					var target: Variant = null
					if pl.has("need"):
						var cand: Array = g.players.filter(func(o: Game.Player) -> bool:
							if o.id == c.id:
								return false
							if pl.need == "living_any":
								return o.alive
							if pl.need == "any_hand":
								return o.hand.size() > 0
							if pl.need == "dead":
								return not o.alive
							if pl.need == "dead_hand":
								return not o.alive and o.hand.size() > 0
							return o.alive and o.hand.size() > 0)
						if not cand.is_empty():
							target = cand[int(tp.next() * cand.size())].id
					if not pl.has("need") or target != null:
						var err := g.act(c.id, {"a": "play", "cards": [card.id], "target": target}, now)
						if _check(err == "", "el jugador de pruebas no pudo jugar %s: %s" % [pl.eff, err]):
							stats[pl.eff] = int(stats.get(pl.eff, 0)) + 1
							acted = true
		# decisión alter/bury sin responder: el jugador de pruebas deja vencer el plazo (los bots ya sabrían contestar)
		var hold: bool = g.prompt != null and (g.prompt.type == "alter" or g.prompt.type == "bury")
		if not acted and not hold:
			for k in n:
				var id := "b%d" % ((first + k) % n)
				var a := bots.decide(id)
				if a.is_empty():
					continue
				var err2 := g.act(id, a, now)
				bots.note(id, a, err2)
				bots.learn()
				acted = true
				first = (first + k + 1) % n
				break
		if acted:
			now += 400
		else:
			var d := g.next_deadline()
			if g.over != null:
				break   # la partida pudo terminar al resolverse una jugada en tick()
			if g.prompt != null and (g.prompt.type == "alter" or g.prompt.type == "bury"):
				stats["exp_" + g.prompt.type] = int(stats.get("exp_" + g.prompt.type, 0)) + 1
			if not _check(d >= 0, "partida atascada con La Cripta (semilla %d)" % seed_value):
				return ""
			now = maxi(now + 1, d)
		if not _check(_count(g) == total, "se perdieron o duplicaron cartas con La Cripta (semilla %d)" % seed_value):
			return ""
		if steps % 5 == 0:
			for p in g.players:
				for e: Dictionary in g.view(p.id, now).events:
					if (e.type == "peek" or e.type == "buried" or e.type == "future") and e.get("to", "") != p.id:
						_check(false, "un evento privado llegó a quien no debía (semilla %d)" % seed_value)
						return ""
				var vp: Variant = g.view(p.id, now).prompt
				if vp != null and (vp.type == "alter" or vp.type == "bury") and not vp.mine and (vp.has("cards") or vp.has("card")):
					_check(false, "la decisión oculta se filtró a otro jugador (semilla %d)" % seed_value)
					return ""
		if g.over == null:
			var eks := 0
			for x in g.draw:
				eks += 1 if x.type == "exploding" else 0
			if g.prompt != null:
				eks += (1 if g.prompt.has("card") and g.prompt.card.type == "exploding" else 0) + (g.prompt.eks.size() if g.prompt.has("eks") else 0)
			if not _check(eks == g.living().size() - 1, "explosivos en juego != vivos - 1 con La Cripta (semilla %d)" % seed_value):
				return ""
	return g.over.winner


func _crypt_simulation() -> void:
	var stats := {}
	var games := 0
	for s in 110:
		for n in [2, 3, 4, 5]:
			if _crypt_sim_game(n, 5000 + s * 29 + n, "full" if s % 4 == 0 else "official", [["easy", "normal", "hard"], ["hard"], ["normal", "easy"]][s % 3], stats) == "":
				return
			games += 1
	var played := true
	for t: String in CRYPT_1 + CRYPT_2:
		played = _check(int(stats.get(t, 0)) > 0, "la simulación nunca jugó %s" % t) and played
	for k: String in ["resp_alter", "resp_bury", "exp_alter", "exp_bury", "dead_haunt"]:
		played = _check(int(stats.get(k, 0)) > 0, "la simulación nunca ejerció %s" % k) and played
	if played:
		print("    %d partidas con La Cripta sin atascos ni cartas perdidas; jugadas de prueba: %s" % [games, stats])


# ---------------------------------------------------------------- La Cripta, cartas 6-9 (+ arreglo del Ataque Dirigido)

## Sustituye el mazo: types[0] = fondo … types.back() = arriba. Ids x0, x1…
func _setdraw(g: Game, types: Array) -> Array[Game.Card]:
	var out: Array[Game.Card] = []
	for i in types.size():
		out.append(Game.Card.new("x%d" % i, types[i], false))
	g.draw.clear()
	g.draw.append_array(out)
	return out


func _public_info(g: Game) -> Array:
	return _evs(g, "info").filter(func(e: Dictionary) -> bool: return not e.has("to"))


func _test_crypt_cards_2() -> void:
	print("Plus: La Cripta (cartas 6-9)")
	var f0 := _fails
	_crypt2_deal()
	_crypt_alter_future()
	_crypt_bury()
	_crypt_soul_swap()
	_crypt_haunt()
	_crypt_targeted_attack_self()
	if _fails == f0:
		_ok("Alterar el Futuro, Entierro, Trueque de Almas, Espanto y el arreglo del Ataque Dirigido: reparto, casos y contadores")


func _crypt2_deal() -> void:
	var want := {2: [1, 1, 0, 0], 3: [1, 1, 1, 2], 4: [2, 2, 1, 2], 5: [2, 2, 1, 2]}
	var extra := {2: 4, 3: 13, 4: 17, 5: 17}
	var kinds := {2: 4, 3: 9, 4: 9, 5: 9}
	for n: int in [2, 3, 4, 5]:
		var g := _mk(n, 7, "official", null, true, ["crypt"])
		var base := _mk(n, 7, "official", null, true)
		for i in CRYPT_2.size():
			var got := _count_type(g, CRYPT_2[i])
			_check(got == want[n][i], "%d jugadores: %d copias de %s (salieron %d)" % [n, want[n][i], CRYPT_2[i], got])
			_check((got > 0) == g.deck_types.has(CRYPT_2[i]), "%d jugadores: deck_types coherente con %s" % [n, CRYPT_2[i]])
			_check(_count_type(base, CRYPT_2[i]) == 0 and not base.deck_types.has(CRYPT_2[i]), "%d jugadores, plus sin packs: no aparece %s" % [n, CRYPT_2[i]])
		_check(_count(g) == _count(base) + extra[n], "%d jugadores: %d cartas más que sin pack con las cartas 1-9 (hay %d)" % [n, extra[n], _count(g) - _count(base)])
		var nt := 0
		for t: String in CRYPT_1 + CRYPT_2:
			nt += 1 if g.deck_types.has(t) else 0
		_check(nt == kinds[n], "%d jugadores: %d tipos nuevos en deck_types (hay %d)" % [n, kinds[n], nt])


# ---- Alterar el Futuro

func _crypt_alter_future() -> void:
	var g := _cg(4)
	var al := _give(g, 0, "alter_future")
	var cs := _setdraw(g, ["cat_a", "cat_b", "super_skip", "see_future", "dig_deeper"])
	g.tops = 3
	_check(g.plan("b0", [al.id]).get("kind") == "action" and g.view("b0", 0).playable.get(al.id) == 1, "Alterar el Futuro: jugable sin objetivo")
	var ob := _give(g, 1, "alter_future")
	_check(g.plan("b1", [ob.id]).has("err"), "Alterar el Futuro: fuera de turno rechazado")
	g.players[1].hand.clear()
	_check(_play(g, "b0", al) == "", "Alterar el Futuro: se juega")
	_check(_evs(g, "play")[0].text == "B0 juega Alterar el Futuro (3x).", "Alterar el Futuro: texto del evento play")
	_resolve(g)
	var pr: Variant = g.prompt
	_check(pr != null and pr.type == "alter" and pr.player == "b0" and pr.cards.size() == 3 and pr.cards[0] == cs[4] and pr.cards[1] == cs[3] and pr.cards[2] == cs[2], "Alterar el Futuro: abre la decisión con las 3 de arriba (la primera es la próxima)")
	_check(g.draw.size() == 5 and g.cur == 0 and _in_discard(g, al), "Alterar el Futuro: las cartas siguen en el mazo y la carta jugada va al descarte")
	var v0 := g.view("b0", _clk)
	var v1 := g.view("b1", _clk)
	_check(v0.prompt.type == "alter" and v0.prompt.mine and v0.prompt.player == "b0" and v0.prompt.cards == ["dig_deeper", "see_future", "super_skip"], "Alterar el Futuro: quien decide ve los tipos")
	_check(v1.prompt.type == "alter" and not v1.prompt.mine and v1.prompt.player == "b0" and not v1.prompt.has("cards") and not v1.prompt.has("card") and v1.prompt.remain > 0 and v1.prompt.total == 40000, "Alterar el Futuro: los demás solo ven quién decide y el tiempo")
	_check(g.next_deadline() == pr.deadline, "Alterar el Futuro: next_deadline es el plazo de la decisión")
	# estados y argumentos inválidos
	var sig := g.signature()
	var ids := _ids(g.draw)
	var bad: Array = [[0, 1], [0, 1, 2, 3], [0, 0, 1], [0, 1, 3], [-1, 0, 1], [0, 1, "2"], [0.5, 1, 2], [0, 1, null], null, "012", {}, [true, 0, 1], []]
	var all_bad := true
	for o: Variant in bad:
		all_bad = all_bad and g.act("b0", {"a": "reorder", "order": o}, _clk) != ""
	all_bad = all_bad and g.act("b0", {"a": "reorder"}, _clk) != ""
	_check(all_bad and g.prompt == pr and g.signature() == sig and _ids(g.draw) == ids, "Alterar el Futuro: órdenes inválidos rechazados sin cambiar nada")
	_check(g.act("b1", {"a": "reorder", "order": [0, 1, 2]}, _clk) != "" and g.act("b0", {"a": "bury", "pos": 0}, _clk) != "" and g.act("b0", {"a": "draw"}, _clk) != "", "Alterar el Futuro: otro jugador, otra acción o robar son rechazados")
	var hc := _give(g, 0, "skip")
	_check(g.plan("b0", [hc.id]).has("err") and g.act("b0", {"a": "pass"}, _clk) != "", "Alterar el Futuro: mientras decide no se puede jugar otra carta")
	g.players[0].hand.clear()
	# respuesta válida
	var m0 := g.mut
	var s0 := g.shuf
	g.events.clear()
	_check(g.act("b0", {"a": "reorder", "order": [2, 0, 1]}, _clk) == "", "Alterar el Futuro: reorder [2, 0, 1] aceptado")
	_check(g.draw[4] == cs[2] and g.draw[3] == cs[4] and g.draw[2] == cs[3] and g.draw[1] == cs[1] and g.draw[0] == cs[0], "Alterar el Futuro: order[0] pasa a ser la próxima carta y el resto del mazo no cambia")
	_check(g.prompt == null and g.mut == m0 + 1 and g.shuf == s0 + 1 and g.tops == 0, "Alterar el Futuro: mut + 1, shuf + 1, tops a 0")
	_check(g.cur == 0 and g.turns_left == 1 and not g.attacked, "Alterar el Futuro: NO termina el turno")
	var fu := _evs(g, "future")
	_check(fu.size() == 1 and fu[0].to == "b0" and fu[0].cards == ["super_skip", "dig_deeper", "see_future"] and fu[0].mut == g.mut and fu[0].shuf == g.shuf and fu[0].len == 5 and fu[0].tops == 0, "Alterar el Futuro: evento future privado con el orden nuevo y tops")
	var pub := _public_info(g)
	_check(pub.size() == 1 and pub[0].text == "B0 reordena el futuro.", "Alterar el Futuro: info público «X reordena el futuro.»")
	_check(g.view("b1", _clk).events.filter(func(e: Dictionary) -> bool: return e.type == "future").is_empty() and g.view("b1", _clk).tops == 0 and g.view("b1", _clk).shuf == s0 + 1, "Alterar el Futuro: el future no llega a otros y view.tops/shuf reflejan los contadores")
	# mismos campos que Ver el Futuro
	var sf := _give(g, 0, "see_future")
	g.events.clear()
	_play(g, "b0", sf)
	_resolve(g)
	var k1: Array = fu[0].keys()
	var k2: Array = _evs(g, "future")[0].keys()
	k1.sort()
	k2.sort()
	_check(k1 == k2, "Alterar el Futuro: el future lleva los mismos campos que el de Ver el Futuro")
	_check(_evs(g, "future")[0].cards == ["super_skip", "dig_deeper", "see_future"], "Ver el Futuro tras alterar: ve el orden nuevo")
	# order con números reales (como llega por JSON)
	g = _cg(3)
	al = _give(g, 0, "alter_future")
	cs = _setdraw(g, ["cat_a", "cat_b", "cat_c"])
	_play(g, "b0", al)
	_resolve(g)
	_check(g.act("b0", {"a": "reorder", "order": [1.0, 2.0, 0.0]}, _clk) == "" and g.draw[2] == cs[1] and g.draw[1] == cs[0] and g.draw[0] == cs[2], "Alterar el Futuro: acepta índices enteros en coma flotante")
	# anulada con Nop
	g = _cg(3)
	al = _give(g, 0, "alter_future")
	var nope := _give(g, 1, "nope")
	_setdraw(g, ["cat_a", "cat_b", "cat_c"])
	ids = _ids(g.draw)
	_play(g, "b0", al)
	g.act("b1", {"a": "play", "cards": [nope.id]}, _clk)
	_resolve(g)
	_check(g.prompt == null and _ids(g.draw) == ids and g.shuf == 0 and _in_discard(g, al) and _evs(g, "cancel").size() == 1, "Alterar el Futuro anulado: sin decisión, sin cambios y la carta se pierde")
	# con Clon
	g = _cg(3)
	g.discard.append({"card": _card("alter_future"), "by": "b2"})
	var cl := _give(g, 0, "clone")
	_setdraw(g, ["cat_a", "cat_b", "cat_c"])
	_check(g.plan("b0", [cl.id]).get("kind") == "action", "Clon de Alterar el Futuro: jugable sin objetivo")
	_play(g, "b0", cl)
	_check(_evs(g, "play")[0].text == "B0 juega Clon (como Alterar el Futuro (3x)).", "Clon de Alterar el Futuro: texto")
	_resolve(g)
	_check(g.prompt != null and g.prompt.type == "alter" and g.prompt.cards.size() == 3, "Clon de Alterar el Futuro: abre la decisión")
	# sin efecto si dejó de ser mi turno
	g = _cg(3)
	al = _give(g, 0, "alter_future")
	_setdraw(g, ["cat_a", "cat_b", "cat_c"])
	_play(g, "b0", al)
	g.cur = 2
	_resolve(g)
	_check(g.prompt == null, "Alterar el Futuro: sin efecto si dejó de ser mi turno")
	# menos de 3 cartas
	g = _cg(3)
	al = _give(g, 0, "alter_future")
	cs = _setdraw(g, ["cat_a", "cat_b"])
	_play(g, "b0", al)
	_resolve(g)
	_check(g.prompt != null and g.prompt.cards.size() == 2 and g.act("b0", {"a": "reorder", "order": [0, 1, 2]}, _clk) != "" and g.act("b0", {"a": "reorder", "order": [0]}, _clk) != "", "Alterar el Futuro con 2 cartas: la permutación es de 2")
	_check(g.act("b0", {"a": "reorder", "order": [1, 0]}, _clk) == "" and g.draw[1] == cs[0] and g.draw[0] == cs[1], "Alterar el Futuro con 2 cartas: reordena")
	g = _cg(3)
	al = _give(g, 0, "alter_future")
	cs = _setdraw(g, ["cat_a"])
	_play(g, "b0", al)
	_resolve(g)
	_check(g.prompt != null and g.prompt.cards.size() == 1 and g.act("b0", {"a": "reorder", "order": [0]}, _clk) == "" and g.draw[0] == cs[0], "Alterar el Futuro con 1 carta: decisión de tamaño 1")
	g = _cg(3)
	al = _give(g, 0, "alter_future")
	_setdraw(g, [])
	_play(g, "b0", al)
	_resolve(g)
	_check(g.prompt == null and g.cur == 0 and _evs(g, "info").size() == 1, "Alterar el Futuro con el mazo vacío: no hace nada y no deja la partida atascada")
	# plazo vencido: se deja el orden original
	g = _cg(3)
	g.players[0].bot = false
	al = _give(g, 0, "alter_future")
	cs = _setdraw(g, ["cat_a", "cat_b", "cat_c", "cat_d"])
	_play(g, "b0", al)
	_resolve(g)
	var dl: int = g.prompt.deadline
	_check(g.next_deadline() == dl, "Alterar el Futuro: el plazo cuenta (next_deadline)")
	g.set_connected("b0", false, _clk)
	_check(g.prompt.deadline <= _clk + int(g.cfg["GONE_MS"]) and g.prompt.deadline < dl, "Alterar el Futuro: set_connected acorta el plazo si quien decide se desconecta")
	g.set_connected("b0", true, _clk)
	g.events.clear()
	m0 = g.mut
	g.tick(g.prompt.deadline - 1)
	_check(g.prompt != null, "Alterar el Futuro: antes del plazo sigue esperando")
	g.tick(g.prompt.deadline)
	_check(g.prompt == null and g.draw[3] == cs[3] and g.draw[2] == cs[2] and g.draw[1] == cs[1] and g.draw[0] == cs[0], "Alterar el Futuro: plazo vencido deja el orden original")
	_check(g.cur == 0 and g.turns_left == 1 and g.mut == m0 + 1 and _evs(g, "future").size() == 1 and _evs(g, "future")[0].cards == ["cat_d", "cat_c", "cat_b"], "Alterar el Futuro: plazo vencido no termina el turno y emite el future")


# ---- Entierro

func _bury_game(n: int, types: Array) -> Game:
	var g := _cg(n)
	var by := _give(g, 0, "bury")
	_setdraw(g, types)
	_play(g, "b0", by)
	_resolve(g)
	return g


func _crypt_bury() -> void:
	var g := _cg(4)
	var by := _give(g, 0, "bury")
	var cs := _setdraw(g, ["cat_a", "cat_b", "cat_c", "cat_d", "super_skip"])
	g.tops = 7
	var m0 := g.mut
	_check(g.plan("b0", [by.id]).get("kind") == "action" and g.view("b0", 0).playable.get(by.id) == 1, "Entierro: jugable sin objetivo")
	var ob := _give(g, 1, "bury")
	_check(g.plan("b1", [ob.id]).has("err"), "Entierro: fuera de turno rechazado")
	g.players[1].hand.clear()
	_play(g, "b0", by)
	_check(_evs(g, "play")[0].text == "B0 juega Entierro.", "Entierro: texto del evento play")
	_resolve(g)
	var pr: Variant = g.prompt
	_check(pr != null and pr.type == "bury" and pr.player == "b0" and pr.card == cs[4] and g.draw.size() == 4 and g.draw[3] == cs[3], "Entierro: la carta de arriba sale del mazo y abre la decisión")
	_check(g.mut == m0 + 1 and g.tops == 8 and g.players[0].hand.is_empty() and _in_discard(g, by), "Entierro: mut + 1, tops + 1 y la carta no entra en la mano")
	var v0 := g.view("b0", _clk)
	var v1 := g.view("b1", _clk)
	_check(v0.prompt.type == "bury" and v0.prompt.mine and v0.prompt.card == "super_skip", "Entierro: quien decide ve la carta")
	_check(v1.prompt.type == "bury" and not v1.prompt.mine and v1.prompt.player == "b0" and not v1.prompt.has("card") and not v1.prompt.has("cards") and v1.prompt.remain > 0, "Entierro: los demás solo ven quién decide y el tiempo")
	_check(g.next_deadline() == pr.deadline and g.draw.size() == 4, "Entierro: next_deadline es el plazo de la decisión")
	# argumentos inválidos
	var sig := g.signature()
	var all_bad := true
	for pos: Variant in [-1, 5, 1.5, "1", null, true, [0], 4.001, {}]:
		all_bad = all_bad and g.act("b0", {"a": "bury", "pos": pos}, _clk) != ""
	all_bad = all_bad and g.act("b0", {"a": "bury"}, _clk) != ""
	_check(all_bad and g.prompt == pr and g.signature() == sig and g.draw.size() == 4, "Entierro: posiciones inválidas rechazadas sin cambiar nada")
	_check(g.act("b1", {"a": "bury", "pos": 0}, _clk) != "" and g.act("b0", {"a": "reorder", "order": [0]}, _clk) != "" and g.act("b0", {"a": "draw"}, _clk) != "", "Entierro: otro jugador, otra acción o robar son rechazados")
	# posiciones válidas: 0 = arriba … 4 = fondo
	for pos: int in [0, 2, 4]:
		g = _bury_game(4, ["cat_a", "cat_b", "cat_c", "cat_d", "super_skip"])
		var bc: Game.Card = g.prompt.card
		g.tops = 7
		m0 = g.mut
		var s0 := g.shuf
		g.events.clear()
		_check(g.act("b0", {"a": "bury", "pos": pos}, _clk) == "", "Entierro: pos %d aceptada" % pos)
		_check(g.draw.size() == 5 and g.draw[4 - pos] == bc, "Entierro: pos %d deja la carta con %d cartas encima" % [pos, pos])
		var rest := g.draw.filter(func(c: Game.Card) -> bool: return c != bc)
		_check(_ids(rest) == "x0,x1,x2,x3", "Entierro: el resto del mazo conserva el orden (pos %d)" % pos)
		_check(g.mut == m0 + 1 and g.shuf == s0 + 1 and g.tops == 0 and g.prompt == null, "Entierro: mut + 1, shuf + 1, tops a 0 (pos %d)" % pos)
		var bu := _evs(g, "buried")
		_check(bu.size() == 1 and bu[0].to == "b0" and bu[0].pos == pos and bu[0].len == 5, "Entierro: evento buried privado {pos, len} (pos %d)" % pos)
		var pub := _public_info(g)
		_check(pub.size() == 1 and pub[0].text == "B0 entierra una carta en el mazo.", "Entierro: info público «X entierra una carta en el mazo.»")
		_check(g.cur == 1 and g.turns_left == 1, "Entierro: termina el turno (pos %d)" % pos)
		var seen := 0
		for o in ["b1", "b2", "b3"]:
			seen += g.view(o, _clk).events.filter(func(e: Dictionary) -> bool: return e.type == "buried").size()
		_check(seen == 0 and g.view("b0", _clk).events.filter(func(e: Dictionary) -> bool: return e.type == "buried").size() == 1, "Entierro: buried solo lo ve quien entierra")
		_check(g.view("b2", _clk).tops == 0 and g.view("b2", _clk).shuf == s0 + 1, "Entierro: view.tops/shuf reflejan los contadores")
	# un explosivo NO explota: se entierra
	for with_zombie: bool in [true, false]:
		g = _cg(3)
		by = _give(g, 0, "bury")
		if with_zombie:
			_give(g, 0, "zombie")
		var ek := Game.Card.new("e1", "exploding", false)
		g.draw.clear()
		g.draw.append_array([Game.Card.new("d0", "cat_a", false), ek])
		var total := _count(g)
		_play(g, "b0", by)
		_resolve(g)
		_check(g.prompt != null and g.prompt.type == "bury" and g.prompt.card == ek and g.players[0].alive and _evs(g, "boom").is_empty() and _evs(g, "died").is_empty(), "Entierro con explosivo (zombi: %s): no explota" % with_zombie)
		_check(g.view("b0", _clk).prompt.card == "exploding" and not g.view("b1", _clk).prompt.has("card"), "Entierro con explosivo: solo quien entierra ve qué es")
		_check(_count(g) == total and g.act("b0", {"a": "bury", "pos": 1}, _clk) == "" and g.draw[0] == ek and g.draw.size() == 2, "Entierro con explosivo: lo entierra en el fondo sin perder cartas")
		_check(g.players[0].alive and g.cur == 1 and _count(g) == total, "Entierro con explosivo: sigue vivo y pasa el turno")
	# anulado con Nop
	g = _cg(3)
	by = _give(g, 0, "bury")
	var nope := _give(g, 1, "nope")
	_setdraw(g, ["cat_a", "cat_b", "cat_c"])
	var ids := _ids(g.draw)
	g.tops = 4
	_play(g, "b0", by)
	g.act("b1", {"a": "play", "cards": [nope.id]}, _clk)
	_resolve(g)
	_check(g.prompt == null and _ids(g.draw) == ids and g.tops == 4 and g.cur == 0 and _in_discard(g, by), "Entierro anulado: no saca ninguna carta, no termina el turno y la carta se pierde")
	# con Clon
	g = _cg(3)
	g.discard.append({"card": _card("bury"), "by": "b2"})
	var cl := _give(g, 0, "clone")
	_setdraw(g, ["cat_a", "cat_b", "cat_c"])
	_play(g, "b0", cl)
	_check(_evs(g, "play")[0].text == "B0 juega Clon (como Entierro).", "Clon de Entierro: texto")
	_resolve(g)
	_check(g.prompt != null and g.prompt.type == "bury" and g.prompt.card.type == "cat_c", "Clon de Entierro: abre la decisión")
	# sin efecto si dejó de ser mi turno
	g = _cg(3)
	by = _give(g, 0, "bury")
	_setdraw(g, ["cat_a", "cat_b", "cat_c"])
	_play(g, "b0", by)
	g.cur = 2
	_resolve(g)
	_check(g.prompt == null and g.draw.size() == 3, "Entierro: sin efecto si dejó de ser mi turno")
	# atacado: gasta un turno de los pendientes
	g = _cg(3)
	g.turns_left = 2
	g.attacked = true
	by = _give(g, 0, "bury")
	_setdraw(g, ["cat_a", "cat_b", "cat_c"])
	_play(g, "b0", by)
	_resolve(g)
	g.act("b0", {"a": "bury", "pos": 1}, _clk)
	_check(g.cur == 0 and g.turns_left == 1, "Entierro atacado: gasta un turno de los dos")
	# mazo de una sola carta: tras sacarla solo cabe la posición 0
	g = _bury_game(3, ["cat_a"])
	_check(g.prompt != null and g.draw.is_empty() and g.act("b0", {"a": "bury", "pos": 1}, _clk) != "" and g.act("b0", {"a": "bury", "pos": 0}, _clk) == "" and g.draw.size() == 1, "Entierro con 1 carta en el mazo: solo vale pos 0")
	# mazo vacío
	g = _cg(3)
	by = _give(g, 0, "bury")
	_setdraw(g, [])
	_play(g, "b0", by)
	_resolve(g)
	_check(g.prompt == null and g.cur == 0, "Entierro con el mazo vacío: no hace nada y no deja la partida atascada")
	# plazo vencido: posición al azar con rnd
	for pair: Array in [[0.0, 0], [0.999, 2], [0.5, 1]]:
		g = _bury_game(3, ["cat_a", "cat_b", "cat_c"])
		g.players[0].bot = false
		var bc2: Game.Card = g.prompt.card
		var dl: int = g.prompt.deadline
		g.set_connected("b0", false, _clk)
		_check(g.prompt.deadline < dl and g.next_deadline() == g.prompt.deadline, "Entierro: set_connected acorta el plazo si quien decide se desconecta")
		g.set_connected("b0", true, _clk)
		g.prompt.deadline = dl
		g.rnd = func() -> float: return pair[0]
		g.events.clear()
		g.tick(dl - 1)
		_check(g.prompt != null, "Entierro: antes del plazo sigue esperando")
		g.tick(dl)
		_check(g.prompt == null and g.draw.size() == 3 and g.draw[2 - int(pair[1])] == bc2, "Entierro: plazo vencido entierra en una posición al azar (rnd %s → pos %d)" % [pair[0], pair[1]])
		_check(g.cur == 1 and _evs(g, "buried").size() == 1 and _evs(g, "buried")[0].pos == pair[1], "Entierro: plazo vencido termina el turno y emite buried")


# ---- Trueque de Almas

func _crypt_soul_swap() -> void:
	var g := _cg(4)
	var ss := _give(g, 0, "soul_swap")
	var keep := _give(g, 0, "cat_a")
	var z := _give(g, 1, "zombie")
	var sk := _give(g, 1, "skip")
	var cb := _give(g, 1, "cat_b")
	g.players[1].alive = false
	_give(g, 2, "cat_c")
	g.players[3].alive = false
	_check(g.plan("b0", [ss.id]).get("need") == "dead_hand" and g.view("b0", 0).playable.get(ss.id) == "dead_hand", "Trueque de Almas: need dead_hand (en plan y en view)")
	_check(g.plan("b0", [ss.id], "b2").has("err") and g.plan("b0", [ss.id], "b3").has("err") and g.plan("b0", [ss.id], "b0").has("err") and g.plan("b0", [ss.id], "zz").has("err"), "Trueque de Almas: vivo, muerto sin cartas, uno mismo y desconocido rechazados")
	_check(g.plan("b0", [ss.id], "b1").get("kind") == "action", "Trueque de Almas: vale un muerto con cartas")
	_check(_play(g, "b0", ss, "b2") != "" and _play(g, "b0", ss, "b3") != "" and _play(g, "b0", ss) != "", "Trueque de Almas: act rechaza objetivo inválido o ausente")
	var os := _give(g, 2, "soul_swap")
	_check(g.plan("b2", [os.id], "b1").has("err"), "Trueque de Almas: fuera de turno rechazado")
	g.players[2].hand.erase(os)
	_check(_play(g, "b0", ss, "b1") == "", "Trueque de Almas: se juega")
	_check(_evs(g, "play")[0].text == "B0 juega Trueque de Almas y quiere la mano de B1.", "Trueque de Almas: texto del evento play")
	_resolve(g)
	_check(g.players[0].hand.size() == 3 and g.players[0].hand[0] == z and g.players[0].hand[1] == sk and g.players[0].hand[2] == cb, "Trueque de Almas: b0 recibe la mano del muerto")
	_check(g.players[1].hand.size() == 1 and g.players[1].hand[0] == keep and not g.players[1].alive, "Trueque de Almas: el muerto recibe la mano de b0 y sigue muerto")
	var sw := _evs(g, "swap")
	_check(sw.size() == 1 and sw[0].player == "b0" and sw[0].target == "b1" and not sw[0].has("to"), "Trueque de Almas: evento swap público {player, target}")
	var gots := _evs(g, "got")
	_check(gots.size() == 2 and gots.any(func(e: Dictionary) -> bool: return e.to == "b0" and e.n == 3) and gots.any(func(e: Dictionary) -> bool: return e.to == "b1" and e.n == 1), "Trueque de Almas: got privado con el número de cartas a cada uno")
	_check(g.view("b2", _clk).events.filter(func(e: Dictionary) -> bool: return e.type == "got").is_empty(), "Trueque de Almas: got no llega a terceros")
	_check(g.cur == 0 and g.turns_left == 1 and _in_discard(g, ss), "Trueque de Almas: no termina el turno")
	# sin muertos con cartas: error
	var g2 := _cg(3)
	var s2 := _give(g2, 0, "soul_swap")
	_check(g2.plan("b0", [s2.id]).has("err"), "Trueque de Almas: sin muertos con cartas es un error")
	g2.players[1].alive = false
	_check(g2.plan("b0", [s2.id]).has("err"), "Trueque de Almas: un muerto sin cartas no cuenta")
	# anulado con Nop
	g = _cg(3)
	ss = _give(g, 0, "soul_swap")
	_give(g, 0, "cat_a")
	_give(g, 1, "cat_b")
	g.players[1].alive = false
	var nope := _give(g, 2, "nope")
	_play(g, "b0", ss, "b1")
	g.act("b2", {"a": "play", "cards": [nope.id]}, _clk)
	_resolve(g)
	_check(g.players[0].hand.size() == 1 and g.players[0].hand[0].type == "cat_a" and g.players[1].hand.size() == 1 and g.players[1].hand[0].type == "cat_b" and _evs(g, "swap").is_empty() and _in_discard(g, ss), "Trueque de Almas anulado: las manos no cambian y la carta se pierde")
	# con Clon
	g = _cg(3)
	g.discard.append({"card": _card("soul_swap"), "by": "b2"})
	var cl := _give(g, 0, "clone")
	var mine := _give(g, 0, "cat_a")
	var theirs := _give(g, 1, "cat_b")
	g.players[1].alive = false
	_check(g.plan("b0", [cl.id]).get("need") == "dead_hand", "Clon de Trueque de Almas: pide objetivo dead_hand")
	_check(g.plan("b0", [cl.id], "b2").has("err"), "Clon de Trueque de Almas: objetivo vivo rechazado")
	_check(_play(g, "b0", cl, "b1") == "", "Clon de Trueque de Almas: se juega")
	_check(_evs(g, "play")[0].text == "B0 juega Clon (como Trueque de Almas) y quiere la mano de B1.", "Clon de Trueque de Almas: texto")
	_resolve(g)
	_check(g.players[0].hand.size() == 1 and g.players[0].hand[0] == theirs and g.players[1].hand.size() == 1 and g.players[1].hand[0] == mine, "Clon de Trueque de Almas: intercambia las manos")
	# el muerto fue revivido antes de resolverse
	g = _cg(3)
	ss = _give(g, 0, "soul_swap")
	_give(g, 0, "cat_a")
	_give(g, 1, "cat_b")
	g.players[1].alive = false
	_play(g, "b0", ss, "b1")
	g.players[1].alive = true
	_resolve(g)
	_check(g.players[0].hand.size() == 1 and g.players[0].hand[0].type == "cat_a" and g.players[1].hand[0].type == "cat_b" and _evs(g, "swap").is_empty(), "Trueque de Almas: si el muerto fue revivido, no tiene efecto")
	# el muerto se quedó sin cartas
	g = _cg(3)
	ss = _give(g, 0, "soul_swap")
	_give(g, 0, "cat_a")
	_give(g, 1, "cat_b")
	g.players[1].alive = false
	_play(g, "b0", ss, "b1")
	g.players[1].hand.clear()
	_resolve(g)
	_check(g.players[0].hand.size() == 1 and g.players[1].hand.is_empty() and _evs(g, "swap").is_empty(), "Trueque de Almas: si el muerto ya no tiene cartas, no tiene efecto")
	# en pareja se ignora su texto
	g = _cg(3)
	var pa := _give(g, 0, "soul_swap")
	var pb := _give(g, 0, "soul_swap")
	_give(g, 1, "skip")
	_check(_play(g, "b0", [pa, pb], "b1") == "", "Trueque de Almas en pareja: se juega como combo")
	_resolve(g)
	_check(_evs(g, "swap").is_empty() and _evs(g, "steal").size() == 1, "Trueque de Almas en pareja: roba una carta y no intercambia")


# ---- Espanto

func _crypt_haunt() -> void:
	var g := _cg(4)
	var hc := _give(g, 1, "haunt")
	var sk := _give(g, 0, "skip")
	var ca := _give(g, 0, "cat_a")
	_give(g, 2, "cat_b")
	g.players[1].alive = false
	g.rnd = func() -> float: return 0.0
	_check(g.plan("b1", [hc.id]).get("need") == "living" and g.view("b1", 0).playable.get(hc.id) == "living", "Espanto: un muerto lo juega fuera de turno con need living")
	_check(g.plan("b1", [hc.id], "b3").has("err"), "Espanto: objetivo vivo sin cartas rechazado")
	_check(g.plan("b1", [hc.id], "b1").has("err") and g.plan("b1", [hc.id], "zz").has("err"), "Espanto: uno mismo y desconocido rechazados")
	g.players[3].alive = false
	_check(g.plan("b1", [hc.id], "b3").has("err"), "Espanto: objetivo muerto rechazado")
	g.players[3].alive = true
	_check(_play(g, "b1", hc, "b3") != "" and _play(g, "b1", hc) != "", "Espanto: act rechaza objetivo inválido o ausente")
	# un vivo no puede jugarlo
	var live := _give(g, 0, "haunt")
	_check(g.plan("b0", [live.id], "b2").get("err") == "Solo los muertos pueden espantar.", "Espanto: un vivo en su turno recibe «Solo los muertos pueden espantar.»")
	_check(_play(g, "b0", live, "b2") == "Solo los muertos pueden espantar." and not g.view("b0", 0).playable.has(live.id), "Espanto: act y view.playable lo rechazan para un vivo")
	var live2 := _give(g, 2, "haunt")
	_check(g.plan("b2", [live2.id], "b0").get("err") == "Solo los muertos pueden espantar.", "Espanto: un vivo fuera de turno recibe el mismo error")
	g.players[0].hand.erase(live)
	g.players[2].hand.erase(live2)
	g.discard.append({"card": _card("haunt"), "by": "b1"})
	var cl := _give(g, 0, "clone")
	_check(g.plan("b0", [cl.id], "b2").get("err") == "Solo los muertos pueden espantar.", "Espanto: un vivo no puede clonarlo")
	g.players[0].hand.erase(cl)
	g.discard.pop_back()
	# caso normal
	g.events.clear()
	_check(_play(g, "b1", hc, "b0") == "", "Espanto: el muerto lo juega fuera de turno")
	_check(_evs(g, "play")[0].text == "B1 juega Espanto desde el más allá contra B0.", "Espanto: texto del evento play")
	_resolve(g)
	_check(g.players[0].hand.size() == 1 and g.players[0].hand[0] == ca and g.cur == 0 and g.turns_left == 1, "Espanto: quita una carta al azar al objetivo y no toca el turno")
	var td: Variant = g.top_discard()
	_check(td != null and td.card == sk and td.by == "b0", "Espanto: la carta descartada queda arriba del descarte con by = objetivo")
	_check(g.discard[g.discard.size() - 2].card == hc and g.discard[g.discard.size() - 2].by == "b1", "Espanto: la carta del Espanto queda justo debajo")
	var ev := _evs(g, "haunt")
	_check(ev.size() == 1 and ev[0].player == "b1" and ev[0].target == "b0" and ev[0].card == "skip" and not ev[0].has("to"), "Espanto: evento haunt público {player, target, card}")
	_check(g.view("b2", _clk).discard.back().type == "skip" and g.view("b2", _clk).events.any(func(e: Dictionary) -> bool: return e.type == "haunt"), "Espanto: todos ven la carta descartada")
	# un Clon posterior la copia
	var cl2 := _give(g, 0, "clone")
	g.events.clear()
	_check(_play(g, "b0", cl2) == "" and _evs(g, "play")[0].text == "B0 juega Clon (como Saltar).", "Espanto: un Clon posterior copia la carta descartada")
	_resolve(g)
	_check(g.cur == 2, "Espanto: el Clon de la carta descartada se resuelve (Saltar termina el turno; b1 está muerto)")
	# otras tiradas del azar
	g = _cg(3)
	hc = _give(g, 1, "haunt")
	g.players[1].alive = false
	_give(g, 0, "cat_a")
	_give(g, 0, "cat_b")
	_give(g, 0, "cat_c")
	g.rnd = func() -> float: return 0.999
	_play(g, "b1", hc, "b0")
	_resolve(g)
	_check(g.top_discard().card.type == "cat_c" and g.players[0].hand.size() == 2, "Espanto: la carta elegida sale de rnd")
	# se puede jugar con una jugada pendiente (⚡) pero no durante una decisión
	g = _cg(4)
	hc = _give(g, 1, "haunt")
	g.players[1].alive = false
	var skp := _give(g, 0, "skip")
	_give(g, 0, "cat_a")
	_play(g, "b0", skp)
	_check(g.plan("b1", [hc.id], "b0").get("kind") == "action", "Espanto: se puede jugar con una jugada pendiente en la pila (⚡)")
	g = _cg(4)
	hc = _give(g, 1, "haunt")
	g.players[1].alive = false
	var al := _give(g, 0, "alter_future")
	_give(g, 0, "cat_a")
	_setdraw(g, ["cat_a", "cat_b", "cat_c"])
	_play(g, "b0", al)
	_resolve(g)
	_check(g.prompt != null and g.plan("b1", [hc.id], "b0").has("err"), "Espanto: no se puede jugar durante una decisión")
	# anulado con Nop
	g = _cg(4)
	hc = _give(g, 1, "haunt")
	g.players[1].alive = false
	_give(g, 0, "cat_a")
	var nope := _give(g, 2, "nope")
	_play(g, "b1", hc, "b0")
	g.act("b2", {"a": "play", "cards": [nope.id]}, _clk)
	_resolve(g)
	_check(g.players[0].hand.size() == 1 and _evs(g, "haunt").is_empty() and _in_discard(g, hc), "Espanto anulado: el objetivo conserva su mano y la carta se pierde")
	# el objetivo ya no tiene cartas / ya no vive al resolverse
	g = _cg(4)
	hc = _give(g, 1, "haunt")
	g.players[1].alive = false
	_give(g, 0, "cat_a")
	_play(g, "b1", hc, "b0")
	g.players[0].hand.clear()
	_resolve(g)
	_check(_evs(g, "haunt").is_empty() and g.discard.size() == 1, "Espanto: si el objetivo se quedó sin cartas, no hace nada")
	g = _cg(4)
	hc = _give(g, 1, "haunt")
	g.players[1].alive = false
	_give(g, 0, "cat_a")
	_play(g, "b1", hc, "b0")
	g.players[0].alive = false
	_resolve(g)
	_check(_evs(g, "haunt").is_empty() and g.players[0].hand.size() == 1, "Espanto: si el objetivo murió, no hace nada")
	# nadie tiene cartas
	g = _cg(3)
	hc = _give(g, 1, "haunt")
	g.players[1].alive = false
	_check(g.plan("b1", [hc.id]).has("err"), "Espanto: sin vivos con cartas es un error")


# ---- Arreglo de Ataque Dirigido: nadie se ataca a sí mismo

func _crypt_targeted_attack_self() -> void:
	var g := _cg(4)
	g.cur = 3
	var ta := _give(g, 3, "targeted_attack")
	_play(g, "b3", ta, "b2")
	g.players[2].alive = false
	_resolve(g)
	_check(g.cur == 0 and g.turns_left == 2 and g.attacked and _evs(g, "attack")[0].target == "b0" and _evs(g, "attack")[0].player == "b3", "Ataque Dirigido: si el siguiente vivo es quien lo jugó, salta al siguiente")
	g = _cg(4)
	g.cur = 3
	ta = _give(g, 3, "targeted_attack")
	_play(g, "b3", ta, "b2")
	g.players[2].alive = false
	g.players[0].alive = false
	_resolve(g)
	_check(g.cur == 1 and g.turns_left == 2, "Ataque Dirigido: el salto también se salta a los muertos")
	g = _cg(4)
	g.cur = 1
	g.dir = -1
	ta = _give(g, 1, "targeted_attack")
	_play(g, "b1", ta, "b2")
	g.players[2].alive = false
	_resolve(g)
	_check(g.cur == 0 and g.turns_left == 2, "Ataque Dirigido: con dir = -1 también evita al que lo jugó")
	g = _cg(4)
	g.cur = 3
	ta = _give(g, 3, "targeted_attack")
	_play(g, "b3", ta, "b0")
	_resolve(g)
	_check(g.cur == 0 and g.turns_left == 2, "Ataque Dirigido: con el objetivo vivo no cambia nada")



# ================================================================ IA de La Cripta (T24 + T33)

var _keep: Rng = null   # mantiene vivo el generador que usa un bot durante una comprobación
const NEW_CARDS := ["targeted_attack", "reverse", "draw_bottom", "crow_eye", "apocalypse", "alter_future", "bury", "soul_swap", "haunt"]


func _zero() -> float:
	return 0.0


func _bots(g: Game, levels: Dictionary) -> Bots:
	return Bots.new(g, levels, _zero, true)


func _lv(g: Game, level: String) -> Dictionary:
	var d := {}
	for p in g.players:
		d[p.id] = level
	return d


## Partida solo con bots (sin «jugador de pruebas»). `cheat`: en algunas decisiones comprueba que la jugada no cambia
## al permutar lo que el bot no puede ver (manos ajenas y mazo). stats acumula jugadas, turnos y plazos vencidos.
func _bot_game(n: int, seed_value: int, mode: String, levels: Array, plus: bool, packs: Array, stats: Dictionary, cheat: bool = false) -> String:
	var rng := Rng.new(seed_value)
	var g := _mk(n, 0, mode, rng, plus, packs)
	var lv := {}
	for i in n:
		lv["b%d" % i] = levels[i % levels.size()]
	var bots := Bots.new(g, lv, rng.next, plus)
	var total := _count(g)
	var now := 0
	var steps := 0
	var first := 0
	var seen := 0
	while g.over == null:
		steps += 1
		if not _check(steps < 20000, "partida interminable con bots (semilla %d, %d jugadores)" % [seed_value, n]):
			return ""
		g.tick(now)
		bots.learn()
		for e: Dictionary in g.events:
			if e.seq > seen:
				seen = e.seq
				if e.type == "turn":
					stats["turns"] = int(stats.get("turns", 0)) + 1
		var acted := false
		for k in n:
			var id := "b%d" % ((first + k) % n)
			var a: Dictionary
			if cheat and steps % 9 == 0 and (g.prompt == null or g.prompt.type != "alter"):
				_keep = Rng.new(steps * 7 + k)
				bots.rnd = _keep.next
				a = bots.decide(id)
				if not a.is_empty():
					var a2 := _decide_blind(g, bots, id, steps * 7 + k)
					if not _check(JSON.stringify(a) == JSON.stringify(a2), "la decisión de %s cambió al permutar información oculta (semilla %d): %s / %s" % [id, seed_value, JSON.stringify(a), JSON.stringify(a2)]):
						return ""
					stats["cheat_checks"] = int(stats.get("cheat_checks", 0)) + 1
				bots.rnd = rng.next
			else:
				a = bots.decide(id)
			if a.is_empty():
				continue
			var pl := {}
			if a.a == "play":
				pl = g.plan(id, a.cards, a.get("target"), a.get("named"))
			var err := g.act(id, a, now)
			bots.note(id, a, err)
			bots.learn()
			if plus and not _check(err == "", "acción rechazada de %s: %s (%s)" % [id, err, JSON.stringify(a)]):
				return ""
			if err == "":
				stats["actions"] = int(stats.get("actions", 0)) + 1
				if a.a == "play" and pl.has("eff"):
					stats[pl.eff] = int(stats.get(pl.eff, 0)) + 1
					stats["%d:%s" % [n, pl.eff]] = int(stats.get("%d:%s" % [n, pl.eff], 0)) + 1
					if a.cards.size() == 1 and g.discard.size() > 0 and g.discard[g.discard.size() - 1].card.type == "clone":
						stats["clon_como_" + pl.eff] = int(stats.get("clon_como_" + pl.eff, 0)) + 1
			acted = true
			first = (first + k + 1) % n
			break
		if acted:
			now += 400
		else:
			var d := g.next_deadline()
			if g.over != null:
				break
			if g.prompt != null and (g.prompt.type == "alter" or g.prompt.type == "bury"):
				stats["exp_" + g.prompt.type] = int(stats.get("exp_" + g.prompt.type, 0)) + 1
			if not _check(d >= 0, "partida atascada con bots (semilla %d, %d jugadores)" % [seed_value, n]):
				return ""
			now = maxi(now + 1, d)
		if not _check(_count(g) == total, "se perdieron o duplicaron cartas con bots (semilla %d)" % seed_value):
			return ""
		if g.over == null:
			var eks := 0
			for c in g.draw:
				eks += 1 if c.type == "exploding" else 0
			if g.prompt != null:
				eks += (1 if g.prompt.has("card") and g.prompt.card.type == "exploding" else 0) + (g.prompt.eks.size() if g.prompt.has("eks") else 0)
			if not _check(eks == g.living().size() - 1, "explosivos en juego != vivos - 1 con bots (semilla %d)" % seed_value):
				return ""
	stats["games"] = int(stats.get("games", 0)) + 1
	return g.over.winner


## Decide con las cartas de los rivales y del mazo permutadas (se restauran después).
func _decide_blind(g: Game, bots: Bots, id: String, seed_value: int) -> Dictionary:
	var cards: Array = []
	for p in g.players:
		if p.id != id:
			cards.append_array(p.hand)
	cards.append_array(g.draw)
	var orig: Array = cards.map(func(c: Game.Card) -> String: return c.type)
	var k := cards.size()
	for i in k:
		cards[i].type = orig[(i + 1) % k]
	_keep = Rng.new(seed_value)
	bots.rnd = _keep.next
	var a := bots.decide(id)
	for i in k:
		cards[i].type = orig[i]
	return a


func _plus_bot_sim() -> void:
	var stats := {}
	var mixes := [["easy", "normal", "hard"], ["hard", "normal"], ["hard"], ["normal", "easy", "hard", "normal"], ["normal"]]
	var games := 0
	for s in 170:
		for n in [2, 3, 4, 5]:
			if _bot_game(n, 12000 + s * 37 + n, "official" if s % 4 != 3 else "full", mixes[s % mixes.size()], true, ["crypt"], stats) == "":
				return
			games += 1
	var ok := true
	for n: int in [2, 3, 4, 5]:
		var deck := _mk(n, 1, "official", null, true, ["crypt"]).deck_types
		for t: String in NEW_CARDS:
			if deck.has(t):
				ok = _check(int(stats.get("%d:%s" % [n, t], 0)) > 0, "con %d jugadores los bots nunca jugaron %s" % [n, t]) and ok
	ok = _check(int(stats.get("exp_alter", 0)) == 0 and int(stats.get("exp_bury", 0)) == 0, "venció un plazo de alter/bury con un bot (alter %d, bury %d)" % [int(stats.get("exp_alter", 0)), int(stats.get("exp_bury", 0))]) and ok
	var line := []
	for t: String in NEW_CARDS:
		line.append("%s %d" % [t, int(stats.get(t, 0))])
	print("    %d partidas con bots y La Cripta. Jugadas por los bots: %s" % [games, ", ".join(PackedStringArray(line))])
	var cl := []
	for k: String in stats:
		if k.begins_with("clon_como_"):
			cl.append("%s %d" % [k, stats[k]])
	print("    Clon copiando: %s; plazos vencidos alter/bury: 0; combos: pareja %d, trío %d; feed_dead %d" % [", ".join(PackedStringArray(cl)), int(stats.get("combo2", 0)), int(stats.get("combo3", 0)), int(stats.get("feed_dead", 0))])
	if ok:
		_ok("%d partidas con bots solos: sin atascos ni cartas perdidas, cada carta nueva se juega y ningún plazo vence" % games)
	# Sin trampas: la decisión no depende de manos ajenas ni del mazo
	var cs := {}
	for s in 40:
		for n in [2, 3, 4]:
			if _bot_game(n, 31000 + s * 11 + n, "official", mixes[s % mixes.size()], true, ["crypt"], cs, true) == "":
				return
	if _check(int(cs.get("cheat_checks", 0)) > 500, "pocas comprobaciones de «sin trampas» (%d)" % int(cs.get("cheat_checks", 0))):
		_ok("sin trampas: %d decisiones idénticas al permutar manos ajenas y mazo" % int(cs.get("cheat_checks", 0)))


func _duel_plus(a: String, b: String, n: int) -> int:
	var w := 0
	for i in n:
		var levels := [a, b] if i % 2 == 1 else [b, a]
		if _bot_game(2, 9000 + i, "official", levels, true, ["crypt"], {}) == ("b0" if i % 2 == 1 else "b1"):
			w += 1
	return int(round(100.0 * w / n))


func _plus_difficulty() -> void:
	var hn := _duel_plus("hard", "normal", 400)
	var ne := _duel_plus("normal", "easy", 400)
	var he := _duel_plus("hard", "easy", 400)
	print("    Plus con La Cripta (2 jugadores) - difícil vs normal: %d%%   normal vs fácil: %d%%   difícil vs fácil: %d%%" % [hn, ne, he])
	if _check(hn >= 60 and ne > 55 and he > 60, "en Plus las dificultades no están ordenadas con claridad"):
		_ok("Plus: difícil > normal > fácil")


func _plus_duration() -> void:
	var mix := ["easy", "normal", "hard"]
	for n: int in [2, 3, 4, 5]:
		var cs := {}
		var ps := {}
		for s in 60:
			_bot_game(n, 20000 + s * 13 + n, "official", mix, false, [], cs)
			_bot_game(n, 20000 + s * 13 + n, "official", mix, true, ["crypt"], ps)
		print("    %d jugadores - acciones/partida: clásico %.0f, Plus %.0f   turnos/partida: clásico %.0f, Plus %.0f" % [n, float(cs.actions) / cs.games, float(ps.actions) / ps.games, float(cs.turns) / cs.games, float(ps.turns) / ps.games])


func _test_plus_bots() -> void:
	print("Plus: IA de La Cripta")
	var f0 := _fails
	_plus_bot_sim()
	_bot_cases()
	_plus_difficulty()
	_plus_duration()
	if _fails == f0:
		_ok("IA de La Cripta: simulaciones, casos dirigidos, dificultad y duración")


func _bot_cases() -> void:
	var f0 := _fails
	# --- sabe que arriba hay un explosivo y juega Robar del Fondo
	var g := _cg(3)
	var b := _bots(g, _lv(g, "hard"))
	_give(g, 0, "see_future")
	var db := _give(g, 0, "draw_bottom")
	_give(g, 0, "cat_a")
	_setdraw(g, ["nope", "cat_b", "cat_c", "exploding"])
	b.learn()
	var a := b.decide("b0")
	_check(a.get("a") == "play" and g.P("b0").find_id(a.cards[0]).type == "see_future", "difícil: con riesgo y sin información mira el futuro")
	_check(g.act("b0", a, _clk) == "", "ver el futuro aceptado")
	_resolve(g)
	b.learn()
	_check(b.known("b0", 0) == "exploding", "tras Ver el Futuro sabe que arriba hay un explosivo")
	a = b.decide("b0")
	_check(a.get("a") == "play" and a.cards == [db.id], "difícil: sabe que arriba hay un explosivo y juega Robar del Fondo")
	_check(g.act("b0", a, _clk) == "", "Robar del Fondo aceptado")
	_resolve(g)
	_check(g.P("b0").alive and g.P("b0").find_type("nope") != null and g.cur == 1, "robó el fondo (Nop) y sigue vivo")
	# --- memoria tras robo del fondo
	g = _cg(3)
	b = _bots(g, _lv(g, "hard"))
	var sf := _give(g, 0, "see_future")
	_setdraw(g, ["cat_a", "cat_b", "cat_c", "cat_d", "exploding", "nope"])
	b.learn()
	_play(g, "b0", sf)
	_resolve(g)
	b.learn()
	_check(b.known("b0", 0) == "nope" and b.known("b0", 1) == "exploding" and b.known("b0", 2) == "cat_d", "memoria: lo visto con Ver el Futuro")
	g.cur = 1
	var db2 := _give(g, 1, "draw_bottom")
	_play(g, "b1", db2)
	_resolve(g)
	b.learn()
	_check(g.draw.size() == 5 and b.known("b0", 0) == "nope" and b.known("b0", 1) == "exploding" and b.known("b0", 2) == "cat_d", "memoria: tras un robo del fondo lo de arriba sigue vigente")
	_check(g.act("b2", {"a": "draw"}, _clk) == "", "b2 roba de arriba")
	b.learn()
	_check(b.known("b0", 0) == "exploding" and b.known("b0", 1) == "cat_d" and b.known("b0", 2) == "", "memoria: tras robar de arriba se desplaza")
	# --- Alterar el Futuro: el explosivo le toca al siguiente rival
	for turns: int in [1, 2]:
		g = _cg(3)
		b = _bots(g, _lv(g, "hard"))
		var al := _give(g, 0, "alter_future")
		_setdraw(g, ["cat_a", "cat_b", "cat_c", "exploding", "nope", "skip"])
		if turns == 2:
			g.turns_left = 2
			g.attacked = true
		_play(g, "b0", al)
		_resolve(g)
		a = b.decide("b0")
		_check(a.get("a") == "reorder" and a.order == ([1, 2, 0] if turns == 1 else [1, 0, 2]), "alter (turnos %d): orden %s" % [turns, str(a.get("order"))])
		_check(g.act("b0", a, _clk) == "" and g.prompt == null, "alter respondido (turnos %d)" % turns)
		b.learn()
		if turns == 1:
			g.act("b0", {"a": "draw"}, _clk)
			_check(g.P("b0").alive and g.P("b0").find_type("nope") != null, "b0 roba lo bueno")
			g.act("b1", {"a": "draw"}, _clk)
			_check(g.prompt != null or not g.P("b1").alive, "el rival siguiente roba el explosivo")
		else:
			_check(g.draw[g.draw.size() - 1].type == "nope" and g.draw[g.draw.size() - 2].type == "skip" and g.draw[g.draw.size() - 3].type == "exploding", "con dos turnos el explosivo queda lo más abajo de las 3")
	# --- Entierro
	for turns: int in [1, 2]:
		g = _cg(3)
		b = _bots(g, _lv(g, "hard"))
		var by := _give(g, 0, "bury")
		_setdraw(g, ["cat_a", "cat_b", "exploding"])
		if turns == 2:
			g.turns_left = 2
			g.attacked = true
		_play(g, "b0", by)
		_resolve(g)
		b.learn()
		a = b.decide("b0")
		_check(a.get("a") == "bury" and a.pos == (0 if turns == 1 else 2), "bury (turnos %d): pos %s" % [turns, str(a.get("pos"))])
		_check(g.act("b0", a, _clk) == "", "bury respondido")
		b.learn()
		if turns == 1:
			_check(b.known("b0", 0) == "exploding", "recuerda dónde enterró el explosivo")
		else:
			_check(b._bottom_hidden("b0"), "recuerda que escondió un explosivo al fondo")
	# --- fácil y normal también contestan siempre
	for lvl: String in ["easy", "normal"]:
		g = _cg(3)
		b = _bots(g, _lv(g, lvl))
		var al2 := _give(g, 0, "alter_future")
		_setdraw(g, ["cat_a", "cat_b", "exploding", "skip", "nope"])
		_play(g, "b0", al2)
		_resolve(g)
		a = b.decide("b0")
		_check(a.get("a") == "reorder" and g.act("b0", a, _clk) == "", "%s responde a alter" % lvl)
		g = _cg(3)
		b = _bots(g, _lv(g, lvl))
		var by2 := _give(g, 0, "bury")
		_setdraw(g, ["cat_a", "cat_b", "exploding", "skip", "nope"])
		_play(g, "b0", by2)
		_resolve(g)
		a = b.decide("b0")
		_check(a.get("a") == "bury" and g.act("b0", a, _clk) == "", "%s responde a bury" % lvl)
	# --- bot muerto
	g = _cg(3)
	b = _bots(g, _lv(g, "hard"))
	g.P("b2").alive = false
	_give(g, 2, "haunt")
	_give(g, 0, "cat_a")
	_give(g, 0, "cat_b")
	for t: String in ["cat_a", "cat_b", "cat_c", "cat_d", "nope"]:
		_give(g, 1, t)
	a = b.decide("b2")
	_check(a.get("a") == "play" and a.get("target") == "b1" and g.P("b2").find_id(a.cards[0]).type == "haunt", "muerto: juega Espanto contra el vivo con más cartas")
	_check(g.act("b2", a, _clk) == "", "Espanto del bot muerto aceptado")
	_resolve(g)
	_check(g.P("b1").hand.size() == 4, "el Espanto descartó una carta")
	g = _cg(3)
	b = _bots(g, _lv(g, "hard"))
	g.P("b2").alive = false
	_give(g, 2, "haunt")
	_give(g, 1, "cat_a")
	var fv := _give(g, 0, "favor")
	_play(g, "b0", fv, "b1")
	_check(b.decide("b2").is_empty(), "muerto: no espanta con la mesa ocupada")
	g = _cg(3)
	b = _bots(g, _lv(g, "normal"))
	g.P("b2").alive = false
	var fd := _give(g, 2, "feed_dead")
	_give(g, 0, "cat_a")
	_give(g, 1, "cat_b")
	a = b.decide("b2")
	_check(a.get("a") == "play" and a.cards == [fd.id] and a.get("target") == "b2", "muerto con pocas cartas: Alimenta a los Muertos sobre sí mismo")
	# --- Nop contra jugadas que le perjudican
	g = _cg(4)
	b = _bots(g, _lv(g, "hard"))
	var n1 := _give(g, 1, "nope")
	_give(g, 2, "nope")
	var ta := _give(g, 0, "targeted_attack")
	_play(g, "b0", ta, "b1")
	a = b.decide("b1")
	_check(a.get("a") == "play" and a.cards == [n1.id], "Nop contra Ataque Dirigido hacia él")
	_check(b.decide("b2").get("a") == "pass", "no anula un Ataque Dirigido que no va contra él")
	g = _cg(4)
	b = _bots(g, _lv(g, "hard"))
	g.P("b3").alive = false
	_give(g, 1, "nope")
	var ht := _give(g, 3, "haunt")
	_give(g, 1, "cat_a")
	_play(g, "b3", ht, "b1")
	_check(b.decide("b1").get("a") == "play", "Nop contra Espanto sobre él")
	g = _cg(4)
	b = _bots(g, _lv(g, "hard"))
	_give(g, 1, "nope")
	_give(g, 2, "nope")
	var ap := _give(g, 0, "apocalypse")
	_play(g, "b0", ap)
	_check(b.decide("b1").get("a") == "play" and b.decide("b2").get("a") == "pass", "Nop contra Apocalipsis solo si él es el siguiente en robar")
	g = _cg(4)
	b = _bots(g, _lv(g, "hard"))
	g.P("b3").alive = false
	for i in 6:
		_give(g, 3, "cat_a")
	_give(g, 1, "nope")
	var ss := _give(g, 0, "soul_swap")
	_play(g, "b0", ss, "b3")
	_check(b.decide("b1").get("a") == "play", "Nop contra Trueque de Almas cuando la mano del muerto es mucho mejor")
	# --- Clon para esquivar
	g = _cg(3)
	b = _bots(g, _lv(g, "hard"))
	var cl := _give(g, 0, "clone")
	_setdraw(g, ["cat_a", "cat_b", "exploding"])
	g.emit("future", {"cards": ["exploding", "cat_b", "cat_a"], "mut": g.mut, "len": g.draw.size(), "shuf": g.shuf}, "b0")
	g.discard.append({"card": _card("attack"), "by": "b1"})
	b.learn()
	a = b.decide("b0")
	_check(a.get("a") == "play" and a.cards == [cl.id], "Clon: copia el Ataque del descarte para esquivar")
	_check(g.act("b0", a, _clk) == "", "Clon aceptado")
	# --- Barajar tras un Ver el Futuro rival
	g = _cg(3)
	b = _bots(g, _lv(g, "hard"))
	var types: Array = ["exploding"]
	for i in 6:
		types.append("cat_a")
	types.append("exploding")
	for i in 7:
		types.append("cat_b")
	_setdraw(g, types)
	g.cur = 1
	var sf1 := _give(g, 1, "see_future")
	_give(g, 2, "shuffle")
	_give(g, 0, "shuffle")
	_play(g, "b1", sf1)
	b.learn()
	_resolve(g)
	b.learn()
	a = b.decide("b2")
	_check(a.get("a") == "play" and g.P("b2").find_id(a.cards[0]).type == "shuffle", "Barajar: el siguiente en robar rompe lo que vio el rival")
	_check(b.decide("b0").is_empty(), "Barajar: quien no es el siguiente y tiene poco riesgo no baraja")
	# --- Ojo de Cuervo + trío nombrando lo visto
	g = _cg(3)
	b = _bots(g, _lv(g, "hard"))
	var ce := _give(g, 0, "crow_eye")
	for i in 3:
		_give(g, 0, "cat_a")
	var nopec := _give(g, 1, "nope")
	_give(g, 1, "cat_b")
	_give(g, 1, "cat_c")
	_give(g, 2, "cat_d")
	_setdraw(g, ["cat_a", "exploding", "cat_b", "exploding", "cat_c"])
	b.learn()
	a = b.decide("b0")
	_check(a.get("a") == "play" and a.cards == [ce.id] and a.get("target") == "b1", "difícil: mira la mano del rival antes del trío")
	g.act("b0", a, _clk)
	_resolve(g)
	b.learn()
	a = b.decide("b0")
	_check(a.get("a") == "play" and a.cards.size() == 3 and a.get("named") == "nope" and a.get("target") == "b1", "difícil: nombra en el trío lo que vio")
	g.P("b1").hand.erase(nopec)
	g.discard.append({"card": nopec, "by": "b1"})
	b.learn()
	_check(not b._peek_cards("b0", "b1").has("nope"), "lo visto caduca cuando el rival juega esa carta")
	# --- Ataque Dirigido: al rival sin Zombi conocido
	g = _cg(3)
	b = _bots(g, _lv(g, "hard"))
	var tgt := _give(g, 0, "targeted_attack")
	_give(g, 1, "zombie")
	_give(g, 1, "cat_a")
	_give(g, 1, "cat_b")
	_give(g, 2, "cat_c")
	_setdraw(g, ["cat_a", "cat_b", "exploding"])
	g.emit("future", {"cards": ["exploding", "cat_b", "cat_a"], "mut": g.mut, "len": g.draw.size(), "shuf": g.shuf}, "b0")
	g.emit("peek", {"target": "b1", "cards": ["zombie", "cat_a", "cat_b"]}, "b0")
	b.learn()
	a = b.decide("b0")
	_check(a.get("a") == "play" and a.cards == [tgt.id] and a.get("target") == "b2", "Ataque Dirigido con explosivo arriba: al rival sin Zombi conocido")
	# --- Apocalipsis: todos saben que arriba hay explosivos
	g = _cg(3)
	b = _bots(g, {"b0": "hard", "b1": "normal", "b2": "easy"})
	var apo := _give(g, 0, "apocalypse")
	_play(g, "b0", apo)
	_resolve(g)
	b.learn()
	_check(b.known("b1", 0) == "exploding" and b.known("b1", 1) == "exploding" and b.known("b1", 2) != "exploding" and b.known("b2", 0) == "", "Apocalipsis: los no-fáciles saben que arriba hay N explosivos")
	# --- trío de normal
	g = _cg(3)
	b = _bots(g, _lv(g, "normal"))
	for i in 3:
		_give(g, 0, "cat_a")
	_give(g, 1, "cat_b")
	a = b.decide("b0")
	_check(a.get("a") == "play" and a.cards.size() == 3 and a.get("named") == "zombie", "normal: hace tríos de cartas baratas pidiendo Zombi")
	if _fails == f0:
		_ok("casos dirigidos: Robar del Fondo, memoria con tops, alter, bury, muerto, Nop, Clon, Barajar, Ojo de Cuervo, Apocalipsis y trío")



# ---------------------------------------------------------------- medición de equilibrio (NO forma parte de la suite)
# godot --headless --path godot -s tests/run_tests.gd -- --balance [--games=400] [--variants=A,C,D] [--players=2,3,4,5]
#                                                            [--levels=mixed,normal] [--difficulty=C,D] [--seed=50000]
# Sin opciones: todas las variantes, 2-5 jugadores, niveles mezclados y todos «normal», 400 partidas por celda.
# Los asientos de niveles mezclados rotan de una partida a otra, así el % por asiento no queda sesgado por el nivel.
# Las semillas dependen solo del número de partida y de jugadores: todas las variantes juegan los mismos barajados base.

## Partida con contador de turnos reales: un turno termina cada vez que _end_turn se ejecuta, o que el turno pasa
## de mano por otra vía (Ataque, Súper Salto, muerte, Ataque Dirigido). No cuenta eventos ni robos fuera de turno.
class CountGame:
	extends Game
	var turn_ends := 0
	var _in_end := false
	var _in_adv := false

	func _end_turn(now: int) -> void:
		turn_ends += 1
		_in_end = true
		super(now)
		_in_end = false

	func _advance(n: int, was_attacked: bool, now: int) -> void:
		if not _in_end:
			turn_ends += 1
		_in_adv = true
		super(n, was_attacked, now)
		_in_adv = false

	func emit(type: String, data: Dictionary = {}, to: String = "") -> Dictionary:
		if type == "turn" and not _in_adv:
			turn_ends += 1   # Ataque Dirigido: cambia de jugador sin pasar por _advance
		return super(type, data, to)


const BAL_VARIANTS := {
	"A": {"d": "Clásico (plus=false)", "plus": false, "packs": [], "rules": {}},
	"B": {"d": "Plus sin pack", "plus": true, "packs": [], "rules": {}},
	"C": {"d": "Plus+pack, mano 7", "plus": true, "packs": ["crypt"], "rules": {}},
	"D": {"d": "Plus+pack, mano 6", "plus": true, "packs": ["crypt"], "rules": {"hand": 6}},
	"E": {"d": "Plus+pack, mano 5", "plus": true, "packs": ["crypt"], "rules": {"hand": 5}},
	"F": {"d": "Plus+pack, mano 7, bottom/bury<=1", "plus": true, "packs": ["crypt"], "rules": {"crypt_copies": {"draw_bottom": [1, 1], "bury": [1, 1]}}},
	"G": {"d": "Plus+pack, mano 6, bottom/bury<=1", "plus": true, "packs": ["crypt"], "rules": {"hand": 6, "crypt_copies": {"draw_bottom": [1, 1], "bury": [1, 1]}}},
	"H": {"d": "Plus+pack, mano 8", "plus": true, "packs": ["crypt"], "rules": {"hand": 8}},
	"I": {"d": "Plus+pack, mano 8, bottom/bury<=1", "plus": true, "packs": ["crypt"], "rules": {"hand": 8, "crypt_copies": {"draw_bottom": [1, 1], "bury": [1, 1]}}},
	"J": {"d": "Plus+pack, mano 8, bottom/bury/reverse/targeted/haunt<=1", "plus": true, "packs": ["crypt"], "rules": {"hand": 8, "crypt_copies": {"draw_bottom": [1, 1], "bury": [1, 1], "reverse": [0, 1], "targeted_attack": [0, 1], "haunt": [0, 1]}}},
	"K": {"d": "Plus+pack, mano 8, J + bottom/bury solo sin huella", "plus": true, "packs": ["crypt"], "rules": {"hand": 8, "crypt_copies": {"draw_bottom": [0, 1], "bury": [0, 1], "reverse": [0, 1], "targeted_attack": [0, 1], "haunt": [0, 1]}}},
	"L": {"d": "K + sin apocalypse ni soul_swap", "plus": true, "packs": ["crypt"], "rules": {"hand": 8, "crypt_copies": {"draw_bottom": [0, 1], "bury": [0, 1], "reverse": [0, 1], "targeted_attack": [0, 1], "haunt": [0, 1], "apocalypse": [0, 0], "soul_swap": [0, 0]}}},
	"M": {"d": "K + sin haunt ni reverse", "plus": true, "packs": ["crypt"], "rules": {"hand": 8, "crypt_copies": {"draw_bottom": [0, 1], "bury": [0, 1], "reverse": [0, 0], "targeted_attack": [0, 1], "haunt": [0, 0]}}},
	"N": {"d": "K + sin targeted ni reverse", "plus": true, "packs": ["crypt"], "rules": {"hand": 8, "crypt_copies": {"draw_bottom": [0, 1], "bury": [0, 1], "reverse": [0, 0], "targeted_attack": [0, 0], "haunt": [0, 1]}}},
}


static func _bal_arg(args: PackedStringArray, key: String, def: String) -> String:
	for a in args:
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return def


## Juega una partida de bots y rellena out con turns, actions, winner (índice de asiento), deaths y revives.
func _bal_game(n: int, seed_value: int, levels: Array, shift: int, v: Dictionary, out: Dictionary) -> bool:
	var rng := Rng.new(seed_value)
	var players: Array = []
	for i in n:
		players.append({"id": "b%d" % i, "name": "B%d" % i, "bot": true})
	var opts := {"players": players, "deck_mode": "official", "rng": rng, "now": 0}
	if v.plus:
		opts["plus"] = true
		opts["packs"] = v.packs
		opts["rules"] = v.rules
	var g := CountGame.new(opts)
	var lv := {}
	for i in n:
		lv["b%d" % i] = levels[(i + shift) % levels.size()]
	var bots := Bots.new(g, lv, rng.next, bool(v.plus))
	var now := 0
	var steps := 0
	var first := 0
	var actions := 0
	while g.over == null:
		steps += 1
		if steps > 20000:
			push_error("balance: partida interminable (semilla %d, %d jugadores)" % [seed_value, n])
			return false
		g.tick(now)
		bots.learn()
		var acted := false
		for k in n:
			var id := "b%d" % ((first + k) % n)
			var a := bots.decide(id)
			if a.is_empty():
				continue
			var err := g.act(id, a, now)
			bots.note(id, a, err)
			bots.learn()
			if err == "":
				actions += 1
			acted = true
			first = (first + k + 1) % n
			break
		if acted:
			now += 400
		else:
			var d := g.next_deadline()
			if g.over != null:
				break
			if d < 0:
				push_error("balance: partida atascada (semilla %d, %d jugadores)" % [seed_value, n])
				return false
			now = maxi(now + 1, d)
	var deaths := 0
	var revives := 0
	for e: Dictionary in g.events:
		if e.type == "died":
			deaths += 1
		elif e.type == "revived":
			revives += 1
	out["turns"] = g.turn_ends
	out["actions"] = actions
	out["winner"] = int(str(g.over.winner).substr(1)) if g.over.winner != null else -1
	out["deaths"] = deaths
	out["revives"] = revives
	return true


func _bal_median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	if b.is_empty():
		return 0.0
	var m := b.size() / 2
	return float(b[m]) if b.size() % 2 == 1 else (float(b[m - 1]) + float(b[m])) / 2.0


## Duelo 2 jugadores con la variante: % de victorias de `a` sobre `b` (asientos alternados).
func _bal_duel(v: Dictionary, a: String, b: String, n: int) -> int:
	var w := 0
	for i in n:
		var out := {}
		var a_first := i % 2 == 1
		if not _bal_game(2, 9000 + i, [a, b] if a_first else [b, a], 0, v, out):
			continue
		if out.winner == (0 if a_first else 1):
			w += 1
	return int(round(100.0 * w / n))


func _balance(args: PackedStringArray) -> void:
	var games := int(_bal_arg(args, "games", "400"))
	var base_seed := int(_bal_arg(args, "seed", "50000"))
	var ids := Array(_bal_arg(args, "variants", ",".join(PackedStringArray(BAL_VARIANTS.keys()))).split(",", false))
	var counts := Array(_bal_arg(args, "players", "2,3,4,5").split(",", false)).map(func(s: String) -> int: return int(s))
	var sets := Array(_bal_arg(args, "levels", "mixed,normal").split(",", false))
	var diff := Array(_bal_arg(args, "difficulty", "").split(",", false))
	if not ids.has("A"):
		ids.push_front("A")   # referencia obligatoria: de ella salen % de duración y umbral de «larga»
	var t0 := Time.get_ticks_msec()
	for n: int in counts:
		print("\n=== %d jugadores, %d partidas por celda (mazo official, semillas %d+) ===" % [n, games, base_seed])
		print("turnos = veces que un jugador termina un turno; dur% = turnos medios frente a A con los mismos niveles; >2xMed = % de partidas con más del doble de la mediana de turnos de A")
		print("%-3s %-8s %6s %6s %7s %7s  %-*s %6s %6s %6s %7s" % ["var", "niveles", "t.med", "t.mdn", "dur%", "accion", n * 5 + 4, "victoria por asiento %", "maxdev", "muert", "reviv", ">2xMed"])
		var ref := {}   # niveles -> {mean, med}
		for vid: String in ids:
			var v: Dictionary = BAL_VARIANTS[vid]
			for lvset: String in sets:
				var levels: Array = ["easy", "normal", "hard"] if lvset == "mixed" else ["normal"]
				var turns: Array = []
				var acts := 0.0
				var deaths := 0.0
				var revs := 0.0
				var wins: Array = []
				wins.resize(n)
				wins.fill(0)
				var done := 0
				for i in games:
					var out := {}
					if not _bal_game(n, base_seed + i * 37 + n, levels, i, v, out):
						continue
					done += 1
					turns.append(out.turns)
					acts += out.actions
					deaths += out.deaths
					revs += out.revives
					if out.winner >= 0:
						wins[out.winner] += 1
				var tsum := 0
				for t: int in turns:
					tsum += t
				var tmean := float(tsum) / maxi(done, 1)
				var tmed := _bal_median(turns)
				if vid == "A":
					ref[lvset] = {"mean": tmean, "med": tmed}
				var r: Dictionary = ref[lvset]
				var long := 0
				for t: int in turns:
					if t > 2.0 * r.med:
						long += 1
				var ws: Array = []
				var maxdev := 0.0
				for w: int in wins:
					var pct := 100.0 * w / maxi(done, 1)
					ws.append("%4.1f" % pct)
					maxdev = maxf(maxdev, pct - 100.0 / n)
				print("%-3s %-8s %6.1f %6.1f %+6.0f%% %7.0f  %-*s %6.1f %6.2f %6.2f %6.1f%%" % [vid, lvset, tmean, tmed, 100.0 * (tmean / r.mean - 1.0), acts / maxi(done, 1), n * 5 + 4, " ".join(PackedStringArray(ws)), maxdev, deaths / maxi(done, 1), revs / maxi(done, 1), 100.0 * long / maxi(done, 1)])
	if not diff.is_empty():
		print("\n=== Dificultad (2 jugadores, 400 partidas por duelo; objetivo: difícil>normal>fácil) ===")
		for vid: String in diff:
			var v: Dictionary = BAL_VARIANTS[vid]
			print("%s (%s): difícil vs normal %d%%   normal vs fácil %d%%   difícil vs fácil %d%%" % [vid, v.d, _bal_duel(v, "hard", "normal", 400), _bal_duel(v, "normal", "easy", 400), _bal_duel(v, "hard", "easy", 400)])
	print("\nLeyenda: " + "; ".join(PackedStringArray(BAL_VARIANTS.keys().map(func(k: String) -> String: return "%s = %s" % [k, BAL_VARIANTS[k].d]))))
	print("(%d ms)" % (Time.get_ticks_msec() - t0))
