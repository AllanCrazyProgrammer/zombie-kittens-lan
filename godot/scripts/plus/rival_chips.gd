class_name RivalChips
extends HBoxContainer
## Fichas de los rivales (UX-10). Se crean una vez por rival; `update` solo cambia textos, colores e
## iconos, así que seleccionar cartas de la mano no crea ni destruye nodos.

## Reservada para el «modo puntería»: se emite al tocar la ficha de un rival (si `set_pickable(true)`).
signal chip_pressed(player_id: String)

const LEVEL_NAMES := {"easy": "Fácil", "normal": "Normal", "hard": "Difícil"}
const DEAD_BG := Color("241a38")

var _chips := {}          # id -> {panel, pic, name, info, state}
var _order: Array = []    # ids de los rivales, en orden de turno a partir del jugador
var _builds := 0
var _pickable := false
var _target := ""         # objetivo de la jugada en curso (para pulsar solo al cambiar)
var _time := 0.0


func _init() -> void:
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Cuántas fichas se han construido en total (prueba: no debe cambiar al seleccionar cartas).
func debug_chip_builds() -> int:
	return _builds


## Texto de estado que muestra la ficha de ese rival ("" si no existe).
func debug_state_of(id: String) -> String:
	return _chips[id].state.text if _chips.has(id) else ""


## Hace las fichas tocables. Apagado, no interceptan ningún toque (pasan a la mesa).
func set_pickable(on: bool) -> void:
	_pickable = on
	for id: String in _chips:
		_chips[id].panel.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


## view: vista de la partida. level_of: Callable(id) -> nivel de la IA.
func update(view: Dictionary, level_of: Callable) -> void:
	var n: int = view.players.size()
	var my_idx := 0
	for i in n:
		if view.players[i].id == view.you:
			my_idx = i
	var rivals: Array = []
	for k in range(1, n):
		rivals.append(view.players[(my_idx + k) % n])
	var ids: Array = rivals.map(func(p: Dictionary) -> String: return p.id)
	if ids != _order:
		_rebuild(rivals, n)
	var target := _target_of(view)
	for p: Dictionary in rivals:
		_fill(_chips[p.id], p, view, level_of, p.id == target)
	_target = target


func _target_of(view: Dictionary) -> String:
	if view.stack.is_empty():
		return ""
	var t: Variant = view.stack[view.stack.size() - 1]
	return str(t.get("target", "")) if t is Dictionary and t.get("target") != null else ""


func _rebuild(rivals: Array, n: int) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_chips.clear()
	_order.clear()
	var small := n >= 5
	for p: Dictionary in rivals:
		_builds += 1
		_order.append(p.id)
		var chip := UIKit.panel(UIKit.C.panel, UIKit.C.line, Vector2(8 if small else 10, 8))
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.mouse_filter = Control.MOUSE_FILTER_STOP if _pickable else Control.MOUSE_FILTER_IGNORE
		chip.gui_input.connect(_on_chip_input.bind(p.id))
		var ch := UIKit.hbox(6)
		chip.add_child(ch)
		var pic := UIKit.avatar_icon(int(p.get("avatar", 0)), Vector2(48, 62) if small else Vector2(84, 108))
		ch.add_child(pic)
		var cv := UIKit.vbox(0)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ch.add_child(cv)
		var name_l := UIKit.label(p.name, 36 if small else 44, UIKit.C.ink, true)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.clip_text = true
		cv.add_child(name_l)
		var info_l := UIKit.label("", 28 if small else 32, UIKit.C.dim)
		info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info_l.clip_text = true
		cv.add_child(info_l)
		var state_l := UIKit.label("", 26 if small else 30, UIKit.C.dim)
		state_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		state_l.clip_text = true
		cv.add_child(state_l)
		add_child(chip)
		_chips[p.id] = {"panel": chip, "pic": pic, "name": name_l, "info": info_l, "state": state_l}


func _fill(c: Dictionary, p: Dictionary, view: Dictionary, level_of: Callable, is_target: bool) -> void:
	var is_cur: bool = p.id == view.cur
	var away: bool = not p.connected and not p.bot
	var multi: bool = is_cur and p.alive and int(view.turnsLeft) > 1
	var border: Color = UIKit.C.gold if is_target else (UIKit.C.toxic if is_cur else UIKit.C.line)
	var bw := 8 if is_target else 5
	c.panel.add_theme_stylebox_override("panel", UIKit.box(DEAD_BG if not p.alive else UIKit.C.panel, border, 30, bw, Vector2(10, 8)))
	c.pic.modulate = Color.WHITE if p.alive else Color(0.4, 0.4, 0.5)
	c.name.text = p.name
	c.name.add_theme_color_override("font_color", UIKit.C.dim if not p.alive else UIKit.C.ink)
	var info := "%d cartas" % p.count
	if multi:
		info += "  ⚔×%d" % int(view.turnsLeft)
	c.info.text = info
	c.info.add_theme_color_override("font_color", UIKit.C.gold if multi else UIKit.C.dim)
	var state: String
	var color: Color = UIKit.C.dim
	if not p.alive:
		state = "☠ MUERTO"
		color = UIKit.C.red
	elif away:
		state = "sin conexión"
		color = UIKit.C.red
	elif is_target:
		state = "¡objetivo!"
		color = UIKit.C.gold
	elif is_cur:
		state = "su turno"
		color = UIKit.C.toxic
	else:
		state = LEVEL_NAMES.get(level_of.call(p.id), "")
	c.state.text = state
	c.state.add_theme_color_override("font_color", color)
	if is_target and p.id != _target:
		_pulse(c.panel)


func _pulse(chip: Control) -> void:
	chip.pivot_offset = chip.size / 2.0
	var t := chip.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(chip, "scale", Vector2(1.08, 1.08), 0.14)
	t.tween_property(chip, "scale", Vector2.ONE, 0.22)


func _on_chip_input(event: InputEvent, id: String) -> void:
	if not _pickable:
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		chip_pressed.emit(id)
