class_name RivalChips
extends HBoxContainer
## Fichas de los rivales (UX-10). Se crean una vez por rival; `update` solo cambia textos, colores e
## iconos, así que seleccionar cartas de la mano no crea ni destruye nodos.

## Modo puntería (UX-01): se emite al tocar la ficha de un rival (si `set_pickable(true)`).
signal chip_pressed(player_id: String)

const LEVEL_NAMES := {"easy": "Fácil", "normal": "Normal", "hard": "Difícil"}
const DEAD_BG := Color("241a38")

var _chips := {}          # id -> {panel, pic, name, info, state}
var _order: Array = []    # ids de los rivales, en orden de turno a partir del jugador
var _builds := 0
var _pickable := false
var _target := ""         # objetivo de la jugada en curso (para pulsar solo al cambiar)
var _time := 0.0
var _aim := {}            # modo puntería: id -> válido (vacío = apagado)
var _bar_state := {}      # id -> estado de color de la barra de turno (para no repintar cada cuadro)


func _init() -> void:
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


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


## Modo puntería: resalta las fichas válidas (borde brillante pulsante) y atenúa las demás.
## valid: id del rival -> si es un objetivo válido. Vacío = apagar.
func set_aim(valid: Dictionary) -> void:
	if valid == _aim:
		return
	_aim = valid.duplicate()
	set_process(not _aim.is_empty())
	for id: String in _chips:
		var panel: Control = _chips[id].panel
		panel.modulate = Color.WHITE
		if _aim.has(id) and not _aim[id]:
			panel.modulate = Color(0.55, 0.55, 0.62, 0.62)


## Prueba: ids de las fichas marcadas como válidas.
func debug_aim_valid() -> Array:
	return _aim.keys().filter(func(id: String) -> bool: return _aim[id])


func _process(delta: float) -> void:
	_time += delta
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	for id: String in _aim:
		if _aim[id] and _chips.has(id):
			_chips[id].panel.modulate = Color(1, 1, 1).lerp(Color(1.35, 1.45, 1.1), pulse * 0.6)


## Barra de tiempo de turno en la ficha de `id` (UX-07). frac 0-1; `red`: últimos 10 s (0 = no, 1 = rojo, 2 = rojo apagado).
## id "" apaga todas. Solo la ficha del jugador en turno la muestra.
func set_turn(id: String, frac: float, red: int = 0) -> void:
	for cid: String in _chips:
		var bar: ProgressBar = _chips[cid].bar
		bar.visible = cid == id
		if cid != id:
			_bar_state.erase(cid)
			continue
		bar.value = clampf(frac, 0.0, 1.0) * 100.0
		if _bar_state.get(cid, -1) != red:
			_bar_state[cid] = red
			var col: Color = UIKit.C.gold if red == 0 else (UIKit.C.red if red == 1 else Color("7a1020"))
			bar.add_theme_stylebox_override("fill", UIKit.box(col, col, 6, 0, Vector2.ZERO))


## Prueba: {visible, value, red} de la barra de turno de esa ficha.
func debug_turn_bar(id: String) -> Dictionary:
	if not _chips.has(id):
		return {}
	var bar: ProgressBar = _chips[id].bar
	return {"visible": bar.visible, "value": bar.value, "red": int(_bar_state.get(id, 0))}


## view: vista de la partida. level_of: Callable(id) -> nivel de la IA. trait_of: Callable(id) -> rasgo del bot (Plus).
func update(view: Dictionary, level_of: Callable, trait_of: Callable = Callable()) -> void:
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
		_fill(_chips[p.id], p, view, level_of, p.id == target, trait_of)
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
		var bar := UIKit.timer_bar()
		bar.custom_minimum_size = Vector2(0, 10)
		bar.visible = false
		cv.add_child(bar)
		add_child(chip)
		_chips[p.id] = {"panel": chip, "pic": pic, "name": name_l, "info": info_l, "state": state_l, "bar": bar, "small": small}


func _fill(c: Dictionary, p: Dictionary, view: Dictionary, level_of: Callable, is_target: bool, trait_of: Callable = Callable()) -> void:
	var is_cur: bool = p.id == view.cur
	var away: bool = not p.connected and not p.bot
	var multi: bool = is_cur and p.alive and int(view.turnsLeft) > 1
	var border: Color = UIKit.C.gold if is_target else (UIKit.C.toxic if is_cur else UIKit.C.line)
	var bw := 8 if is_target else 5
	if _aim.get(p.id, false):
		border = Color("dcff8a")
		bw = 10
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
		var lv: String = level_of.call(p.id)
		state = LEVEL_NAMES.get(lv, "")
		if trait_of.is_valid() and p.bot and lv != "easy":
			var tr: String = str(trait_of.call(p.id))
			if tr != "" and ZKBots.TRAIT_LABELS.has(tr):
				state += " · " + ZKBots.TRAIT_LABELS[tr]   # IA-03: «Difícil · Agresivo»
	c.state.text = state
	var sfs := 26 if c.small else 30
	if state.length() > 12:
		sfs = 20 if c.small else 24    # «Difícil · Agresivo» es largo: letra algo menor para que quepa
	c.state.add_theme_font_size_override("font_size", sfs)
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
