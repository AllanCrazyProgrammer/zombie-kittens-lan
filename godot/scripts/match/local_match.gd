class_name LocalMatch
extends Node
## Partida local: un jugador humano contra la IA, todo en este dispositivo.
## Es el "anfitrión" de la partida: tiene el motor de reglas, hace avanzar el reloj y mueve a los bots.
## La pantalla de juego solo usa `view()`, `act()` y la señal `updated`; una partida en red ofrecerá lo mismo.

signal updated

const BOT_NAMES := ["Bigotes", "Garritas", "Pelusa", "Don Miau"]
const MIX := ["easy", "normal", "hard", "normal"]

var game: ZKGame
var bots: ZKBots
var me_id := "p0"
var levels := {}
var _due := {}          # id del bot -> instante (ms) en que hará su jugada
var _sig := ""
var _rng: ZKRng
var _me_delay := 900     # solo en modo demostración: cuánto tarda la IA en jugar por el humano


## opts: {name, rivals: 1..4, level: easy|normal|hard|mix, deck_mode, autoplay?: bool, seed?: int}
func start(opts: Dictionary) -> void:
	var players: Array = [{"id": me_id, "name": opts.get("name", "Tú"), "bot": false}]
	levels = {}
	for i in int(opts.get("rivals", 2)):
		var id := "p%d" % (i + 1)
		players.append({"id": id, "name": BOT_NAMES[i % BOT_NAMES.size()], "bot": true})
		levels[id] = MIX[i % MIX.size()] if opts.get("level", "normal") == "mix" else opts.get("level", "normal")
	if opts.get("autoplay", false):
		levels[me_id] = "normal"   # modo demostración: la IA juega también por el humano
		_me_delay = int(opts.get("me_delay", 900))
	_rng = ZKRng.new(int(opts.get("seed", randi())))
	game = ZKGame.new({"players": players, "deck_mode": opts.get("deck_mode", "official"), "rng": _rng, "now": now()})
	bots = ZKBots.new(game, levels, _rng.next)
	_due = {}
	_sig = ""


func now() -> int:
	return Time.get_ticks_msec()


func view() -> Dictionary:
	return game.view(me_id, now())


## Acción del jugador humano. Devuelve "" o el motivo por el que no se pudo.
func act(a: Dictionary) -> String:
	var err := game.act(me_id, a, now())
	_check_changed()
	return err


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


## Huella barata del estado: si cambia, la pantalla se redibuja.
func _check_changed() -> void:
	var g := game
	var s := "%d|%d|%d|%d|%d|%d|%s" % [g.seq, g.cur, g.turns_left, g.draw.size(), g.discard.size(), g.stack.size(), "o" if g.over != null else ""]
	var top: Variant = g.top()
	if top != null:
		s += "|%d/%d/%d" % [top.id, top.nopes, top.passed.size()]
	if g.prompt != null:
		var pr: Dictionary = g.prompt
		s += "|" + pr.type + str(pr.get("revived")) + str(pr.get("pendingPos") != null)
		if pr.has("waiting"):
			s += str(pr.waiting.size())
		if pr.has("watchers"):
			s += str(pr.watchers.size())
	if s != _sig:
		_sig = s
		updated.emit()
