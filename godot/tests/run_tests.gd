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


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	_test_versions()
	_test_rng_and_setup()
	_test_traces()
	_test_simulations()
	_test_difficulty()
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


static func _mk(n: int, seed_value: int, mode: String = "official", rng: Rng = null) -> Game:
	var players: Array = []
	for i in n:
		players.append({"id": "b%d" % i, "name": "B%d" % i, "bot": true})
	return Game.new({"players": players, "deck_mode": mode, "rng": rng if rng != null else Rng.new(seed_value), "now": 0})


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
func _simulate(n: int, seed_value: int, mode: String, levels: Array) -> String:
	var rng := Rng.new(seed_value)
	var g := _mk(n, 0, mode, rng)
	var lv := {}
	for i in n:
		lv["b%d" % i] = levels[i % levels.size()]
	var bots := Bots.new(g, lv, rng.next)
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
