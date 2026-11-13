class_name DirIndicator
extends Node3D
## Sentido de juego (V-06): aro de flechas sobre el tapete que gira despacio en el sentido en que
## pasan los turnos. Con sentido +1 los turnos van, visto desde tu asiento, en el sentido de las
## agujas del reloj (tú → rival de la izquierda → … → rival de la derecha → tú). Al invertirse da
## una vuelta rápida y las flechas se giran.

const RADIUS := 1.02
const ARROWS := 6
const SPIN := 0.22           # rad/s

var dir := 1
var _ring: Node3D            # gira sin parar
var _heads: Node3D           # flechas: se giran 180° al invertir el sentido
var _mat: StandardMaterial3D
var _boost := 0.0            # giro extra tras invertirse (rad/s, decae)
var _time := 0.0


func _init() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.albedo_color = Color(0.71, 0.95, 0.23, 0.5)
	_ring = Node3D.new()
	add_child(_ring)
	var band := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.012
	torus.outer_radius = RADIUS + 0.012
	torus.rings = 72
	torus.ring_segments = 4
	band.mesh = torus
	band.scale = Vector3(1, 0.05, 1)
	band.material_override = _mat
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(band)
	_heads = Node3D.new()
	_ring.add_child(_heads)
	for i in ARROWS:
		var a := float(i) / ARROWS * TAU
		var holder := Node3D.new()
		holder.position = Vector3(sin(a), 0, cos(a)) * RADIUS
		holder.rotation.y = a        # el eje X local queda tangente al aro
		var cone := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = 0.0
		m.bottom_radius = 0.07
		m.height = 0.16
		m.radial_segments = 3
		m.rings = 1
		cone.mesh = m
		cone.rotation.z = PI / 2.0       # la punta mira a -X local: ángulo decreciente = sentido horario visto desde tu asiento
		cone.material_override = _mat
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(cone)
		_heads.add_child(holder)
	visible = false


## Sentido: +1 o -1. `animate`: da la vuelta rápida de aviso (no en la primera vez).
func set_dir(value: int, animate: bool = true) -> void:
	var d := 1 if value >= 0 else -1
	if d == dir and _heads.rotation.y == _target_yaw(d):
		return
	var changed := d != dir
	dir = d
	if animate and changed:
		_boost = 7.0
		var t := _heads.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(_heads, "rotation:y", _target_yaw(d), 0.45)
	else:
		_heads.rotation.y = _target_yaw(d)


## V-04 (Marcha Atrás): giro extra del aro, además de la vuelta de las flechas.
func kick(extra: float = 12.0) -> void:
	_boost = maxf(_boost, extra)


func _target_yaw(d: int) -> float:
	# Girar todas las flechas 180° sobre sí mismas (cada una en su sitio) las deja apuntando al otro lado
	return 0.0 if d > 0 else PI


func _process(delta: float) -> void:
	_time += delta
	_boost = maxf(0.0, _boost - delta * 9.0)
	# Visto desde arriba, el sentido horario es un giro negativo alrededor de Y
	_ring.rotation.y -= (SPIN + _boost) * dir * delta
	_mat.albedo_color.a = 0.42 + 0.14 * sin(_time * 2.2)
