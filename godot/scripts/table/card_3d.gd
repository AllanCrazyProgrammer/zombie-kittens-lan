class_name Card3D
extends Node3D
## Una carta física sobre la mesa: modelo de Blender + textura de frente/dorso, se puede tocar y voltear.

signal tapped(card: Card3D)

const MODEL := preload("res://assets/models/card.glb")
const SIZE := Vector3(0.63, 0.006, 0.882)
const CARD_SHADER := preload("res://shaders/card.gdshader")
## Cartas especiales con más brillo tornasol
const FOIL := {"zombie": 0.3, "exploding": 0.32, "nope": 0.16}

var type: String = ""
var face_up: bool = true
var _busy: bool = false
var _body: Node3D
var _front: ShaderMaterial


func setup(card_type: String, up: bool = true) -> Card3D:
	type = card_type
	face_up = up
	_body = MODEL.instantiate()
	add_child(_body)
	var mesh := _find_mesh(_body)
	if mesh:
		_front = _mat(CardDB.texture(type), FOIL.get(type, 0.1))
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
