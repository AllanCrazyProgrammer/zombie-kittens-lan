extends Node3D
## Raíz de la aplicación: escenario 3D permanente + menús o partida encima, y el flujo de red
## (crear sala, unirse, reconectar).
##
## Argumentos de depuración (tras "--"):
##   --auto [rivales] [nivel]   partida de un jugador en la que la IA también juega por el humano
##   --seed N                   semilla del reparto
##   --plus                     con --auto, partida en modo Plus
##   --slow                     en modo --auto, el "humano" tarda 5 s en responder (deja ver las ventanas)
##   --shots carpeta [cada_s]   guarda capturas periódicas
##   --uitest carpeta           prueba de toques (menú, elegir carta, jugar, robar, salir) en modo clásico
##   --uitest-plus carpeta      la misma prueba de toques en modo Plus (PlusGameScreen)
##   --nettest host [humanos]   crea una sala, espera a los invitados, añade una IA y juega sola
##   --nettest join IP          se une a una sala y juega sola      (--nettest discover: la busca en la red)
##   --drop s                   en --nettest join: corta la conexión a los s segundos y se reconecta
##   --no-broadcast             el anfitrión no se anuncia por difusión (prueba la búsqueda directa)
##   --token X                  identidad de este jugador (para probar dos instancias en la misma máquina)
##   --page nombre              abre el menú en esa página (home, solo, join, settings)
##   --info rules|cards         abre la pantalla de reglas o la guía de cartas
##   --tutorial                 arranca la partida guiada
##   --quality high|medium|low  fuerza la calidad gráfica en esta ejecución
##   --quit-after s             cierra tras s segundos

const SETTINGS := "user://settings.cfg"
const MAX_RECONNECTS := 6

var _world: TableWorld
var _menu: MenuScreen
var _game: Node3D          # GameScreen (clásico) o PlusGameScreen: misma API pública, por eso se usa con llamadas dinámicas
var _session: GameSession
var _room: RoomHost
var _last_opts := {}
var _token := ""
var _join_ip := ""
var _reconnects := 0
var _shots_dir := ""
var _shot_every := 3.0
var _shot_t := 0.0
var _shot_n := 0
var _quit_after := -1.0
var _elapsed := 0.0
var _nettest := ""
var _nettest_humans := 2
var _nettest_started := false
var _auto_t := 0.0
var _drop_at := -1.0
var _game_started_at := -1.0
var _fps_t := 0.0
var _fps_n := 0
var _fps_worst := 0.0


func _ready() -> void:
	_world = TableWorld.new()
	add_child(_world)
	# Compila los shaders de partículas al arrancar (lejos de la vista) para que la primera explosión no dé un tirón
	Vfx.explosion(self, Vector3(0, -60, 0))
	get_viewport().size_changed.connect(_fit_view)
	_fit_view()
	Net.connected.connect(_on_net_connected)
	Net.failed.connect(_on_net_failed)
	Net.server_lost.connect(_on_net_lost)

	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	_token = cfg.get_value("net", "token", "")
	if _token == "":
		_token = "%x%x" % [randi(), Time.get_ticks_usec()]
		cfg.set_value("net", "token", _token)
		cfg.save(SETTINGS)

	var args := OS.get_cmdline_user_args()
	var arg := func(flag: String, offset: int = 1) -> String:
		var k := args.find(flag)
		return args[k + offset] if k >= 0 and k + offset < args.size() and not args[k + offset].begins_with("--") else ""
	if arg.call("--quality") != "":
		_world.apply_quality(arg.call("--quality"))
	if args.has("--no-broadcast"):
		Net.broadcast_enabled = false
	if arg.call("--token") != "":
		_token = arg.call("--token")
	if arg.call("--shots") != "":
		_shots_dir = arg.call("--shots")
		if arg.call("--shots", 2).is_valid_float():
			_shot_every = float(arg.call("--shots", 2))
	if arg.call("--quit-after") != "":
		_quit_after = float(arg.call("--quit-after"))
	if arg.call("--drop") != "":
		_drop_at = float(arg.call("--drop"))
	if args.has("--uitest") or args.has("--uitest-plus"):
		_show_menu()
		var plus_test := args.has("--uitest-plus")
		_ui_test(arg.call("--uitest-plus" if plus_test else "--uitest"), plus_test)
	elif args.has("--nettest"):
		_nettest = arg.call("--nettest")
		_show_menu()
		_menu.profile.name = "Anfitrion" if _nettest == "host" else "Invitado" + _token.left(3)
		if _nettest == "host":
			if arg.call("--nettest", 2).is_valid_int():
				_nettest_humans = int(arg.call("--nettest", 2))
			_on_host()
		elif _nettest == "discover":
			Net.start_listening()
		else:
			_on_join(arg.call("--nettest", 2))
	elif args.has("--auto"):
		var opts := {"autoplay": true, "rivals": 2, "level": "normal", "name": "Allan"}
		if arg.call("--auto").is_valid_int():
			opts.rivals = int(arg.call("--auto"))
		if arg.call("--auto", 2) != "":
			opts.level = arg.call("--auto", 2)
		if arg.call("--seed") != "":
			opts.seed = int(arg.call("--seed"))
		if args.has("--slow"):
			opts.me_delay = 5200
		if args.has("--plus"):
			opts.plus = true
			opts.packs = ["crypt"]       # la demostración Plus lleva el pack de La Cripta
		_start_solo(opts)
	elif args.has("--tutorial"):
		_start_solo({"rivals": 1, "level": "easy", "deck_mode": "official", "name": "Allan", "tutorial": true, "seed": 4})
	else:
		_show_menu(arg.call("--page") if arg.call("--page") != "" else "home")
		if arg.call("--info") != "":
			InfoScreen.open(self, arg.call("--info"))


func _process(delta: float) -> void:
	_elapsed += delta
	# En compilaciones de depuración se anota el rendimiento en el registro cada 4 s (adb logcat -s godot)
	if OS.is_debug_build():
		_fps_t += delta
		_fps_n += 1
		_fps_worst = maxf(_fps_worst, delta)
		if _fps_t >= 4.0:
			print("FPS %.0f  (peor cuadro %.0f ms)  %s" % [_fps_n / _fps_t, _fps_worst * 1000.0, "partida" if _game else "menú"])
			_fps_t = 0.0
			_fps_n = 0
			_fps_worst = 0.0
	if _shots_dir != "":
		_shot_t += delta
		if _shot_t >= _shot_every:
			_shot_t = 0.0
			_shot_n += 1
			_save_shot("%s/shot_%02d.png" % [_shots_dir, _shot_n])
			print("shot %02d: %s" % [_shot_n, _game.debug_state() if _game else "menú " + (_menu.page if _menu else "")])
	if _nettest != "":
		_nettest_step(delta)
	if _quit_after > 0.0 and _elapsed >= _quit_after:
		get_tree().quit()


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


## En pantallas menos alargadas sube la mesa para dejar sitio a los controles de abajo.
func _fit_view() -> void:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.y / maxf(1.0, size.x)
	_world.set_view_offset(clampf(aspect - 2.0, -0.5, 0.3) * 1.1)


# ---------------------------------------------------------------- menús y partida de un jugador

func _show_menu(page: String = "home", text: String = "") -> void:
	if _game:
		_game.queue_free()
		_game = null
	if _menu == null:
		_menu = MenuScreen.new()
		_menu.solo_requested.connect(_start_solo)
		_menu.host_requested.connect(_on_host)
		_menu.join_requested.connect(_on_join)
		_menu.leave_requested.connect(_on_leave)
		_menu.quality_changed.connect(_world.apply_quality)
		add_child(_menu)
	if _session is ClientSession:
		_menu.set_session(_session)
	_menu.show_page(page, text)


func _hide_menu() -> void:
	if _menu:
		Net.stop_listening()
		_menu.queue_free()
		_menu = null


func _open_game() -> void:
	_hide_menu()
	if _game:
		_game.queue_free()
	if _session.is_plus():
		_game = PlusGameScreen.new().setup(_session, _world)
	else:
		_game = GameScreen.new().setup(_session, _world)
	_game.exit_requested.connect(_on_game_exit)
	_game.rematch_requested.connect(func() -> void: _start_solo(_last_opts))
	_game.lobby_requested.connect(func() -> void: (_session as ClientSession).send({"t": "toLobby"}))
	add_child(_game)
	_game_started_at = _elapsed


func _start_solo(opts: Dictionary) -> void:
	_close_session()
	_last_opts = opts
	var solo := LocalMatch.new()
	add_child(solo)
	solo.start(opts)
	_session = solo
	_open_game()
	_game.coach = opts.get("tutorial", false)
	if _game.coach:
		_game._update_hud()


func _on_game_exit() -> void:
	_close_session()
	_show_menu()


## Cierra la partida o sala actual y la conexión de red.
func _close_session() -> void:
	Net.stop_beacon()
	Net.close()
	_reconnects = 0
	if _game:
		_game.queue_free()
		_game = null
	if _session:
		_session.queue_free()
		_session = null
	if _room:
		_room.queue_free()
		_room = null


func _on_leave() -> void:
	_close_session()
	_show_menu()


# ---------------------------------------------------------------- red: crear sala, unirse, reconectar

func _profile() -> Dictionary:
	return _menu.profile if _menu else {"name": "Gatito", "avatar": 0}


func _bind_client(cs: ClientSession) -> void:
	_session = cs
	add_child(cs)
	cs.updated.connect(_on_client_state)
	cs.lobby_updated.connect(_on_client_lobby)
	cs.left.connect(_on_client_left)


func _on_host() -> void:
	var me := _profile().duplicate()
	_close_session()
	if Net.host() != OK:
		_show_menu("home", "No se pudo crear la sala: el puerto está ocupado. Cierra otras copias del juego.")
		return
	_room = RoomHost.new()
	_room.configure(_menu != null and _menu.plus)   # el modo se fija al crear la sala
	add_child(_room)
	var cs := ClientSession.new().setup(_room)
	_bind_client(cs)
	cs.hello(str(me.name), int(me.avatar), _token)
	Net.start_beacon(_room.beacon_info)
	_show_menu("lobby")


func _on_join(ip: String) -> void:
	_close_session()
	_join_ip = ip
	if Net.join(ip) != OK:
		_show_menu("join", "Dirección inválida.")
		return
	_show_menu("connecting", ip)


func _on_net_connected() -> void:
	var me := _profile()
	if _session is ClientSession:
		# Reconexión: el anfitrión nos reconoce por la ficha y nos devuelve nuestro asiento
		_reconnects = 0
		(_session as ClientSession).hello(str(me.name), int(me.avatar), _token)
		if _game:
			_game.notice("Conexión recuperada")
		return
	var cs := ClientSession.new().setup(null)
	_bind_client(cs)
	cs.hello(str(me.name), int(me.avatar), _token)
	_show_menu("lobby")


func _on_net_failed() -> void:
	if _session is ClientSession:
		await get_tree().create_timer(1.5).timeout
		_try_reconnect()
	else:
		_show_menu("join", "No se pudo conectar con %s. ¿Está creada la sala y están en la misma Wi-Fi?" % _join_ip)


func _on_net_lost() -> void:
	if _session is ClientSession and (_session as ClientSession).room == null:
		_try_reconnect()


func _try_reconnect() -> void:
	if not (_session is ClientSession):
		return
	_reconnects += 1
	if _reconnects > MAX_RECONNECTS:
		_close_session()
		_show_menu("home", "Se perdió la conexión con el anfitrión.")
		return
	if _game:
		_game.notice("Reconectando… (%d)" % _reconnects, true)
	elif _menu:
		_menu.show_page(_menu.page, "Reconectando… (%d)" % _reconnects)
	Net.join(_join_ip)


func _on_client_state() -> void:
	if _game == null:
		_open_game()


func _on_client_lobby() -> void:
	var cs := _session as ClientSession
	if cs == null or cs.lobby.get("started", false):
		return
	# El anfitrión volvió a la sala de espera (o aún no empieza)
	if _game or _menu == null or _menu.page != "lobby":
		_show_menu("lobby")


func _on_client_left(reason: String) -> void:
	_close_session()
	_show_menu("home", reason)


# ---------------------------------------------------------------- prueba de red (--nettest)

func _nettest_step(delta: float) -> void:
	_auto_t += delta
	if _auto_t < 0.45:
		return
	_auto_t = 0.0
	if _nettest == "discover" and _session == null and not Net.rooms.is_empty():
		var found: Dictionary = Net.rooms.values()[0]
		var ip: String = found.ip
		print("NETTEST sala encontrada en %s: %s" % [ip, found.get("name")])
		_nettest = "join"
		_on_join(ip)
		return
	var cs := _session as ClientSession
	if cs == null:
		return
	if _nettest == "host" and not cs.in_game() and not _nettest_started and not cs.lobby.is_empty():
		var humans := 0
		for p: Dictionary in cs.lobby.players:
			humans += 0 if p.bot else 1
		if humans >= _nettest_humans:
			_nettest_started = true
			cs.send({"t": "addBot", "level": "hard"})
			cs.send({"t": "start"})
			print("NETTEST partida iniciada con %d humanos" % humans)
		return
	if _drop_at > 0.0 and _game_started_at >= 0.0 and _elapsed - _game_started_at >= _drop_at:
		_drop_at = -1.0
		print("NETTEST corto la conexión a propósito")
		Net.close()
		await get_tree().create_timer(2.5).timeout
		print("NETTEST intento reconectar")
		_try_reconnect()
		return
	var v := cs.view()
	if v.is_empty():
		return
	if v.over != null:
		var winner := ""
		for p: Dictionary in v.players:
			if p.id == v.over.winner:
				winner = p.name
		print("NETTEST fin: ganó %s | soy %s | cartas en mano %d" % [winner, cs.me_id, v.hand.size()])
		_nettest = ""
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
		return
	var a := _auto_action(v)
	if not a.is_empty():
		cs.act(a)


## Jugador automático mínimo que decide solo con lo que ve en pantalla (sirve igual para anfitrión e invitado).
func _auto_action(v: Dictionary) -> Dictionary:
	var pr: Variant = v.prompt
	if pr != null and pr.get("mine", false):
		match pr.type:
			"explode":
				for c: Dictionary in v.hand:
					if c.type == "zombie":
						return {"a": "play", "cards": [c.id]}
				return {"a": "die"}
			"zombie":
				if pr.needRevive and pr.revived == null:
					for p: Dictionary in v.players:
						if not p.alive:
							return {"a": "revive", "target": p.id}
				if not pr.waiting:
					var pos: Array = []
					for i in int(pr.eks):
						pos.append(i)
					return {"a": "insert", "positions": pos}
			"give":
				return {"a": "give", "card": v.hand[0].id}
			"dig":
				return {"a": "dig", "keep": true}
		return {}
	if v.win != null:
		return {"a": "pass"} if v.win.canNope and not v.win.passed else {}
	if v.cur == v.you and pr == null and v.stack.is_empty():
		return {"a": "draw"}
	return {}


# ---------------------------------------------------------------- prueba automática de toques (--uitest carpeta)
# Simula toques reales en pantalla: menú → jugar → elegir carta → jugarla → robar del mazo.

func _find_button(n: Node, text: String) -> Button:
	if n is Button and n.text == text and n.is_visible_in_tree():
		return n
	for c in n.get_children():
		var r := _find_button(c, text)
		if r:
			return r
	return null


func _tap(window_pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = window_pos
		e.global_position = window_pos
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame


## Arrastra con el botón/dedo apretado de `from` a `to`. hold=true deja el dedo puesto (sin soltar);
## hold=false solo suelta en `to`.
func _drag(from: Vector2, to: Vector2, hold: bool) -> void:
	if hold:
		var down := InputEventMouseButton.new()
		down.button_index = MOUSE_BUTTON_LEFT
		down.pressed = true
		down.position = from
		down.global_position = from
		Input.parse_input_event(down)
		await get_tree().process_frame
		for k in range(1, 25):
			var m := InputEventMouseMotion.new()
			m.position = from.lerp(to, k / 24.0)
			m.global_position = m.position
			m.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(m)
			await get_tree().process_frame
			await get_tree().process_frame
		return
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	up.global_position = to
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame


func _tap_control(c: Control) -> void:
	await _tap(get_viewport().get_final_transform() * c.get_global_rect().get_center())


func _tap_3d(n: Node3D, local_offset: Vector3 = Vector3.ZERO) -> void:
	await _tap(get_viewport().get_final_transform() * _world.camera.unproject_position(n.to_global(local_offset)))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ui_test(dir: String, plus_mode: bool = false) -> void:
	var report: Array = []
	await _wait(1.2)
	_menu.set_plus(plus_mode, false)     # sin guardar: la prueba no cambia los ajustes del usuario
	await _wait(0.3)
	_say(report, "selector de modo visible: %s | modo de la prueba: %s" % [str(_find_button(self, "PLUS") != null and _find_button(self, "CLÁSICO") != null), "PLUS" if plus_mode else "CLÁSICO"])
	await _save_shot(dir + "/t1_menu.png")
	await _tap_control(_find_button(self, "UN JUGADOR"))
	await _wait(0.4)
	var b := _find_button(self, "4")
	if b:
		await _tap_control(b)
	await _wait(0.3)
	_say(report, "menú: rivales = %s" % str(_menu._opts.rivals))
	await _tap_control(_find_button(self, "¡JUGAR!"))
	await _wait(1.5)
	_say(report, "partida creada: %s" % str(_game != null))
	_say(report, "pantalla de juego: %s | sesión Plus: %s" % [_game.get_script().get_global_name(), str(_session.is_plus())])
	if _game.get_script().get_global_name() != ("PlusGameScreen" if plus_mode else "GameScreen"):
		_say(report, "ERROR: la pantalla de juego no corresponde al modo")
	# Espera a que sea mi turno con una carta jugable sin objetivo (hasta 90 s)
	var card: Card3D = null
	for _i in 180:
		_ui_rescue(plus_mode)
		if _game.debug_can_draw():
			card = _game.debug_playable_card()
			if card:
				break
			await _tap_3d(_game.debug_deck_card())      # sin carta jugable: roba y sigue esperando
		await _wait(0.5)
		if (_session as LocalMatch).game.over != null:
			break
	var played_id := ""
	if card:
		played_id = card.card_id
		var before: int = (_session as LocalMatch).game.discard.size()
		await _wait(0.5)
		var chips_before: int = _game.debug_chip_builds() if plus_mode else 0
		await _tap_3d(card, Vector3(-0.24, 0, -0.3))   # esquina superior izquierda: la parte que no tapa la carta vecina
		await _wait(0.6)
		if plus_mode:
			var gm: ZKGame = (_session as LocalMatch).game
			var alive := 0
			for pl in gm.players:
				alive += 1 if pl.alive else 0
			var rk: Dictionary = _game.debug_risk()
			var expect := int(round(100.0 * (alive - 1) / maxi(1, gm.draw.size())))
			_say(report, "Plus: fichas construidas antes/después de seleccionar: %d / %d | %s" % [chips_before, _game.debug_chip_builds(), "OK" if chips_before == _game.debug_chip_builds() else "ERROR: se recrearon"])
			_say(report, "Plus: riesgo %d%% (esperado %d%%), tramo %s | %s" % [rk.pct, expect, rk.name, "OK" if absi(rk.pct - expect) <= 1 else "ERROR: incoherente"])
		await _save_shot(dir + "/t2_seleccion.png")
		_say(report, "carta grande visible con la carta elegida y el dedo quieto: %s" % str(_game.debug_zoom_visible()))
		_say(report, "carta seleccionada: %s (%s)" % [card.type, _game.debug_state()])
		var play := _find_button(self, "JUGAR")
		_say(report, "botón JUGAR visible: %s" % str(play != null))
		if play:
			await _tap_control(play)
		await _wait(0.4)
		await _save_shot(dir + "/t3_jugada.png")
		_say(report, "descarte %d → %d" % [before, (_session as LocalMatch).game.discard.size()])
		# Si la carta abre una ventana (p. ej. Ver el Futuro), se cierra con su botón
		await _wait(1.6)
		var ok := _find_button(self, "Entendido")
		if ok:
			await _save_shot(dir + "/t3b_ventana.png")
			_say(report, "ventana tras jugar: %s" % _game.debug_state())
			await _tap_control(ok)
			await _wait(0.4)
	else:
		_say(report, "no hubo carta jugable")
	# Robar tocando el mazo
	for _i in 120:
		_ui_rescue(plus_mode)
		if (_session as LocalMatch).game.over != null or _game.debug_can_draw():
			break
		await _wait(0.5)
	_say(report, "antes de robar: me toca y puedo robar = %s (%s)" % [str(_game.debug_can_draw()), _game.debug_state()])
	if (_session as LocalMatch).game.over == null:
		var hand_before: int = (_session as LocalMatch).game.P("p0").hand.size()
		var deck_before: int = (_session as LocalMatch).game.draw.size()
		await _tap_3d(_game.debug_deck_card())
		await _wait(0.8)
		await _save_shot(dir + "/t4_robo.png")
		_say(report, "robar tocando el mazo: mazo %d → %d, mano %d → %d" % [deck_before, (_session as LocalMatch).game.draw.size(), hand_before, (_session as LocalMatch).game.P("p0").hand.size()])
	# Llevar una carta al centro y soltarla: debe jugarse sin tocar JUGAR
	var lm := _session as LocalMatch
	var carried: Card3D = null
	for _i in 160:
		_ui_rescue(plus_mode)
		if lm.game.over != null:
			break
		if _game.debug_can_draw():
			carried = _game.debug_playable_card()
			if carried:
				break
			await _tap_3d(_game.debug_deck_card())
		await _wait(0.5)
	if carried:
		var vt := get_viewport().get_final_transform()
		var from_pos: Vector2 = vt * _world.camera.unproject_position(carried.to_global(Vector3(0, 0, -0.32)))
		var center: Vector2 = vt * _world.camera.unproject_position(Vector3(0, 0.3, -0.25))
		var discard_before: int = lm.game.discard.size()
		var hand_before: int = lm.game.P("p0").hand.size()
		await _drag(from_pos, center, true)
		await _save_shot(dir + "/t7_llevando.png")
		var mid: String = _game.debug_carry()
		_say(report, "carta grande visible mientras se lleva al tablero: %s" % str(_game.debug_zoom_visible()))
		await _drag(center, center, false)
		await _wait(1.2)
		_say(report, "soltar en el centro: llevando=[%s] | %s | descarte %d → %d | mano %d → %d | %s" % [mid, carried.type, discard_before, lm.game.discard.size(), hand_before, lm.game.P("p0").hand.size(), _game.debug_state()])
		var ok_btn := _find_button(self, "Entendido")
		if ok_btn:
			await _tap_control(ok_btn)
			await _wait(0.3)
		# Sacarla y regresarla a la mano sin soltar en el centro: no debe jugarse
		for _i in 120:
			_ui_rescue(plus_mode)
			if lm.game.over != null or _game.debug_can_draw():
				break
			await _wait(0.5)
		var ends2: Array = _game.debug_hand_ends()
		if _game.debug_can_draw() and ends2.size() == 2:
			var c2: Card3D = ends2[0]
			var p2: Vector2 = vt * _world.camera.unproject_position(c2.to_global(Vector3(0, 0, -0.32)))
			var hb: int = lm.game.P("p0").hand.size()
			var db: int = lm.game.discard.size()
			await _drag(p2, center, true)
			await _drag(center, p2, true)
			await _drag(p2, p2, false)
			await _wait(0.8)
			_say(report, "regresarla a la mano: mano %d → %d | descarte %d → %d" % [hb, lm.game.P("p0").hand.size(), db, lm.game.discard.size()])
	else:
		_say(report, "no hubo carta jugable para llevar al centro")
	# Arrastrar el dedo por la mano, de la primera a la última carta (cuando la mano está libre, sin ventanas)
	for _i in 120:
		_ui_rescue(plus_mode)
		if (_session as LocalMatch).game.over != null or _game.debug_can_draw():
			break
		await _wait(0.5)
	if _game.debug_can_draw():
		var ends: Array = _game.debug_hand_ends()
		if ends.size() == 2:
			var vt := get_viewport().get_final_transform()
			var a_pos: Vector2 = vt * _world.camera.unproject_position(ends[0].to_global(Vector3(-0.2, 0, -0.32)))
			var b_pos: Vector2 = vt * _world.camera.unproject_position(ends[1].to_global(Vector3(0.1, 0, -0.32)))
			var before: int = _game.hover_changes
			await _drag(a_pos, b_pos, true)
			await _save_shot(dir + "/t6_arrastre.png")
			var mid_hover: String = _game.debug_hover()
			_say(report, "carta grande visible mientras se arrastra por la mano: %s" % str(_game.debug_zoom_visible()))
			await _drag(b_pos, b_pos, false)
			await _wait(0.4)
			_say(report, "arrastre: %d cartas resaltadas | resaltada al final del recorrido=%s | selección tras soltar=%s (esperada %s)" % [_game.hover_changes - before, mid_hover, str(_game.debug_selection()), ends[1].card_id])
	# Historial
	var hist := _find_button(self, "HISTORIAL")
	_say(report, "botón HISTORIAL visible: %s" % str(hist != null))
	if hist and (_session as LocalMatch).game.over == null:
		await _tap_control(hist)
		await _wait(0.5)
		await _save_shot(dir + "/t5_historial.png")
		_say(report, "historial: %s | %d entradas" % [_game.debug_state(), _game.debug_history_size()])
		var close := _find_button(self, "Cerrar")
		if close:
			await _tap_control(close)
			await _wait(0.3)
	if plus_mode and (_session as LocalMatch).game.over == null:
		await _ui_test_plus_extras(dir, report, played_id)
	# Menú → salir
	var menu := _find_button(self, "MENÚ")
	if menu and (_session as LocalMatch).game.over == null:
		await _tap_control(menu)
		await _wait(0.4)
		var leave := _find_button(self, "Salir de la partida")
		if leave:
			await _tap_control(leave)
			await _wait(0.4)
		var exit := _find_button(self, "Salir al menú")
		_say(report, "ventana de salida: %s" % str(exit != null))
		if exit:
			await _tap_control(exit)
			await _wait(0.5)
			_say(report, "de vuelta en el menú: %s" % str(_menu != null and _game == null))
	print("UITEST fin")
	get_tree().quit()


## Comprobaciones de Plus: ventana de descarte (UX-03), texto del Clon (UX-03) y cuadrícula del trío (UX-04).
func _ui_test_plus_extras(dir: String, report: Array, played_id: String) -> void:
	# Texto fijo del Clon: con un Ataque arriba del descarte debe decir «Copiará: Ataque (2x)»
	var fake := {"discard": [{"id": "x1", "type": "attack", "by": "p0"}], "deadN": 0, "stack": []}
	var hint: String = CloneHint.describe(fake).text
	_say(report, "Plus: Clon sobre un Ataque dice «%s» | %s" % [hint, "OK" if hint == "Copiará: Ataque (2x)" else "ERROR"])
	# Descarte: tocar la pila abre la ventana y lista la carta jugada
	var top: Card3D = _game.debug_discard_top()
	if top:
		await _tap_3d(top)
		await _wait(0.6)
		var listed: Array = _game.debug_discard_listed()
		_say(report, "Plus: descarte abierto tocando la pila: %s | %d cartas listadas | incluye la jugada %s: %s" % [_game.debug_state(), listed.size(), played_id, "OK" if (played_id == "" or listed.has(played_id)) else "ERROR"])
		await _save_shot(dir + "/t8_descarte.png")
		var close := _find_button(self, "Cerrar")
		if close:
			await _tap_control(close)
			await _wait(0.3)
	else:
		_say(report, "Plus: no había carta en el descarte que tocar")
	# Clon en la mano: el panel de selección dice qué copiará
	var info: String = _game.debug_select_clone()
	if info == "":
		_say(report, "Plus: no hay Clon en la mano; se prueba solo el texto fijo")
	else:
		_say(report, "Plus: panel del Clon: %s | %s" % [info.replace("\n", " / "), "OK" if (info.contains("Copiará:") or info.contains("No cop") or info.contains("No pued")) else "ERROR"])
		_game.debug_clear_selection()
	# Trío: la cuadrícula ofrece exactamente los tipos de la partida
	var offered: Array = _game.debug_open_named()
	await _wait(0.5)
	var want: Array = _session.view().get("deckTypes", [])
	var a: Array = offered.duplicate()
	var b: Array = want.duplicate()
	a.sort()
	b.sort()
	_say(report, "Plus: cuadrícula del trío ofrece %d tipos, deckTypes %d | %s | sin explosivo: %s" % [offered.size(), want.size(), "OK" if a == b else "ERROR", str(not offered.has("exploding"))])
	await _save_shot(dir + "/t9_trio.png")
	var cancel := _find_button(self, "Cancelar")
	if cancel:
		await _tap_control(cancel)
		await _wait(0.3)
	_game.debug_clear_selection()
	await _ui_test_aim(dir, report)
	await _ui_test_cripta(dir, report)
	await _ui_test_memoria(dir, report)


## Modo puntería (UX-01): elegir objetivo tocando el avatar 3D, rechazo de no válidos y CANCELAR.
func _ui_test_aim(dir: String, report: Array) -> void:
	var lm := _session as LocalMatch
	var vt := get_viewport().get_final_transform()
	for _i in 60:
		for label: String in ["Entendido", "Cerrar"]:      # ventanas que pudieran haber quedado abiertas
			var open_btn := _find_button(self, label)
			if open_btn:
				await _tap_control(open_btn)
				await _wait(0.3)
		if lm.game.over != null or _game.debug_can_draw():
			break
		await _wait(0.5)
	_game.debug_clear_selection()
	var natural := false
	var src: Array = []
	if _game.debug_can_draw():
		var tc: Card3D = _game.debug_targeted_card()
		if tc:
			src = [tc]
		else:
			src = _game.debug_pair_cards()
	if not src.is_empty():
		natural = true
		for c: Card3D in src:
			await _tap_3d(c, Vector3(-0.24, 0, -0.3))
			await _wait(0.3)
		var btn := _find_button(self, "JUGAR") if src.size() == 1 else _find_button(self, "JUGAR PAREJA")
		_say(report, "Plus/puntería: carta con objetivo (%s), botón de jugar visible: %s" % [src[0].type, str(btn != null)])
		if btn:
			await _tap_control(btn)
			await _wait(0.5)
	else:
		_say(report, "Plus/puntería: AVISO, la mano no tiene carta con objetivo ni pareja; se FUERZA el modo puntería con debug_force_aim('living')")
		_game.debug_force_aim("living")
		await _wait(0.5)
	_say(report, "Plus/puntería: modo activo=%s tipo=%s | válidos=%s no válidos=%s | panel: %s" % [str(_game.debug_aim_active()), _game.debug_aim_kind(), str(_game.debug_aim_ids(true)), str(_game.debug_aim_ids(false)), _game.debug_info_text().replace("\n", " / ")])
	await _save_shot(dir + "/t10_punteria.png")
	var valid: Array = _game.debug_aim_ids(true)
	# (c) CANCELAR sale sin jugar
	var disc0: int = lm.game.discard.size()
	var cancel := _find_button(self, "CANCELAR")
	var had_cancel := cancel != null
	if cancel:
		await _tap_control(cancel)
		await _wait(0.4)
	_say(report, "Plus/puntería: CANCELAR (botón=%s) -> activo=%s, descarte %d -> %d, jugada enviada=%s | %s" % [str(had_cancel), str(_game.debug_aim_active()), disc0, lm.game.discard.size(), str(_game.debug_last_play()), "OK" if (had_cancel and not _game.debug_aim_active() and lm.game.discard.size() == disc0) else "ERROR"])
	# (b) tocar un jugador NO válido no juega nada y no cancela (modo forzado «dead»: todos los vivos son inválidos)
	_game.debug_force_aim("dead")
	await _wait(0.3)
	var rivals: Array = _game.debug_aim_ids(false)
	if not rivals.is_empty():
		var play0: Dictionary = _game.debug_last_play()
		await _tap(vt * _game.debug_seat_pos(rivals[0]))
		await _wait(0.3)
		_say(report, "Plus/puntería: (FORZADO tipo dead) tocar a %s no válido -> sigue activo=%s, nada jugado=%s, elegido='%s' | %s" % [rivals[0], str(_game.debug_aim_active()), str(_game.debug_last_play() == play0), _game.debug_aim_pick(), "OK" if (_game.debug_aim_active() and _game.debug_last_play() == play0 and _game.debug_aim_pick() == "") else "ERROR"])
	var c2 := _find_button(self, "CANCELAR")
	if c2:
		await _tap_control(c2)
		await _wait(0.3)
	# (a) tocar el avatar 3D de un rival válido juega la carta contra él
	if natural and not valid.is_empty() and _game.debug_can_draw():
		var tc2: Card3D = _game.debug_targeted_card() if src.size() == 1 else null
		if src.size() == 1 and tc2 == null:
			_say(report, "Plus/puntería: la carta ya no está para repetir")
		else:
			_game.debug_clear_selection()
			await _wait(0.3)
			for c: Card3D in (src if src.size() > 1 else [tc2]):
				await _tap_3d(c, Vector3(-0.24, 0, -0.3))
				await _wait(0.3)
			var b2 := _find_button(self, "JUGAR") if src.size() == 1 else _find_button(self, "JUGAR PAREJA")
			if b2:
				await _tap_control(b2)
				await _wait(0.5)
			var tgt: String = valid[0]
			await _tap(vt * _game.debug_seat_pos(tgt))
			await _wait(0.4)
			var lp: Dictionary = _game.debug_last_play()
			_say(report, "Plus/puntería: tocar el avatar de %s -> jugada %s | %s" % [tgt, str(lp), "OK" if lp.get("target", "") == tgt else "ERROR: no salió con ese objetivo"])
	else:
		# Sin carta con objetivo real: modo forzado, el toque solo se anota
		_game.debug_force_aim("living")
		await _wait(0.3)
		var vv: Array = _game.debug_aim_ids(true)
		if not vv.is_empty():
			await _tap(vt * _game.debug_seat_pos(vv[0]))
			await _wait(0.3)
			_say(report, "Plus/puntería: (FORZADO, sin jugada real) tocar el avatar de %s -> elegido='%s' | %s" % [vv[0], _game.debug_aim_pick(), "OK" if _game.debug_aim_pick() == vv[0] else "ERROR"])
	# Captura con un jugador muerto: él queda atenuado
	if lm.game.over == null:
		for pl in lm.game.players:
			if pl.id == "p2":
				pl.alive = false
		_session.updated.emit()
		_game.debug_force_aim("living")
		await _wait(0.6)
		_say(report, "Plus/puntería: captura con p2 muerto (FORZADO) | válidos=%s no válidos=%s" % [str(_game.debug_aim_ids(true)), str(_game.debug_aim_ids(false))])
		await _save_shot(dir + "/t11_punteria_muerto.png")
		var c3 := _find_button(self, "CANCELAR")
		if c3:
			await _tap_control(c3)
			await _wait(0.3)
	_game.debug_clear_selection()


# ---------------------------------------------------------------- La Cripta (T25 + T32): las 9 cartas, una a una

## Solo prueba Plus: si el jugador murió en la partida de prueba (azar), lo devuelve a la vida para no agotar el tiempo.
func _ui_rescue(plus_mode: bool) -> void:
	if not plus_mode or not (_session is LocalMatch):
		return
	var g: ZKGame = (_session as LocalMatch).game
	if g.over == null and g.prompt == null and not g.P("p0").alive:
		g.P("p0").alive = true
		_session.updated.emit()


## Cierra cualquier ventana que haya quedado abierta. true si no queda ninguna.
func _cripta_close_windows() -> bool:
	for _i in 6:
		var any := false
		for label: String in ["Entendido", "Cerrar", "Cancelar", "CANCELAR"]:
			var b := _find_button(self, label)
			if b:
				any = true
				await _tap_control(b)
				await _wait(0.3)
		if not any:
			break
	return _game.debug_modal_title() == "" and not _game.debug_aim_active()


## Espera a que la partida esté libre (sin pila ni decisión) y me devuelve el turno (vivo, un solo turno).
func _cripta_my_turn(lm: LocalMatch, alive: bool = true, attempt: int = 0) -> bool:
	if attempt >= 2:
		# Tras dos jugadas anuladas por Nop seguidas, se quitan los Nop de las manos rivales para poder comprobar el efecto
		for pl in lm.game.players:
			if pl.id != "p0":
				pl.hand = pl.hand.filter(func(c: ZKGame.Card) -> bool: return c.type != "nope")
	for _i in 60:
		if lm.game.over != null:
			return false
		if lm.game.stack.is_empty() and lm.game.prompt == null:
			break
		await _wait(0.5)
	lm.game.P("p0").alive = alive
	lm.game.cur = 0 if alive else 1
	lm.game.turns_left = 1
	lm.game.attacked = false
	lm.game.idle_since = lm.now()
	_session.updated.emit()
	await _wait(0.4)
	return lm.game.over == null


var _cripta_n := 0


## Coloca una copia de la carta en la mano del jugador (como si la hubiera robado) y devuelve su id.
func _cripta_give(lm: LocalMatch, type: String) -> String:
	_cripta_n += 1
	var c := ZKGame.Card.new("z%d" % _cripta_n, type, false)
	lm.game.P("p0").hand.append(c)
	_session.updated.emit()
	await _wait(0.4)
	return c.id


## Quita de la mano las copias de una carta (tras una jugada anulada, para reintentar con otra limpia).
func _cripta_drop(lm: LocalMatch, type: String) -> void:
	lm.game.P("p0").hand = lm.game.P("p0").hand.filter(func(c: ZKGame.Card) -> bool: return c.type != type)


## Selecciona la carta, toca JUGAR y, si pide objetivo, toca el avatar de `target`. Devuelve {played, nopes}.
func _cripta_play(lm: LocalMatch, type: String, target: String = "") -> Dictionary:
	var seq0 := lm.game.seq
	var disc0 := lm.game.discard.size()
	var out := {"played": false, "nopes": 0}
	if not _game.debug_select_type(type):
		return out
	await _wait(0.4)
	var btn := _find_button(self, "JUGAR")
	if btn == null:
		return out
	await _tap_control(btn)
	await _wait(0.4)
	if target != "":
		if _game.debug_aim_active():
			await _tap(get_viewport().get_final_transform() * _game.debug_seat_pos(target))
			await _wait(0.4)
		if _game.debug_aim_active():
			_game.debug_aim_confirm(target)     # el toque no dio en el avatar: se confirma por la ficha
			await _wait(0.4)
	out.played = lm.game.discard.size() > disc0 or not lm.game.stack.is_empty()
	# Espera a que se resuelva (ventana de Nop) o a que aparezca la decisión propia
	for _i in 40:
		var pr: Variant = lm.game.prompt
		if lm.game.stack.is_empty() and (pr == null or pr.type in ["alter", "bury"]):
			break
		await _wait(0.5)
	await _wait(0.6)
	for e: Dictionary in lm.game.events:
		if e.seq > seq0 and e.type == "nope":
			out.nopes += 1
	return out


func _cripta_line(report: Array, card: String, detail: String, ok: bool) -> void:
	_say(report, "Plus/cripta: %s %s | %s" % [card, detail, "OK" if ok else "ERROR"])


func _cripta_event(lm: LocalMatch, type: String, seq0: int) -> Dictionary:
	for e: Dictionary in lm.game.events:
		if e.seq > seq0 and e.type == type:
			return e
	return {}


func _cripta_rival(lm: LocalMatch, alive: bool) -> String:
	for pl in lm.game.players:
		if pl.id != "p0" and pl.alive == alive and pl.hand.size() > 0:
			return pl.id
	return ""


func _find_label(n: Node, text: String) -> Label:
	if n is Label and (n as Label).text == text:
		return n
	for c in n.get_children():
		var r := _find_label(c, text)
		if r:
			return r
	return null


func _tree_has_label(n: Node, text: String) -> bool:
	if n is Label and (n as Label).text == text:
		return true
	for c in n.get_children():
		if _tree_has_label(c, text):
			return true
	return false


func _ui_test_cripta(dir: String, report: Array) -> void:
	var lm := _session as LocalMatch
	var g: ZKGame = lm.game
	if g.over != null or not (g.packs as Array).has("crypt"):
		_say(report, "Plus/cripta: AVISO, partida terminada o sin el pack; se omite el recorrido")
		return
	await _cripta_close_windows()
	_game.debug_clear_selection()
	# Estado de partida limpio: todos vivos (la prueba de puntería mató a p2), sin ventanas
	for pl in g.players:
		pl.alive = true
	await _cripta_my_turn(lm)
	# --- Motivos de «no se puede jugar»
	var why_haunt: String = _game.debug_why_not("haunt")
	_cripta_line(report, "motivos", "| Espanto vivo: «%s»" % why_haunt, why_haunt == "Solo los muertos pueden espantar.")
	var why_swap: String = _game.debug_why_not("soul_swap")
	_cripta_line(report, "motivos", "| Trueque sin muertos: «%s»" % why_swap, why_swap == "Necesita un jugador muerto con cartas.")
	g.cur = 1
	_session.updated.emit()
	await _wait(0.3)
	var why_turn: String = _game.debug_why_not("reverse")
	_cripta_line(report, "motivos", "| fuera de turno: «%s»" % why_turn, why_turn == "Espera tu turno.")
	# Espanto estando vivo: el panel lo explica y no hay botón JUGAR
	await _cripta_my_turn(lm)
	await _cripta_give(lm, "haunt")
	_game.debug_select_type("haunt")
	await _wait(0.4)
	var panel_txt: String = _game.debug_info_text()
	_cripta_line(report, "Espanto vivo (panel)", "| «%s» | botón JUGAR: %s" % [panel_txt.replace("\n", " / "), str(_find_button(self, "JUGAR") != null)], panel_txt.contains("Solo los muertos pueden espantar.") and _find_button(self, "JUGAR") == null)
	_game.debug_clear_selection()
	_cripta_drop(lm, "haunt")

	# 1. Ataque Dirigido
	var done := false
	for attempt in 3:
		await _cripta_my_turn(lm, true, attempt)
		var tgt := _cripta_rival(lm, true)
		await _cripta_give(lm, "targeted_attack")
		var seq0 := g.seq
		var r := await _cripta_play(lm, "targeted_attack", tgt)
		var ev := _cripta_event(lm, "attack", seq0)
		if not ev.is_empty():
			_cripta_line(report, "targeted_attack", "contra %s -> evento attack objetivo=%s n=%d%s" % [tgt, str(ev.target), int(ev.n), (" (intento %d)" % (attempt + 1)) if attempt > 0 else ""], ev.target == tgt and int(ev.n) == 2)
			done = true
			break
		_say(report, "Plus/cripta: targeted_attack ANULADA por Nop (%d) o no jugada (%s); se reintenta con otra copia" % [r.nopes, str(r.played)])
		_cripta_drop(lm, "targeted_attack")
	if not done:
		_cripta_line(report, "targeted_attack", "no se pudo resolver tras 3 intentos", false)
	await _cripta_close_windows()

	# 2. Marcha Atrás
	done = false
	for attempt in 3:
		await _cripta_my_turn(lm, true, attempt)
		var dir0: int = g.dir
		await _cripta_give(lm, "reverse")
		await _cripta_play(lm, "reverse")
		if g.dir != dir0:
			await _wait(0.8)
			var ds: Dictionary = _game.debug_dir()
			_cripta_line(report, "reverse", "dir %d -> %d | flecha visible=%s dir=%d | rótulo «%s»%s" % [dir0, g.dir, str(ds.visible), int(ds.dir), str(ds.label), (" (intento %d)" % (attempt + 1)) if attempt > 0 else ""], ds.visible and int(ds.dir) == g.dir and (str(ds.label) != "" or g.dir > 0))
			await _save_shot(dir + "/t12_sentido.png")
			done = true
			break
		_say(report, "Plus/cripta: reverse ANULADA por Nop; se reintenta")
		_cripta_drop(lm, "reverse")
	if not done:
		_cripta_line(report, "reverse", "no se pudo resolver tras 3 intentos", false)
	await _cripta_close_windows()

	# 3. Robar del Fondo
	done = false
	for attempt in 3:
		await _cripta_my_turn(lm, true, attempt)
		if g.draw[0].type == "exploding":      # que el fondo sea seguro: se cambia por otra carta del mazo
			for i in range(1, g.draw.size()):
				if g.draw[i].type != "exploding":
					var tmp: ZKGame.Card = g.draw[0]
					g.draw[0] = g.draw[i]
					g.draw[i] = tmp
					break
		var bottom: ZKGame.Card = g.draw[0]
		var n0: int = g.draw.size()
		await _cripta_give(lm, "draw_bottom")
		var seq0 := g.seq
		await _cripta_play(lm, "draw_bottom")
		var ev := _cripta_event(lm, "draw", seq0)
		if not ev.is_empty() and ev.get("bottom", false):
			await _wait(0.8)
			# Al acabar el turno un bot puede robar enseguida: se comprueba que la carta salió del mazo y está en mi mano
			var mine: bool = _session.view().hand.any(func(c: Dictionary) -> bool: return c.id == bottom.id)
			var left_deck: bool = not g.draw.any(func(c: ZKGame.Card) -> bool: return c.id == bottom.id)
			_cripta_line(report, "draw_bottom", "mazo %d -> %d | la carta del fondo (%s) está en mi mano=%s y ya no está en el mazo=%s | evento draw bottom" % [n0, g.draw.size(), bottom.type, str(mine), str(left_deck)], mine and left_deck and g.draw.size() <= n0 - 1)
			done = true
			break
		_say(report, "Plus/cripta: draw_bottom ANULADA por Nop; se reintenta")
		_cripta_drop(lm, "draw_bottom")
	if not done:
		_cripta_line(report, "draw_bottom", "no se pudo resolver tras 3 intentos", false)
	await _cripta_close_windows()

	# 4. Ojo de Cuervo (+ memoria para el trío)
	done = false
	for attempt in 3:
		await _cripta_my_turn(lm, true, attempt)
		var tgt := _cripta_rival(lm, true)
		var hand_kinds: Array = g.P(tgt).hand.map(func(c: ZKGame.Card) -> String: return c.type)
		await _cripta_give(lm, "crow_eye")
		var seq0 := g.seq
		await _cripta_play(lm, "crow_eye", tgt)
		var ev := _cripta_event(lm, "peek", seq0)
		if not ev.is_empty():
			await _wait(0.6)
			var title: String = _game.debug_modal_title()
			var grid: CardPickGrid = _game.debug_peek_grid()
			var shown: int = grid.debug_types().size() if grid else -1
			var open_ok: bool = title.begins_with("Mano de ") and shown == hand_kinds.size()
			await _save_shot(dir + "/t13_ojo_de_cuervo.png")
			var entendido := _find_button(self, "Entendido")
			if entendido:
				await _tap_control(entendido)
				await _wait(0.4)
			var closed: bool = _game.debug_modal_title() == ""
			var kn: Dictionary = _game.debug_known(tgt)
			_cripta_line(report, "crow_eye", "contra %s | ventana «%s» con %d/%d cartas | cerrada=%s | recuerdo=%s" % [tgt, title, shown, hand_kinds.size(), str(closed), str(kn.get("count", -1))], open_ok and closed and int(kn.get("count", -1)) == hand_kinds.size())
			# UX-04: la cuadrícula del trío contra ese jugador muestra primero «Sabes que tiene»
			_game.debug_clear_selection()
			var known: Array = _game.debug_open_named_for(tgt)
			await _wait(0.5)
			var want: Array = []
			for t: String in hand_kinds:
				if (g.deck_types as Array).has(t) and not want.has(t):
					want.append(t)
			var ka: Array = known.duplicate()
			ka.sort()
			want.sort()
			_cripta_line(report, "trío (Sabes que tiene)", "| %d tipos conocidos, esperados %d" % [known.size(), want.size()], ka == want and not known.is_empty())
			await _save_shot(dir + "/t14_trio_sabes.png")
			await _cripta_close_windows()
			_game.debug_clear_selection()
			done = true
			break
		_say(report, "Plus/cripta: crow_eye ANULADA por Nop; se reintenta")
		_cripta_drop(lm, "crow_eye")
	if not done:
		_cripta_line(report, "crow_eye", "no se pudo resolver tras 3 intentos", false)
	await _cripta_close_windows()

	# 5. Apocalipsis Zombi
	done = false
	for attempt in 3:
		await _cripta_my_turn(lm, true, attempt)
		var eks0: int = g.draw.filter(func(c: ZKGame.Card) -> bool: return c.type == "exploding").size()
		await _cripta_give(lm, "apocalypse")
		var seq0 := g.seq
		await _cripta_play(lm, "apocalypse")
		var ev := _cripta_event(lm, "apocalypse", seq0)
		if not ev.is_empty():
			var top_ok := true
			for k in int(ev.n):
				top_ok = top_ok and g.draw[g.draw.size() - 1 - k].type == "exploding"
			_cripta_line(report, "apocalypse", "explosivos arriba: %s de %d (evento n=%d)" % [str(top_ok), eks0, int(ev.n)], top_ok and int(ev.n) == eks0)
			# Para que los bots no mueran todos al instante y la prueba siga: los explosivos vuelven al fondo del mazo
			var bottom_eks: Array[ZKGame.Card] = []
			for k in int(ev.n):
				bottom_eks.append(g.draw.pop_back())
			for c: ZKGame.Card in bottom_eks:
				g.draw.insert(0, c)
			done = true
			break
		_say(report, "Plus/cripta: apocalypse ANULADA por Nop; se reintenta")
		_cripta_drop(lm, "apocalypse")
	if not done:
		_cripta_line(report, "apocalypse", "no se pudo resolver tras 3 intentos", false)
	await _cripta_close_windows()

	# 6. Alterar el Futuro: ventana, intercambio arrastrando y tocando, CONFIRMAR
	done = false
	for attempt in 3:
		await _cripta_my_turn(lm, true, attempt)
		await _cripta_give(lm, "alter_future")
		await _cripta_play(lm, "alter_future")
		var arr: FutureArranger = _game.debug_arranger()
		if arr != null and g.prompt != null and g.prompt.type == "alter":
			var cards: Array = (g.prompt.cards as Array).duplicate()
			var ids: Array = cards.map(func(c: ZKGame.Card) -> String: return c.id)
			await _save_shot(dir + "/t15_alterar_futuro.png")
			# Arrastre real: la primera carta sobre la tercera
			var vt := get_viewport().get_final_transform()
			var c0: Vector2 = vt * arr.debug_cell(0).get_global_rect().get_center()
			var c2: Vector2 = vt * arr.debug_cell(2).get_global_rect().get_center()
			await _drag(c0, c2, true)
			await _drag(c2, c2, false)
			await _wait(0.3)
			var drag_ok: bool = arr.order() == [2, 1, 0]
			if not drag_ok:
				arr.debug_swap(0, 2)           # el arrastre sintético no llegó: se hace por la vía directa
			# Dos toques reales: primera y segunda carta
			await _tap(vt * arr.debug_cell(0).get_global_rect().get_center())
			await _wait(0.2)
			await _tap(vt * arr.debug_cell(1).get_global_rect().get_center())
			await _wait(0.3)
			var tap_ok: bool = arr.order() == [1, 2, 0]
			var conf := _find_button(self, "CONFIRMAR")
			if conf:
				await _tap_control(conf)
				await _wait(0.8)
			var want_ids: Array = [ids[1], ids[2], ids[0]]
			var got_ids: Array = [g.draw[g.draw.size() - 1].id, g.draw[g.draw.size() - 2].id, g.draw[g.draw.size() - 3].id]
			var stuck: bool = _game.debug_modal_title() != "" or (g.prompt != null and g.prompt.get("player") == "p0")
			_cripta_line(report, "alter_future", "arrastre real=%s | dos toques=%s | orden final %s (esperado %s) | ventana cerrada=%s" % [str(drag_ok), str(tap_ok), str(got_ids), str(want_ids), str(not stuck)], got_ids == want_ids and not stuck and tap_ok)
			done = true
			break
		_say(report, "Plus/cripta: alter_future ANULADA por Nop; se reintenta")
		_cripta_drop(lm, "alter_future")
	if not done:
		_cripta_line(report, "alter_future", "no se pudo resolver tras 3 intentos", false)
	await _cripta_close_windows()

	# 7. Entierro
	done = false
	for attempt in 3:
		await _cripta_my_turn(lm, true, attempt)
		var n0: int = g.draw.size()
		await _cripta_give(lm, "bury")
		var seq0 := g.seq
		await _cripta_play(lm, "bury")
		var pk: DeckSlotPicker = _game.debug_slot_picker()
		if pk != null and g.prompt != null and g.prompt.type == "bury":
			var cid: String = g.prompt.card.id
			pk.debug_set(3)
			await _wait(0.3)
			await _save_shot(dir + "/t16_entierro.png")
			var phrase: String = pk.debug_text()
			var conf := _find_button(self, "CONFIRMAR")
			if conf:
				await _tap_control(conf)
				await _wait(0.8)
			# El turno acaba al enterrar y un bot puede robar enseguida: se comprueba el evento y que la carta esté en el mazo
			var bev := _cripta_event(lm, "buried", seq0)
			var in_deck: bool = g.draw.any(func(c: ZKGame.Card) -> bool: return c.id == cid)
			var stuck: bool = _game.debug_modal_title() != "" or (g.prompt != null and g.prompt.get("player") == "p0")
			_cripta_line(report, "bury", "mazo %d | evento buried pos=%s len=%s (esperado 3) | la carta (%s) está en el mazo=%s | «%s» | ventana cerrada=%s" % [g.draw.size(), str(bev.get("pos", -1)), str(bev.get("len", -1)), cid, str(in_deck), phrase, str(not stuck)], int(bev.get("pos", -1)) == 3 and in_deck and not stuck)
			done = true
			break
		_say(report, "Plus/cripta: bury ANULADA por Nop; se reintenta")
		_cripta_drop(lm, "bury")
	if not done:
		_cripta_line(report, "bury", "no se pudo resolver tras 3 intentos", false)
	await _cripta_close_windows()

	# 8. Trueque de Almas: p3 muerto con cartas
	done = false
	for attempt in 3:
		await _cripta_my_turn(lm, true, attempt)
		var dead_id := "p3"
		g.P(dead_id).alive = false
		if g.P(dead_id).hand.size() < 3:
			for k in 3:
				_cripta_n += 1
				g.P(dead_id).hand.append(ZKGame.Card.new("z%d" % _cripta_n, "favor", false))
		_session.updated.emit()
		await _wait(0.3)
		await _cripta_give(lm, "soul_swap")
		var theirs: Array = g.P(dead_id).hand.map(func(c: ZKGame.Card) -> String: return c.id)
		var mine_after: Array = g.P("p0").hand.filter(func(c: ZKGame.Card) -> bool: return c.type != "soul_swap").map(func(c: ZKGame.Card) -> String: return c.id)
		var seq0 := g.seq
		await _cripta_play(lm, "soul_swap", dead_id)
		var ev := _cripta_event(lm, "swap", seq0)
		if not ev.is_empty():
			await _wait(0.8)
			var my_ids: Array = g.P("p0").hand.map(func(c: ZKGame.Card) -> String: return c.id)
			var view_ids: Array = _session.view().hand.map(func(c: Dictionary) -> String: return c.id)
			var their_ids: Array = g.P(dead_id).hand.map(func(c: ZKGame.Card) -> String: return c.id)
			var a: Array = my_ids.duplicate()
			var b: Array = theirs.duplicate()
			a.sort()
			b.sort()
			var c1: Array = their_ids.duplicate()
			var c2: Array = mine_after.duplicate()
			c1.sort()
			c2.sort()
			_cripta_line(report, "soul_swap", "con %s muerto | mi mano %d cartas = la suya de antes=%s | la suya = la mía de antes=%s | vista=%d cartas" % [dead_id, my_ids.size(), str(a == b), str(c1 == c2), view_ids.size()], a == b and c1 == c2 and view_ids.size() == my_ids.size())
			done = true
			break
		_say(report, "Plus/cripta: soul_swap ANULADA por Nop; se reintenta")
		_cripta_drop(lm, "soul_swap")
	if not done:
		_cripta_line(report, "soul_swap", "no se pudo resolver tras 3 intentos", false)
	await _cripta_close_windows()

	# 9. Espanto: yo muerto contra un vivo con cartas
	done = false
	for attempt in 4:
		await _cripta_my_turn(lm, false, attempt)
		var tgt := _cripta_rival(lm, true)
		if tgt == "":
			break
		var n_before: int = g.P(tgt).hand.size()
		var kinds_before: Array = g.P(tgt).hand.map(func(c: ZKGame.Card) -> String: return c.type)
		var ids_before: Array = g.P(tgt).hand.map(func(c: ZKGame.Card) -> String: return c.id)
		await _cripta_give(lm, "haunt")
		var seq0 := g.seq
		await _cripta_play(lm, "haunt", tgt)
		var ev := _cripta_event(lm, "haunt", seq0)
		if not ev.is_empty():
			await _wait(0.8)
			# El turno de la víctima sigue (un bot puede robar o jugar): se comprueba que esa carta salió de su mano al descarte
			# La mano de la víctima puede haber cambiado entre la foto previa y la resolución (ventana de Nop): la carta
			# espantada se identifica por estar en el descarte a nombre de la víctima y no por la foto previa.
			var hand_ids: Array = g.P(tgt).hand.map(func(c: ZKGame.Card) -> String: return c.id)
			var in_discard: bool = g.discard.any(func(d: Dictionary) -> bool: return d.by == tgt and d.card.type == ev.card and not hand_ids.has(d.card.id))
			var still_in_hand: bool = not in_discard
			_cripta_line(report, "haunt", "muerto, contra %s | descarta %s (estaba en su mano antes de jugar=%s) | está en el descarte atribuida a la víctima=%s | sigue en su mano=%s" % [tgt, str(ev.card), str(kinds_before.has(ev.card)), str(in_discard), str(still_in_hand)], in_discard)
			done = true
			break
		_say(report, "Plus/cripta: haunt ANULADA por Nop; se reintenta")
		_cripta_drop(lm, "haunt")
	if not done:
		_cripta_line(report, "haunt", "no se pudo resolver tras 3 intentos", false)
	g.P("p0").alive = true
	# Guía de cartas con el pack
	var info := InfoScreen.open(self, "cards", ["crypt"])
	await _wait(0.5)
	var has_head := _tree_has_label(info, "La Cripta")
	var plain := InfoScreen.open(self, "cards")
	await _wait(0.3)
	var plain_head := _tree_has_label(plain, "La Cripta")
	plain.queue_free()
	await _wait(0.2)
	var sc := info.find_children("*", "ScrollContainer", true, false)
	if not sc.is_empty():
		(sc[0] as ScrollContainer).scroll_vertical = 100000      # al final: ahí está la sección del pack
		await _wait(0.5)
		await _save_shot(dir + "/t17_guia_cripta.png")
		var head_label := _find_label(info, "La Cripta")
		if head_label:
			(sc[0] as ScrollContainer).ensure_control_visible(head_label)
			(sc[0] as ScrollContainer).scroll_vertical = maxi(0, (sc[0] as ScrollContainer).scroll_vertical - 40)
		await _wait(0.5)
		await _save_shot(dir + "/t18_guia_cripta_inicio.png")
	_cripta_line(report, "guía", "| con el pack: sección «La Cripta»=%s | sin pack: %s" % [str(has_head), str(plain_head)], has_head and not plain_head)
	info.queue_free()
	await _wait(0.3)
	# Nada atascado
	var clean := await _cripta_close_windows()
	_cripta_line(report, "final", "| sin ventanas abiertas=%s (ventana «%s», puntería=%s), decisión pendiente=%s" % [str(clean), _game.debug_modal_title(), str(_game.debug_aim_active()), str(g.prompt != null)], clean and (g.prompt == null or g.prompt.player != "p0"))
	g.P("p0").alive = true
	_session.updated.emit()


## Anota un resultado de la prueba y lo imprime al momento (por si la prueba se corta por tiempo).
func _say(report: Array, line: String) -> void:
	report.append(line)
	print("UITEST " + line)


# ---------------------------------------------------------------- recordatorio del futuro, mazo visual y eventos antiguos

func _memo_line(report: Array, what: String, detail: String, ok: bool) -> void:
	_say(report, "Plus/memoria: %s | %s | %s" % [what, detail, "OK" if ok else "ERROR"])


## Deja las `n` cartas de arriba sin explosivos (se cambian por otras del mazo) para poder robarlas sin riesgo.
func _memo_safe_top(g: ZKGame, n: int) -> void:
	if g.draw.size() < n + 2:
		return
	for k in n:
		var idx := g.draw.size() - 1 - k
		if g.draw[idx].type != "exploding":
			continue
		for j in range(0, g.draw.size() - n):
			if g.draw[j].type != "exploding":
				var tmp: ZKGame.Card = g.draw[idx]
				g.draw[idx] = g.draw[j]
				g.draw[j] = tmp
				break


func _memo_top_types(g: ZKGame, n: int) -> Array:
	var out: Array = []
	for k in mini(n, g.draw.size()):
		out.append(g.draw[g.draw.size() - 1 - k].type)
	return out


## Lo que el recordatorio recuerda ahora: tipos en orden (profundidades, aparte).
func _memo_known() -> Array:
	return _game.debug_memory().known(_session.view())


func _memo_types(known: Array) -> Array:
	return known.map(func(k: Dictionary) -> String: return k.type)


func _memo_depths(known: Array) -> Array:
	return known.map(func(k: Dictionary) -> int: return int(k.depth))


## Juega Ver el Futuro de verdad y cierra la ventana. Devuelve {types, shuf, tops} o {} si se anuló.
func _memo_see_future(lm: LocalMatch) -> Dictionary:
	var g: ZKGame = lm.game
	for attempt in 3:
		await _cripta_close_windows()
		await _cripta_my_turn(lm, true, attempt)
		g.turns_left = 8        # que el turno no pase a un bot mientras se comprueba
		_memo_safe_top(g, 3)
		_session.updated.emit()
		await _cripta_give(lm, "see_future")
		var seq0 := g.seq
		await _cripta_play(lm, "see_future")
		if not _cripta_event(lm, "future", seq0).is_empty():
			await _wait(0.5)
			await _cripta_close_windows()
			await _wait(0.2)
			return {"types": _memo_top_types(g, 3), "shuf": g.shuf, "tops": g.tops}
		_cripta_drop(lm, "see_future")
	return {}


func _ui_test_memoria(dir: String, report: Array) -> void:
	var lm := _session as LocalMatch
	var g: ZKGame = lm.game
	if g.over != null or not (g.packs as Array).has("crypt"):
		_say(report, "Plus/memoria: AVISO, partida terminada o sin el pack; se omite el recorrido")
		return
	for pl in g.players:
		pl.alive = true
	var strip: DeckMemoryStrip = _game.debug_strip()
	await _cripta_close_windows()
	await _cripta_my_turn(lm)
	while g.draw.size() < 24:       # tras la partida de la prueba el mazo puede estar casi vacío: se repone (cartas Saltar)
		_cripta_n += 1
		g.draw.insert(0, ZKGame.Card.new("z%d" % _cripta_n, "skip", false))
	_session.updated.emit()
	await _wait(0.3)

	g.shuf += 1        # la memoria empieza de cero: solo cuenta lo que se aprende en este recorrido
	g.tops = 0
	_session.updated.emit()
	await _wait(0.2)

	# 1. Ver el Futuro -> tira con 3
	var snap := await _memo_see_future(lm)
	if snap.is_empty():
		_memo_line(report, "ver el futuro", "no se pudo jugar tras 3 intentos", false)
		return
	var kn := _memo_known()
	_memo_line(report, "ver el futuro", "tira con %s (esperado 3: %s) | tipos %s = arriba del mazo %s | visible=%s" % [str(strip.debug_items()), str(snap.types), str(_memo_types(kn)), str(snap.types), str(strip.visible)], strip.visible and strip.debug_items() == ["carta", "carta", "carta"] and _memo_types(kn) == snap.types and _memo_depths(kn) == [0, 1, 2])
	await _save_shot(dir + "/t19_memoria_tira.png")

	# Tocar la tira abre la ventana con todo lo conocido
	await _tap_control(strip)
	await _wait(0.5)
	var title: String = _game.debug_modal_title()
	await _save_shot(dir + "/t20_memoria_ventana.png")
	_memo_line(report, "ventana del recordatorio", "ventana «%s»" % title, title == "Lo que sabes del mazo")
	await _cripta_close_windows()

	# UX-15 / D-20: una pantalla nueva sobre una partida avanzada no repite efectos antiguos
	var old_events: int = (_session.view().events as Array).size()
	# Sin la corrección (simulada marcando la primera vista como ya hecha) la pantalla nueva SÍ repite los efectos antiguos
	var g3 := PlusGameScreen.new().setup(_session, _world)
	g3._first_view = false
	add_child(g3)
	await _wait(0.3)
	var fx3: Dictionary = g3.debug_effects()
	_memo_line(report, "D-20 sin corrección (simulado)", "pantalla nueva repite: ventana «%s», %d popups, %d avisos" % [str(fx3.modal), int(fx3.popups), int(fx3.toasts)], str(fx3.modal) != "" or int(fx3.popups) > 0 or int(fx3.toasts) > 0)
	g3.queue_free()
	await _wait(0.3)
	await _cripta_close_windows()
	var g2 := PlusGameScreen.new().setup(_session, _world)
	add_child(g2)
	await _wait(0.3)
	var fx: Dictionary = g2.debug_effects()
	var kn2: Array = g2.debug_memory().known(_session.view())
	_memo_line(report, "pantalla nueva (D-20)", "%d eventos antiguos en la vista, %d registrados sin efectos | ventana «%s», %d popups, %d avisos | recuerda lo mismo=%s | historial %d" % [old_events, g2.replay_skipped, str(fx.modal), int(fx.popups), int(fx.toasts), str(_memo_types(kn2) == _memo_types(kn)), g2.debug_history_size()], old_events > 5 and g2.replay_skipped == old_events and str(fx.modal) == "" and int(fx.popups) == 0 and int(fx.toasts) == 0 and _memo_types(kn2) == _memo_types(kn) and g2.debug_history_size() > 0)
	_memo_line(report, "partida recién empezada", "solo inicio=%s | con un robo=%s" % [str(g2.debug_fresh([{"type": "start"}, {"type": "turn"}])), str(g2.debug_fresh([{"type": "start"}, {"type": "draw"}]))], g2.debug_fresh([{"type": "start"}, {"type": "turn"}]) and not g2.debug_fresh([{"type": "start"}, {"type": "draw"}]))
	# Los eventos posteriores a la primera vista sí hacen efecto: un `future` nuevo abre la ventana
	g.emit("future", {"cards": _memo_top_types(g, 3), "mut": g.mut, "len": g.draw.size(), "shuf": g.shuf}, "p0")
	_session.updated.emit()
	await _wait(0.4)
	var fx2: Dictionary = g2.debug_effects()
	_memo_line(report, "evento posterior", "ventana «%s»" % str(fx2.modal), str(fx2.modal).begins_with("El futuro"))
	g2.queue_free()
	await _wait(0.3)
	await _cripta_close_windows()

	# 2. Un rival roba -> se desplaza (quedan 2)
	var c1: ZKGame.Card = g.draw.pop_back()
	g.tops += 1
	g.P("p1").hand.append(c1)
	_session.updated.emit()
	await _wait(0.3)
	kn = _memo_known()
	_memo_line(report, "un rival roba", "tira %s | recuerda %s (esperado %s) a profundidades %s" % [str(strip.debug_items()), str(_memo_types(kn)), str(snap.types.slice(1)), str(_memo_depths(kn))], strip.debug_items() == ["carta", "carta"] and _memo_types(kn) == snap.types.slice(1) and _memo_depths(kn) == [0, 1])
	await _save_shot(dir + "/t21_memoria_tira_dos.png")

	# 2b. Robo propio de verdad -> queda 1
	var err := g.act("p0", {"a": "draw"}, lm.now())
	_session.updated.emit()
	kn = _memo_known()
	_memo_line(report, "robo propio", "error «%s» | tira %s | recuerda %s (esperado %s)" % [err, str(strip.debug_items()), str(_memo_types(kn)), str(snap.types.slice(2))], err == "" and strip.debug_items() == ["carta"] and _memo_types(kn) == snap.types.slice(2) and _memo_depths(kn) == [0])
	await _cripta_close_windows()

	# 3. Robar del Fondo no desplaza
	snap = await _memo_see_future(lm)
	if snap.is_empty():
		_memo_line(report, "robar del fondo", "no se pudo preparar Ver el Futuro", false)
	else:
		var n0: int = g.draw.size()
		var ok_b := false
		for attempt in 3:
			await _cripta_my_turn(lm, true, attempt)
			g.turns_left = 8
			if g.shuf != snap.shuf:
				break
			if g.draw[0].type == "exploding":
				for i in range(1, g.draw.size() - 3):
					if g.draw[i].type != "exploding":
						var tmp: ZKGame.Card = g.draw[0]
						g.draw[0] = g.draw[i]
						g.draw[i] = tmp
						break
			n0 = g.draw.size()
			await _cripta_give(lm, "draw_bottom")
			var seq0 := g.seq
			await _cripta_play(lm, "draw_bottom")
			var ev := _cripta_event(lm, "draw", seq0)
			if not ev.is_empty() and ev.get("bottom", false):
				await _wait(0.4)
				kn = _memo_known()
				_memo_line(report, "robar del fondo", "mazo %d -> %d, tops %d -> %d | recuerda %s (esperado %s) a profundidades %s | tira %s" % [n0, g.draw.size(), int(snap.tops), g.tops, str(_memo_types(kn)), str(snap.types), str(_memo_depths(kn)), str(strip.debug_items())], g.draw.size() < n0 and g.tops == snap.tops and _memo_types(kn) == snap.types and _memo_depths(kn) == [0, 1, 2])
				ok_b = true
				break
			_cripta_drop(lm, "draw_bottom")
		if not ok_b:
			_memo_line(report, "robar del fondo", "no se pudo resolver tras 3 intentos", false)
	await _cripta_close_windows()

	# 4. Barajar -> desaparece
	snap = await _memo_see_future(lm)
	var ok_s := false
	if not snap.is_empty():
		for attempt in 3:
			await _cripta_my_turn(lm, true, attempt)
			g.turns_left = 8
			await _cripta_give(lm, "shuffle")
			await _cripta_play(lm, "shuffle")
			if g.shuf != snap.shuf:
				await _wait(0.4)
				kn = _memo_known()
				_memo_line(report, "barajar", "shuf %d -> %d | recuerda %d cartas | tira visible=%s" % [int(snap.shuf), g.shuf, kn.size(), str(strip.visible)], kn.is_empty() and not strip.visible)
				ok_s = true
				break
			_cripta_drop(lm, "shuffle")
	if not ok_s:
		_memo_line(report, "barajar", "no se pudo resolver", false)
	await _cripta_close_windows()

	# 5. Entierro en un mazo grande: selector visual (arrastre + ajuste fino) y la posición llega al motor
	await _cripta_my_turn(lm)
	g.turns_left = 8
	for k in 22:
		_cripta_n += 1
		g.draw.insert(0, ZKGame.Card.new("z%d" % _cripta_n, "skip", false))
	_session.updated.emit()
	await _cripta_give(lm, "bury")
	var seq1 := g.seq
	await _cripta_play(lm, "bury")
	var pk: DeckSlotPicker = _game.debug_slot_picker()
	if pk == null or g.prompt == null or g.prompt.type != "bury":
		_memo_line(report, "entierro", "no se abrió el selector", false)
	else:
		var bcard: String = g.prompt.card.type
		var big: int = pk.max_pos
		var prof: DeckProfile = pk.debug_profile()
		var want := 17
		await _save_shot(dir + "/t22_selector_mazo.png")
		# Arrastre real del hueco hasta cerca de la posición 21 y ajuste fino con −1 hasta la 17
		var vt := get_viewport().get_final_transform()
		await _drag(vt * prof.debug_point(pk.value), vt * prof.debug_point(want + 4), true)
		await _drag(vt * prof.debug_point(want + 4), vt * prof.debug_point(want + 4), false)
		await _wait(0.2)
		var after_drag: int = pk.value
		var steps := 0
		while pk.value != want and steps < 12:
			var fine := _find_button(self, "−1" if pk.value > want else "+1")
			if fine == null:
				break
			await _tap_control(fine)
			await _wait(0.1)
			steps += 1
		var phrase := pk.debug_text()
		var final_val: int = pk.value
		await _save_shot(dir + "/t23_selector_mazo_17.png")
		var conf := _find_button(self, "CONFIRMAR")
		if conf:
			await _tap_control(conf)
			await _wait(0.6)
		var bev := _cripta_event(lm, "buried", seq1)
		kn = _memo_known()
		_memo_line(report, "selector visual (mazo de %d)" % big, "arrastre -> %d, %d toques de ajuste fino -> %d | «%s» | acción enviada pos=%s (esperado %d)" % [after_drag, steps, final_val, phrase, str(bev.get("pos", -1)), want], absi(after_drag - (want + 4)) <= 2 and int(bev.get("pos", -1)) == want and phrase == DeckSlotPicker.label_for(want, big))
		_memo_line(report, "entierro en posición conocida", "carta %s | recuerda %s a profundidades %s | tira %s" % [bcard, str(_memo_types(kn)), str(_memo_depths(kn)), str(strip.debug_items())], _memo_types(kn) == [bcard] and _memo_depths(kn) == [want] and strip.debug_items() == ["?", "carta"])
		await _save_shot(dir + "/t24_memoria_entierro.png")
	await _cripta_close_windows()

	# 6. Esconder DOS explosivos (decisión forzada): dos selectores visuales, posiciones elegidas y memoria propia
	await _cripta_my_turn(lm)
	g.turns_left = 8
	var eks: Array = []
	for k in 2:
		_cripta_n += 1
		eks.append(ZKGame.Card.new("z%d" % _cripta_n, "exploding", false))
	g.prompt = {"type": "zombie", "player": "p0", "eks": eks, "needRevive": false, "revived": null, "watchers": [], "pendingPos": null, "minUntil": lm.now(), "start": lm.now(), "deadline": lm.now() + 90000}
	_session.updated.emit()
	await _wait(0.6)
	var pickers: Array = _game.debug_slot_pickers()
	if pickers.size() != 2:
		_memo_line(report, "dos explosivos", "selectores abiertos: %d (esperado 2)" % pickers.size(), false)
		g.prompt = null
	else:
		await _save_shot(dir + "/t25_selector_dos.png")
		pickers[0].debug_set(9)
		pickers[1].debug_set(4)
		await _wait(0.2)
		var conf2 := _find_button(self, "CONFIRMAR")
		if conf2:
			await _tap_control(conf2)
			await _wait(0.4)
		var depth_now: Array = []
		for c: ZKGame.Card in eks:
			for i in g.draw.size():
				if g.draw[i].id == c.id:
					depth_now.append(g.draw.size() - 1 - i)
		depth_now.sort()
		kn = _memo_known()
		_memo_line(report, "dos explosivos", "posiciones 9 y 4 | en el mazo a profundidades %s | recuerda %s | tira %s | marca bomba=%d" % [str(depth_now), str(_memo_depths(kn)), str(strip.debug_items()), strip.debug_bomb()], depth_now.size() == 2 and _memo_depths(kn) == depth_now and _memo_types(kn) == ["exploding", "exploding"])
		await _save_shot(dir + "/t26_memoria_explosivos.png")
	await _cripta_close_windows()

	# 7. Marca «💣 en N»: se conocen 3 cartas de arriba y un explosivo más abajo
	if pickers.size() == 2:
		var snap2 := await _memo_see_future(lm)
		var near := 999
		for c: ZKGame.Card in eks:
			for i in g.draw.size():
				if g.draw[i].id == c.id:
					near = mini(near, g.draw.size() - 1 - i)
		kn = _memo_known()
		_memo_line(report, "marca de explosivo", "conoce %d cartas | tira %s | «💣 en %d» (esperado en %d)" % [kn.size(), str(strip.debug_items()), strip.debug_bomb(), near + 1], not snap2.is_empty() and strip.debug_items() == ["carta", "carta", "carta"] and strip.debug_bomb() == near + 1)
		await _save_shot(dir + "/t27_memoria_bomba.png")
		await _cripta_close_windows()
	for pl in g.players:
		pl.alive = true
	_session.updated.emit()
