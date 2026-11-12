class_name RoomHost
extends Node
## Sala de juego en el dispositivo anfitrión: lobby, reconexión por ficha (token), bots y la partida.
## Port de la sala de web/www/room.js. Habla con cada jugador mediante mensajes {t: ...}:
##   recibe: hello (con proto), set, addBot, botLevel, kick, settings, start, toLobby, act
##   envía:  welcome, lobby, state, err, kicked, full

signal local_message(m: Dictionary)

const BOT_NAMES := ["Bigotes", "Garritas", "Pelusa", "Don Miau", "Ronroneo", "Michi"]
const LEVELS := ["easy", "normal", "hard"]
const MAX_PLAYERS := 5
const LOCAL := 1   # el propio anfitrión

const PACKS := ["crypt"]
const PLUS_REJECT := "Esta sala es de Zombie Kittens Plus. Actualiza el juego para entrar."

var players: Array[Dictionary] = []   # {id, token, name, avatar, bot, level, peer}  (peer 0 = sin conexión)
## {deck_mode, plus, packs, rules}. `plus` se fija al crear la sala y no cambia; en una sala clásica packs = [] y rules = {}.
var settings := {"deck_mode": "official", "plus": false, "packs": [], "rules": {}}
var game: ZKGame
var bots: ZKBots
var _rng: ZKRng
var _due := {}
var _sig := ""
var _next_id := 1
## Plus (M-06): victorias por id de jugador mientras la sala exista. Solo se llena en salas Plus.
var scores := {}
var _scored := false   # la partida en curso ya se ha contado


func _ready() -> void:
	Net.message.connect(on_msg)
	Net.peer_left.connect(_on_peer_left)


func now() -> int:
	return Time.get_ticks_msec()


func send(peer: int, m: Dictionary) -> void:
	if peer == LOCAL:
		local_message.emit.call_deferred(m.duplicate(true))
	elif peer > LOCAL:
		Net.send(peer, m)


## Datos que el anfitrión anuncia en la red.
func beacon_info() -> Dictionary:
	var host_name := ""
	for p in players:
		if p.peer == LOCAL:
			host_name = p.name
	return {"name": host_name, "players": players.size(), "started": game != null, "plus": bool(settings.plus), "proto": Net.PROTO}


## Fija el modo de la sala. Solo vale antes de que entre nadie (el anfitrión local lo indica al crearla).
func configure(plus: bool) -> void:
	if not players.is_empty() or game != null:
		return
	settings.plus = plus


func _by_peer(peer: int) -> Dictionary:
	for p in players:
		if p.peer == peer and peer != 0:
			return p
	return {}


func _by_id(id: Variant) -> Dictionary:
	for p in players:
		if p.id == id:
			return p
	return {}


func _on_peer_left(peer: int) -> void:
	var p := _by_peer(peer)
	if p.is_empty():
		return
	p.peer = 0
	if game != null:
		game.set_connected(p.id, false, now())
		_broadcast_state()
	else:
		_drop(p)
		_send_lobby()


## Saca a un jugador de la sala y borra su marcador.
func _drop(p: Dictionary) -> void:
	players.erase(p)
	scores.erase(p.id)


func on_msg(peer: int, m: Dictionary) -> void:
	var t: String = m.get("t", "")
	if t == "hello":
		_hello(peer, m)
		return
	var p := _by_peer(peer)
	if p.is_empty():
		return
	var is_host := peer == LOCAL
	match t:
		"set":
			if game != null:
				return
			if m.has("name"):
				p.name = _clean_name(str(m.name), p)
			if m.has("avatar"):
				p.avatar = int(m.avatar) % 6
			_send_lobby()
		"addBot":
			if not is_host or game != null or players.size() >= MAX_PLAYERS:
				return
			var used: Array = players.map(func(x: Dictionary) -> String: return x.name)
			var bot_name := "Bot"
			for n: String in BOT_NAMES:
				if not used.has(n):
					bot_name = n
					break
			var avatars: Array = players.map(func(x: Dictionary) -> int: return x.avatar)
			var av := 0
			for i in 6:
				if not avatars.has(i):
					av = i
					break
			var level: String = m.get("level", "normal")
			players.append({"id": "p%d" % _next_id, "token": "", "name": bot_name, "avatar": av, "bot": true, "level": level if LEVELS.has(level) else "normal", "peer": 0})
			_next_id += 1
			_send_lobby()
		"botLevel":
			if not is_host or game != null:
				return
			var b := _by_id(m.get("id"))
			if b.is_empty() or not b.bot:
				return
			b.level = LEVELS[(LEVELS.find(b.level) + 1) % LEVELS.size()]
			_send_lobby()
		"kick":
			if not is_host or game != null:
				return
			var k := _by_id(m.get("id"))
			if k.is_empty() or k.peer == LOCAL:
				return
			_drop(k)
			if k.peer > LOCAL:
				send(k.peer, {"t": "kicked", "msg": "El anfitrión te sacó de la sala."})
			_send_lobby()
		"settings":
			if not is_host or game != null:
				return
			if m.get("deck_mode", "") in ["official", "full"]:
				settings.deck_mode = m.deck_mode
			if settings.plus:   # packs y reglas solo existen en salas Plus; en las clásicas se rechazan en silencio
				if m.get("packs") is Array:
					settings.packs = (m.packs as Array).filter(func(k: Variant) -> bool: return k is String and PACKS.has(k))
				if m.get("rules") is Dictionary:
					settings.rules = _clean_rules(m.rules)
			_send_lobby()
		"start":
			if not is_host or game != null:
				return
			if players.size() < 2:
				send(peer, {"t": "err", "msg": "Se necesitan al menos 2 jugadores."})
				return
			_start()
		"toLobby":
			if not is_host:
				return
			game = null
			bots = null
			for q: Dictionary in players.duplicate():
				if not q.bot and q.peer == 0:
					_drop(q)
			_send_lobby()
		"act":
			if game == null:
				return
			var err := game.act(p.id, m.get("a"), now())
			if err != "":
				send(peer, {"t": "err", "msg": err})
			_check_changed()


func _clean_name(raw: String, me: Dictionary) -> String:
	var n := raw.strip_edges().left(14)
	for ch: String in ["<", ">", "&", "\"", "'"]:
		n = n.replace(ch, "")
	if n == "":
		n = "Gatito"
	var base := n
	var k := 2
	while players.any(func(x: Dictionary) -> bool: return not is_same(x, me) and x.name == n):
		n = "%s %d" % [base.left(12), k]
		k += 1
	return n


## Solo deja pasar las reglas opcionales conocidas, con los mismos límites que `ZKGame._sanitize_rules`.
## `hand` null o 0 significa «normal» y se quita de las reglas (el motor decide: 7, u 8 con La Cripta).
func _clean_rules(raw: Dictionary) -> Dictionary:
	var out: Dictionary = settings.rules.duplicate()
	if _is_num(raw.get("turn_ms")):
		var t := int(raw.turn_ms)
		out["turn_ms"] = 0 if t <= 0 else clampi(t, 5000, 600000)
	if raw.has("hand"):
		if raw.hand == null or (_is_num(raw.hand) and int(raw.hand) <= 0):
			out.erase("hand")
		elif _is_num(raw.hand):
			out["hand"] = clampi(int(raw.hand), 4, 8)
	for k: String in ["nope_fixed", "sudden_death"]:
		if raw.get(k) is bool:
			out[k] = raw[k]
	return out


static func _is_num(v: Variant) -> bool:
	return v is int or (v is float and is_finite(v))


func _hello(peer: int, m: Dictionary) -> void:
	# Las salas Plus exigen cliente con protocolo 3; las clásicas aceptan a cualquiera (clientes 2.x incluidos)
	if settings.plus and int(m.get("proto", 0)) < 3:
		send(peer, {"t": "full", "msg": PLUS_REJECT})
		return
	var token := str(m.get("token", ""))
	var p := {}
	for x in players:
		if token != "" and x.token == token:
			p = x
	if not p.is_empty():
		# Vuelve un jugador conocido: recupera su asiento y su mano
		if p.peer > LOCAL and p.peer != peer:
			send(p.peer, {"t": "kicked", "msg": "Te conectaste desde otro lugar."})
		p.peer = peer
	else:
		if game != null:
			send(peer, {"t": "full", "msg": "La partida ya empezó. Espera a la siguiente."})
			return
		if players.size() >= MAX_PLAYERS:
			send(peer, {"t": "full", "msg": "La sala está llena (máximo 5 jugadores)."})
			return
		# Si el gato elegido ya está en la sala, se le da el siguiente libre
		var taken: Array = players.map(func(x: Dictionary) -> int: return x.avatar)
		var avatar := int(m.get("avatar", 0)) % 6
		for _i in 6:
			if not taken.has(avatar):
				break
			avatar = (avatar + 1) % 6
		p = {"id": "p%d" % _next_id, "token": token, "name": "", "avatar": avatar, "bot": false, "level": "", "peer": peer}
		_next_id += 1
		p.name = _clean_name(str(m.get("name", "Gatito")), p)
		players.append(p)
	send(peer, {"t": "welcome", "you": p.id, "host": peer == LOCAL})
	if game != null:
		game.set_connected(p.id, true, now())
		send(peer, _lobby_msg())          # para que conozca nombres y niveles
		_broadcast_state()
	else:
		_send_lobby()


func _lobby_msg() -> Dictionary:
	var m := {
		"t": "lobby", "settings": settings.duplicate(true), "started": game != null,
		"players": players.map(func(p: Dictionary) -> Dictionary: return {"id": p.id, "name": p.name, "avatar": p.avatar, "bot": p.bot, "host": p.peer == LOCAL, "level": p.level}),
	}
	if settings.plus:
		m["scores"] = scores.duplicate()   # M-06: solo en salas Plus
	return m


func _send_lobby() -> void:
	var m := _lobby_msg()
	for p in players:
		if p.peer > 0:
			send(p.peer, m)


func _start() -> void:
	var list: Array = []
	var levels := {}
	for p in players:
		list.append({"id": p.id, "name": p.name, "avatar": p.avatar, "bot": p.bot})
		if p.bot:
			levels[p.id] = p.level
	_rng = ZKRng.new(randi())
	var game_opts := {"players": list, "deck_mode": settings.deck_mode, "rng": _rng, "now": now()}
	if settings.plus:
		game_opts["plus"] = true
		game_opts["packs"] = settings.packs.duplicate()
		game_opts["rules"] = settings.rules.duplicate()
		game_opts["names"] = CardDB.names_for(settings.packs)
	game = ZKGame.new(game_opts)
	bots = ZKBots.new(game, levels, _rng.next, bool(settings.plus))
	for p in players:
		if not p.bot and p.peer == 0:
			game.set_connected(p.id, false, now())
	_due = {}
	_sig = ""
	_scored = false
	_send_lobby()
	_check_changed()


func _process(_delta: float) -> void:
	if game == null:
		return
	var t := now()
	game.tick(t)
	bots.learn()
	if game.over == null:
		for id: String in bots.levels:
			if _due.has(id):
				if t >= _due[id]:
					_due.erase(id)
					var a := bots.decide(id)
					if not a.is_empty():
						bots.note(id, a, game.act(id, a, t))
						bots.learn()
			elif not bots.decide(id).is_empty():
				_due[id] = t + 650 + int(_rng.next() * 900)
	_check_changed()


## Plus: suma una victoria al ganador (una sola vez por partida) y reenvía el lobby con el marcador nuevo.
func _score_if_over() -> void:
	if not settings.plus or _scored or game == null or game.over == null:
		return
	_scored = true
	var w: Variant = game.over.get("winner")
	if w is String and not _by_id(w).is_empty():
		scores[w] = int(scores.get(w, 0)) + 1
	_send_lobby()


func _check_changed() -> void:
	_score_if_over()
	var s := game.signature()
	if s != _sig:
		_sig = s
		_broadcast_state()


func _broadcast_state() -> void:
	if game == null:
		return
	var t := now()
	for p in players:
		if p.peer > 0:
			send(p.peer, {"t": "state", "view": game.view(p.id, t)})
