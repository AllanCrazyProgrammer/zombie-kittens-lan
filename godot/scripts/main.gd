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
		if _game.debug_can_draw():
			card = _game.debug_playable_card()
			if card:
				break
			await _tap_3d(_game.debug_deck_card())      # sin carta jugable: roba y sigue esperando
		await _wait(0.5)
		if (_session as LocalMatch).game.over != null:
			break
	if card:
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


## Anota un resultado de la prueba y lo imprime al momento (por si la prueba se corta por tiempo).
func _say(report: Array, line: String) -> void:
	report.append(line)
	print("UITEST " + line)
