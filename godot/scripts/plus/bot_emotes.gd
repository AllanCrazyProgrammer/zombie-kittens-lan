class_name BotEmotes
extends RefCounted
## IA-04: los bots de Plus reaccionan a veces. Solo MIRA los eventos públicos de la partida y devuelve las
## reacciones que toca enviar; nunca toca el motor ni su generador de azar (usa uno propio), así que la partida
## evoluciona exactamente igual con o sin reacciones.
##   😹 / 👏  explota un rival      🙀  le atacan o le roban      😾  le anulan una jugada con Nop
##   💀       muere él              🙏  el Putrefacto está arriba y le toca robar

const CHANCE := 0.4
const CHANCE_RARE := 0.7      # muerte propia y Putrefacto arriba: sucesos más claros, reaccionan más a menudo
const COOLDOWN_MS := 8000     # por bot
const DELAY_MIN_MS := 500
const DELAY_MAX_MS := 1500

var _rng := RandomNumberGenerator.new()
var _seq := 0
var _last := {}               # bot -> instante de su última reacción (ms)
var _pending: Array[Dictionary] = []   # {id, e, at}
var _plays: Array[Dictionary] = []     # jugadas aún sin resolver: {player, eff}


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Empieza a mirar a partir de los eventos que ya existen (no reacciona a lo anterior).
func start(game: ZKGame) -> BotEmotes:
	_seq = game.seq
	return self


## Lee los eventos nuevos de `game` y encola reacciones de los bots `bot_ids`.
func observe(game: ZKGame, bot_ids: Array, now: int) -> void:
	for e: Dictionary in game.events:
		if e.seq <= _seq:
			continue
		_seq = e.seq
		if e.has("to"):
			continue          # solo eventos públicos
		_on_event(game, e, bot_ids, now)


## Reacciones listas para enviar ahora: [{id, e}]. Respeta la espera de 8 s de cada bot.
func due(now: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keep: Array[Dictionary] = []
	for p: Dictionary in _pending:
		if now < int(p.at):
			keep.append(p)
		elif now - int(_last.get(p.id, -COOLDOWN_MS)) >= COOLDOWN_MS:
			_last[p.id] = now
			out.append({"id": p.id, "e": p.e})
	_pending = keep
	return out


func _on_event(game: ZKGame, e: Dictionary, bots: Array, now: int) -> void:
	var cands: Array[Array] = []    # [bot, índice, probabilidad]
	match e.type:
		"play":
			_plays.append({"player": e.player, "eff": str(e.get("eff", ""))})
			if _plays.size() > 12:
				_plays.pop_front()
		"cancel":
			for i in range(_plays.size() - 1, -1, -1):
				if _plays[i].eff == str(e.get("eff", "")):
					var victim: String = _plays[i].player
					_plays.remove_at(i)
					if bots.has(victim):
						cands.append([victim, 2, CHANCE])
					break
		"attack":
			var t: String = str(e.get("target", ""))
			if bots.has(t) and t != e.get("player", ""):
				cands.append([t, 1, CHANCE])
		"steal":
			var t: String = str(e.get("target", ""))
			if bots.has(t):
				cands.append([t, 1, CHANCE])
		"died":
			var who: String = str(e.get("player", ""))
			for b: String in bots:
				if b == who:
					cands.append([b, 3, CHANCE_RARE])
				else:
					cands.append([b, 0 if _rng.randf() < 0.5 else 5, CHANCE * 0.6])
		"turn":
			var cur: String = str(e.get("player", ""))
			if bots.has(cur) and game.rot_depth() == 0:
				cands.append([cur, 4, CHANCE_RARE])
	if cands.is_empty():
		return
	var c: Array = cands[_rng.randi() % cands.size()]    # como mucho una reacción por suceso
	if _rng.randf() >= float(c[2]):
		return
	var id: String = c[0]
	if now - int(_last.get(id, -COOLDOWN_MS)) < COOLDOWN_MS:
		return
	for p: Dictionary in _pending:
		if p.id == id:
			return
	_pending.append({"id": id, "e": int(c[1]), "at": now + _rng.randi_range(DELAY_MIN_MS, DELAY_MAX_MS)})
