class_name AimMode
extends Node3D
## «Modo puntería» (UX-01): elegir el objetivo de una jugada tocando la mesa.
## Reglas de validez por tipo de objetivo (CONTRATO-PLUS §2.3), aros pulsantes bajo los asientos
## válidos, atenuado de los no válidos y detección de toques sobre un asiento (avatar o cartas).
## No contiene reglas del juego: solo decide qué jugadores resalta la interfaz.

const KINDS := ["living", "living_any", "any_hand", "dead", "dead_hand"]
const HALO_PX := 256
const HALO_SIZE := 0.95
const FLOOR_RADIUS := 0.36

static var _halo_tex: ImageTexture

var _kind := ""
var _valid := {}                # id del rival -> bool
var _rings := {}                # id -> {halo, floor}
var _seats: Dictionary = {}     # referencia viva a los asientos de la pantalla
var _time := 0.0
var _floor_mat: StandardMaterial3D


## Motivo por el que `p` no es un objetivo válido para `kind` ("" si lo es).
static func reason(kind: String, p: Dictionary, you: String) -> String:
	if p.is_empty():
		return "Ese jugador no existe."
	var pname: String = p.get("name", "?")
	var is_me: bool = p.id == you
	match kind:
		"living", "living_any", "any_hand":
			if is_me:
				return "No puedes elegirte a ti mismo."
			if kind != "any_hand" and not p.alive:
				return "%s está muerto." % pname
			if kind != "living_any" and int(p.count) == 0:
				return "%s no tiene cartas." % pname
		"dead", "dead_hand":
			if p.alive:
				return "Sigues vivo." if is_me else "%s sigue vivo." % pname
			if kind == "dead_hand" and int(p.count) == 0:
				return "Ya no tiene cartas." if is_me else "%s no tiene cartas." % pname
		_:
			return "Objetivo desconocido."
	return ""


## Frase del panel inferior para ese tipo de objetivo.
static func prompt(kind: String) -> String:
	match kind:
		"dead": return "Toca a un jugador muerto"
		"dead_hand": return "Toca a un jugador muerto con cartas"
		"any_hand": return "Toca a un rival con cartas (vivo o muerto)"
		_: return "Toca a un rival"


## Ids de los rivales válidos (no incluye al jugador).
static func valid_ids(kind: String, view: Dictionary) -> Array:
	var out: Array = []
	for p: Dictionary in view.players:
		if p.id != view.you and reason(kind, p, view.you) == "":
			out.append(p.id)
	return out


## Si el propio jugador es un objetivo válido (botón «Yo mismo»).
static func self_valid(kind: String, view: Dictionary) -> bool:
	for p: Dictionary in view.players:
		if p.id == view.you:
			return reason(kind, p, view.you) == ""
	return false


func active() -> bool:
	return _kind != ""


func current() -> String:
	return _kind


## Rival válido o no (solo con el modo activo).
func is_valid(id: String) -> bool:
	return _valid.get(id, false)


## Activa el resaltado para `kind` ("" lo apaga). `seats` es el diccionario vivo de asientos de la pantalla.
func set_kind(p_kind: String, view: Dictionary, p_seats: Dictionary) -> void:
	_seats = p_seats
	var valid := {}
	if p_kind != "":
		for p: Dictionary in view.players:
			if p.id != view.you:
				valid[p.id] = reason(p_kind, p, view.you) == ""
	if p_kind == _kind and valid == _valid:
		return
	_kind = p_kind
	_valid = valid
	for id: String in _rings:
		_rings[id].halo.visible = false
		_rings[id].floor.visible = false
	for id: String in _valid:
		if _valid[id] and _seats.has(id):
			var r := _ring_for(id)
			r.halo.visible = true
			r.floor.visible = true


func _ring_for(id: String) -> Dictionary:
	if _rings.has(id):
		return _rings[id]
	if _floor_mat == null:
		_floor_mat = StandardMaterial3D.new()
		_floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_floor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_floor_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_floor_mat.albedo_color = UIKit.C.toxic
	var seat: Dictionary = _seats[id]
	var halo := Sprite3D.new()
	halo.texture = _halo_texture()
	halo.pixel_size = HALO_SIZE / float(HALO_PX)
	halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	halo.shaded = false
	halo.no_depth_test = true
	halo.render_priority = -1
	halo.modulate = UIKit.C.toxic
	add_child(halo)
	halo.global_position = (seat.avatar as Node3D).global_position
	var floor_ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = FLOOR_RADIUS - 0.05
	torus.outer_radius = FLOOR_RADIUS
	torus.rings = 48
	torus.ring_segments = 6
	floor_ring.mesh = torus
	floor_ring.material_override = _floor_mat
	floor_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_ring.scale = Vector3(1.5, 0.3, 1.0)
	add_child(floor_ring)
	floor_ring.global_position = (seat.root as Node3D).global_position + Vector3(0, 0.02, 0)
	floor_ring.global_rotation.y = (seat.root as Node3D).global_rotation.y
	_rings[id] = {"halo": halo, "floor": floor_ring}
	return _rings[id]


static func _halo_texture() -> ImageTexture:
	if _halo_tex == null:
		var img := Image.create(HALO_PX, HALO_PX, false, Image.FORMAT_RGBA8)
		var c := (HALO_PX - 1) / 2.0
		for y in HALO_PX:
			for x in HALO_PX:
				var d := Vector2(x - c, y - c).length() / c      # 0 centro .. 1 borde
				var ring := clampf(1.0 - absf(d - 0.86) / 0.1, 0.0, 1.0)
				var glow := clampf(1.0 - absf(d - 0.8) / 0.3, 0.0, 1.0) * 0.28
				img.set_pixel(x, y, Color(1, 1, 1, clampf(maxf(ring, glow), 0.0, 1.0)))
		_halo_tex = ImageTexture.create_from_image(img)
	return _halo_tex


func _process(delta: float) -> void:
	_time += delta
	if _kind == "":
		return
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	for id: String in _rings:
		var r: Dictionary = _rings[id]
		if not r.halo.visible:
			continue
		var seat: Dictionary = _seats.get(id, {})
		if seat.is_empty():
			continue
		r.halo.global_position = (seat.avatar as Node3D).global_position
		r.halo.modulate = Color(UIKit.C.toxic.r, UIKit.C.toxic.g, UIKit.C.toxic.b, 0.65 + 0.35 * pulse)
		r.halo.scale = Vector3.ONE * (1.0 + 0.07 * pulse)
		r.floor.scale = Vector3(1.5, 0.3, 1.0) * (1.0 + 0.12 * pulse)
	if _floor_mat == null:
		return      # ningún rival válido: aún no se creó ningún aro
	_floor_mat.albedo_color = Color(UIKit.C.toxic.r, UIKit.C.toxic.g, UIKit.C.toxic.b, 0.55 + 0.4 * pulse)
	# Atenuado de los asientos no válidos (la pantalla restablece los colores al salir)
	for id: String in _valid:
		if _valid[id] or not _seats.has(id):
			continue
		(_seats[id].avatar as Sprite3D).modulate = Color(0.28, 0.28, 0.34, 0.8)


## Rival cuyo asiento (avatar o cartas) está bajo un punto de la pantalla ("" si ninguno).
func seat_at(cam: Camera3D, screen_pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	var right := cam.global_transform.basis.x
	for id: String in _seats:
		var av := (_seats[id].avatar as Node3D).global_position
		var a := cam.unproject_position(av)
		var b := cam.unproject_position((_seats[id].root as Node3D).global_position)
		var r := absf(cam.unproject_position(av + right * 0.3).x - a.x) + 16.0
		var d := _dist_to_segment(screen_pos, a, b)
		if d <= r and d < best_d:
			best_d = d
			best = id
	return best


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 < 0.001 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
