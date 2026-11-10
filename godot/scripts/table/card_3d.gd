class_name Card3D
extends Node3D
## Una carta física sobre la mesa: modelo de Blender + textura de frente/dorso, se puede tocar y voltear.

signal tapped(card: Card3D)

const MODEL := preload("res://assets/models/card.glb")
const SIZE := Vector3(0.63, 0.006, 0.882)

var type: String = ""
var face_up: bool = true
var _busy: bool = false
var _body: Node3D


func setup(card_type: String, up: bool = true) -> Card3D:
	type = card_type
	face_up = up
	_body = MODEL.instantiate()
	add_child(_body)
	var mesh := _find_mesh(_body)
	if mesh:
		mesh.set_surface_override_material(0, _mat(CardDB.texture(type)))
		mesh.set_surface_override_material(1, _mat(CardDB.texture("back")))
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


func _mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


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
