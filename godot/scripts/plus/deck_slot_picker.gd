class_name DeckSlotPicker
extends VBoxContainer
## Selector de posición dentro del mazo (UX-06): el mazo dibujado de perfil con un hueco que se arrastra
## arriba y abajo, la frase que dice dónde queda, ajuste fino «−1 / +1» y atajos Arriba / Segunda /
## Al azar / Fondo. Lo usan «Esconde el Gatito Explosivo» y Entierro.
## Interfaz pública: `setup`, `changed` y `value`.

## Posición elegida (0 = arriba del todo … max_pos = fondo).
signal changed(pos: int)

var value := 0
var max_pos := 0

var _profile: DeckProfile
var _where: Label


## Frase que describe una posición del mazo.
static func label_for(pos: int, p_max: int) -> String:
	if pos <= 0:
		return "Arriba del todo: será la PRÓXIMA carta"
	if pos >= p_max:
		return "Hasta el fondo del mazo"
	return "Debajo de %d carta%s (posición %d de %d)" % [pos, "s" if pos > 1 else "", pos + 1, p_max + 1]


## p_max: posición más baja posible (cartas que hay en el mazo). p_value: posición inicial.
## title: rótulo opcional sobre el mazo. known: [{depth, type}] de lo que el recordatorio del futuro sabe
## de las cartas del mazo (se marcan en el perfil). profile_h: alto del dibujo del mazo.
func setup(p_max: int, p_value: int, title: String = "", known: Array = [], profile_h: int = 470) -> DeckSlotPicker:
	max_pos = maxi(0, p_max)
	value = clampi(p_value, 0, max_pos)
	add_theme_constant_override("separation", 12)
	if title != "":
		add_child(UIKit.label(title, 42, UIKit.C.gold, true))
	var row := UIKit.hbox(16)
	add_child(row)
	_profile = DeckProfile.new().setup(max_pos, value, known, profile_h)
	_profile.moved.connect(_set_value)
	row.add_child(_profile)
	var side := UIKit.vbox(14)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(side)
	_where = UIKit.label(label_for(value, max_pos), 30, UIKit.C.ink, false, true)
	_where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_where.custom_minimum_size = Vector2(300, 0)
	side.add_child(_where)
	var fine := UIKit.hbox(12)
	side.add_child(fine)
	for step: Array in [["−1", -1], ["+1", 1]]:
		var delta: int = step[1]
		var b := UIKit.button(step[0], "normal", 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _set_value(value + delta))
		fine.add_child(b)
	var hint := UIKit.label("Arrastra el hueco verde o ajusta de 1 en 1", 22, UIKit.C.dim, false, true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(hint)
	var quick := GridContainer.new()
	quick.columns = 2
	quick.add_theme_constant_override("h_separation", 10)
	quick.add_theme_constant_override("v_separation", 10)
	side.add_child(quick)
	for opt: Array in [["Arriba", 0], ["Segunda", 1], ["Al azar", -1], ["Fondo", max_pos]]:
		var target_pos: int = opt[1]
		var b := UIKit.button(opt[0], "normal", 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_set_value((randi() % (max_pos + 1)) if target_pos < 0 else mini(target_pos, max_pos)))
		quick.add_child(b)
	return self


func _set_value(pos: int) -> void:
	var p := clampi(pos, 0, max_pos)
	_profile.set_pos(p)
	if p == value:
		return
	value = p
	_where.text = label_for(value, max_pos)
	changed.emit(value)


## Prueba: elige una posición como si se moviera el hueco.
func debug_set(pos: int) -> void:
	_set_value(pos)


## Prueba: frase que se muestra.
func debug_text() -> String:
	return _where.text


## Prueba: el dibujo del mazo (para arrastrar el hueco con toques reales).
func debug_profile() -> DeckProfile:
	return _profile
