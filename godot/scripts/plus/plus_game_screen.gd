class_name PlusGameScreen
extends Node3D
## Pantalla de juego de Zombie Kittens PLUS. Empezó como copia de game_screen.gd (clásica, congelada) y evoluciona por separado.
## Pantalla de juego: sincroniza la mesa 3D (mano, mazo, descarte) y los controles con el estado de la partida.
## No contiene reglas: lee `session.view()` y envía acciones con `session.act()`.

signal exit_requested
signal rematch_requested
signal lobby_requested

const DECK_POS := Vector3(-0.5, 0, -0.3)
const DISCARD_POS := Vector3(0.5, 0, -0.3)
const HAND_STEP := 0.012
const HAND_SCALE := 0.86
## Media altura de una carta (del centro al borde superior)
const SIZE_Z := 0.441

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
## Historial de la partida: [{text, kind, player, target, mine, cards}] (kind: "turn" separador, "me" privado, "" normal). El más nuevo al final.
var _history: Array[Dictionary] = []
const HISTORY_MAX := 300
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
	"aim": "Toca al rival que quieres elegir: los resaltados son válidos. Toca CANCELAR para volver sin jugar la carta.",
	"dead": "Explotaste, pero conservas tu mano. Aún puedes jugar Nop y cartas ⚡, y otro jugador puede revivirte con su Gatito Zombi.",
}

var _turn: Label
var _turn_panel: PanelContainer
var _opps: RivalChips
var _risk: RiskMeter
var _status: Label
var _status_timer: ProgressBar
var _buttons: HBoxContainer
var _info_slot: VBoxContainer
var _modal_root: Control
var _fx_root: Control
var _zoom: Control             # carta seleccionada, en grande, para apreciar el arte y leer el texto
var _zoom_pic: TextureRect
var _zoom_type := ""
## Arrastrar el dedo por la mano: la carta bajo el dedo se resalta (y se ve en grande); al soltar, se elige
var _hover := ""
var _press_pos := Vector2.ZERO
var _press_card := ""
var _pressing := false
var _dragging := false
var hover_changes := 0      # para la prueba automática
const DRAG_START_PX := 22.0
## Llevar una carta al centro para jugarla
var _carry := ""                 # id de la carta que el dedo lleva fuera de la mano ("" = ninguna)
var _carry_over := false         # el dedo está sobre la zona de juego
var _carry_prev := Vector3.ZERO
var _sel_before: Array[String] = []
var _drop_ring: MeshInstance3D
var _drop_mat: StandardMaterial3D
var drops := 0                   # para la prueba automática: cartas soltadas en el centro
const PLAY_ZONE_CENTER := Vector3(0, 0, -0.25)
const PLAY_ZONE_RADIUS := 1.25
const CARRY_HEIGHT := 0.32
var _toasts: VBoxContainer
var _discard_list: DiscardList   # ventana «Descarte» abierta (UX-03)
var _named_grid: CardPickGrid    # cuadrícula del trío abierta (UX-04)
## Accesibilidad: si es true, el objetivo se elige en una lista de botones (ventana) en vez de tocando la mesa
var aim_with_list := false
var _aim: AimMode                # resaltado de asientos y toques sobre la mesa (UX-01)
var _aim_kind := ""              # tipo de objetivo que se está eligiendo ("" = modo puntería apagado)
var _aim_forced := false         # solo prueba: modo puntería sin jugada detrás
var _aim_debug_pick := ""        # solo prueba: último rival elegido en un modo forzado
var _last_play := {}             # última jugada enviada sin error (prueba)
# --- La Cripta
var _known_hands := {}           # id del rival -> {cards: [tipos], count: n}: lo visto con Ojo de Cuervo (UX-04)
var _alter_order: Array = []     # orden elegido en la ventana de Alterar el Futuro (se conserva al reconstruirla)
var _alter_live := false         # tengo una decisión «alter» abierta (para no abrir «El futuro» al confirmarla)
var _arranger: FutureArranger    # ventana de Alterar el Futuro abierta
var _slot_picker: DeckSlotPicker # selector de posición abierto (esconder el explosivo / Entierro)
var _picker_sig := ""            # huella de la decisión con selectores de mazo abierta (no se reconstruye mientras no cambie)
var _picker_bar: ProgressBar     # barra de tiempo de esa ventana
var _slot_pickers: Array[DeckSlotPicker] = []   # todos los selectores abiertos (con 2 explosivos hay dos)
var _peek_grid: CardPickGrid     # ventana de Ojo de Cuervo abierta
var _bottom_draw := false        # el próximo robo sale de DEBAJO del mazo
var _dir_ring: DirIndicator      # flecha de sentido de juego sobre el tapete (V-06)
var _dir_label: Label            # «↺ INVERTIDO» junto al distintivo PLUS (solo con el sentido invertido)
var _memory := DeckMemory.new()  # lo que sé de posiciones concretas del mazo (UX-02)
var _mem_strip: DeckMemoryStrip  # tira con las próximas cartas conocidas, junto al mazo
var _first_view := true          # la próxima vista es la primera de esta pantalla (UX-15)
var _stats := MatchStats.new()   # contadores de la ventana final (UX-09), desde los eventos públicos
var room_scores := {}            # {id: victorias} del marcador de sala (otra tarea); vacío = sin columna
var _hist_mine := false          # filtro del historial: solo lo mío (UX-12)
var _auto_pass := NopWindow.load_auto_pass()   # «Dejar pasar lo que no me afecta» (UX-05)
var _auto_sig := ""              # jugada sobre la que ya se pasó sola
var _nop_lit: Array[String] = [] # Nop de la mano resaltados mientras puedo responder
var replay_skipped := 0          # solo prueba: eventos antiguos registrados sin efectos al abrir la pantalla (UX-15)


func setup(p_session: GameSession, p_world: TableWorld) -> PlusGameScreen:
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
	_drop_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = PLAY_ZONE_RADIUS - 0.06
	torus.outer_radius = PLAY_ZONE_RADIUS
	torus.rings = 64
	torus.ring_segments = 6
	_drop_ring.mesh = torus
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drop_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_drop_ring.material_override = _drop_mat
	_drop_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drop_ring.position = PLAY_ZONE_CENTER + Vector3(0, 0.02, 0)
	_drop_ring.scale = Vector3(1, 0.3, 1)
	_drop_ring.visible = false
	add_child(_drop_ring)
	_aim = AimMode.new()
	add_child(_aim)
	_dir_ring = DirIndicator.new()
	_dir_ring.position = Vector3(0, 0.016, -0.2)
	add_child(_dir_ring)
	_build_hud()
	_opps.chip_pressed.connect(_aim_pick)
	session.updated.connect(_refresh)
	session.error.connect(func(msg: String) -> void: _toast(msg, true))
	_refresh()


func _process(delta: float) -> void:
	_time += delta
	_hand_root.position.y = sin(_time * 1.4) * 0.006
	if _drop_ring.visible:
		var pulse := 0.5 + 0.5 * sin(_time * 7.0)
		_drop_mat.albedo_color = Color(0.71, 0.95, 0.23, 0.55 + 0.35 * pulse) if _carry_over else Color(1, 1, 1, 0.18 + 0.12 * pulse)
	for id: String in _seats:
		var av: Sprite3D = _seats[id].avatar
		var is_cur: bool = not _v.is_empty() and _v.cur == id
		av.scale = Vector3.ONE * (1.0 + (0.06 * sin(_time * 5.0) if is_cur else 0.0))
	_place_strip()
	var now := session.now()
	for t: Array in _timers:
		if is_instance_valid(t[0]):
			t[0].value = clampf(float(t[1] - now) / float(maxi(1, t[2])), 0.0, 1.0) * 100.0


## Fichas de rivales construidas hasta ahora (prueba: no cambia al seleccionar cartas).
func debug_chip_builds() -> int:
	return _opps.debug_chip_builds()


## Porcentaje y tramo del medidor de riesgo: {pct, tier, name}.
func debug_risk() -> Dictionary:
	return _risk.debug_risk()


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


## Para la prueba automática: dos cartas de la mano, la primera y la última del abanico.
func debug_hand_ends() -> Array:
	var hand := _sorted_hand()
	return [] if hand.size() < 2 else [_hand[hand[0].id], _hand[hand[-1].id]]


func debug_zoom_visible() -> bool:
	return _zoom.visible


func debug_carry() -> String:
	return "%s sobre la zona=%s" % [_carry, str(_carry_over)]


func debug_selection() -> Array:
	return _sel.duplicate()


func debug_hover() -> String:
	return _hover


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
	if _aim_kind != "" and not _aim_still_valid():
		_exit_aim(false)
	if _modal.get("type", "") in ["discard", "memory"] and (_v.over != null or (_v.prompt != null and _v.prompt.mine)):
		_modal = {}       # una decisión propia o el final de la partida pasan por delante de la lista
	_sync_seats()
	_process_events()
	_sync_deck()
	_sync_hand()
	_sync_discard()
	_sync_dir()
	var pr0: Variant = _v.prompt
	_alter_live = pr0 != null and pr0.mine and pr0.type == "alter"
	_update_hud()
	_check_auto_pass()


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


## Punto de donde sale una carta robada del FONDO: de debajo del mazo, asomando por un lado.
func _deck_bottom_out() -> Vector3:
	return DECK_POS + Vector3(0.1, 0.004, 0.07)


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


## Pone la tira del recordatorio justo debajo del mazo (sigue su proyección en pantalla).
func _place_strip() -> void:
	if _mem_strip == null or not _mem_strip.visible or world == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var p := world.camera.unproject_position(DECK_POS + Vector3(0, 0.03, 0.4))
	var sz := _mem_strip.get_combined_minimum_size()
	_mem_strip.size = sz
	_mem_strip.position = Vector2(clampf(p.x - sz.x * 0.5, 12.0, maxf(12.0, screen.x - sz.x - 12.0)), p.y + 6.0)


## Abre la ventana con todo lo que sé del mazo (tocar la tira).
func _open_memory() -> void:
	if _v.is_empty() or _v.over != null or (_v.prompt != null and _v.prompt.mine):
		return
	_exit_aim(false)
	_modal = {"type": "memory"}
	_update_hud()


## Flecha de sentido (V-06): solo con un pack activo. Refleja `view.dir`.
func _sync_dir() -> void:
	var on: bool = not (_v.get("packs", []) as Array).is_empty() and _v.over == null
	var first := not _dir_ring.visible
	_dir_ring.visible = on
	if on:
		_dir_ring.set_dir(int(_v.get("dir", 1)), not first)
	if _dir_label != null:
		_dir_label.visible = on and int(_v.get("dir", 1)) < 0


func _sorted_hand() -> Array:
	var order: Array = CardDB.types_for(_v.get("packs", []))   # base + cartas de los packs de la partida
	var hand: Array = _v.hand.duplicate()
	hand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ia := order.find(a.type)
		var ib := order.find(b.type)
		return ia < ib if ia != ib else int(a.id.substr(1)) < int(b.id.substr(1)))
	return hand


func _sync_hand() -> void:
	var hand := _sorted_hand()
	_nop_lit = NopWindow.nop_ids(_v)
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
			n.global_position = _deck_bottom_out() if _bottom_draw else _deck_top()
			n.scale = Vector3.ONE * 0.6
			_hand[c.id] = n
			_bottom_draw = false
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
		if hand[i].id == _carry:
			n.set_meta("slot", Vector3(sin(ang) * radius, HAND_STEP * i, radius - cos(ang) * radius))
			continue
		var pos := Vector3(sin(ang) * radius, HAND_STEP * i, radius - cos(ang) * radius)
		n.set_meta("slot", pos)       # lugar en el abanico (sin levantar), para saber qué carta está bajo el dedo
		var selected := _sel.has(hand[i].id)
		var hovered: bool = _hover == hand[i].id
		if selected:
			pos += Vector3(0, 0.1, -0.2)
		elif hovered:
			pos += Vector3(0, 0.07, -0.12)
		var lit := _nop_lit.has(hand[i].id)
		# Los Nop brillan (sin moverse del abanico: así no tapan a sus vecinas ni cambian dónde se toca)
		n.set_glow(0.16 if selected else (0.1 if hovered else (0.5 if lit else 0.0)))
		var grow := 1.08 if selected else (1.05 if hovered else 1.0)
		n.fly_to(pos, Vector3(0, -ang, 0), 0.12 if hovered else 0.3, hand_scale * grow)


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
			n.tapped.connect(_on_card_tapped)
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
	if _bottom_draw:
		_ek.position = _deck_bottom_out()
		_bottom_draw = false
	Sfx.play("fuse")
	world.shake(0.3)
	_ek.fly_to(Vector3(0, 0.95, 0.3), Vector3(deg_to_rad(54.0), 0, 0), 0.45, 1.3)
	_ek.flip()
	await get_tree().create_timer(0.95).timeout


## Robo del FONDO del mazo: la carta asoma por debajo y sale de ahí (no de arriba).
func _fx_bottom_draw(player_id: String) -> void:
	if not _deck_cards.is_empty():
		var c := _deck_cards[0]
		var home := c.position
		var t := c.create_tween()
		t.tween_property(c, "position", home + Vector3(0.1, 0, 0.07), 0.14)
		t.tween_property(c, "position", home, 0.2)
	if player_id == _v.you:
		_bottom_draw = true
	else:
		_ghost(_deck_bottom_out(), _pos_of(player_id))


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


## ¿La partida acaba de empezar? (solo hay eventos de inicio: la primera vista debe mostrarlo normal.)
func _is_fresh_start(events: Array) -> bool:
	for e: Dictionary in events:
		if not (e.type in ["start", "turn"]):
			return false
	return true


func _process_events() -> void:
	var me: String = _v.you
	_memory.feed(_v)
	# UX-15: al abrir la pantalla en una partida ya empezada, los eventos antiguos van al historial
	# (y al recordatorio del futuro) pero no disparan sonidos, avisos ni ventanas.
	var quiet := false
	if _first_view:
		_first_view = false
		quiet = not _is_fresh_start(_v.events)
	for e: Dictionary in _v.events:
		if e.seq <= _seq:
			continue
		_seq = e.seq
		if e.has("text") and not e.has("to"):
			_log_last = e.text
		_record(e)
		_stats.feed(e, _v.players)
		if quiet:
			replay_skipped += 1
			continue
		match e.type:
			"start":
				Sfx.play("shuffle")
			"play":
				Sfx.play("card")
			"draw":
				Sfx.play("draw", -3.0)
				if e.get("bottom", false):
					_fx_bottom_draw(e.player)
				elif e.player != me:
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
			"reverse":
				Sfx.play("shuffle")
				Sfx.play("turn", -3.0)
				world.flash(Color("49e0e6"), 0.25, 0.4)
				world.shake(0.25)
				_popup("¡MARCHA ATRÁS!", Color("49e0e6"))
			"apocalypse":
				Sfx.play("alarm")
				Sfx.play("explosion", -6.0, 0.0)
				world.flash(UIKit.C.red, 0.55, 0.7)
				world.shake(0.9)
				Input.vibrate_handheld(200)
				_jiggle_deck()
				_popup("¡APOCALIPSIS!", UIKit.C.red)
				_toast(e.text, true)
			"swap":
				Sfx.play("steal")
				_ghost(_pos_of(e.player), _pos_of(e.target))
				_ghost(_pos_of(e.target), _pos_of(e.player))
				world.flash(Color("8a5cff"), 0.2, 0.35)
				_popup("¡TRUEQUE!", Color("c9a6ff"))
				_known_hands.erase(e.player)      # lo visto con Ojo de Cuervo ya no vale
				_known_hands.erase(e.target)
			"haunt":
				Sfx.play("steal")
				Sfx.play("zombie", -7.0)
				# La carta descartada vuela de la víctima a la pila: lo hace _sync_discard (el descarte lleva `by` = víctima)
				Vfx.zombie_rise(self, _pos_of(e.target) + Vector3(0, 0.2, 0))
				world.flash(Color("8a5cff"), 0.2, 0.35)
				if e.target == me:
					_popup("¡TE ESPANTAN!", UIKit.C.red)
					_toast(e.text, true)
					Input.vibrate_handheld(120)
				else:
					_popup("¡ESPANTO!", Color("c9a6ff"))
			"peek":
				Sfx.play("draw", -2.0)
				_known_hands[e.target] = {"cards": (e.cards as Array).duplicate(), "count": (e.cards as Array).size()}
				_modal = {"type": "peek", "target": e.target, "cards": e.cards}
			"buried":
				Sfx.play("card")
				_jiggle_deck()
				_toast(e.text)
			"info":
				if str(e.get("text", "")).ends_with("mira la mano de %s." % str(_me().get("name", "?"))):
					Sfx.play("draw", -4.0)
					_toast(e.text, true)      # a quien miran se le avisa
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
				if _alter_live:
					_toast("Nuevo orden: " + ", ".join(PackedStringArray((e.cards as Array).map(func(t: String) -> String: return CardDB.display_name(t)))) + ".")
				else:
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
	elif a.get("a", "") == "play":
		_last_play = a.duplicate(true)


func _on_deck_tapped(_c: Card3D) -> void:
	if _aim_kind != "":
		return          # eligiendo objetivo: el mazo no hace nada
	if _my_turn() and _idle():
		_sel.clear()
		_act({"a": "draw"})


# ---------------------------------------------------------------- arrastrar el dedo por la mano

## Carta de la mano que está bajo un punto de la pantalla ("" si ninguna).
func _hand_card_at(screen_pos: Vector2) -> String:
	var cam := world.camera
	var from := cam.project_ray_origin(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen_pos) * 30.0)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return ""
	var card := (hit.collider as Node).get_parent() as Card3D
	if card == null or not _hand.has(card.card_id):
		return ""
	# El dedo está sobre la mano: se elige la carta cuyo lugar en el abanico quede más cerca en horizontal.
	# (Si se usara solo lo que toca el rayo, la carta levantada taparía a sus vecinas y se saltarían cartas.)
	var best := card.card_id
	var best_d := INF
	for id: String in _hand:
		var n: Card3D = _hand[id]
		if not n.has_meta("slot"):
			continue
		var sx := cam.unproject_position(_hand_pivot.to_global(n.get_meta("slot"))).x
		var d := absf(sx - screen_pos.x)
		if d < best_d:
			best_d = d
			best = id
	return best


func _set_hover(id: String) -> void:
	if id == _hover:
		return
	_hover = id
	if id != "":
		hover_changes += 1
		Sfx.play("tap", -14.0, 0.15)
		Input.vibrate_handheld(8)
	_sync_hand()
	_update_zoom()


func _input(event: InputEvent) -> void:
	if _v.is_empty() or _v.over != null or _modal_root.get_child_count() > 0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Modo puntería: tocar un asiento (avatar o cartas) elige a ese jugador
			if _aim_kind != "" and get_viewport().gui_get_hovered_control() == null:
				var sid := _aim.seat_at(world.camera, event.position)
				if sid != "":
					_pressing = false
					_dragging = false
					get_viewport().set_input_as_handled()
					_aim_pick(sid)
					return
			# Si el dedo empieza sobre un botón de la interfaz, no es un arrastre por la mano
			_pressing = get_viewport().gui_get_hovered_control() == null
			_dragging = false
			_press_pos = event.position
			_press_card = _hand_card_at(event.position) if _pressing else ""
			_sel_before = _sel.duplicate()
		elif _pressing and _carry != "":
			_pressing = false
			_dragging = false
			_drop_carry(event.position)
			_update_zoom()
		elif _pressing:
			_pressing = false
			var target := _hover
			var was_drag := _dragging
			_dragging = false
			_set_hover("")
			# Soltar sobre otra carta distinta de la inicial la elige (la inicial ya se eligió al tocarla)
			if was_drag and target != "" and target != _press_card and _hand.has(target):
				_on_card_tapped(_hand[target])
			_update_zoom()
	elif event is InputEventMouseMotion and _pressing and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if not _dragging and event.position.distance_to(_press_pos) >= DRAG_START_PX:
			_dragging = true
			_update_zoom()
		if _carry != "":
			_move_carry(event.position)
		elif _dragging and event.position.y < _hand_top_y() - 30.0:
			# El dedo salió de la mano hacia arriba: se lleva la carta (la que se tocó o la resaltada)
			var id := _hover if _hover != "" else _press_card
			if id != "" and _hand.has(id):
				_start_carry(id, event.position)
		elif _dragging:
			_set_hover(_hand_card_at(event.position))


## Altura en pantalla del borde superior de la mano.
func _hand_top_y() -> float:
	return world.camera.unproject_position(_hand_pivot.to_global(Vector3(0, 0.14, -0.2 - SIZE_Z * HAND_SCALE))).y


## Punto de la mesa (a cierta altura) bajo el dedo.
func _table_point(screen_pos: Vector2, height: float) -> Vector3:
	var cam := world.camera
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return from
	return from + dir * ((height - from.y) / dir.y)


func _start_carry(id: String, screen_pos: Vector2) -> void:
	if _aim_kind != "":
		_exit_aim(false)
	_carry = id
	# Si la carta era parte de una pareja o trío ya elegidos, se lleva el combo; si no, solo esa carta
	if _sel_before.has(id):
		_sel = _sel_before.duplicate()
	else:
		_sel.clear()
		_sel.append(id)
	_hover = ""
	var n: Card3D = _hand[id]
	n.kill_motion()
	n.set_glow(0.2)
	_carry_prev = n.global_position
	_drop_ring.visible = true
	Sfx.play("card", -4.0)
	Input.vibrate_handheld(15)
	_sync_hand()
	_update_hud()          # el panel de abajo describe la carta que se lleva
	_move_carry(screen_pos)


func _move_carry(screen_pos: Vector2) -> void:
	var n: Card3D = _hand.get(_carry)
	if n == null:
		_carry = ""
		_drop_ring.visible = false
		return
	var p := _table_point(screen_pos, CARRY_HEIGHT)
	var vel := p - _carry_prev
	_carry_prev = p
	n.global_position = n.global_position.lerp(p, 0.65)
	# La carta se inclina hacia la cámara y se ladea un poco según hacia dónde se mueve
	var tilt := clampf(-vel.x * 2.2, -0.35, 0.35)
	n.global_rotation = Vector3(deg_to_rad(38.0), 0.0, tilt)
	n.scale = Vector3.ONE * HAND_SCALE * 1.12
	var on_table := Vector2(p.x - PLAY_ZONE_CENTER.x, p.z - PLAY_ZONE_CENTER.z).length() < PLAY_ZONE_RADIUS + 0.35
	var over := on_table and screen_pos.y < _hand_top_y() - 30.0
	if over != _carry_over:
		_carry_over = over
		if over:
			Input.vibrate_handheld(10)


## Soltar la carta: en el centro se juega; fuera, vuelve a la mano.
func _drop_carry(screen_pos: Vector2 = Vector2(-1, -1)) -> void:
	var id := _carry
	var over := _carry_over
	var need := _carry_need()
	_carry = ""
	_carry_over = false
	_drop_ring.visible = false
	if not _hand.has(id):
		_sync_hand()
		_update_hud()
		return
	# Soltada sobre un rival: si la jugada necesita objetivo y es válido, se juega contra él directamente
	if need != "" and screen_pos.x >= 0.0:
		var sid := _aim.seat_at(world.camera, screen_pos)
		if sid != "":
			var why := AimMode.reason(need, _player(sid), _v.you)
			if why != "":
				_toast(why, true)
			else:
				drops += 1
				_play_selected(sid)
			_sync_hand()
			_update_hud()
			return
	if not over:
		_sync_hand()
		_update_hud()
		return
	drops += 1
	var playable := false
	if _sel.size() == 1:
		playable = _v.playable.has(id)
		if not playable:
			var c := {}
			for x: Dictionary in _v.hand:
				if x.id == id:
					c = x
			_toast(_why_not(c), true)
	else:
		var cs := _combo_state()
		playable = not cs.is_empty() and not cs.has("err")
		if not playable:
			_toast(cs.get("err", "Ese combo no se puede jugar ahora."), true)
	if playable:
		_play_selected()      # igual que tocar JUGAR (pide objetivo si hace falta)
	_sync_hand()
	_update_hud()


func _on_card_tapped(card: Card3D) -> void:
	# Tocar la pila de descarte abre la lista (no si se está llevando una carta ni con otra ventana abierta)
	if _discard_nodes.get(card.card_id) == card:
		if _carry == "" and not _dragging and _modal.is_empty() and _modal_root.get_child_count() == 0 and _v.over == null:
			_open_discard()
		return
	if not _hand.has(card.card_id) or _v.over != null:
		return
	if _aim_kind != "":
		_exit_aim(false)      # tocar otra carta de la mano cancela la puntería
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
			_request_target(need)
			return
	else:
		var cs := _combo_state()
		if cs.is_empty() or cs.has("err"):
			return
		if target == "":
			_request_target("living")
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
	_exit_aim(false)
	_act(a)
	_update_hud()


# ---------------------------------------------------------------- modo puntería (UX-01)

## La jugada necesita objetivo: modo puntería sobre la mesa, o la lista antigua si `aim_with_list`.
func _request_target(kind: String) -> void:
	if aim_with_list:
		_modal = {"type": "target", "kind": kind}
	else:
		_aim_kind = kind
		_aim_forced = false
		_modal = {}
	_update_hud()


## Tipo de objetivo de lo que se lleva en la mano ("" si no necesita ninguno).
func _carry_need() -> String:
	if _carry == "" or _sel.is_empty():
		return ""
	if _sel.size() == 1:
		var need: Variant = _v.playable.get(_sel[0])
		return need if need is String else ""
	var cs := _combo_state()
	return "living" if (not cs.is_empty() and not cs.has("err")) else ""


## Tipo de objetivo cuyos asientos se resaltan: el de la puntería o el de la carta que se lleva.
func _aim_vis_kind() -> String:
	return _aim_kind if _aim_kind != "" else _carry_need()


func _aim_still_valid() -> bool:
	if _aim_forced:
		return _v.over == null
	if _v.over != null or _sel.is_empty():
		return false
	if _sel.size() == 1:
		return _v.playable.get(_sel[0]) is String
	var cs := _combo_state()
	return not cs.is_empty() and not cs.has("err")


## Sale del modo puntería sin jugar. `refresh`: redibuja la interfaz y restablece los asientos.
func _exit_aim(refresh: bool = true) -> void:
	if _aim_kind == "":
		return
	_aim_kind = ""
	_aim_forced = false
	_aim.set_kind("", _v, _seats)
	if refresh:
		_sync_seats()
		_update_hud()


## Se tocó a un jugador (asiento o ficha) en modo puntería: lo confirma o avisa por qué no vale.
func _aim_pick(id: String) -> void:
	if _aim_kind == "":
		return
	var why := AimMode.reason(_aim_kind, _player(id), _v.you)
	if why != "":
		_toast(why, true)
		return
	if _aim_forced:
		_aim_debug_pick = id
		_exit_aim()
		return
	_exit_aim(false)
	_play_selected(id)


func _aim_cancel() -> void:
	_exit_aim()


## Panel inferior del modo puntería: carta, instrucción, «Yo mismo» (si vale) y CANCELAR.
func _build_aim_panel() -> void:
	var panel := UIKit.panel(UIKit.C.cream, UIKit.C.toxic_dark, Vector2(24, 16))
	var col := UIKit.vbox(8)
	panel.add_child(col)
	var title := "Elige un objetivo"
	var cards := _sel_cards()
	if cards.size() == 1:
		title = CardDB.display_name(cards[0].type)
	elif cards.size() > 1:
		var cs := _combo_state()
		title = ("Pareja" if cards.size() == 2 else "Trío") + ((" de " + CardDB.display_name(cs.of)) if cs.has("of") else "")
	col.add_child(UIKit.label(title, 44, UIKit.C.dark, true))
	col.add_child(UIKit.label(AimMode.prompt(_aim_kind), 36, Color("3a2f4a"), false, true))
	var row := UIKit.hbox(14)
	col.add_child(row)
	if AimMode.self_valid(_aim_kind, _v):
		_add_btn(row, "Yo mismo", "normal", func() -> void: _aim_pick(_v.you), 40)
	var cancel := _add_btn(row, "CANCELAR", "danger", _aim_cancel, 40)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_slot.add_child(panel)


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
	# Distintivo del modo: así se sabe de un vistazo que esta es la pantalla de Plus
	var badge := UIKit.panel(UIKit.C.toxic, UIKit.C.dark, Vector2(12, 4))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_label := UIKit.label("PLUS", 30, UIKit.C.dark, true)
	badge_label.add_theme_constant_override("outline_size", 0)
	badge.add_child(badge_label)
	bar.add_child(badge)
	# Sentido invertido: rótulo corto en la misma fila (sin añadir altura); con sentido normal no se ve
	_dir_label = UIKit.label("↺ INVERTIDO", 30, UIKit.C.gold, true)
	_dir_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dir_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dir_label.visible = false
	bar.add_child(_dir_label)
	_turn_panel = UIKit.panel(UIKit.C.panel, UIKit.C.line, Vector2(20, 8))
	_turn_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn = UIKit.label("", 50, UIKit.C.ink, true)
	_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_panel.add_child(_turn)
	bar.add_child(_turn_panel)
	var hist := UIKit.button("HISTORIAL", "normal", 34)
	hist.size_flags_horizontal = Control.SIZE_SHRINK_END
	hist.pressed.connect(_open_history)
	bar.add_child(hist)
	_opps = RivalChips.new()
	tv.add_child(_opps)
	_risk = RiskMeter.new()
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

	# Recordatorio del futuro (UX-02): tira junto al mazo; solo su rectángulo recibe toques
	_mem_strip = DeckMemoryStrip.new()
	_mem_strip.tapped.connect(_open_memory)
	root.add_child(_mem_strip)

	# Carta seleccionada en grande. No intercepta toques: se puede seguir tocando la mano debajo.
	_zoom = Control.new()
	_zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom.visible = false
	root.add_child(_zoom)
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.5)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shadow.offset_left = 14
	shadow.offset_top = 18
	shadow.offset_right = 14
	shadow.offset_bottom = 18
	_zoom.add_child(shadow)
	_zoom_pic = TextureRect.new()
	_zoom_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_zoom_pic.stretch_mode = TextureRect.STRETCH_SCALE
	_zoom_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_zoom.add_child(_zoom_pic)

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

	# Modo puntería: asientos y fichas resaltados (también mientras se lleva una carta que pide objetivo)
	var vis := _aim_vis_kind()
	_aim.set_kind(vis, v, _seats)
	_opps.set_aim({} if vis == "" else _aim_valid_map(vis))
	_opps.set_pickable(_aim_kind != "")
	_opps.update(v, session.level_of)
	_risk.update(v)
	_mem_strip.update(_memory.strip(v))

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
		if NopWindow.can_respond(v):
			_add_btn(_buttons, NopWindow.button_text(v), "danger", _play_nope)
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
			"alter": _status.text = "Reordenas el futuro…" if pr.mine else "%s reordena el futuro…" % who
			"bury": _status.text = "Entierras una carta…" if pr.mine else "%s entierra una carta…" % who
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
	_update_zoom.call_deferred()


## Muestra en grande, entre los rivales y la mano, la última carta seleccionada (no mientras se arrastra).
func _update_zoom() -> void:
	if not is_inside_tree():
		return
	var type := ""
	# Solo con una carta elegida y el dedo quieto: mientras se arrastra (por la mano o al tablero) se oculta
	var show_id: String = "" if (_dragging or _carry != "" or _aim_kind != "") else (_sel[-1] if _sel.size() > 0 else "")
	if show_id != "" and _v.over == null and _modal_root.get_child_count() == 0:
		for c: Dictionary in _v.hand:
			if c.id == show_id:
				type = c.type
	if type == "":
		_zoom.visible = false
		_zoom_type = ""
		return
	var screen := get_viewport().get_visible_rect().size
	# Espacio libre: debajo de las fichas de rivales y encima de la mano (según dónde cae en pantalla)
	var top := _risk.get_global_rect().end.y + 18.0
	var hand_edge := _hand_pivot.to_global(Vector3(0, 0.14, -0.2 - SIZE_Z * HAND_SCALE))
	# unproject_position ya devuelve coordenadas de la interfaz (no de la ventana)
	var bottom := world.camera.unproject_position(hand_edge).y - 18.0
	var h := clampf(bottom - top, screen.y * 0.36, screen.y * 0.52)   # en pantallas cortas puede tapar un poco la mano
	var w := h * 5.0 / 7.0
	if w > screen.x * 0.74:
		w = screen.x * 0.74
		h = w * 7.0 / 5.0
	_zoom.size = Vector2(w, h)
	_zoom.position = Vector2((screen.x - w) / 2.0, top + maxf(0.0, (bottom - top - h) / 2.0))
	_zoom.pivot_offset = _zoom.size / 2.0
	_zoom.visible = true
	if type != _zoom_type:
		_zoom_type = type
		_zoom_pic.texture = CardDB.texture(type)
		_zoom.scale = Vector2(0.72, 0.72)
		_zoom.modulate.a = 0.0
		_zoom.rotation_degrees = -4.0
		var t := _zoom.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(_zoom, "scale", Vector2.ONE, 0.2)
		t.tween_property(_zoom, "rotation_degrees", 0.0, 0.2)
		t.tween_property(_zoom, "modulate:a", 1.0, 0.12)


## Por qué una carta (sola) no se puede jugar ahora.
func _why_not(c: Dictionary) -> String:
	if c.is_empty():
		return "No se puede jugar ahora."
	if CardDB.defs[c.type].cat:
		return "Selecciona otra igual para jugar una pareja."
	if c.type == "zombie":
		return "Se usa sola cuando sacas un Gatito Explosivo."
	if c.type == "nope":
		return "Úsala cuando alguien juegue una carta."
	if c.type == "clairvoyance":
		return "Úsala cuando otro juegue un Gatito Zombi."
	if c.type == "haunt":
		if _me().alive:
			return "Solo los muertos pueden espantar."
		if not _v.players.any(func(p: Dictionary) -> bool: return p.id != _v.you and p.alive and p.count > 0):
			return "Nadie tiene cartas que espantar."
		if not _idle():
			return "Espera a que termine la jugada en curso."
		return "No se puede espantar ahora."
	if not _me().alive:
		return "Estás muerto: solo Nop y cartas ⚡."
	if _v.cur != _v.you:
		return "Espera tu turno."
	if c.type in ["attack_dead", "grave_robber", "feed_dead"] and _v.deadN == 0:
		return "Necesita que haya jugadores muertos."
	if not _idle():
		return "Espera a que termine la jugada en curso."
	match c.type:
		"soul_swap":
			if not _v.players.any(func(p: Dictionary) -> bool: return not p.alive and p.count > 0):
				return "Necesita un jugador muerto con cartas."
		"targeted_attack":
			if not _v.players.any(func(p: Dictionary) -> bool: return p.id != _v.you and p.alive):
				return "No hay ningún rival vivo al que atacar."
		"crow_eye":
			if not _v.players.any(func(p: Dictionary) -> bool: return p.id != _v.you and p.count > 0):
				return "Nadie más tiene cartas que mirar."
		"alter_future", "bury", "draw_bottom":
			if int(_v.draw) == 0:
				return "El mazo está vacío."
	return "No se puede jugar ahora."


func _aim_valid_map(kind: String) -> Dictionary:
	var out := {}
	for p: Dictionary in _v.players:
		if p.id != _v.you:
			out[p.id] = AimMode.reason(kind, p, _v.you) == ""
	return out


func _build_selection_info() -> void:
	if _aim_kind != "" and _v.over == null:
		_build_aim_panel()
		return
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
			desc += "\n→ " + _why_not(c)
		if c.type == "clone":
			var ch := CloneHint.describe(_v)
			desc += "\n" + str(ch.text)
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


## Huella de una decisión propia con selector de mazo («zombie» / «bury»); "" si no es de ese tipo.
func _picker_signature(pr: Variant) -> String:
	if pr == null or not pr.mine or not (pr.type in ["zombie", "bury"]):
		return ""
	return "%s|%d|%s|%s|%s|%s" % [pr.type, int(_v.draw), str(pr.get("eks")), str(pr.get("revived")), str(pr.get("waiting")), str(pr.get("card"))]


func _build_modal() -> void:
	# Un selector de mazo no se reconstruye por avisos ajenos a la decisión: así no se pierde un arrastre en curso
	var sig := _picker_signature(_v.prompt)
	if sig != "" and sig == _picker_sig and is_instance_valid(_slot_picker) and _slot_picker.is_inside_tree() and _modal_root.get_child_count() > 0 and not _fx_running:
		if is_instance_valid(_picker_bar):
			_track(_picker_bar, _v.prompt)
		return
	_picker_sig = ""
	var keep_scroll := _discard_list.scroll_value() if is_instance_valid(_discard_list) else 0   # la lista conserva su posición al reconstruirse
	_clear(_modal_root)
	_discard_list = null
	_named_grid = null
	_peek_grid = null
	_arranger = null
	_slot_picker = null
	_slot_pickers = []
	_modal_title = ""
	var v := _v
	if _fx_running and (v.over != null or (v.prompt != null and v.prompt.mine and v.prompt.type == "explode")):
		return      # primero se ve la animación; _run_fx vuelve a llamar al terminar
	if v.over != null:
		var won: bool = v.over.winner == v.you
		var box := _open_modal("¡GANASTE!" if won else "Ganó " + _pname(v.over.winner), UIKit.C.toxic if won else UIKit.C.gold)
		_text(box, "Eres el último gatito con vida." if won else "Fue el último gatito con vida.")
		box.add_child(_stats.build_table(v, room_scores))
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
	if pr == null or not pr.mine or pr.type != "alter":
		_alter_order = []
	if pr == null or not (pr.type in ["zombie", "bury"]):
		_ins = [0, 0]
	if pr != null and pr.mine:
		_build_prompt_modal(pr)
		_picker_sig = _picker_signature(pr)
		return
	if _modal.is_empty():
		return
	match _modal.type:
		"target":
			var dead: bool = str(_modal.kind).begins_with("dead")
			var box := _open_modal("¿A qué muerto eliges?" if dead else "¿Contra quién?")
			var list: Array = []
			for p: Dictionary in v.players:
				if AimMode.reason(_modal.kind, p, v.you) == "":
					list.append(p)
			_player_buttons(box, list, func(id: String) -> void: _play_selected(id))
			_add_btn(box, "Cancelar", "ghost", _close_modal)
		"named":
			var box := _open_modal("¿Qué carta quieres?")
			_text(box, "Si %s la tiene, te la da." % _pname(_modal.target))
			var types: Array = v.get("deckTypes", CardDB.types_for(v.get("packs", [])))
			types = types.filter(func(t: String) -> bool: return t != "exploding")
			var target: String = _modal.target
			var known: Array = []
			var kh: Dictionary = _known_hands.get(target, {})
			if not kh.is_empty() and int(kh.count) == int(_player(target).get("count", -1)):
				for t: String in kh.cards:
					if types.has(t) and not known.has(t):
						known.append(t)        # lo que se vio con Ojo de Cuervo y sigue siendo cierto (UX-04)
			_named_grid = CardPickGrid.new().setup(types, get_viewport().get_visible_rect().size.y * 0.5, known)
			_named_grid.picked.connect(func(type: String) -> void: _play_selected(target, type))
			box.add_child(_named_grid)
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
		"peek":
			var box := _open_modal("Mano de %s" % _pname(_modal.target))
			var n_seen: int = (_modal.cards as Array).size()
			_text(box, "Solo tú lo ves. Tiene %d carta%s." % [n_seen, "" if n_seen == 1 else "s"], 30)
			_peek_grid = CardPickGrid.new().setup(_modal.cards, get_viewport().get_visible_rect().size.y * 0.5)
			box.add_child(_peek_grid)
			_add_btn(box, "Entendido", "primary", _close_modal)
		"clair":
			var box := _open_modal("Clarividencia")
			_text(box, "Viste dónde quedaron los explosivos (mazo de %d cartas):" % int(_modal.len))
			for i in _modal.positions.size():
				var p := int(_modal.positions[i])
				_text(box, "Explosivo %s: %s" % [str(i + 1) if _modal.positions.size() > 1 else "", "arriba del todo" if p == 0 else "debajo de %d carta%s" % [p, "s" if p > 1 else ""]], 38, UIKit.C.gold)
			_add_btn(box, "Entendido", "primary", _close_modal)
		"memory":
			var box := _open_modal("Lo que sabes del mazo", UIKit.C.gold)
			DeckMemoryStrip.fill_window(box, _memory.known(v), int(v.draw))
			_add_btn(box, "Cerrar", "primary", _close_modal)
		"history":
			var box := _open_modal("Historial")
			var avatars := {}
			for p: Dictionary in v.players:
				avatars[p.id] = int(p.avatar)
			var hl := HistoryList.new().setup(_history, _hist_mine, avatars, get_viewport().get_visible_rect().size.y * 0.5)
			hl.filter_changed.connect(func(mine: bool) -> void:
				_hist_mine = mine
				_update_hud())
			box.add_child(hl)
			_add_btn(box, "Cerrar", "primary", _close_modal)
		"discard":
			var box := _open_modal("Descarte")
			_text(box, "Las cartas jugadas, la más reciente arriba.", 28, UIKit.C.dim)
			_discard_list = DiscardList.new().setup(v, get_viewport().get_visible_rect().size.y * 0.5, keep_scroll)
			box.add_child(_discard_list)
			_add_btn(box, "Cerrar", "primary", _close_modal)
		"menu":
			var box := _open_modal("Menú")
			_add_btn(box, "Seguir jugando", "primary", _close_modal)
			var info := UIKit.hbox(12)
			box.add_child(info)
			_add_btn(info, "Cómo jugar", "normal", func() -> void: InfoScreen.open(self, "rules"), 38)
			_add_btn(info, "Cartas", "normal", func() -> void: InfoScreen.open(self, "cards", _v.get("packs", [])), 38)
			var audio := UIKit.hbox(12)
			box.add_child(audio)
			_add_btn(audio, "Sonido: sí" if Sfx.sfx_on else "Sonido: no", "normal", _toggle_sfx, 34)
			_add_btn(audio, "Música: sí" if Sfx.music_on else "Música: no", "normal", _toggle_music, 34)
			_add_btn(box, "Paso automático: sí" if _auto_pass else "Paso automático: no", "normal", _toggle_auto_pass, 34)
			_text(box, "Dejar pasar lo que no me afecta: no se te pide Nop ante jugadas ajenas que no van contra ti.", 24, UIKit.C.dim)
			_add_btn(box, "Salir de la partida", "danger", _ask_exit, 40)
		"exit":
			var box := _open_modal("¿Salir de la partida?")
			_text(box, "Se perderá la partida en curso." if not session.is_network() else ("Eres el anfitrión: la partida termina para todos." if session.is_host() else "Podrás volver a entrar mientras la partida siga."))
			_add_btn(box, "Seguir jugando", "primary", _close_modal)
			_add_btn(box, "Salir al menú", "danger", func() -> void: exit_requested.emit())


func _open_menu() -> void:
	_exit_aim(false)
	_modal = {"type": "menu"}
	_update_hud()


func _ask_exit() -> void:
	_modal = {"type": "exit"}
	_update_hud()


func _toggle_sfx() -> void:
	Sfx.set_sfx(not Sfx.sfx_on)
	_update_hud()


func _toggle_auto_pass() -> void:
	_auto_pass = not _auto_pass
	NopWindow.save_auto_pass(_auto_pass)
	_update_hud()
	_check_auto_pass()


## Con «Paso automático» activo, envía «pasar» ante una jugada ajena que no me afecta (una vez por jugada).
func _check_auto_pass() -> void:
	if not _auto_pass or not NopWindow.should_auto_pass(_v):
		return
	var sig := NopWindow.signature(_v)
	if sig == _auto_sig:
		return
	_auto_sig = sig
	_auto_pass_send.call_deferred(sig)


func _auto_pass_send(sig: String) -> void:
	if _auto_pass and NopWindow.signature(_v) == sig and NopWindow.should_auto_pass(_v):
		_act({"a": "pass"})


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
		["aim", _aim_kind != ""],
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
	_memory.note_insert(pos)
	_act({"a": "insert", "positions": pos})


func _confirm_alter() -> void:
	var order: Array = _arranger.order() if is_instance_valid(_arranger) else _alter_order
	_alter_order = []
	_act({"a": "reorder", "order": order})


func _confirm_bury() -> void:
	var pos := _ins[0]
	_ins = [0, 0]
	_act({"a": "bury", "pos": pos})


func _confirm_give() -> void:
	if _give_sel != "":
		var cid := _give_sel
		_give_sel = ""
		_act({"a": "give", "card": cid})


func _pick_give(cid: String) -> void:
	_give_sel = cid
	_update_hud()


# ---------------------------------------------------------------- historial

## Guarda en el historial lo que pasó, en palabras. Los eventos sin texto (robar, cambio de turno,
## ver el futuro) se redactan aquí para que el historial cuente toda la partida.
func _record(e: Dictionary) -> void:
	var text := ""
	var kind := ""
	match e.type:
		"turn":
			text = "Tu turno" if e.player == _v.you else "Turno de " + _pname(e.player)
			kind = "turn"
		"draw":
			var from_bottom: bool = e.get("bottom", false)
			if e.player == _v.you:
				text = "Robas la carta del fondo del mazo." if from_bottom else "Robas una carta."
			else:
				text = ("%s roba la carta del fondo del mazo." if from_bottom else "%s roba una carta.") % _pname(e.player)
		"future":
			var names: Array = e.cards.map(func(t: String) -> String: return CardDB.display_name(t))
			text = ("Reordenaste el futuro: " if _alter_live else "Viste el futuro: ") + ", ".join(PackedStringArray(names)) + "."
			kind = "me"
		"peek":
			var seen: Array = e.cards.map(func(t: String) -> String: return CardDB.display_name(t))
			text = "Viste la mano de %s: %s." % [_pname(e.target), ", ".join(PackedStringArray(seen))]
			kind = "me"
		_:
			text = e.get("text", "")
			if e.has("to"):
				kind = "me"
	if text == "":
		return
	var me: String = _v.you
	_history.append({
		"text": text, "kind": kind,
		"player": e.get("player"), "target": e.get("target"),
		"mine": kind == "me" or e.get("player") == me or e.get("target") == me,
		"cards": HistoryList.cards_of(e),
	})
	if _history.size() > HISTORY_MAX:
		_history.pop_front()


func _open_discard() -> void:
	_exit_aim(false)
	_modal = {"type": "discard"}
	_update_hud()


func _open_history() -> void:
	_exit_aim(false)
	_modal = {"type": "history"}
	_update_hud()


## Para la prueba automática.
func debug_history_size() -> int:
	return _history.size()


## Para la prueba (UX-12): entradas del historial con el filtro dado.
func debug_history_count(mine_only: bool) -> int:
	return HistoryList.count(_history, mine_only)


## Para la prueba (UX-12): entradas dibujadas en la ventana «Historial» abierta (-1 si no está abierta).
func debug_history_rows() -> int:
	var hl := _find_history(_modal_root)
	return hl.debug_rows() if hl != null else -1


## Para la prueba (UX-12): {avatars, thumbs, blockers} de la ventana abierta.
func debug_history_info() -> Dictionary:
	var hl := _find_history(_modal_root)
	return hl.debug_info() if hl != null else {}


func _find_history(n: Node) -> HistoryList:
	if n is HistoryList:
		return n
	for c in n.get_children():
		var r := _find_history(c)
		if r != null:
			return r
	return null


## Para la prueba (UX-05): textos de los botones de la zona inferior.
func debug_buttons() -> Array[String]:
	var out: Array[String] = []
	for b in _buttons.get_children():
		if b is Button:
			out.append(b.text)
	return out


## Para la prueba (UX-05): ids de los Nop resaltados en la mano.
func debug_nop_lit() -> Array[String]:
	return _nop_lit


## Para la prueba (UX-05): activa o apaga el paso automático sin guardarlo en los ajustes.
func debug_set_auto_pass(on: bool) -> void:
	_auto_pass = on
	_auto_sig = ""
	_check_auto_pass()


## Para la prueba (UX-05): texto de estado de la zona inferior.
func debug_status() -> String:
	return _status.text


## Para la prueba (UX-09): contadores acumulados.
func debug_stats() -> MatchStats:
	return _stats


## Para la prueba automática: la carta de arriba de la pila de descarte (para tocarla).
func debug_discard_top() -> Card3D:
	var all: Array = _v.discard
	return _discard_nodes.get(all.back().id) if not all.is_empty() else null


## Ids que lista la ventana «Descarte» (vacío si no está abierta), la más reciente primero.
func debug_discard_listed() -> Array[String]:
	return _discard_list.debug_ids() if is_instance_valid(_discard_list) else ([] as Array[String])


## Texto «Copiará: …» del primer Clon de la mano ("" si no hay Clon).
func debug_clone_hint() -> String:
	for c: Dictionary in _v.hand:
		if c.type == "clone":
			return str(CloneHint.describe(_v).text)
	return ""


## Selecciona el primer Clon de la mano y devuelve el texto del panel de selección ("" si no hay Clon).
func debug_select_clone() -> String:
	for c: Dictionary in _v.hand:
		if c.type == "clone":
			_sel.clear()
			_sel.append(c.id)
			_sync_hand()
			_update_hud()
			return _info_text()
	return ""


## Texto de todas las etiquetas del panel de selección.
func _info_text() -> String:
	var out := ""
	var stack: Array = [_info_slot]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			out += n.text + "\n"
		stack.append_array(n.get_children())
	return out


## Abre la cuadrícula del trío contra el primer rival vivo y devuelve los tipos que ofrece.
func debug_open_named() -> Array[String]:
	if _sel.is_empty() and not _v.hand.is_empty():
		_sel.append(_v.hand[0].id)       # la ventana se cierra sola sin selección
	for p: Dictionary in _v.players:
		if p.id != _v.you and p.alive:
			_modal = {"type": "named", "target": p.id}
			_update_hud()
			break
	return _named_grid.debug_types() if is_instance_valid(_named_grid) else ([] as Array[String])


## Modo puntería activo (prueba).
func debug_aim_active() -> bool:
	return _aim_kind != ""


func debug_aim_kind() -> String:
	return _aim_kind


## Última jugada enviada sin error ({} si ninguna).
func debug_last_play() -> Dictionary:
	return _last_play.duplicate(true)


## Último rival elegido en un modo puntería forzado.
func debug_aim_pick() -> String:
	return _aim_debug_pick


## Carta de la mano que pide objetivo (Favor, etc.) o null.
func debug_targeted_card() -> Card3D:
	for c: Dictionary in _v.hand:
		if _v.playable.get(c.id) is String and c.type != "nope":
			return _hand.get(c.id)
	return null


## Dos cartas iguales de la mano (para una pareja) o [] si no hay.
func debug_pair_cards() -> Array:
	var seen := {}
	for c: Dictionary in _v.hand:
		if c.type in ["clone", "nope", "exploding"]:
			continue
		if seen.has(c.type):
			return [_hand[seen[c.type]], _hand[c.id]]
		seen[c.type] = c.id
	return []


## Prueba: fuerza el modo puntería (sin jugada detrás). Elegir a alguien solo lo anota en debug_aim_pick().
func debug_force_aim(kind: String) -> void:
	_aim_kind = kind
	_aim_forced = true
	_modal = {}
	_update_hud()


## Posición en pantalla (coordenadas del viewport) del avatar de un rival.
func debug_seat_pos(id: String) -> Vector2:
	return world.camera.unproject_position((_seats[id].avatar as Node3D).global_position)


## Rivales válidos / no válidos para el tipo de objetivo actual (vacío si no hay puntería).
func debug_aim_ids(valid: bool) -> Array:
	var out: Array = []
	for id: String in _seats:
		if _aim.active() and _aim.is_valid(id) == valid:
			out.append(id)
	return out


## Texto del panel inferior de selección/puntería.
func debug_info_text() -> String:
	return _info_text()


## Quita la selección de cartas (prueba).
func debug_clear_selection() -> void:
	_sel.clear()
	_sync_hand()
	_update_hud()


# ---------------------------------------------------------------- ayudas de prueba (La Cripta)

## Selecciona la primera carta de ese tipo de la mano (sin tocar la pantalla). false si no hay.
func debug_select_type(type: String) -> bool:
	for c: Dictionary in _sorted_hand():
		if c.type == type:
			_sel.clear()
			_sel.append(c.id)
			_sync_hand()
			_update_hud()
			return true
	return false


## Motivo por el que una carta de ese tipo no se podría jugar ahora (`_why_not`).
func debug_why_not(type: String) -> String:
	return _why_not({"id": "debug", "type": type})


## Título de la ventana abierta ("" si no hay ninguna).
func debug_modal_title() -> String:
	return _modal_title


func debug_arranger() -> FutureArranger:
	return _arranger if is_instance_valid(_arranger) else null


func debug_memory() -> DeckMemory:
	return _memory


func debug_strip() -> DeckMemoryStrip:
	return _mem_strip


## Prueba: abre la ventana del recordatorio como al tocar la tira.
func debug_open_memory() -> void:
	_open_memory()


func debug_slot_pickers() -> Array[DeckSlotPicker]:
	return _slot_pickers


## Prueba: ¿se consideraría «partida recién empezada» una vista con estos eventos?
func debug_fresh(events: Array) -> bool:
	return _is_fresh_start(events)


## Prueba: avisos y efectos en pantalla (popups, toasts) y ventana abierta.
func debug_effects() -> Dictionary:
	return {"popups": _fx_root.get_child_count(), "toasts": _toasts.get_child_count(), "modal": _modal_title}


func debug_slot_picker() -> DeckSlotPicker:
	return _slot_picker if is_instance_valid(_slot_picker) else null


func debug_peek_grid() -> CardPickGrid:
	return _peek_grid if is_instance_valid(_peek_grid) else null


func debug_named_grid() -> CardPickGrid:
	return _named_grid if is_instance_valid(_named_grid) else null


## Lo que se recuerda de la mano de un rival: {cards, count} o {}.
func debug_known(id: String) -> Dictionary:
	return _known_hands.get(id, {})


## Estado de la flecha de sentido: {visible, dir, label}.
func debug_dir() -> Dictionary:
	return {"visible": _dir_ring.visible, "dir": _dir_ring.dir, "label": _dir_label.text if _dir_label.visible else ""}


## Abre la cuadrícula del trío contra ese jugador (necesita una selección) y devuelve los tipos de «Sabes que tiene».
func debug_open_named_for(id: String) -> Array[String]:
	if _sel.is_empty() and not _v.hand.is_empty():
		_sel.append(_v.hand[0].id)
	_modal = {"type": "named", "target": id}
	_update_hud()
	return _named_grid.debug_known() if is_instance_valid(_named_grid) else ([] as Array[String])


## Confirma un objetivo en modo puntería como si se hubiera tocado su ficha.
func debug_aim_confirm(id: String) -> void:
	_aim_pick(id)


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
				# Lo conocido se marca solo en el primer selector (el segundo cuenta con el primer explosivo ya dentro)
				var picker := DeckSlotPicker.new().setup(max_pos, _ins[i], title, _memory.known(v) if i == 0 else [], 470 if pr.eks == 1 else 330)
				picker.changed.connect(func(pos: int) -> void: _ins[idx] = pos)
				box.add_child(picker)
				_slot_picker = picker
				_slot_pickers.append(picker)
			var bar := UIKit.timer_bar()
			box.add_child(bar)
			_track(bar, pr)
			_picker_bar = bar
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
		"alter":
			var box := _open_modal("Alterar el Futuro")
			_text(box, "Solo tú lo ves. Arrastra una carta sobre otra o toca dos cartas para intercambiarlas.", 30)
			var types: Array = pr.cards
			var order: Array = _alter_order if _alter_order.size() == types.size() else []
			_arranger = FutureArranger.new().setup(types, 370, order)
			_arranger.order_changed.connect(func(o: Array) -> void: _alter_order = o)
			_alter_order = _arranger.order()
			box.add_child(_arranger)
			_text(box, "Las etiquetas son fijas: la carta de PRÓXIMA será la siguiente que se robe.", 26, UIKit.C.dim)
			var bar := UIKit.timer_bar()
			box.add_child(bar)
			_track(bar, pr)
			_add_btn(box, "CONFIRMAR", "primary", _confirm_alter, 54)
		"bury":
			var box := _open_modal("Entierro")
			_text(box, "Robaste esta carta y no entra en tu mano. Entiérrala en secreto donde quieras; tu turno termina.", 30)
			if pr.card == "exploding":
				_text(box, "¡Es un Gatito Explosivo! No explota: se entierra igual.", 30, UIKit.C.gold)
			_centered(box, UIKit.card_image(pr.card, 380))
			var max_pos: int = int(v.draw)
			_ins[0] = mini(_ins[0], max_pos)
			var picker := DeckSlotPicker.new().setup(max_pos, _ins[0], "", _memory.known(v))
			picker.changed.connect(func(pos: int) -> void: _ins[0] = pos)
			box.add_child(picker)
			_slot_picker = picker
			var bar := UIKit.timer_bar()
			box.add_child(bar)
			_track(bar, pr)
			_picker_bar = bar
			_add_btn(box, "CONFIRMAR", "primary", _confirm_bury, 54)
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
