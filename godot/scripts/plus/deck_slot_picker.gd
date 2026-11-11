class_name DeckSlotPicker
extends VBoxContainer
## Selector de posición dentro del mazo: deslizador Arriba ↔ Fondo, frase que dice dónde queda y
## atajos Arriba / Segunda / Al azar / Fondo. Lo usan «Esconde el Gatito Explosivo» y Entierro.
## (Otra tarea lo sustituirá por un mazo visual: la interfaz pública es `setup`, `changed` y `value`.)

## Posición elegida (0 = arriba del todo … max_pos = fondo).
signal changed(pos: int)

var value := 0
var max_pos := 0

var _slider: HSlider
var _where: Label


## Frase que describe una posición del mazo.
static func label_for(pos: int, p_max: int) -> String:
	if pos <= 0:
		return "Arriba del todo: será la PRÓXIMA carta"
	if pos >= p_max:
		return "Hasta el fondo del mazo"
	return "Debajo de %d carta%s (posición %d de %d)" % [pos, "s" if pos > 1 else "", pos + 1, p_max + 1]


## p_max: posición más baja posible (cartas que hay en el mazo). p_value: posición inicial.
## title: rótulo opcional sobre el deslizador.
func setup(p_max: int, p_value: int, title: String = "") -> DeckSlotPicker:
	max_pos = maxi(0, p_max)
	value = clampi(p_value, 0, max_pos)
	add_theme_constant_override("separation", 20)
	if title != "":
		add_child(UIKit.label(title, 42, UIKit.C.gold, true))
	var row := UIKit.hbox(12)
	row.add_child(UIKit.label("Arriba", 26, UIKit.C.dim))
	_slider = UIKit.slider(max_pos, value)
	row.add_child(_slider)
	row.add_child(UIKit.label("Fondo", 26, UIKit.C.dim))
	add_child(row)
	_where = UIKit.label(label_for(value, max_pos), 30, UIKit.C.ink, false, true)
	_where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_where)
	_slider.value_changed.connect(_on_slide)
	var quick := UIKit.hbox(10)
	add_child(quick)
	for opt: Array in [["Arriba", 0], ["Segunda", 1], ["Al azar", -1], ["Fondo", max_pos]]:
		var target_pos: int = opt[1]
		var b := UIKit.button(opt[0], "normal", 30)
		b.pressed.connect(func() -> void:
			_slider.value = (randi() % (max_pos + 1)) if target_pos < 0 else mini(target_pos, max_pos))
		quick.add_child(b)
	return self


func _on_slide(v: float) -> void:
	value = int(v)
	_where.text = label_for(value, max_pos)
	changed.emit(value)


## Prueba: elige una posición como si se moviera el deslizador.
func debug_set(pos: int) -> void:
	_slider.value = clampi(pos, 0, max_pos)


## Prueba: frase que se muestra.
func debug_text() -> String:
	return _where.text
