class_name MenuScreen
extends CanvasLayer
## Menú principal (por ahora: partida de un jugador contra la IA).

signal start_requested(opts: Dictionary)

const LEVELS := [["easy", "Fácil", "Juega casi al azar. Ideal para aprender."], ["normal", "Normal", "Esquiva cuando el riesgo sube."], ["hard", "Difícil", "Recuerda el mazo y te roba los Zombis."], ["mix", "Mixta", "Cada rival con una dificultad distinta."]]
const SETTINGS := "user://settings.cfg"

var _opts := {"rivals": 2, "level": "normal", "deck_mode": "official", "name": "Tú"}
var _box: VBoxContainer


func _ready() -> void:
	layer = 3
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		for k: String in _opts.keys():
			_opts[k] = cfg.get_value("solo", k, _opts[k])
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
	var panel := UIKit.panel(Color(0.17, 0.11, 0.36, 0.92), UIKit.C.line, Vector2(30, 26))
	margin.add_child(panel)
	_box = UIKit.vbox(14)
	panel.add_child(_box)
	_build()


func _build() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_box.add_child(UIKit.label("Rivales controlados por la IA", 40, UIKit.C.toxic, true))
	var row := UIKit.hbox(12)
	_box.add_child(row)
	for n in [1, 2, 3, 4]:
		var b := UIKit.button(str(n), "on" if _opts.rivals == n else "normal", 56)
		b.pressed.connect(_choose.bind("rivals", n))
		row.add_child(b)
	_box.add_child(UIKit.label("Dificultad", 40, UIKit.C.toxic, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_box.add_child(grid)
	var hint := ""
	for lv: Array in LEVELS:
		var b := UIKit.button(lv[1], "on" if _opts.level == lv[0] else "normal", 44)
		b.pressed.connect(_choose.bind("level", lv[0]))
		grid.add_child(b)
		if _opts.level == lv[0]:
			hint = lv[2]
	var hl := UIKit.label(hint, 30, UIKit.C.dim, false, true)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(hl)
	var full: bool = _opts.deck_mode == "full"
	var deck := UIKit.button("Mazo: completo" if full else "Mazo: oficial", "normal", 38)
	deck.pressed.connect(_choose.bind("deck_mode", "official" if full else "full"))
	_box.add_child(deck)
	var players: int = int(_opts.rivals) + 1
	var info := "Todas las cartas (57) y %d explosivos." % (players - 1)
	if not full:
		info = "Oficial para 2: las 24 cartas con huella y 1 explosivo." if players == 2 else ("Oficial para 3: las 33 cartas sin huella y 2 explosivos." if players == 3 else "Oficial: todas las cartas y %d explosivos." % (players - 1))
	var il := UIKit.label(info, 28, UIKit.C.dim, false, true)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(il)
	var play := UIKit.button("¡JUGAR!", "primary", 68)
	play.pressed.connect(func() -> void: start_requested.emit(_opts.duplicate()))
	_box.add_child(play)
	var ver := UIKit.label("Godot · v%s" % ProjectSettings.get_setting("application/config/version"), 24, UIKit.C.dim)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(ver)


func _choose(key: String, value: Variant) -> void:
	_opts[key] = value
	var cfg := ConfigFile.new()
	for k: String in _opts.keys():
		cfg.set_value("solo", k, _opts[k])
	cfg.save(SETTINGS)
	_build()
