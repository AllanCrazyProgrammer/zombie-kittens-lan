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
var plus := false               # modo elegido en la pantalla de inicio (user://settings.cfg, [game] plus)
var _plus_ephemeral := false    # el modo viene de una prueba automática: no se guarda en el archivo
var _title: Label
var _tag: Label
var _opts := {"rivals": 2, "level": "normal", "deck_mode": "official", "packs": ["crypt"]}
## Reglas de Plus de «Un jugador» (user://settings.cfg, [plus]). hand 0 = normal (el motor decide: 7, u 8 con La Cripta).
var _rules := {"turn_ms": 0, "hand": 0, "sudden_death": false, "nope_fixed": false, "rotten": false}
var _rule_touched := ""   # última regla cambiada: enseña su nota aunque haya quedado desactivada
var _box: VBoxContainer
var _panel: PanelContainer
var _scroll: ScrollContainer    # solo existe cuando el contenido no cabe (p. ej. reglas de Plus en pantallas pequeñas)
var _fit_gen := 0
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
		plus = bool(cfg.get_value("game", "plus", false))
		_rules = _clean_solo_rules({
			"turn_ms": cfg.get_value("plus", "turn_ms", 0), "hand": cfg.get_value("plus", "hand", 0),
			"sudden_death": cfg.get_value("plus", "sudden_death", false), "nope_fixed": cfg.get_value("plus", "nope_fixed", false),
				"rotten": cfg.get_value("plus", "rotten", false)})
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
	_title = title
	_refresh_title()
	var tag := UIKit.label("Explota. Revive. Vuelve a explotar.", 44, Color("ff5c8d"), true)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tag.offset_top = 270
	root.add_child(tag)
	_tag = tag

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
	_panel = panel
	Updater.changed.connect(_on_update_state)
	_build()


func _process(_delta: float) -> void:
	# La lista de salas se refresca sola, sin reconstruir el resto (para no perder lo que se está escribiendo)
	if page == "join" and _rooms_box != null:
		var sig := JSON.stringify(Net.rooms.keys()) + str(Net.rooms.values().map(func(r: Dictionary) -> String: return "%s%s%s%s" % [r.get("name"), r.get("players"), r.get("started"), r.get("plus")]))
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


## En Plus el título dice «Zombie Kittens Plus» (más pequeño para que quepa en una línea).
func _refresh_title() -> void:
	if _title == null:
		return
	_title.text = "ZOMBIE KITTENS PLUS" if plus else "ZOMBIE KITTENS"
	_title.add_theme_font_size_override("font_size", 96 if plus else 132)


## Cambia el modo. `persist = false` solo para pruebas automáticas (no toca user://settings.cfg).
func set_plus(value: bool, persist: bool = true) -> void:
	plus = value
	_plus_ephemeral = not persist
	if persist:
		save_profile()
	_refresh_title()
	if is_inside_tree() and page == "home":
		_build()


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	if not _plus_ephemeral:
		cfg.set_value("game", "plus", plus)
	for k: String in _opts.keys():
		cfg.set_value("solo", k, _opts[k])
	for k: String in profile.keys():
		cfg.set_value("profile", k, profile[k])
	for k: String in _rules.keys():
		cfg.set_value("plus", k, _rules[k])
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
	_fit_gen += 1
	if _title != null:
		_title.visible = true
		_tag.visible = true
	if plus and (page == "solo" or page == "lobby"):
		_fit(_fit_gen)
	elif _scroll != null:
		_unscroll()


## Si el contenido no cabe bajo el título, lo mete en un ScrollContainer. En pantallas que caben no se toca nada.
func _fit(gen: int) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if gen != _fit_gen or not is_inside_tree():
		return
	var avail := get_viewport().get_visible_rect().size.y - 70.0 - 350.0 - 52.0
	var need := _box.get_combined_minimum_size().y
	# Si el panel sube hasta el título, se oculta el título (así no se transparenta detrás de la sala)
	if _title != null and _panel.get_global_rect().position.y < 345.0:
		_title.visible = false
		_tag.visible = false
	if need <= avail:
		if _scroll != null:
			_unscroll()
		return
	if _scroll == null:
		_scroll = ScrollContainer.new()
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_panel.remove_child(_box)
		_panel.add_child(_scroll)
		_scroll.add_child(_box)
		_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size.y = avail


func _unscroll() -> void:
	_scroll.remove_child(_box)
	_panel.remove_child(_scroll)
	_scroll.queue_free()
	_scroll = null
	_panel.add_child(_box)


func _go(p: String) -> void:
	save_profile()
	show_page(p)


## Aviso arriba del menú cuando hay una versión nueva publicada.
func _update_banner() -> void:
	if Updater.state != "available":
		return
	var panel := UIKit.panel(Color("23401a"), UIKit.C.toxic, Vector2(22, 14))
	var row := UIKit.hbox(14)
	panel.add_child(row)
	var txt := UIKit.label("¡Hay una versión nueva! (%s)" % Updater.latest.version, 34, Color("ecffd0"), false, true)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(txt)
	var b := _add("DESCARGAR", "primary", Updater.open_download, 34, row)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	_box.add_child(panel)


func _on_update_state() -> void:
	if page == "home" or page == "settings":
		_build()


func _build_home() -> void:
	_update_banner()
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
	var mode := UIKit.hbox(12)
	_box.add_child(mode)
	for m: Array in [["CLÁSICO", false], ["PLUS", true]]:
		var mb := _add(m[0], "on" if plus == m[1] else "normal", set_plus.bind(m[1]), 38, mode)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_note("Versión %s" % Updater.installed_version(), 24)


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
	var info: String = {
		"idle": "", "checking": "Buscando actualizaciones…",
		"latest": "Tienes la versión más reciente (%s)." % Updater.installed_version(),
		"available": "Hay una versión nueva: %s" % Updater.latest.get("version", ""),
		"error": "No se pudo revisar si hay actualizaciones. ¿Tienes internet?",
	}[Updater.state]
	if Updater.state == "available":
		_add("DESCARGAR VERSIÓN %s" % Updater.latest.version, "primary", Updater.open_download, 40)
	else:
		var chk := _add("Buscar actualizaciones", "normal", Updater.check, 38)
		chk.disabled = Updater.state == "checking"
	if info != "":
		_note(info, 28, UIKit.C.toxic if Updater.state == "available" else UIKit.C.dim)
	_note("Versión instalada: %s" % Updater.installed_version(), 24)
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
	o["plus"] = plus
	o["packs"] = (_opts.packs as Array).duplicate() if plus else []
	o["rules"] = _solo_rules_for_engine() if plus else {}
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
	if plus:
		var crypt: bool = "crypt" in _opts.packs
		_add("La Cripta: sí" if crypt else "La Cripta: no", "normal", _choose.bind("packs", [] if crypt else ["crypt"]), 38)
		_note("Añade 9 cartas nuevas: Ataque Dirigido, Marcha Atrás, Robar del Fondo, Ojo de Cuervo y más." if crypt else "Solo las cartas originales, con las mejoras de Plus.", 28)
		_rules_block(_rules, _set_solo_rule, false, crypt, int(_opts.rivals) + 1)
	_add("¡JUGAR!", "primary", _on_solo_play, 68)
	_add("Volver", "ghost", _go.bind("home"), 38)


## Normaliza las reglas guardadas: mismos límites que el motor (turn_ms 0 o 5000-600000, hand 4-8; 0 = normal).
static func _clean_solo_rules(raw: Dictionary) -> Dictionary:
	var out := {"turn_ms": 0, "hand": 0, "sudden_death": false, "nope_fixed": false, "rotten": false}
	var t: Variant = raw.get("turn_ms")
	if t is int or t is float:
		out.turn_ms = 0 if int(t) <= 0 else clampi(int(t), 5000, 600000)
	var h: Variant = raw.get("hand")
	if h is int or h is float:
		out.hand = 0 if int(h) <= 0 else clampi(int(h), 4, 8)
	for k: String in ["sudden_death", "nope_fixed", "rotten"]:
		if raw.get(k) is bool:
			out[k] = raw[k]
	return out


## Reglas tal como las recibe el motor: `hand` solo si se ha elegido una.
func _solo_rules_for_engine() -> Dictionary:
	var r := _rules.duplicate()
	if int(r.hand) <= 0:
		r.erase("hand")
	return r


func _set_solo_rule(key: String, value: Variant) -> void:
	_rules[key] = value
	_rule_touched = key
	save_profile()
	_build()


func _send_rule(key: String, value: Variant) -> void:
	_rule_touched = key
	session.send({"t": "settings", "rules": {key: value}})


static func _turn_label(ms: int) -> String:
	return "sin límite" if ms <= 0 else "%d s" % roundi(ms / 1000.0)


## Siguiente valor de «Tiempo por turno»: sin límite, 30 s, 60 s y vuelta a sin límite.
static func _next_turn_ms(ms: int) -> int:
	return 30000 if ms <= 0 else (60000 if ms < 60000 else 0)


## Resumen de solo lectura de las reglas activas, p. ej. «Reglas: 30 s por turno · muerte súbita».
static func rules_summary(r: Dictionary) -> String:
	var parts: Array[String] = []
	if int(r.get("turn_ms", 0)) > 0:
		parts.append("%s por turno" % _turn_label(int(r.turn_ms)))
	if int(r.get("hand", 0)) > 0:
		parts.append("mano de %d" % int(r.hand))
	if bool(r.get("sudden_death", false)):
		parts.append("muerte súbita")
	if bool(r.get("nope_fixed", false)):
		parts.append("Nop sin pistas")
	if bool(r.get("rotten", false)):
		parts.append("Gatito Putrefacto")
	return "Reglas: " + (" · ".join(parts) if not parts.is_empty() else "las de siempre")


## Bloque «Reglas de Plus»: cuatro botones que alternan y una nota de una línea por regla activa (o recién cambiada).
## `change(key, value)` aplica el cambio; en la sala lo manda el anfitrión, en «Un jugador» se guarda.
## `crypt`: La Cripta activada (solo con ella existe el Gatito Putrefacto); `players`: jugadores de la partida.
func _rules_block(r: Dictionary, change: Callable, in_lobby: bool, crypt: bool = false, players: int = 0) -> void:
	_box.add_child(UIKit.label("Reglas de Plus", 36 if in_lobby else 40, UIKit.C.toxic, true))
	var turn := int(r.get("turn_ms", 0))
	var hand := int(r.get("hand", 0))
	var sd := bool(r.get("sudden_death", false))
	var nf := bool(r.get("nope_fixed", false))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_box.add_child(grid)
	var items := [
		["turn_ms", "Tiempo por turno: " + _turn_label(turn), turn > 0, _next_turn_ms(turn),
			"Si no juegas a tiempo, se roba carta solo." if turn > 0 else "Los turnos no tienen límite de tiempo."],
		["hand", "Mano inicial: " + ("normal" if hand <= 0 else ("corta (5)" if hand == 5 else str(hand))), hand > 0, 0 if hand > 0 else 5,
			"Cada jugador empieza con %d cartas: partida más rápida." % hand if hand > 0 else "Mano inicial de siempre (7 cartas, 8 con La Cripta)."],
		["sudden_death", "Muerte súbita: " + ("sí" if sd else "no"), sd, not sd,
			"Con 2 vivos, cada vuelta se retira la carta del fondo del mazo." if sd else "Sin muerte súbita."],
		["nope_fixed", "Nop sin pistas: " + ("sí" if nf else "no"), nf, not nf,
			"La espera para anular dura siempre lo mismo, para no delatar quién tiene Nop." if nf else "La espera para anular se acorta si nadie tiene Nop."],
	]
	for it: Array in items:
		var key: String = it[0]
		var b := _add(it[1], "on" if it[2] else "normal", change.bind(key, it[3]), 30, grid)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
	var rot := bool(r.get("rotten", false))
	if crypt:
		var rb := _add("Gatito Putrefacto: " + ("sí" if rot else "no"), "on" if rot else "normal", change.bind("rotten", not rot), 30)
		rb.clip_text = true
	for it: Array in items:
		if it[2] or _rule_touched == it[0]:
			_note(it[4], 26)
	if crypt and (rot or _rule_touched == "rotten"):
		var rn := "Sustituye a un explosivo. Con 3 o más jugadores."
		if players > 0 and players < 3:
			rn += "\nCon %d jugadores no tendrá efecto." % players if in_lobby else "\nCon 1 rival no tendrá efecto: elige 2 o más."
		_note(rn, 26)


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
		var tag := "PLUS" if r.get("plus", false) else "CLÁSICO"
		var b := UIKit.button("Sala de %s  ·  %d/5  ·  %s%s" % [r.get("name", "?"), int(r.get("players", 0)), tag, "  (en partida)" if started else ""], "on" if not started else "normal", 42)
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
	if session.is_plus():
		_note("Modo PLUS", 30, UIKit.C.gold)
	if is_host:
		var ips: Array = Net.local_ips()
		_note(("Los demás tocan «Unirse a una sala». Si no aparece, tu dirección es  %s" % ips[0]) if ips.size() > 0 else "Sin red local: conéctate a una Wi-Fi o activa tu zona Wi-Fi para que otros se unan.", 28, UIKit.C.ink)
	var scores: Dictionary = session.scores()
	var show_scores := scores.values().any(func(v: Variant) -> bool: return int(v) > 0)
	for p: Dictionary in players:
		var row := UIKit.panel(UIKit.C.panel2, UIKit.C.line, Vector2(14, 6))
		var h := UIKit.hbox(12)
		row.add_child(h)
		h.add_child(UIKit.avatar_icon(int(p.avatar), Vector2(70, 92)))
		var name_l := UIKit.label(p.name, 42, UIKit.C.ink, true)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		h.add_child(name_l)
		if show_scores:
			h.add_child(UIKit.label("🏆 %d" % int(scores.get(p.id, 0)), 32, UIKit.C.gold))
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
		if session.is_plus():
			var crypt_on: bool = "crypt" in lobby.settings.get("packs", [])
			_add("La Cripta: sí" if crypt_on else "La Cripta: no", "normal", func() -> void: session.send({"t": "settings", "packs": [] if crypt_on else ["crypt"]}), 38, tools)
	_note(_deck_info(maxi(2, n), full), 28)
	if session.is_plus() and not is_host:
		_note("La Cripta: activada" if "crypt" in lobby.settings.get("packs", []) else "La Cripta: desactivada", 28)
		_note(rules_summary(lobby.settings.get("rules", {})), 28)
	elif session.is_plus():
		_rules_block(lobby.settings.get("rules", {}), _send_rule, true, "crypt" in lobby.settings.get("packs", []), n)
	if status != "":
		_note(status, 32, UIKit.C.gold)
	if is_host:
		var start := _add("¡EMPEZAR PARTIDA!" if n >= 2 else "Faltan jugadores", "primary", func() -> void: session.send({"t": "start"}), 60)
		start.disabled = n < 2
	else:
		_note("Esperando a que el anfitrión empiece…", 34, UIKit.C.ink)
	_add("Cerrar la sala" if is_host else "Salir de la sala", "ghost", func() -> void: leave_requested.emit(), 38)
