extends Node3D
## Raíz de la aplicación: escenario 3D permanente + menú o partida encima.
##
## Argumentos de depuración (tras "--"):
##   --auto [rivales] [nivel]   arranca una partida en la que la IA también juega por el humano
##   --seed N                   semilla del reparto
##   --shots carpeta [cada_s]   guarda capturas periódicas (para revisar la interfaz sin tocar la pantalla)
##   --slow                     en modo --auto, el "humano" tarda 5 s en responder (deja ver las ventanas)
##   --quit-after s             cierra tras s segundos

var _world: TableWorld
var _menu: MenuScreen
var _game: GameScreen
var _session: LocalMatch
var _last_opts := {}
var _shots_dir := ""
var _shot_every := 3.0
var _shot_t := 0.0
var _shot_n := 0
var _quit_after := -1.0
var _elapsed := 0.0


func _ready() -> void:
	_world = TableWorld.new()
	add_child(_world)
	# Compila los shaders de partículas al arrancar (lejos de la vista) para que la primera explosión no dé un tirón
	Vfx.explosion(self, Vector3(0, -60, 0))
	get_viewport().size_changed.connect(_fit_view)
	_fit_view()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		_shots_dir = args[i + 1]
		if i + 2 < args.size() and args[i + 2].is_valid_float():
			_shot_every = float(args[i + 2])
	i = args.find("--quit-after")
	if i >= 0 and i + 1 < args.size():
		_quit_after = float(args[i + 1])
	i = args.find("--uitest")
	if i >= 0 and i + 1 < args.size():
		_show_menu()
		_ui_test(args[i + 1])
		return
	i = args.find("--auto")
	if i >= 0:
		var opts := {"autoplay": true, "rivals": 2, "level": "normal", "name": "Allan"}
		if i + 1 < args.size() and args[i + 1].is_valid_int():
			opts.rivals = int(args[i + 1])
		if i + 2 < args.size() and not args[i + 2].begins_with("--"):
			opts.level = args[i + 2]
		var s := args.find("--seed")
		if s >= 0 and s + 1 < args.size():
			opts.seed = int(args[s + 1])
		if args.has("--slow"):
			opts.me_delay = 5200
		_start_game(opts)
	else:
		_show_menu()


func _process(delta: float) -> void:
	_elapsed += delta
	if _shots_dir != "":
		_shot_t += delta
		if _shot_t >= _shot_every:
			_shot_t = 0.0
			_shot_n += 1
			_save_shot("%s/shot_%02d.png" % [_shots_dir, _shot_n])
			if _game:
				print("shot %02d: %s" % [_shot_n, _game.debug_state()])
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


func _show_menu() -> void:
	_end_game()
	_menu = MenuScreen.new()
	_menu.start_requested.connect(_start_game)
	add_child(_menu)


func _end_game() -> void:
	if _game:
		_game.queue_free()
		_game = null
	if _session:
		_session.queue_free()
		_session = null


func _start_game(opts: Dictionary) -> void:
	if _menu:
		_menu.queue_free()
		_menu = null
	_end_game()
	_last_opts = opts
	_session = LocalMatch.new()
	add_child(_session)
	_session.start(opts)
	_game = GameScreen.new().setup(_session, _world)
	_game.exit_requested.connect(_show_menu)
	_game.rematch_requested.connect(func() -> void: _start_game(_last_opts))
	add_child(_game)


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


func _tap_control(c: Control) -> void:
	await _tap(get_viewport().get_final_transform() * c.get_global_rect().get_center())


func _tap_3d(n: Node3D, local_offset: Vector3 = Vector3.ZERO) -> void:
	await _tap(get_viewport().get_final_transform() * _world.camera.unproject_position(n.to_global(local_offset)))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ui_test(dir: String) -> void:
	var report: Array = []
	await _wait(1.2)
	await _save_shot(dir + "/t1_menu.png")
	var b := _find_button(self, "4")
	if b:
		await _tap_control(b)
	await _wait(0.3)
	report.append("menú: rivales = %s" % str(_menu._opts.rivals))
	await _tap_control(_find_button(self, "¡JUGAR!"))
	await _wait(1.5)
	report.append("partida creada: %s" % str(_game != null))
	# Espera a que sea mi turno con una carta jugable sin objetivo (hasta 90 s)
	var card: Card3D = null
	for _i in 180:
		if _game.debug_can_draw():
			card = _game.debug_playable_card()
			if card:
				break
			await _tap_3d(_game.debug_deck_card())      # sin carta jugable: roba y sigue esperando
		await _wait(0.5)
		if _session.game.over != null:
			break
	if card:
		var before: int = _session.game.discard.size()
		await _wait(0.5)
		await _tap_3d(card, Vector3(-0.24, 0, -0.3))   # esquina superior izquierda: la parte que no tapa la carta vecina
		await _wait(0.6)
		await _save_shot(dir + "/t2_seleccion.png")
		report.append("carta seleccionada: %s (%s)" % [card.type, _game.debug_state()])
		var play := _find_button(self, "JUGAR")
		report.append("botón JUGAR visible: %s" % str(play != null))
		if play:
			await _tap_control(play)
		await _wait(0.4)
		await _save_shot(dir + "/t3_jugada.png")
		report.append("descarte %d → %d" % [before, _session.game.discard.size()])
		# Si la carta abre una ventana (p. ej. Ver el Futuro), se cierra con su botón
		await _wait(1.6)
		var ok := _find_button(self, "Entendido")
		if ok:
			await _save_shot(dir + "/t3b_ventana.png")
			report.append("ventana tras jugar: %s" % _game.debug_state())
			await _tap_control(ok)
			await _wait(0.4)
	else:
		report.append("no hubo carta jugable")
	# Robar tocando el mazo
	for _i in 120:
		if _session.game.over != null or _game.debug_can_draw():
			break
		await _wait(0.5)
	report.append("antes de robar: me toca y puedo robar = %s (%s)" % [str(_game.debug_can_draw()), _game.debug_state()])
	if _session.game.over == null:
		var hand_before: int = _session.game.P("p0").hand.size()
		var deck_before: int = _session.game.draw.size()
		await _tap_3d(_game.debug_deck_card())
		await _wait(0.8)
		await _save_shot(dir + "/t4_robo.png")
		report.append("robar tocando el mazo: mazo %d → %d, mano %d → %d" % [deck_before, _session.game.draw.size(), hand_before, _session.game.P("p0").hand.size()])
	# Menú → salir
	var menu := _find_button(self, "MENÚ")
	if menu and _session.game.over == null:
		await _tap_control(menu)
		await _wait(0.4)
		var exit := _find_button(self, "Salir al menú")
		report.append("ventana de salida: %s" % str(exit != null))
		if exit:
			await _tap_control(exit)
			await _wait(0.5)
			report.append("de vuelta en el menú: %s" % str(_menu != null and _game == null))
	for line: String in report:
		print("UITEST " + line)
	get_tree().quit()
