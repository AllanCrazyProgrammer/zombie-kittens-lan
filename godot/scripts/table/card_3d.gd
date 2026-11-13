class_name Card3D
extends Node3D
## Una carta física sobre la mesa: modelo de Blender + textura de frente/dorso, se puede tocar y voltear.

signal tapped(card: Card3D)

const MODEL := preload("res://assets/models/card.glb")
const SIZE := Vector3(0.63, 0.006, 0.882)
const CARD_SHADER := preload("res://shaders/card.gdshader")
## Cartas especiales con más brillo tornasol
const FOIL := {"zombie": 0.16, "exploding": 0.18, "nope": 0.1}
## Aditivo (Plus): brillo tornasol de las cartas de la expansión (el clásico solo usa FOIL)
const PLUS_FOIL := {"apocalypse": 0.18, "rotten": 0.18}

var type: String = ""
## Identificador de la carta en la partida (vacío en cartas decorativas)
var card_id: String = ""
var face_up: bool = true
var _busy: bool = false
var _body: Node3D
var _front: ShaderMaterial
var _move: Tween


func setup(card_type: String, up: bool = true) -> Card3D:
	type = card_type
	face_up = up
	_body = MODEL.instantiate()
	add_child(_body)
	var mesh := _find_mesh(_body)
	if mesh:
		_front = _mat(CardDB.texture(type), FOIL.get(type, PLUS_FOIL.get(type, 0.1)))
		mesh.set_surface_override_material(0, _front)
		mesh.set_surface_override_material(1, _mat(CardDB.texture("back"), 0.06))
	if not up:
		_body.rotation.z = PI
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE + Vector3(0, 0.05, 0)
	shape.shape = box
	area.add_child(shape)
	area.input_event.connect(_on_input)
	add_child(area)
	return self


## Mueve la carta suavemente a una posición/rotación (en el espacio de su padre).
func fly_to(pos: Vector3, rot: Vector3, time: float = 0.28, target_scale: float = -1.0) -> Tween:
	if _move:
		_move.kill()
	_move = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move.tween_property(self, "position", pos, time)
	_move.tween_property(self, "rotation", rot, time)
	if target_scale > 0.0:
		_move.tween_property(self, "scale", Vector3.ONE * target_scale, time)
	return _move


## Detiene cualquier movimiento animado (para que la carta pueda seguir al dedo).
func kill_motion() -> void:
	if _move:
		_move.kill()
		_move = null


## Cambia de padre conservando su lugar en el mundo (para volar entre la mano, el mazo y el descarte).
func move_under(new_parent: Node3D) -> void:
	var gt := global_transform
	if get_parent():
		get_parent().remove_child(self)
	new_parent.add_child(self)
	global_transform = gt


func set_face_up(up: bool) -> void:
	face_up = up
	_body.rotation.z = 0.0 if up else PI


func flip() -> void:
	if _busy:
		return
	_busy = true
	face_up = not face_up
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_body, "position:y", 0.45, 0.18)
	t.parallel().tween_property(_body, "rotation:z", _body.rotation.z + PI, 0.42)
	t.tween_property(_body, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.finished.connect(func() -> void: _busy = false)


func _mat(tex: Texture2D, foil: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CARD_SHADER
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("foil", foil)
	return m


## Resalta la carta (elegida o jugable) con un resplandor.
func set_glow(amount: float) -> void:
	if _front:
		_front.set_shader_parameter("glow", amount)


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null


func _on_input(_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(self)


## Aditivo (Plus): una carta que flota o se rompe no debe recibir toques ni tapar lo que tiene detrás.
func set_pickable(on: bool) -> void:
	for c in get_children():
		if c is Area3D:
			(c as Area3D).input_ray_pickable = on
			(c as Area3D).monitorable = on


## Aditivo (Plus): oculta solo el modelo de la carta (sus hijos, como las mitades de una carta rota, siguen visibles).
func set_body_visible(on: bool) -> void:
	if _body:
		_body.visible = on


# ------------------------------------------------------------------ Plus (V-07): jugable / no jugable

static var _edge_tex: Texture2D
var _edge: MeshInstance3D
var _dim: StandardMaterial3D


static func _edge_texture() -> Texture2D:
	if _edge_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.86, 0.925, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_SQUARE
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_edge_tex = t
	return _edge_tex


## Aditivo (Plus): borde luminoso suave alrededor de la carta (las jugables ahora mismo). No toca el brillo de `set_glow`.
func set_edge(on: bool, color: Color = Color(0.71, 0.95, 0.23)) -> void:
	if not on:
		if _edge != null and is_instance_valid(_edge):
			_edge.visible = false
		return
	if _edge == null or not is_instance_valid(_edge):
		var pm := PlaneMesh.new()
		pm.size = Vector2(SIZE.x + 0.1, SIZE.z + 0.1)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = _edge_texture()
		m.albedo_color = Color(color.r, color.g, color.b, 0.55)
		_edge = MeshInstance3D.new()
		_edge.mesh = pm
		_edge.material_override = m
		_edge.position = Vector3(0, -0.004, 0)
		_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_edge)
	_edge.visible = true


func has_edge() -> bool:
	return _edge != null and is_instance_valid(_edge) and _edge.visible


## Aditivo (Plus): oscurece la carta (las no jugables), `amount` = fracción de negro (0 la deja como estaba).
func set_dim(amount: float) -> void:
	var mesh := _find_mesh(_body) if _body else null
	if mesh == null:
		return
	if amount <= 0.001:
		mesh.material_overlay = null
		return
	if _dim == null:
		_dim = StandardMaterial3D.new()
		_dim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dim.albedo_color = Color(0, 0, 0, amount)
	_dim.albedo_color.a = amount
	mesh.material_overlay = _dim


func dim_amount() -> float:
	var mesh := _find_mesh(_body) if _body else null
	if mesh == null or mesh.material_overlay == null or _dim == null:
		return 0.0
	return _dim.albedo_color.a


func is_body_visible() -> bool:
	return _body != null and _body.visible
