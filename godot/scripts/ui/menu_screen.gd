class_name MenuScreen
extends CanvasLayer
## Menús fuera de la partida: inicio y perfil, un jugador, unirse a una sala y sala de espera.

signal solo_requested(opts: Dictionary)
signal host_requested
signal join_requested(ip: String)
signal leave_requested
signal quality_changed(level: String)

const LEVELS := [["easy", "Fácil", "Juega casi al azar. Ideal para aprender."], ["normal", "Normal", "Esquiva cuando el riesgo sube."], ["hard", "Difícil", "Recuerda el mazo y te roba los Zombis."], ["mix", "Mixta", "Cada rival con una dificultad distinta."]]
const LEVEL_NAMES := {"easy": "Fácil", "normal": "Normal", "hard": "Difícil"}
const SETTINGS := "user://settings.cfg"

var page := "home"
var status := ""
var session: ClientSession      # solo en la sala de espera
var profile := {"name": "", "avatar": 0}
var _opts := {"rivals": 2, "level": "normal", "deck_mode": "official"}
var _box: VBoxContainer
var _rooms_box: VBoxContainer
var _rooms_sig := ""
var _manual_ip := ""


func _ready() -> void:
	layer = 3
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		for k: String in _opts.keys():
			_opts[k] = cfg.get_value("solo", k, _opts[k])
		for k: String in profile.keys():
			profile[k] = cfg.get_value("profile", k, profile[k])
	if str(profile.name).strip_edges() == "":
		profile.name = "Gatito%d" % (10 + randi() % 90)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var title := UIKit.label("ZOMBIE KITTENS", 132, UIKit.C.toxic, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 110
	root.add_child(title)
	var tag := UIKit.label("Explota. Revive. Vuelve a explotar.", 44, Color("ff5c8d"), true)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tag.offset_top = 270
	root.add_child(tag)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	margin.add_theme_constant_override("margin_bottom", 70)
	root.add_child(margin)
	var panel := UIKit.panel(Color(0.17, 0.11, 0.36, 0.93), UIKit.C.line, Vector2(30, 26))
	margin.add_child(panel)
	_box = UIKit.vbox(14)
	panel.add_child(_box)
	_build()


func _process(_delta: float) -> void:
	# La lista de salas se refresca sola, sin reconstruir el resto (para no perder lo que se está escribiendo)
	if page == "join" and _rooms_box != null:
		var sig := JSON.stringify(Net.rooms.keys()) + str(Net.rooms.values().map(func(r: Dictionary) -> String: return "%s%s%s" % [r.get("name"), r.get("players"), r.get("started")]))
		if sig != _rooms_sig:
			_rooms_sig = sig
			_fill_rooms()


func show_page(p: String, text: String = "") -> void:
	page = p
	status = text
	# Solo se escucha la red mientras se está en la pantalla de unirse
	if p == "join":
		if not Net.is_listening() and not Net.start_listening():
			status = "No se puede buscar salas ahora; escribe la dirección del anfitrión."
	else:
		Net.stop_listening()
	if is_inside_tree():
		_build()


func set_session(s: ClientSession) -> void:
	session = s
	s.lobby_updated.connect(_on_lobby_updated)


func _on_lobby_updated() -> void:
	if page == "lobby":
		_build()


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	for k: String in _opts.keys():
		cfg.set_value("solo", k, _opts[k])
	for k: String in profile.keys():
		cfg.set_value("profile", k, profile[k])
	cfg.save(SETTINGS)


func _add(text: String, kind: String, fn: Callable, size: int = 46, parent: Node = null) -> Button:
	var b := UIKit.button(text, kind, size)
	b.pressed.connect(fn)
	(parent if parent else _box).add_child(b)
	return b


func _note(text: String, size: int = 30, color: Color = UIKit.C.dim) -> void:
	var l := UIKit.label(text, size, color, false, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(l)


func _build() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_rooms_box = null
	match page:
		"home": _build_home()
		"settings": _build_settings()
		"solo": _build_solo()
		"join": _build_join()
		"connecting": _build_connecting()
		"lobby": _build_lobby()


func _go(p: String) -> void:
	save_profile()
	show_page(p)


func _build_home() -> void:
	var row := UIKit.hbox(18)
	_box.add_child(row)
	var av := Button.new()
	av.focus_mode = Control.FOCUS_NONE
	av.flat = true
	av.custom_minimum_size = Vector2(130, 170)
	av.add_child(UIKit.avatar_icon(int(profile.avatar), Vector2(130, 170)))
	av.pressed.connect(_next_avatar)
	row.add_child(av)
	var col := UIKit.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIKit.label("Tu nombre  (toca al gato para cambiarlo)", 26, UIKit.C.dim))
	var name_edit := UIKit.line_edit(str(profile.name), "Gatito")
	name_edit.max_length = 14
	name_edit.text_changed.connect(func(t: String) -> void: profile.name = t)
	col.add_child(name_edit)
	row.add_child(col)
	if status != "":
		_note(status, 32, UIKit.C.gold)
	_add("UN JUGADOR", "primary", _go.bind("solo"), 58)
	_add("CREAR SALA", "normal", _on_host, 50)
	_add("UNIRSE A UNA SALA", "normal", _go.bind("join"), 50)
	_note("Para jugar con otros, todos deben estar en la misma red Wi-Fi (o en la zona Wi-Fi de un teléfono).", 26)
	var learn := UIKit.hbox(12)
	_box.add_child(learn)
	_add("Tutorial", "normal", _on_tutorial, 38, learn)
	_add("Cómo jugar", "normal", _open_info.bind("rules"), 38, learn)
	_add("Cartas", "normal", _open_info.bind("cards"), 38, learn)
	_add("Ajustes", "normal", _go.bind("settings"), 38)
	_note("Godot · v%s" % ProjectSettings.get_setting("application/config/version"), 24)


func _audio_row() -> void:
	var audio := UIKit.hbox(12)
	_box.add_child(audio)
	_add("Sonido: sí" if Sfx.sfx_on else "Sonido: no", "normal", _toggle_sfx, 34, audio)
	_add("Música: sí" if Sfx.music_on else "Música: no", "normal", _toggle_music, 34, audio)


func _open_info(kind: String) -> void:
	InfoScreen.open(self, kind)


## Partida guiada: un rival fácil y consejos en pantalla.
func _on_tutorial() -> void:
	save_profile()
	solo_requested.emit({"rivals": 1, "level": "easy", "deck_mode": "official", "name": profile.name, "avatar": profile.avatar, "tutorial": true})


func _quality() -> String:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return cfg.get_value("video", "quality", "high")


func _next_quality() -> void:
	var order := ["high", "medium", "low"]
	var next: String = order[(order.find(_quality()) + 1) % 3]
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("video", "quality", next)
	cfg.save(SETTINGS)
	quality_changed.emit(next)
	_build()


func _build_settings() -> void:
	_box.add_child(UIKit.label("Ajustes", 52, UIKit.C.toxic, true))
	_audio_row()
	var q := _quality()
	_add("Gráficos: " + {"high": "calidad alta", "medium": "calidad media", "low": "calidad baja"}[q], "normal", _next_quality, 40)
	_note({"high": "Todos los efectos: sombras, brillo y suavizado de bordes.", "medium": "Menos sombras y sin suavizado. Buen equilibrio si el juego va lento.", "low": "Sin sombras ni brillo y menor resolución. Para teléfonos modestos o para ahorrar batería."}[q], 28)
	_add("Volver", "ghost", _go.bind("home"), 38)


func _on_host() -> void:
	save_profile()
	host_requested.emit()


func _toggle_sfx() -> void:
	Sfx.set_sfx(not Sfx.sfx_on)
	_build()


func _toggle_music() -> void:
	Sfx.set_music(not Sfx.music_on)
	_build()


func _on_solo_play() -> void:
	var o := _opts.duplicate()
	o["name"] = profile.name
	o["avatar"] = profile.avatar
	save_profile()
	solo_requested.emit(o)


func _on_connect() -> void:
	var ip := _manual_ip.strip_edges()
	if ip.is_valid_ip_address():
		join_requested.emit(ip)
	else:
		show_page("join", "Escribe la dirección completa, por ejemplo 192.168.1.20")


func _next_avatar() -> void:
	profile.avatar = (int(profile.avatar) + 1) % 6
	Sfx.play("tap")
	_go("home")


func _choose(key: String, value: Variant) -> void:
	_opts[key] = value
	save_profile()
	_build()


func _build_solo() -> void:
	_box.add_child(UIKit.label("Rivales controlados por la IA", 40, UIKit.C.toxic, true))
	var row := UIKit.hbox(12)
	_box.add_child(row)
	for n in [1, 2, 3, 4]:
		_add(str(n), "on" if _opts.rivals == n else "normal", _choose.bind("rivals", n), 56, row)
	_box.add_child(UIKit.label("Dificultad", 40, UIKit.C.toxic, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_box.add_child(grid)
	var hint := ""
	for lv: Array in LEVELS:
		_add(lv[1], "on" if _opts.level == lv[0] else "normal", _choose.bind("level", lv[0]), 44, grid)
		if _opts.level == lv[0]:
			hint = lv[2]
	_note(hint)
	var full: bool = _opts.deck_mode == "full"
	_add("Mazo: completo" if full else "Mazo: oficial", "normal", _choose.bind("deck_mode", "official" if full else "full"), 38)
	_note(_deck_info(int(_opts.rivals) + 1, full), 28)
	_add("¡JUGAR!", "primary", _on_solo_play, 68)
	_add("Volver", "ghost", _go.bind("home"), 38)


static func _deck_info(players: int, full: bool) -> String:
	if full:
		return "Todas las cartas (57) y %d explosivos." % (players - 1)
	if players <= 2:
		return "Oficial para 2: las 24 cartas con huella y 1 explosivo."
	if players == 3:
		return "Oficial para 3: las 33 cartas sin huella y 2 explosivos."
	return "Oficial: todas las cartas y %d explosivos." % (players - 1)


func _build_join() -> void:
	_box.add_child(UIKit.label("Salas en tu red", 44, UIKit.C.toxic, true))
	_rooms_box = UIKit.vbox(10)
	_box.add_child(_rooms_box)
	_rooms_sig = ""
	_fill_rooms()
	_box.add_child(UIKit.label("O escribe la dirección del anfitrión", 36, UIKit.C.toxic, true))
	var row := UIKit.hbox(12)
	_box.add_child(row)
	var ips: Array = Net.local_ips()
	if _manual_ip == "" and ips.size() > 0:
		var parts: PackedStringArray = str(ips[0]).split(".")
		_manual_ip = "%s.%s.%s." % [parts[0], parts[1], parts[2]]
	var ip_edit := UIKit.line_edit(_manual_ip, "192.168.1.20")
	ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	ip_edit.text_changed.connect(func(t: String) -> void: _manual_ip = t)
	row.add_child(ip_edit)
	var go := _add("Conectar", "primary", _on_connect, 42, row)
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	if status != "":
		_note(status, 32, UIKit.C.gold)
	_note("¿No aparece? Comprueben que están en la misma Wi-Fi y que el anfitrión ya creó la sala. Algunas redes públicas bloquean la conexión entre dispositivos: usen la zona Wi-Fi de un teléfono.", 26)
	_add("Volver", "ghost", func() -> void: leave_requested.emit(), 38)


func _fill_rooms() -> void:
	for c in _rooms_box.get_children():
		_rooms_box.remove_child(c)
		c.queue_free()
	if Net.rooms.is_empty():
		var l := UIKit.label("Buscando salas en la red Wi-Fi…", 32, UIKit.C.dim)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rooms_box.add_child(l)
		return
	for key: String in Net.rooms:
		var r: Dictionary = Net.rooms[key]
		var ip: String = r.ip
		var started: bool = r.get("started", false)
		var b := UIKit.button("Sala de %s  ·  %d/5%s" % [r.get("name", "?"), int(r.get("players", 0)), "  (en partida)" if started else ""], "on" if not started else "normal", 42)
		b.pressed.connect(func() -> void: join_requested.emit(ip))
		_rooms_box.add_child(b)


func _build_connecting() -> void:
	_box.add_child(UIKit.label("Conectando…", 52, UIKit.C.toxic, true))
	_note(status if status != "" else "Buscando al anfitrión.", 32)
	_add("Cancelar", "ghost", func() -> void: leave_requested.emit(), 40)


func _build_lobby() -> void:
	if session == null or session.lobby.is_empty():
		_box.add_child(UIKit.label("Entrando a la sala…", 48, UIKit.C.toxic, true))
		_add("Salir", "ghost", func() -> void: leave_requested.emit(), 40)
		return
	var lobby: Dictionary = session.lobby
	var players: Array = lobby.players
	var n := players.size()
	var is_host := session.is_host()
	var host_name := ""
	for p: Dictionary in players:
		if p.host:
			host_name = p.name
	_box.add_child(UIKit.label("Sala de %s   %d/5" % [host_name, n], 50, UIKit.C.toxic, true))
	if is_host:
		var ips: Array = Net.local_ips()
		_note(("Los demás tocan «Unirse a una sala». Si no aparece, tu dirección es  %s" % ips[0]) if ips.size() > 0 else "Sin red local: conéctate a una Wi-Fi o activa tu zona Wi-Fi para que otros se unan.", 28, UIKit.C.ink)
	for p: Dictionary in players:
		var row := UIKit.panel(UIKit.C.panel2, UIKit.C.line, Vector2(14, 6))
		var h := UIKit.hbox(12)
		row.add_child(h)
		h.add_child(UIKit.avatar_icon(int(p.avatar), Vector2(70, 92)))
		var name_l := UIKit.label(p.name, 42, UIKit.C.ink, true)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		h.add_child(name_l)
		if p.host:
			h.add_child(UIKit.label("Anfitrión", 28, UIKit.C.gold))
		if p.id == session.me_id:
			h.add_child(UIKit.label("Tú", 28, UIKit.C.toxic))
		if p.bot:
			if is_host:
				var pid: String = p.id
				var lb := _add("IA: %s" % LEVEL_NAMES.get(p.level, "?"), "normal", func() -> void: session.send({"t": "botLevel", "id": pid}), 28, h)
				lb.size_flags_horizontal = Control.SIZE_SHRINK_END
			else:
				h.add_child(UIKit.label("IA: %s" % LEVEL_NAMES.get(p.level, "?"), 28, UIKit.C.dim))
		if is_host and not p.host:
			var kid: String = p.id
			var kb := _add("X", "danger", func() -> void: session.send({"t": "kick", "id": kid}), 28, h)
			kb.size_flags_horizontal = Control.SIZE_SHRINK_END
		_box.add_child(row)
	var full: bool = lobby.settings.deck_mode == "full"
	if is_host:
		var tools := UIKit.hbox(12)
		_box.add_child(tools)
		var ab := _add("Añadir IA", "normal", func() -> void: session.send({"t": "addBot"}), 38, tools)
		ab.disabled = n >= 5
		_add("Mazo: completo" if full else "Mazo: oficial", "normal", func() -> void: session.send({"t": "settings", "deck_mode": "official" if full else "full"}), 38, tools)
	_note(_deck_info(maxi(2, n), full), 28)
	if status != "":
		_note(status, 32, UIKit.C.gold)
	if is_host:
		var start := _add("¡EMPEZAR PARTIDA!" if n >= 2 else "Faltan jugadores", "primary", func() -> void: session.send({"t": "start"}), 60)
		start.disabled = n < 2
	else:
		_note("Esperando a que el anfitrión empiece…", 34, UIKit.C.ink)
	_add("Cerrar la sala" if is_host else "Salir de la sala", "ghost", func() -> void: leave_requested.emit(), 38)
