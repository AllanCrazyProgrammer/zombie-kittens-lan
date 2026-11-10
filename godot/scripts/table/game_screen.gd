class_name GameScreen
extends Node3D
## Pantalla de juego: sincroniza la mesa 3D (mano, mazo, descarte) y los controles con el estado de la partida.
## No contiene reglas: lee `session.view()` y envía acciones con `session.act()`.

signal exit_requested
signal rematch_requested
signal lobby_requested

const DECK_POS := Vector3(-0.5, 0, -0.3)
const DISCARD_POS := Vector3(0.5, 0, -0.3)
const HAND_STEP := 0.012
const HAND_SCALE := 0.86
const LEVEL_NAMES := {"easy": "Fácil", "normal": "Normal", "hard": "Difícil"}

var session: GameSession
var world: TableWorld
var _v: Dictionary = {}
var _sel: Array[String] = []
var _hand := {}            # id -> Card3D
var _discard_nodes := {}   # id -> Card3D
var _deck_cards: Array[Card3D] = []
var _deck_label: Label3D
var _hand_root: Node3D
var _hand_pivot: Node3D
var _seq := 0
var _modal := {}           # ventana propia de la interfaz (elegir objetivo, ver el futuro...)
var _ins: Array[int] = [0, 0]
var _give_sel := ""
var _log_last := ""
var _time := 0.0
var _timers: Array = []    # [barra, fin_ms, total_ms]
var _modal_title := ""
var _seats := {}           # id del rival -> {pos, root, avatar, cards}
var _turn_light: OmniLight3D
var _ek: Card3D            # el Gatito Explosivo recién sacado, mientras se decide su destino
var _fxq: Array[Callable] = []
var _fx_running := false
var _me_bar: HBoxContainer
## Tutorial: muestra consejos según lo que pasa en la partida (cada uno, una sola vez)
var coach := false
var _tip := ""
var _tips_seen := {}
const TIPS := {
	"intro": "¡Bienvenido! El objetivo es NO sacar el Gatito Explosivo. Gana el último gato con vida.",
	"hand": "Estas son tus cartas. Toca una para levantarla y leer qué hace.",
	"rivals": "Arriba ves a tus rivales y cuántas cartas tienen. El contador amarillo son las cartas que quedan en el mazo.",
	"turn": "Es tu turno. Puedes jugar las cartas que quieras (o ninguna). Para terminar, roba una carta tocando el mazo.",
	"selected": "Si la carta se puede jugar ahora, aparece el botón JUGAR. Toca otra carta igual para armar una pareja y robarle una carta a un rival.",
	"window": "Cuando alguien juega una carta hay unos segundos para anularla con un Nop. La barra amarilla es el tiempo que queda.",
	"nope": "¡Tienes un Nop! Toca ¡NOP! para anular esta jugada, o «Dejar pasar» si no te importa.",
	"risk": "El riesgo de explotar ya es alto. Antes de robar, considera usar Saltar, Ataque o Ver el Futuro.",
	"dead": "Explotaste, pero conservas tu mano. Aún puedes jugar Nop y cartas ⚡, y otro jugador puede revivirte con su Gatito Zombi.",
}

var _turn: Label
var _turn_panel: PanelContainer
var _opps: HBoxContainer
var _risk: Label
var _status: Label
var _status_timer: ProgressBar
var _buttons: HBoxContainer
var _info_slot: VBoxContainer
var _modal_root: Control
var _fx_root: Control
var _toasts: VBoxContainer


func setup(p_session: GameSession, p_world: TableWorld) -> GameScreen:
	session = p_session
	world = p_world
	return self


func _ready() -> void:
	_hand_root = Node3D.new()
	_hand_root.position = Vector3(0, 0, 1.28)
	_hand_pivot = Node3D.new()
	_hand_pivot.rotation_degrees.x = 9.0
	_hand_pivot.position.y = 0.05
	_hand_root.add_child(_hand_pivot)
	add_child(_hand_root)
	_deck_label = Label3D.new()
	_deck_label.font = UIKit.TITLE_FONT
	_deck_label.font_size = 96
	_deck_label.pixel_size = 0.0022
	_deck_label.outline_size = 28
	_deck_label.modulate = UIKit.C.gold
	_deck_label.outline_modulate = UIKit.C.dark
	_deck_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_deck_label.no_depth_test = true
	add_child(_deck_label)
	_turn_light = OmniLight3D.new()
	_turn_light.light_color = UIKit.C.toxic
	_turn_light.light_energy = 2.4
	_turn_light.omni_range = 1.6
	_turn_light.visible = false
	add_child(_turn_light)
	_build_hud()
	session.updated.connect(_refresh)
	session.error.connect(func(msg: String) -> void: _toast(msg, true))
	_refresh()


func _process(delta: float) -> void:
	_time += delta
	_hand_root.position.y = sin(_time * 1.4) * 0.006
	for id: String in _seats:
		var av: Sprite3D = _seats[id].avatar
		var is_cur: bool = not _v.is_empty() and _v.cur == id
		av.scale = Vector3.ONE * (1.0 + (0.06 * sin(_time * 5.0) if is_cur else 0.0))
	var now := session.now()
	for t: Array in _timers:
		if is_instance_valid(t[0]):
			t[0].value = clampf(float(t[1] - now) / float(maxi(1, t[2])), 0.0, 1.0) * 100.0


## Resumen de lo que hay en pantalla (para las capturas de depuración).
func debug_state() -> String:
	return "%s | ventana=%s | botones=%d | sel=%d" % [_status.text.replace("\n", " ").left(60), _modal_title, _buttons.get_child_count(), _sel.size()]


## Para la prueba automática de toques: carta de la mano que se puede jugar sola (sin elegir objetivo), o null.
func debug_playable_card() -> Card3D:
	for c: Dictionary in _v.hand:
		if _v.playable.get(c.id) is int or _v.playable.get(c.id) is float:
			if c.type != "nope":
				return _hand.get(c.id)
	return null


func debug_deck_card() -> Card3D:
	return _deck_cards.back() if _deck_cards.size() > 0 else null


func debug_can_draw() -> bool:
	return not _v.is_empty() and _my_turn() and _idle()


# ================================================================ sincronización con la partida

func _refresh() -> void:
	_v = session.view()
	var ids: Array = _v.hand.map(func(c: Dictionary) -> String: return c.id)
	for id: String in _sel.duplicate():
		if not ids.has(id):
			_sel.erase(id)
	if _give_sel != "" and not ids.has(_give_sel):
		_give_sel = ""
	if _modal.get("type", "") in ["target", "named"] and _sel.is_empty():
		_modal = {}
	_sync_seats()
	_process_events()
	_sync_deck()
	_sync_hand()
	_sync_discard()
	_update_hud()


func _me() -> Dictionary:
	return _player(_v.you)


func _player(id: Variant) -> Dictionary:
	for p: Dictionary in _v.players:
		if p.id == id:
			return p
	return {}


func _pname(id: Variant) -> String:
	return "Tú" if id == _v.you else _player(id).get("name", "?")


## Nombre como complemento: "a ti" / "a Bigotes".
func _to_name(id: Variant) -> String:
	return "ti" if id == _v.you else _player(id).get("name", "?")


func _my_turn() -> bool:
	return _v.cur == _v.you and _me().alive


func _idle() -> bool:
	return _v.prompt == null and _v.stack.is_empty() and _v.over == null


func _deck_top() -> Vector3:
	return DECK_POS + Vector3(0, 0.03 + _deck_cards.size() * 0.007, 0)


func _sync_deck() -> void:
	var want := clampi(_v.draw, 0, 14)
	while _deck_cards.size() > want:
		_deck_cards.pop_back().queue_free()
	while _deck_cards.size() < want:
		var c := Card3D.new().setup("back", false)
		c.position = DECK_POS + Vector3(0, 0.01 + _deck_cards.size() * 0.007, 0)
		c.rotation_degrees.y = randf_range(-3.0, 3.0)
		c.tapped.connect(_on_deck_tapped)
		add_child(c)
		_deck_cards.append(c)
	_deck_label.text = str(_v.draw)
	_deck_label.position = _deck_top() + Vector3(0, 0.3, 0)
	_deck_label.visible = _v.draw > 0


func _sorted_hand() -> Array:
	var order: Array = CardDB.types()
	var hand: Array = _v.hand.duplicate()
	hand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ia := order.find(a.type)
		var ib := order.find(b.type)
		return ia < ib if ia != ib else int(a.id.substr(1)) < int(b.id.substr(1)))
	return hand


func _sync_hand() -> void:
	var hand := _sorted_hand()
	var ids := {}
	var discard_ids := {}
	for d: Dictionary in _v.discard:
		discard_ids[d.id] = true
	for c: Dictionary in hand:
		ids[c.id] = true
		if not _hand.has(c.id):
			# Carta nueva: sale del mazo y vuela a la mano
			var n := Card3D.new().setup(c.type, true)
			n.card_id = c.id
			n.tapped.connect(_on_card_tapped)
			_hand_pivot.add_child(n)
			n.global_position = _deck_top()
			n.scale = Vector3.ONE * 0.6
			_hand[c.id] = n
	for id: String in _hand.keys():
		if ids.has(id):
			continue
		var n: Card3D = _hand[id]
		_hand.erase(id)
		n.set_glow(0.0)
		n.move_under(self)
		if discard_ids.has(id):
			_discard_nodes[id] = n          # la jugué: _sync_discard la lleva a la pila
		else:
			# La di o me la robaron: se va flotando
			var tw := n.fly_to(n.position + Vector3(0, 1.2, -1.6), n.rotation, 0.45, 0.3)
			tw.chain().tween_callback(n.queue_free)
	# Abanico: pivote común bajo la mesa, cada carta un escalón más alta que la anterior
	var count := hand.size()
	# Con muchas cartas el abanico se abre un poco más y las cartas se encogen para que se puedan tocar
	var total := clampf(33.0 + (count - 7) * 2.0, 33.0, 40.0)
	var spread := minf(9.0, total / maxf(1.0, count - 1.0))
	var hand_scale := clampf(HAND_SCALE - (count - 7) * 0.025, 0.72, HAND_SCALE)
	var radius := 2.3
	for i in count:
		var n: Card3D = _hand[hand[i].id]
		var ang := deg_to_rad((float(i) - (count - 1) / 2.0) * spread)
		var pos := Vector3(sin(ang) * radius, HAND_STEP * i, radius - cos(ang) * radius)
		var selected := _sel.has(hand[i].id)
		if selected:
			pos += Vector3(0, 0.1, -0.2)
		n.set_glow(0.16 if selected else 0.0)
		n.fly_to(pos, Vector3(0, -ang, 0), 0.3, hand_scale * (1.08 if selected else 1.0))


func _sync_discard() -> void:
	var all: Array = _v.discard
	var last: Array = all.slice(maxi(0, all.size() - 3))
	var keep := {}
	for i in last.size():
		var d: Dictionary = last[i]
		keep[d.id] = true
		var n: Card3D = _discard_nodes.get(d.id)
		if n == null:
			# Jugada de un rival: la carta llega desde el otro lado de la mesa
			n = Card3D.new().setup(d.type, true)
			n.card_id = d.id
			add_child(n)
			n.position = _pos_of(d.by) + Vector3(0, 0.25, 0)
			n.scale = Vector3.ONE * 0.5
			_discard_nodes[d.id] = n
		if not n.has_meta("yaw"):
			n.set_meta("yaw", deg_to_rad(randf_range(-16.0, 16.0)))
		n.fly_to(DISCARD_POS + Vector3(0, 0.012 + i * 0.008, 0), Vector3(0, n.get_meta("yaw"), 0), 0.34, HAND_SCALE)
	for id: String in _discard_nodes.keys():
		if not keep.has(id):
			_discard_nodes[id].queue_free()
			_discard_nodes.erase(id)


func _avatar_index(id: Variant) -> int:
	return int(_player(id).get("avatar", 0))


## Lugar de un jugador sobre la mesa (mi mano o el asiento del rival).
func _pos_of(id: Variant) -> Vector3:
	if _seats.has(id):
		return _seats[id].pos
	return Vector3(0, 0.15, 1.35)


## Rivales sentados al otro lado de la mesa: avatar, abanico de cartas boca abajo y luz de turno.
func _sync_seats() -> void:
	var n: int = _v.players.size()
	var my_idx := 0
	for i in n:
		if _v.players[i].id == _v.you:
			my_idx = i
	for k in range(1, n):
		var p: Dictionary = _v.players[(my_idx + k) % n]
		if not _seats.has(p.id):
			var a := 0.0 if n == 2 else deg_to_rad(lerpf(-36.0, 36.0, float(k - 1) / float(n - 2)))
			var dir := Vector3(sin(a), 0, -cos(a))
			var root := Node3D.new()
			root.position = dir * 1.42 + Vector3(0, 0.02, 0.05)
			root.rotation.y = -a + PI
			add_child(root)
			var av := Sprite3D.new()
			av.texture = UIKit.avatar(_avatar_index(p.id))
			av.pixel_size = 0.0017
			av.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			av.shaded = false
			av.position = dir * 2.02 + Vector3(0, 0.36, 0.05)
			add_child(av)
			_seats[p.id] = {"pos": root.position, "root": root, "avatar": av, "cards": []}
		var seat: Dictionary = _seats[p.id]
		seat.avatar.modulate = Color.WHITE if p.alive else Color(0.5, 0.5, 0.62)
		seat.avatar.rotation.z = 0.0 if p.alive else 0.5
		var cards: Array = seat.cards
		var want := mini(int(p.count), 7)
		while cards.size() > want:
			cards.pop_back().queue_free()
		while cards.size() < want:
			var c := Card3D.new().setup("back", false)
			c.scale = Vector3.ONE * 0.4
			seat.root.add_child(c)
			cards.append(c)
		for i in cards.size():
			var off := float(i) - (cards.size() - 1) / 2.0
			cards[i].position = Vector3(off * 0.1, 0.006 * i, absf(off) * 0.012)
			cards[i].rotation.y = -off * 0.09
	_turn_light.visible = _seats.has(_v.cur) and _v.over == null
	if _turn_light.visible:
		_turn_light.position = _seats[_v.cur].pos + Vector3(0, 0.45, 0)


## Carta "fantasma" que vuela de un sitio a otro (robos, regalos, robar del mazo de un rival).
func _ghost(from: Vector3, to: Vector3) -> void:
	var c := Card3D.new().setup("back", false)
	add_child(c)
	c.position = from
	c.scale = Vector3.ONE * 0.45
	var tw := c.fly_to(to, Vector3(0, randf_range(-0.4, 0.4), 0), 0.4, 0.42)
	tw.chain().tween_callback(c.queue_free)


# ---------------------------------------------------------------- efectos en secuencia

## Encola un efecto que debe verse completo antes del siguiente (p. ej. revelar el explosivo y luego explotar).
func _enqueue(step: Callable) -> void:
	_fxq.append(step)
	if not _fx_running:
		_run_fx()


func _run_fx() -> void:
	_fx_running = true
	while not _fxq.is_empty():
		var step: Callable = _fxq.pop_front()
		await step.call()
	_fx_running = false
	_update_hud()


## El Gatito Explosivo sale del mazo, se voltea y queda temblando frente a la cámara.
func _fx_reveal() -> void:
	if _ek:
		_ek.queue_free()
	_ek = Card3D.new().setup("exploding", false)
	add_child(_ek)
	_ek.position = _deck_top()
	_ek.scale = Vector3.ONE * HAND_SCALE
	Sfx.play("fuse")
	world.shake(0.3)
	_ek.fly_to(Vector3(0, 0.95, 0.3), Vector3(deg_to_rad(54.0), 0, 0), 0.45, 1.3)
	_ek.flip()
	await get_tree().create_timer(0.95).timeout


func _fx_die(player_id: String, mine: bool) -> void:
	var at := _pos_of(player_id) + Vector3(0, 0.25, 0)
	if _ek:
		at = _ek.global_position
		_ek.queue_free()
		_ek = null
	Vfx.explosion(self, at)
	Vfx.shockwave(self, at)
	Sfx.play("explosion", 2.0, 0.0)
	world.flash(Color("ffd9a0"), 0.8)
	world.shake(1.0)
	Input.vibrate_handheld(350)
	_popup("¡EXPLOTASTE!" if mine else "¡BOOM!", UIKit.C.red)
	# Un instante de cámara lenta para sentir el golpe
	Engine.time_scale = 0.35
	await get_tree().create_timer(0.16, true, false, true).timeout
	Engine.time_scale = 1.0
	await get_tree().create_timer(0.55).timeout


func _fx_over(won: bool) -> void:
	Sfx.play("win" if won else "lose", 0.0, 0.0)
	if won:
		_confetti()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _slashes() -> void:
	var size := get_viewport().get_visible_rect().size
	for i in 3:
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.92)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.size = Vector2(size.x * 1.7, 16)
		r.position = Vector2(-size.x * 0.35, size.y * (0.34 + 0.09 * i))
		r.rotation = -0.38
		r.scale = Vector2(0.0, 1.0)
		_fx_root.add_child(r)
		var t := r.create_tween()
		t.tween_interval(0.05 * i)
		t.tween_property(r, "scale:x", 1.0, 0.1)
		t.tween_property(r, "modulate:a", 0.0, 0.28)
		t.tween_callback(r.queue_free)


func _jiggle_deck() -> void:
	for c in _deck_cards:
		var home := c.position
		var t := c.create_tween()
		for _k in 3:
			t.tween_property(c, "position", home + Vector3(randf_range(-0.12, 0.12), 0, randf_range(-0.08, 0.08)), 0.07)
		t.tween_property(c, "position", home, 0.08)


func _confetti() -> void:
	var size := get_viewport().get_visible_rect().size
	var p := CPUParticles2D.new()
	p.position = Vector2(size.x / 2.0, -20)
	p.amount = 140
	p.lifetime = 3.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(size.x / 2.0, 10)
	p.direction = Vector2(0, 1)
	p.spread = 30.0
	p.gravity = Vector2(0, 520)
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 380.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 10.0
	p.scale_amount_max = 18.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	g.colors = PackedColorArray([UIKit.C.toxic, UIKit.C.gold, Color("ff7fb0"), Color("49e0e6")])
	p.color_initial_ramp = g
	_fx_root.add_child(p)
	var t := p.create_tween()
	t.tween_interval(4.5)
	t.tween_callback(func() -> void: p.emitting = false)
	t.tween_interval(3.5)
	t.tween_callback(p.queue_free)


func _process_events() -> void:
	var me: String = _v.you
	for e: Dictionary in _v.events:
		if e.seq <= _seq:
			continue
		_seq = e.seq
		if e.has("text") and not e.has("to"):
			_log_last = e.text
		match e.type:
			"start":
				Sfx.play("shuffle")
			"play":
				Sfx.play("card")
			"draw":
				Sfx.play("draw", -3.0)
				if e.player != me:
					_ghost(_deck_top(), _pos_of(e.player))
			"turn":
				if e.player == me and _v.over == null:
					_popup("¡TU TURNO!", UIKit.C.toxic)
					Sfx.play("turn")
					Input.vibrate_handheld(40)
			"nope":
				Sfx.play("yup" if e.yup else "nope")
				_popup("¡SIP!" if e.yup else "¡NOP!", UIKit.C.toxic if e.yup else UIKit.C.red)
				world.flash(UIKit.C.toxic if e.yup else UIKit.C.red, 0.22, 0.3)
			"attack":
				Sfx.play("attack")
				_slashes()
				world.shake(0.4)
				if e.target == me:
					_popup("¡TE ATACAN! ×%d" % int(e.n), UIKit.C.red)
					Sfx.play("alarm")
					Input.vibrate_handheld(150)
			"shuffle":
				Sfx.play("shuffle")
				_jiggle_deck()
			"steal":
				Sfx.play("steal")
				_ghost(_pos_of(e.target), _pos_of(e.player))
				if e.target == me and e.has("card"):
					_toast(e.text, true)
			"gave":
				Sfx.play("steal", -4.0)
				_ghost(_pos_of(e.player), _pos_of(e.target))
			"boom":
				_enqueue(_fx_reveal)
			"died":
				_enqueue(_fx_die.bind(e.player, e.player == me))
			"zombie":
				Sfx.play("zombie")
				Vfx.zombie_rise(self, _ek.global_position if _ek else DISCARD_POS + Vector3(0, 0.15, 0))
				world.flash(UIKit.C.toxic, 0.14)
				world.shake(0.3)
				_popup("¡ZOMBI!", UIKit.C.toxic)
			"inserted":
				if _ek:
					# El explosivo vuelve boca abajo al mazo
					var c := _ek
					_ek = null
					c.flip()
					var tw := c.fly_to(_deck_top(), Vector3.ZERO, 0.45, HAND_SCALE)
					tw.chain().tween_callback(c.queue_free)
					Sfx.play("card")
			"revived":
				Sfx.play("revive")
				Vfx.zombie_rise(self, _pos_of(e.target) + Vector3(0, 0.2, 0))
				if e.target == me:
					_popup("¡REVIVISTE!", UIKit.C.toxic)
			"future":
				_modal = {"type": "future", "cards": e.cards}
			"clair":
				_modal = {"type": "clair", "positions": e.positions, "len": e.len}
			"got", "lost":
				_toast(e.text, e.type == "lost")
			"over":
				_enqueue(_fx_over.bind(e.winner == me))


# ================================================================ entrada del jugador

func _act(a: Dictionary) -> void:
	var err := session.act(a)
	if err != "":
		_toast(err, true)


func _on_deck_tapped(_c: Card3D) -> void:
	if _my_turn() and _idle():
		_sel.clear()
		_act({"a": "draw"})


func _on_card_tapped(card: Card3D) -> void:
	if not _hand.has(card.card_id) or _v.over != null:
		return
	var id := card.card_id
	if _sel.has(id):
		_sel.erase(id)
	else:
		var first: Card3D = _hand.get(_sel[0]) if _sel.size() > 0 else null
		if first != null and _sel.size() < 3 and (card.type == first.type or card.type == "clone" or first.type == "clone"):
			_sel.append(id)
		else:
			_sel.clear()
			_sel.append(id)
	_sync_hand()
	_update_hud()


func _sel_cards() -> Array:
	var out: Array = []
	for c: Dictionary in _v.hand:
		if _sel.has(c.id):
			out.append(c)
	return out


## Estado de la selección cuando son 2 o 3 cartas: {} si no aplica, {err} o {n, of}.
func _combo_state() -> Dictionary:
	var sel := _sel_cards()
	if sel.size() < 2:
		return {}
	var real: Array = sel.filter(func(c: Dictionary) -> bool: return c.type != "clone")
	if real.is_empty():
		return {"err": "El Clon necesita acompañar a otra carta."}
	for c: Dictionary in real:
		if c.type != real[0].type:
			return {"err": "Para un combo, las cartas deben ser iguales."}
	if not _my_turn():
		return {"err": "Los combos solo se juegan en tu turno."}
	if _v.prompt != null or not _v.stack.is_empty():
		return {"err": "Espera a que termine la jugada en curso."}
	if not _v.players.any(func(p: Dictionary) -> bool: return p.id != _v.you and p.alive and p.count > 0):
		return {"err": "Nadie tiene cartas para robar."}
	return {"n": sel.size(), "of": real[0].type}


func _play_selected(target: String = "", named: String = "") -> void:
	if _sel.is_empty():
		return
	if _sel.size() == 1:
		var need: Variant = _v.playable.get(_sel[0])
		if need == null:
			return
		if need is String and target == "":
			_modal = {"type": "target", "kind": need}
			_update_hud()
			return
	else:
		var cs := _combo_state()
		if cs.is_empty() or cs.has("err"):
			return
		if target == "":
			_modal = {"type": "target", "kind": "living"}
			_update_hud()
			return
		if cs.n == 3 and named == "":
			_modal = {"type": "named", "target": target}
			_update_hud()
			return
	var a := {"a": "play", "cards": _sel.duplicate()}
	if target != "":
		a["target"] = target
	if named != "":
		a["named"] = named
	_sel.clear()
	_modal = {}
	_act(a)
	_update_hud()


# ================================================================ interfaz (HUD)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		top.add_theme_constant_override("margin_" + side, 24)
	top.add_theme_constant_override("margin_top", 70)
	root.add_child(top)
	var tv := UIKit.vbox(12)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tv)
	var bar := UIKit.hbox(14)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(bar)
	var menu := UIKit.button("MENÚ", "normal", 34)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu.pressed.connect(_open_menu)
	bar.add_child(menu)
	_turn_panel = UIKit.panel(UIKit.C.panel, UIKit.C.line, Vector2(20, 8))
	_turn_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn = UIKit.label("", 50, UIKit.C.ink, true)
	_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_panel.add_child(_turn)
	bar.add_child(_turn_panel)
	_opps = UIKit.hbox(12)
	_opps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(_opps)
	_risk = UIKit.label("", 34, UIKit.C.dim)
	_risk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_risk)
	_toasts = UIKit.vbox(8)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(_toasts)

	var bottom := MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		bottom.add_theme_constant_override("margin_" + side, 24)
	bottom.add_theme_constant_override("margin_bottom", 56)
	root.add_child(bottom)
	var bv := UIKit.vbox(14)
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bv)
	_me_bar = UIKit.hbox(16)
	_me_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_me_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_child(_me_bar)
	_info_slot = UIKit.vbox(0)
	_info_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(_info_slot)
	_status = UIKit.label("", 44, UIKit.C.ink, false, true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_status)
	_status_timer = UIKit.timer_bar()
	bv.add_child(_status_timer)
	_buttons = UIKit.hbox(16)
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(_buttons)

	_fx_root = Control.new()
	_fx_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fx_root)
	_modal_root = Control.new()
	_modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_modal_root)


static func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _add_btn(parent: Node, text: String, kind: String, fn: Callable, size: int = 46) -> Button:
	var b := UIKit.button(text, kind, size)
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _track(bar: ProgressBar, o: Dictionary) -> void:
	_timers.append([bar, session.now() + int(o.remain), int(o.total)])


func _update_hud() -> void:
	var v := _v
	var me := _me()
	_timers.clear()
	var my_turn := _my_turn()
	var cur := _player(v.cur)
	_turn.text = ("TU TURNO" if my_turn else "Turno de " + cur.get("name", "")) + (("  ×%d" % v.turnsLeft) if v.turnsLeft > 1 else "")
	_turn.add_theme_color_override("font_color", UIKit.C.toxic if my_turn else UIKit.C.ink)
	_turn_panel.add_theme_stylebox_override("panel", UIKit.box(UIKit.C.panel, UIKit.C.toxic if my_turn else UIKit.C.line, 30, 5, Vector2(20, 8)))

	# Rivales, en orden de turno a partir de mí
	_clear(_opps)
	var n: int = v.players.size()
	var my_idx := 0
	for i in n:
		if v.players[i].id == v.you:
			my_idx = i
	for k in range(1, n):
		var p: Dictionary = v.players[(my_idx + k) % n]
		var is_cur: bool = p.id == v.cur
		var chip := UIKit.panel(Color("241a38") if not p.alive else UIKit.C.panel, UIKit.C.toxic if is_cur else UIKit.C.line, Vector2(10, 10))
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ch := UIKit.hbox(6)
		chip.add_child(ch)
		if n <= 4:
			var pic := UIKit.avatar_icon(_avatar_index(p.id))
			pic.modulate = Color.WHITE if p.alive else Color(0.4, 0.4, 0.5)
			ch.add_child(pic)
		var cv := UIKit.vbox(0)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ch.add_child(cv)
		var name_l := UIKit.label(p.name, 44, UIKit.C.dim if not p.alive else UIKit.C.ink, true)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.clip_text = true
		cv.add_child(name_l)
		var info := "%d cartas" % p.count
		var info_l := UIKit.label(info, 32, UIKit.C.dim)
		info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(info_l)
		var state: String = "sin conexión" if (not p.connected and not p.bot) else "MUERTO" if not p.alive else (("juega ×%d" % v.turnsLeft) if is_cur and v.turnsLeft > 1 else ("su turno" if is_cur else LEVEL_NAMES.get(session.level_of(p.id), "")))
		var state_l := UIKit.label(state, 30, UIKit.C.red if not p.alive else (UIKit.C.toxic if is_cur else UIKit.C.dim))
		state_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(state_l)
		_opps.add_child(chip)

	var alive := 0
	for p: Dictionary in v.players:
		alive += 1 if p.alive else 0
	var eks := alive - 1
	_risk.text = "Explosivos: %d en %d cartas  ·  riesgo %d%%" % [eks, v.draw, int(round(100.0 * eks / maxi(1, v.draw)))]

	# Barra del jugador: solo donde sobra espacio bajo la mesa
	_clear(_me_bar)
	var screen := get_viewport().get_visible_rect().size
	if screen.y / maxf(1.0, screen.x) >= 2.0 and _sel.is_empty() and not coach:
		var pic := UIKit.avatar_icon(_avatar_index(v.you), Vector2(110, 150))
		pic.modulate = Color.WHITE if me.alive else Color(0.4, 0.4, 0.5)
		_me_bar.add_child(pic)
		var who := UIKit.vbox(0)
		who.alignment = BoxContainer.ALIGNMENT_CENTER
		who.add_child(UIKit.label(me.name, 46, UIKit.C.ink, true))
		who.add_child(UIKit.label(("%d cartas en la mano" % me.count) if me.alive else "MUERTO · %d cartas" % me.count, 30, UIKit.C.dim if me.alive else UIKit.C.red))
		_me_bar.add_child(who)

	# Zona inferior: estado + botones
	_clear(_buttons)
	_clear(_info_slot)
	_status_timer.visible = false
	var t: Variant = v.stack[v.stack.size() - 1] if v.stack.size() > 0 else null
	var pr: Variant = v.prompt
	if v.over != null:
		_status.text = ""
	elif v.win != null and t != null:
		var what: String
		if t.eff == "combo2":
			what = "una pareja de %s para robar a %s" % [CardDB.display_name(t.of), _to_name(t.target)]
		elif t.eff == "combo3":
			what = "un trío de %s y pide %s a %s" % [CardDB.display_name(t.of), CardDB.display_name(t.named), _to_name(t.target)]
		else:
			what = CardDB.display_name(t.eff) + ((" contra " + _to_name(t.target)) if t.target != null else "")
		var verb := "juegas" if t.by == v.you else "juega"
		var st := ""
		if t.nopes > 0:
			st = ("\nANULADA por %s" % _pname(t.last)) if t.nopes % 2 == 1 else "\n¡VUELVE A VALER!"
		_status.text = "%s %s %s%s" % [_pname(t.by), verb, what, st]
		_status_timer.visible = true
		_track(_status_timer, v.win)
		if v.win.canNope and not v.win.passed:
			_add_btn(_buttons, "¡NOP!", "danger", _play_nope)
			_add_btn(_buttons, "Dejar pasar", "normal", func() -> void: _act({"a": "pass"}))
	elif pr != null:
		var who := _pname(pr.get("player"))
		match pr.type:
			"explode": _status.text = "Sacaste un Gatito Explosivo…" if pr.mine else "%s sacó un Gatito Explosivo…" % who
			"zombie":
				_status.text = "%s %s en el mazo…" % ["Escondes" if pr.mine else who + " esconde", "los Gatitos Explosivos" if pr.eks > 1 else "el Gatito Explosivo"]
				if pr.watching:
					_status.text += "\nEstás mirando (Clarividencia)"
				else:
					for c: Dictionary in v.hand:
						if c.type == "clairvoyance" and v.playable.has(c.id):
							var cid: String = c.id
							_add_btn(_buttons, "Jugar Clarividencia", "primary", func() -> void: _act({"a": "play", "cards": [cid]}))
							break
			"give":
				var names: Array = pr.waiting.map(func(id: String) -> String: return _to_name(id))
				var title: String = "Favor" if pr.reason == "favor" else ("Alimenta a los Muertos" if pr.reason == "feed" else "Ladrón de Tumbas")
				_status.text = "%s: esperando carta de %s…" % [title, ", ".join(PackedStringArray(names))]
			"dig": _status.text = "Cavas más hondo…" if pr.mine else "%s cava más hondo…" % who
		_status_timer.visible = true
		_track(_status_timer, pr)
	else:
		if not me.alive:
			_status.text = "Estás muerto. Aún puedes jugar Nop y cartas ⚡."
		elif my_turn:
			_status.text = "Juega cartas si quieres… y luego roba para terminar tu turno."
		else:
			_status.text = _log_last
		if my_turn and _idle():
			_add_btn(_buttons, "ROBAR CARTA", "primary", _draw_card, 54)

	if coach:
		_build_tip()
	_build_selection_info()
	_build_modal()


func _build_selection_info() -> void:
	var cards := _sel_cards()
	if cards.is_empty() or _v.over != null:
		return
	var panel := UIKit.panel(UIKit.C.cream, UIKit.C.dark, Vector2(24, 16))
	var row := UIKit.hbox(16)
	panel.add_child(row)
	var txt := UIKit.vbox(2)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(txt)
	var title := ""
	var desc := ""
	var can := false
	var label := "JUGAR"
	if cards.size() == 1:
		var c: Dictionary = cards[0]
		title = CardDB.display_name(c.type)
		desc = CardDB.defs[c.type].short
		can = _v.playable.has(c.id)
		if not can:
			var why := "No se puede jugar ahora."
			if CardDB.defs[c.type].cat:
				why = "Selecciona otra igual para jugar una pareja."
			elif c.type == "zombie":
				why = "Se usa sola cuando sacas un Gatito Explosivo."
			elif c.type == "nope":
				why = "Úsala cuando alguien juegue una carta."
			elif c.type == "clairvoyance":
				why = "Úsala cuando otro juegue un Gatito Zombi."
			elif not _me().alive:
				why = "Estás muerto: solo Nop y cartas ⚡."
			elif _v.cur != _v.you:
				why = "Espera tu turno."
			elif c.type in ["attack_dead", "grave_robber", "feed_dead"] and _v.deadN == 0:
				why = "Necesita que haya jugadores muertos."
			desc += "\n→ " + why
	else:
		var cs := _combo_state()
		title = "Pareja" if cards.size() == 2 else "Trío"
		if cs.has("err"):
			desc = cs.err
		elif not cs.is_empty():
			title += " de " + CardDB.display_name(cs.of)
			desc = "Roba una carta AL AZAR a un jugador vivo." if cs.n == 2 else "Nombra la carta que quieres: si la tiene, te la da."
			can = true
			label = "JUGAR PAREJA" if cs.n == 2 else "JUGAR TRÍO"
	txt.add_child(UIKit.label(title, 44, UIKit.C.dark, false))
	txt.add_child(UIKit.label(desc, 30, Color("3a2f4a"), false, true))
	if can:
		var b := _add_btn(row, label, "primary", func() -> void: _play_selected(), 44)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_info_slot.add_child(panel)


# ---------------------------------------------------------------- ventanas

func _open_modal(title: String, title_color: Color = UIKit.C.toxic) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.08, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 120)
	margin.add_theme_constant_override("margin_bottom", 80)
	_modal_root.add_child(margin)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(center)
	_modal_title = title
	var panel := UIKit.panel(UIKit.C.panel, UIKit.C.line, Vector2(36, 30))
	center.add_child(panel)
	var box := UIKit.vbox(20)
	panel.add_child(box)
	if title != "":
		var tl := UIKit.label(title, 60, title_color, true, true)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(tl)
	return box


func _text(box: Node, text: String, size: int = 34, color: Color = UIKit.C.ink) -> Label:
	var l := UIKit.label(text, size, color, false, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return l


func _centered(box: Node, child: Control) -> void:
	var c := CenterContainer.new()
	c.add_child(child)
	box.add_child(c)


func _player_buttons(box: Node, players: Array, fn: Callable) -> void:
	for p: Dictionary in players:
		var id: String = p.id
		_add_btn(box, "%s  ·  %d cartas" % ["Yo mismo" if id == _v.you else p.name, p.count], "normal", func() -> void: fn.call(id))


static func _ins_label(pos: int, max_pos: int) -> String:
	if pos <= 0:
		return "Arriba del todo: será la PRÓXIMA carta"
	if pos >= max_pos:
		return "Hasta el fondo del mazo"
	return "Debajo de %d carta%s (posición %d de %d)" % [pos, "s" if pos > 1 else "", pos + 1, max_pos + 1]


func _build_modal() -> void:
	_clear(_modal_root)
	_modal_title = ""
	var v := _v
	if _fx_running and (v.over != null or (v.prompt != null and v.prompt.mine and v.prompt.type == "explode")):
		return      # primero se ve la animación; _run_fx vuelve a llamar al terminar
	if v.over != null:
		var won: bool = v.over.winner == v.you
		var box := _open_modal("¡GANASTE!" if won else "Ganó " + _pname(v.over.winner), UIKit.C.toxic if won else UIKit.C.gold)
		_text(box, "Eres el último gatito con vida." if won else "Fue el último gatito con vida.")
		if not session.is_network():
			_add_btn(box, "JUGAR OTRA VEZ", "primary", func() -> void: rematch_requested.emit(), 54)
			_add_btn(box, "Volver al menú", "ghost", func() -> void: exit_requested.emit())
		elif session.is_host():
			_add_btn(box, "VOLVER A LA SALA", "primary", func() -> void: lobby_requested.emit(), 54)
			_add_btn(box, "Cerrar la sala", "ghost", func() -> void: exit_requested.emit())
		else:
			_text(box, "Esperando a que el anfitrión abra la sala…", 30, UIKit.C.dim)
			_add_btn(box, "Salir de la sala", "ghost", func() -> void: exit_requested.emit())
		return
	var pr: Variant = v.prompt
	if pr != null and pr.mine:
		_build_prompt_modal(pr)
		return
	if _modal.is_empty():
		return
	match _modal.type:
		"target":
			var dead: bool = _modal.kind == "dead"
			var box := _open_modal("¿A qué muerto alimentas?" if dead else "¿Contra quién?")
			var list: Array = []
			for p: Dictionary in v.players:
				if (not p.alive) if dead else (p.alive and p.id != v.you and p.count > 0):
					list.append(p)
			_player_buttons(box, list, func(id: String) -> void: _play_selected(id))
			_add_btn(box, "Cancelar", "ghost", _close_modal)
		"named":
			var box := _open_modal("¿Qué carta quieres?")
			_text(box, "Si %s la tiene, te la da." % _pname(_modal.target))
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 12)
			grid.add_theme_constant_override("v_separation", 12)
			box.add_child(grid)
			var target: String = _modal.target
			for t: String in CardDB.types():
				if t == "exploding":
					continue
				var type := t
				_add_btn(grid, CardDB.display_name(t), "normal", func() -> void: _play_selected(target, type), 32)
			_add_btn(box, "Cancelar", "ghost", _close_modal)
		"future":
			var box := _open_modal("El futuro (solo tú lo ves)")
			var row := UIKit.hbox(14)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			box.add_child(row)
			for i in _modal.cards.size():
				var col := UIKit.vbox(6)
				var l := UIKit.label(["PRÓXIMA", "SEGUNDA", "TERCERA"][mini(i, 2)], 38, UIKit.C.gold, true)
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				col.add_child(l)
				col.add_child(UIKit.card_image(_modal.cards[i], 400))
				row.add_child(col)
			_text(box, "Las cartas siguen en el mismo orden en el mazo.", 28, UIKit.C.dim)
			_add_btn(box, "Entendido", "primary", _close_modal)
		"clair":
			var box := _open_modal("Clarividencia")
			_text(box, "Viste dónde quedaron los explosivos (mazo de %d cartas):" % int(_modal.len))
			for i in _modal.positions.size():
				var p := int(_modal.positions[i])
				_text(box, "Explosivo %s: %s" % [str(i + 1) if _modal.positions.size() > 1 else "", "arriba del todo" if p == 0 else "debajo de %d carta%s" % [p, "s" if p > 1 else ""]], 38, UIKit.C.gold)
			_add_btn(box, "Entendido", "primary", _close_modal)
		"menu":
			var box := _open_modal("Menú")
			_add_btn(box, "Seguir jugando", "primary", _close_modal)
			var info := UIKit.hbox(12)
			box.add_child(info)
			_add_btn(info, "Cómo jugar", "normal", func() -> void: InfoScreen.open(self, "rules"), 38)
			_add_btn(info, "Cartas", "normal", func() -> void: InfoScreen.open(self, "cards"), 38)
			var audio := UIKit.hbox(12)
			box.add_child(audio)
			_add_btn(audio, "Sonido: sí" if Sfx.sfx_on else "Sonido: no", "normal", _toggle_sfx, 34)
			_add_btn(audio, "Música: sí" if Sfx.music_on else "Música: no", "normal", _toggle_music, 34)
			_add_btn(box, "Salir de la partida", "danger", _ask_exit, 40)
		"exit":
			var box := _open_modal("¿Salir de la partida?")
			_text(box, "Se perderá la partida en curso." if not session.is_network() else ("Eres el anfitrión: la partida termina para todos." if session.is_host() else "Podrás volver a entrar mientras la partida siga."))
			_add_btn(box, "Seguir jugando", "primary", _close_modal)
			_add_btn(box, "Salir al menú", "danger", func() -> void: exit_requested.emit())


func _open_menu() -> void:
	_modal = {"type": "menu"}
	_update_hud()


func _ask_exit() -> void:
	_modal = {"type": "exit"}
	_update_hud()


func _toggle_sfx() -> void:
	Sfx.set_sfx(not Sfx.sfx_on)
	_update_hud()


func _toggle_music() -> void:
	Sfx.set_music(not Sfx.music_on)
	_update_hud()


# ---------------------------------------------------------------- tutorial

## Elige el siguiente consejo que toca mostrar, si hay alguno pendiente para la situación actual.
func _coach_pick() -> void:
	if _tip != "" or _v.over != null:
		return
	var me := _me()
	var others_turn: bool = _v.cur != _v.you
	var alive := 0
	for p: Dictionary in _v.players:
		alive += 1 if p.alive else 0
	var risk := 100.0 * (alive - 1) / maxi(1, int(_v.draw))
	var checks := [
		["intro", true],
		["dead", not me.alive],
		["nope", _v.win != null and _v.win.canNope and not _v.win.passed],
		["window", _v.win != null and _v.stack.size() > 0 and _v.stack[-1].by != _v.you],
		["hand", true],
		["selected", _sel.size() > 0],
		["turn", _my_turn() and _idle()],
		["risk", _my_turn() and _idle() and risk >= 25.0],
		["rivals", others_turn],
	]
	for c: Array in checks:
		if c[1] and not _tips_seen.has(c[0]):
			_tip = c[0]
			return


func _dismiss_tip() -> void:
	_tips_seen[_tip] = true
	_tip = ""
	_update_hud()


func _build_tip() -> void:
	_coach_pick()
	if _tip == "":
		return
	var panel := UIKit.panel(Color("23401a"), UIKit.C.toxic, Vector2(24, 16))
	var row := UIKit.hbox(16)
	panel.add_child(row)
	var txt := UIKit.label(TIPS[_tip], 32, Color("ecffd0"), false, true)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(txt)
	var ok := _add_btn(row, "Entendido", "primary", _dismiss_tip, 34)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_info_slot.add_child(panel)


func _play_nope() -> void:
	for c: Dictionary in _v.hand:
		if c.type == "nope":
			_act({"a": "play", "cards": [c.id]})
			return


func _draw_card() -> void:
	_sel.clear()
	_act({"a": "draw"})


func _confirm_insert() -> void:
	var pos: Array = []
	for i in int(_v.prompt.eks):
		pos.append(mini(_ins[i], int(_v.draw) + i))
	_ins = [0, 0]
	_act({"a": "insert", "positions": pos})


func _confirm_give() -> void:
	if _give_sel != "":
		var cid := _give_sel
		_give_sel = ""
		_act({"a": "give", "card": cid})


func _pick_give(cid: String) -> void:
	_give_sel = cid
	_update_hud()


func _close_modal() -> void:
	_modal = {}
	_update_hud()


func _build_prompt_modal(pr: Dictionary) -> void:
	var v := _v
	match pr.type:
		"explode":
			var box := _open_modal("¡GATITO EXPLOSIVO!", UIKit.C.gold)
			_centered(box, UIKit.card_image("exploding", 560))
			var bar := UIKit.timer_bar()
			box.add_child(bar)
			_track(bar, pr)
			for c: Dictionary in v.hand:
				if c.type == "zombie":
					var cid: String = c.id
					_add_btn(box, "JUGAR GATITO ZOMBI", "primary", func() -> void: _act({"a": "play", "cards": [cid]}), 54)
					break
			for c: Dictionary in v.hand:
				if c.type == "clone" and v.playable.has(c.id):
					var cid: String = c.id
					_add_btn(box, "Jugar Clon (copia al Zombi)", "primary", func() -> void: _act({"a": "play", "cards": [cid]}))
					break
			_add_btn(box, "Morir (conservas tus cartas)", "ghost", func() -> void: _act({"a": "die"}))
			_text(box, "Si mueres, otro jugador puede revivirte con su Gatito Zombi.", 28, UIKit.C.dim)
		"zombie":
			if pr.needRevive and pr.revived == null:
				var box := _open_modal("¿A quién revives?")
				_text(box, "Debes traer de vuelta a un jugador muerto. Elige con cuidado: ¡solo ganará si te sobrevive!")
				_player_buttons(box, v.players.filter(func(p: Dictionary) -> bool: return not p.alive), func(id: String) -> void: _act({"a": "revive", "target": id}))
				return
			if pr.waiting:
				var wbox := _open_modal("Escondiendo…")
				_text(wbox, "Colocando los explosivos en el mazo…")
				return
			var box := _open_modal("Esconde el Gatito Explosivo")
			_text(box, "Colócalo en secreto donde quieras. Nadie verá dónde (salvo con Clarividencia).", 30)
			for i in int(pr.eks):
				var idx := i
				var max_pos: int = int(v.draw) + i
				_ins[i] = mini(_ins[i], max_pos)
				var title := "Explosivo" if pr.eks == 1 else ("Tu explosivo" if i == 0 else "El del jugador revivido")
				var tl := UIKit.label(title, 42, UIKit.C.gold, true)
				box.add_child(tl)
				var row := UIKit.hbox(12)
				row.add_child(UIKit.label("Arriba", 26, UIKit.C.dim))
				var slider := UIKit.slider(max_pos, _ins[i])
				row.add_child(slider)
				row.add_child(UIKit.label("Fondo", 26, UIKit.C.dim))
				box.add_child(row)
				var where := _text(box, _ins_label(_ins[i], max_pos), 30, UIKit.C.ink)
				var on_slide := func(val: float) -> void:
					_ins[idx] = int(val)
					where.text = _ins_label(int(val), max_pos)
				slider.value_changed.connect(on_slide)
				var quick := UIKit.hbox(10)
				box.add_child(quick)
				for opt: Array in [["Arriba", 0], ["Segunda", 1], ["Al azar", -1], ["Fondo", max_pos]]:
					var target_pos: int = opt[1]
					var jump := func() -> void:
						slider.value = (randi() % (max_pos + 1)) if target_pos < 0 else mini(target_pos, max_pos)
					_add_btn(quick, opt[0], "normal", jump, 30)
			var bar := UIKit.timer_bar()
			box.add_child(bar)
			_track(bar, pr)
			_add_btn(box, "CONFIRMAR", "primary", _confirm_insert, 54)
		"give":
			var title := "Ladrón de Tumbas"
			if pr.reason == "favor":
				title = "%s te pide un Favor" % _pname(pr.to)
			elif pr.reason == "feed":
				title = "Alimenta a %s" % _pname(pr.to)
			var box := _open_modal(title)
			_text(box, "Elige 1 carta de tu mano: se barajará dentro del mazo." if pr.reason == "rob" else "Elige 1 carta de tu mano para dársela.")
			var grid := GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 12)
			grid.add_theme_constant_override("v_separation", 12)
			_centered(box, grid)
			for c: Dictionary in _sorted_hand():
				var cid: String = c.id
				var tb := TextureButton.new()
				tb.texture_normal = CardDB.texture(c.type)
				tb.ignore_texture_size = true
				tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
				tb.custom_minimum_size = Vector2(215, 301)
				tb.modulate = Color.WHITE if (_give_sel == "" or _give_sel == cid) else Color(0.45, 0.45, 0.5)
				tb.pressed.connect(_pick_give.bind(cid))
				grid.add_child(tb)
			var bar := UIKit.timer_bar()
			box.add_child(bar)
			_track(bar, pr)
			var give := _add_btn(box, "DAR ESTA CARTA", "primary", _confirm_give, 54)
			give.disabled = _give_sel == ""
		"dig":
			var box := _open_modal("Cava Más Hondo")
			_text(box, "Esta es la carta de arriba. ¿Te la quedas? Si no, DEBES robar la siguiente sea cual sea.")
			_centered(box, UIKit.card_image(pr.card, 560))
			var bar := UIKit.timer_bar()
			box.add_child(bar)
			_track(bar, pr)
			var row := UIKit.hbox(14)
			box.add_child(row)
			_add_btn(row, "Me la quedo", "primary", func() -> void: _act({"a": "dig", "keep": true}))
			_add_btn(row, "Robar la siguiente", "danger", func() -> void: _act({"a": "dig", "keep": false}))


# ---------------------------------------------------------------- avisos

## Aviso breve desde fuera de la pantalla (p. ej. "Reconectando…").
func notice(text: String, bad: bool = false) -> void:
	_toast(text, bad)


func _popup(text: String, color: Color) -> void:
	var l := UIKit.label(text, 150, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fx_root.add_child(l)
	l.pivot_offset = get_viewport().get_visible_rect().size / 2.0
	l.scale = Vector2(0.3, 0.3)
	l.rotation_degrees = -6
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.65)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
	t.tween_callback(l.queue_free)


func _toast(text: String, bad: bool = false) -> void:
	var p := UIKit.panel(UIKit.C.cream, UIKit.C.red if bad else UIKit.C.toxic_dark, Vector2(22, 10))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label(text, 32, UIKit.C.dark, false, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 3:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var t := p.create_tween()
	t.tween_interval(2.6)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)
