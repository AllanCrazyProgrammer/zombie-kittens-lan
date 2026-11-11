class_name DeckProfile
extends Control
## Mazo dibujado de perfil (UX-06): una fila fina por carta (agrupadas de 5 en 5, con la cuenta a la
## izquierda) y un hueco brillante que se arrastra arriba y abajo para elegir la posición.
## Posición 0 = arriba del todo; `n` = hasta el fondo (n = cartas que hay en el mazo).
## Las cartas que el recordatorio del futuro conoce se marcan con color y nombre.

## El jugador movió el hueco a esta posición.
signal moved(pos: int)

const GAP_H := 22.0
const PAD_TOP := 30.0
const PAD_BOTTOM := 30.0
const LEFT_W := 54.0
const RIGHT_W := 150.0
const MAX_PITCH := 18.0
const GROUP := 5

var n := 0
var pos := 0
var _known := {}          # profundidad -> tipo
var _dragging := false
var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_VSIZE
	clip_contents = true


## cards: cartas del mazo; at: posición inicial; known: [{depth, type}] de lo que se sabe de esas cartas.
func setup(cards: int, at: int, known: Array, height: int, width: int = 440) -> DeckProfile:
	n = maxi(0, cards)
	pos = clampi(at, 0, n)
	for k: Dictionary in known:
		if int(k.depth) >= 0 and int(k.depth) < n:
			_known[int(k.depth)] = str(k.type)
	custom_minimum_size = Vector2(width, height)
	return self


## Cambia la posición del hueco (sin emitir `moved`).
func set_pos(p: int) -> void:
	pos = clampi(p, 0, n)
	queue_redraw()


## Cartas marcadas como conocidas (profundidad -> tipo) (prueba).
func debug_known() -> Dictionary:
	return _known


func _pitch() -> float:
	if n <= 0:
		return MAX_PITCH
	return minf(MAX_PITCH, (size.y - PAD_TOP - PAD_BOTTOM - GAP_H) / float(n))


## y (local) del borde superior del hueco para una posición.
func _gap_y(p: int) -> float:
	return PAD_TOP + p * _pitch()


## Posición más cercana a una y local.
func pos_at(y: float) -> int:
	if n <= 0:
		return 0
	return clampi(int(round((y - PAD_TOP - GAP_H * 0.5) / _pitch())), 0, n)


## Punto global del centro del hueco en una posición (prueba: para arrastrar de verdad).
func debug_point(p: int) -> Vector2:
	return global_position + Vector2(size.x * 0.5, _gap_y(clampi(p, 0, n)) + GAP_H * 0.5)


func _process(delta: float) -> void:
	_time += delta
	if is_visible_in_tree():
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_move_to(event.position.y)
		accept_event()
	elif event is InputEventMouseMotion and _dragging and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_move_to(event.position.y)
		accept_event()


func _move_to(y: float) -> void:
	var p := pos_at(y)
	if p != pos:
		pos = p
		moved.emit(pos)
		queue_redraw()


func _draw() -> void:
	var font := UIKit.bold()
	var w := size.x
	var pitch := _pitch()
	var rx := LEFT_W
	var rw := maxf(40.0, w - LEFT_W - RIGHT_W)
	draw_string_outline(font, Vector2(rx, 22.0), "ARRIBA", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, UIKit.C.dark)
	draw_string(font, Vector2(rx, 22.0), "ARRIBA", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UIKit.C.dim)
	var bottom_y := PAD_TOP + n * pitch + GAP_H
	draw_string_outline(font, Vector2(rx, bottom_y + 24.0), "FONDO", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, UIKit.C.dark)
	draw_string(font, Vector2(rx, bottom_y + 24.0), "FONDO", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UIKit.C.dim)
	var thin := pitch < 7.0
	var last_label_y := -100.0
	for i in n:
		var y := PAD_TOP + i * pitch + (GAP_H if i >= pos else 0.0)
		var h := maxf(1.5, pitch - (1.0 if thin else 2.5))
		var group := i / GROUP
		var col: Color = UIKit.C.panel2 if group % 2 == 0 else Color("463291")
		var edge: Color = UIKit.C.line
		var r := Rect2(rx, y, rw, h)
		var kind: String = _known.get(i, "")
		if kind != "":
			col = Color("c63a4e") if kind == "exploding" else Color("2a9fb0")
			edge = UIKit.C.gold
		draw_rect(r, col, true)
		if not thin:
			draw_rect(r, edge, false, 1.5)
		elif kind != "":
			draw_rect(r, edge, false, 1.0)
		# Cuenta de 5 en 5 a la izquierda: dónde se está de un vistazo
		if i > 0 and i % GROUP == 0:
			draw_line(Vector2(LEFT_W - 12.0, y - 0.5), Vector2(rx - 2.0, y - 0.5), UIKit.C.dim, 1.5)
			draw_string(font, Vector2(4.0, y + 7.0), str(i), HORIZONTAL_ALIGNMENT_LEFT, LEFT_W - 16.0, 20, UIKit.C.dim)
		if kind != "":
			var ty := y + h * 0.5 + 7.0
			if ty - last_label_y >= 20.0:
				var name := "Explosivo" if kind == "exploding" else CardDB.display_name(kind)
				draw_string_outline(font, Vector2(rx + rw + 10.0, ty), name, HORIZONTAL_ALIGNMENT_LEFT, RIGHT_W - 12.0, 20, 6, UIKit.C.dark)
				draw_string(font, Vector2(rx + rw + 10.0, ty), name, HORIZONTAL_ALIGNMENT_LEFT, RIGHT_W - 12.0, 20, UIKit.C.gold)
				last_label_y = ty
	# El hueco: barra brillante con flechas hacia dentro
	var gy := _gap_y(pos)
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	var gc := UIKit.C.toxic
	draw_rect(Rect2(rx - 8.0, gy + 2.0, rw + 16.0, GAP_H - 4.0), Color(gc.r, gc.g, gc.b, 0.25 + 0.2 * pulse), true)
	draw_rect(Rect2(rx - 8.0, gy + 2.0, rw + 16.0, GAP_H - 4.0), gc, false, 3.0)
	var cy := gy + GAP_H * 0.5
	draw_colored_polygon(PackedVector2Array([Vector2(rx - 36.0, cy - 12.0), Vector2(rx - 36.0, cy + 12.0), Vector2(rx - 12.0, cy)]), gc)
	draw_colored_polygon(PackedVector2Array([Vector2(rx + rw + 36.0, cy - 12.0), Vector2(rx + rw + 36.0, cy + 12.0), Vector2(rx + rw + 12.0, cy)]), gc)
