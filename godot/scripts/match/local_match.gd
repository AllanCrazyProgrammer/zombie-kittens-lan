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
var traits := {}        # id del bot -> rasgo de personalidad (solo Plus, IA-03)
var _due := {}          # id del bot -> instante (ms) en que hará su jugada
var _sig := ""
var _rng: ZKRng
var _plus := false
var _emotes: BotEmotes     # IA-04: reacciones de los bots (solo Plus); su azar es propio
var _emote_at := -100000  # última reacción enviada por el humano (ms)
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
	traits = {}
	if _plus:
		for p: Dictionary in players:
			if p.bot:
				var tr := ZKBots.trait_for_name(p.name)
				if tr != "":
					traits[p.id] = tr
		bots.set_traits(traits)
	_due = {}
	_sig = ""
	_emotes = BotEmotes.new(int(opts.get("emote_seed", 0))).start(game) if _plus else null
	_emote_at = -100000


func view() -> Dictionary:
	return game.view(me_id, now())


## Acción del jugador humano. Devuelve "" o el motivo por el que no se pudo.
func act(a: Dictionary) -> String:
	var err := game.act(me_id, a, now())
	_check_changed()
	return err


func is_plus() -> bool:
	return _plus


## Reacción del jugador humano: se emite al momento, con el mismo límite (1 cada 3 s) que pone la sala.
func send_emote(index: int) -> void:
	if not _plus or game == null or game.over != null or not EmoteSet.valid(index):
		return
	var t := now()
	if t - _emote_at < EmoteSet.COOLDOWN_MS:
		return
	_emote_at = t
	emote.emit(me_id, index)


func scores() -> Dictionary:
	return {}


## Rasgo de personalidad del bot ("" en clásico o si no tiene). Ver ZKBots.TRAIT_LABELS.
func trait_of(id: String) -> String:
	return traits.get(id, "")


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
	if _emotes != null:
		_emotes.observe(game, _bot_ids(), t)
		if game.over == null:
			for r: Dictionary in _emotes.due(t):
				emote.emit(r.id, r.e)


func _bot_ids() -> Array:
	return game.players.filter(func(p: ZKGame.Player) -> bool: return p.bot).map(func(p: ZKGame.Player) -> String: return p.id)


func _check_changed() -> void:
	var s := game.signature()
	if s != _sig:
		_sig = s
		updated.emit()
