class_name LocalMatch
extends GameSession
## Partida local: un jugador humano contra la IA, todo en este dispositivo.
## Es el "anfitrión" de la partida: tiene el motor de reglas, hace avanzar el reloj y mueve a los bots.
## La pantalla de juego solo usa `view()`, `act()` y la señal `updated`; una partida en red ofrecerá lo mismo.

const BOT_NAMES := ["Bigotes", "Garritas", "Pelusa", "Don Miau"]
const MIX := ["easy", "normal", "hard", "normal"]

var game: ZKGame
var bots: ZKBots
var levels := {}
var _due := {}          # id del bot -> instante (ms) en que hará su jugada
var _sig := ""
var _rng: ZKRng
var _plus := false
var _me_delay := 900     # solo en modo demostración: cuánto tarda la IA en jugar por el humano


## opts: {name, rivals: 1..4, level: easy|normal|hard|mix, deck_mode, autoplay?: bool, seed?: int, plus?: bool, packs?: [], rules?: {}}
func start(opts: Dictionary) -> void:
	me_id = "p0"
	var my_avatar := int(opts.get("avatar", 0))
	var players: Array = [{"id": me_id, "name": opts.get("name", "Tú"), "avatar": my_avatar, "bot": false}]
	levels = {}
	for i in int(opts.get("rivals", 2)):
		var id := "p%d" % (i + 1)
		players.append({"id": id, "name": BOT_NAMES[i % BOT_NAMES.size()], "avatar": (my_avatar + i + 1) % 6, "bot": true})
		levels[id] = MIX[i % MIX.size()] if opts.get("level", "normal") == "mix" else opts.get("level", "normal")
	if opts.get("autoplay", false):
		levels[me_id] = "normal"   # modo demostración: la IA juega también por el humano
		_me_delay = int(opts.get("me_delay", 900))
	_rng = ZKRng.new(int(opts.get("seed", randi())))
	_plus = bool(opts.get("plus", false))
	var game_opts := {"players": players, "deck_mode": opts.get("deck_mode", "official"), "rng": _rng, "now": now()}
	if _plus:
		game_opts["plus"] = true
		game_opts["packs"] = opts.get("packs", [])
		game_opts["rules"] = opts.get("rules", {})
		game_opts["names"] = CardDB.names_for(opts.get("packs", []))
	game = ZKGame.new(game_opts)
	bots = ZKBots.new(game, levels, _rng.next, _plus)
	_due = {}
	_sig = ""


func view() -> Dictionary:
	return game.view(me_id, now())


## Acción del jugador humano. Devuelve "" o el motivo por el que no se pudo.
func act(a: Dictionary) -> String:
	var err := game.act(me_id, a, now())
	_check_changed()
	return err


func is_plus() -> bool:
	return _plus


func level_of(id: String) -> String:
	return levels.get(id, "")


func _process(_delta: float) -> void:
	if game == null:
		return
	var t := now()
	game.tick(t)
	bots.learn()
	if game.over == null:
		for id: String in levels:
			if _due.has(id):
				if t >= _due[id]:
					_due.erase(id)
					var a := bots.decide(id)
					if not a.is_empty():
						bots.note(id, a, game.act(id, a, t))
						bots.learn()
			elif not bots.decide(id).is_empty():
				_due[id] = t + (_me_delay if id == me_id else 650 + int(_rng.next() * 900))
	_check_changed()


func _check_changed() -> void:
	var s := game.signature()
	if s != _sig:
		_sig = s
		updated.emit()
