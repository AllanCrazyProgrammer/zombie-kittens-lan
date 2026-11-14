class_name SeatGrave
extends Node3D
## V-03 · Asiento de un rival cuando muere. Al morir, el avatar se hunde, sube una lápida con el nombre y la carta de
## muerte queda boca arriba delante; el avatar vuelve como fantasma translúcido flotando sobre la lápida (sigue
## jugando ⚡). Al revivir, la lápida se agrieta y se hunde, sale una mano verde y el avatar vuelve sólido con un tinte
## verdoso que conserva el resto de la partida.
##
## El nodo está en el sitio de la lápida (espacio de la pantalla). El avatar es el Sprite3D del asiento (lo dibuja la
## pantalla); este nodo solo lo mueve y lo tiñe. `pending` cuenta cambios que vendrán con animación (la pantalla no
## debe encajar el estado a la fuerza mientras tanto); `busy` cuenta animaciones en curso.

const TOMB := preload("res://assets/models/tombstone.glb")
const TOMB_H := 0.42                  # alto de la lápida sobre la mesa
const GHOST_TINT := Color(0.74, 0.9, 1.0, 0.52)
const ZOMBIE_TINT := Color(0.72, 1.0, 0.66, 1.0)

var avatar: Sprite3D
var home := Vector3.ZERO             # dónde está el avatar de un jugador vivo
var pname := ""
var state := "alive"                 # alive | dead | revived
var death_type := "exploding"
var pending := 0
var busy := 0
var low := false                     # calidad baja: lápidas sin sombra, sin polvo ni brillo
var _tomb: Node3D
var _label: Label3D
var _card: Card3D
var _face_z := 0.1
var _time := 0.0
var _phase := 0.0
var _built := false


func setup(av: Sprite3D, p_home: Vector3, spot: Vector3, yaw: float, p_name: String) -> SeatGrave:
	avatar = av
	home = p_home
	position = spot
	rotation.y = yaw
	pname = p_name
	_phase = float(absi(hash(p_name)) % 628) / 100.0
	return self


## Posición del fantasma sobre la lápida (espacio de la pantalla).
func ghost_pos() -> Vector3:
	return position + Vector3(0, TOMB_H + 0.12, 0.08)


func has_tomb() -> bool:
	return _tomb != null and is_instance_valid(_tomb)


func card_node() -> Card3D:
	return _card if _card != null and is_instance_valid(_card) else null


func label_text() -> String:
	return _label.text if _label != null and is_instance_valid(_label) else ""


func tomb_casts_shadow() -> bool:
	if not has_tomb():
		return false
	for m in _meshes(_tomb):
		if (m as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return true
	return false


## Altura de la lápida sobre su sitio final (0 = ya subida; -99 = no hay lápida).
func tomb_y() -> float:
	return _tomb.position.y if has_tomb() else -99.0


func ghost_alpha() -> float:
	return avatar.modulate.a


func tint() -> Color:
	return avatar.modulate


func _process(delta: float) -> void:
	_time += delta
	if state == "dead" and busy == 0 and avatar != null:
		avatar.position = ghost_pos() + Vector3(0, sin(_time * 1.7 + _phase) * 0.035, 0)


# ------------------------------------------------------------------ estado sin animación

## Fuerza el aspecto de `want` sin animar (apertura de la pantalla, estados forzados). No hace nada si ya está así.
func snap_to(want: String, p_type: String) -> void:
	if pending > 0 or busy > 0:
		return
	if want == state and _built:
		_apply_look()
		return
	_built = true
	state = want
	death_type = p_type
	_clear_stage()
	if want == "dead":
		_build_tomb(true)
		_build_card(true)
	_apply_look()


func _apply_look() -> void:
	if avatar == null:
		return
	match state:
		"dead":
			avatar.modulate = GHOST_TINT
			avatar.rotation.z = 0.0
			avatar.position = ghost_pos()
		"revived":
			avatar.modulate = ZOMBIE_TINT
			avatar.rotation.z = 0.0
			avatar.position = home
		_:
			avatar.modulate = Color.WHITE
			avatar.rotation.z = 0.0
			avatar.position = home


func _clear_stage() -> void:
	for n: Node in [_tomb, _label, _card]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_tomb = null
	_label = null
	_card = null


# ------------------------------------------------------------------ piezas

static func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


static func _aabb_of(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var bb: AABB = t * (n as MeshInstance3D).get_aabb()
		acc[0] = bb if acc[0] == null else (acc[0] as AABB).merge(bb)
	for c in n.get_children():
		_aabb_of(c, t, acc)


func _build_tomb(done: bool) -> void:
	_clear_tomb()
	var inst: Node3D = TOMB.instantiate()
	var acc: Array = [null]
	_aabb_of(inst, Transform3D.IDENTITY, acc)
	var bb: AABB = acc[0] if acc[0] != null else AABB(Vector3(-0.5, 0, -0.2), Vector3(1, 1.4, 0.4))
	var k := TOMB_H / maxf(0.01, bb.size.y)
	inst.scale = Vector3.ONE * k
	# Base sobre la mesa y centrada en el asiento
	inst.position = Vector3(-(bb.position.x + bb.size.x / 2.0) * k, -bb.position.y * k, -(bb.position.z + bb.size.z / 2.0) * k)
	_face_z = bb.size.z * k / 2.0
	var holder := Node3D.new()
	holder.add_child(inst)
	add_child(holder)
	_tomb = holder
	for m in _meshes(holder):
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if low else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_label = Label3D.new()
	_label.text = pname
	_label.font = UIKit.TITLE_FONT
	_label.font_size = 64 if pname.length() <= 9 else 48
	_label.pixel_size = 0.0021
	_label.outline_size = 14
	_label.modulate = Color(0.93, 0.97, 0.88)
	_label.outline_modulate = Color(0.04, 0.06, 0.05)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, TOMB_H * 0.58, _face_z + 0.04)
	add_child(_label)
	# El nombre cabe en la cara de la lápida
	var lw := _label.get_aabb().size.x
	var tw := bb.size.x * k * 0.82
	if lw > tw and lw > 0.0:
		_label.pixel_size *= tw / lw
	if not done:
		holder.position.y = -TOMB_H - 0.1
		_label.modulate.a = 0.0


func _clear_tomb() -> void:
	for n: Node in [_tomb, _label]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_tomb = null
	_label = null


func _build_card(done: bool) -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = Card3D.new().setup(death_type, true)
	_card.set_pickable(false)
	add_child(_card)
	var spot := Vector3(0.0, 0.012, 0.34)
	var rot := Vector3(0.0, 0.0, 0.0)
	if done:
		_card.position = spot
		_card.rotation = rot
		_card.scale = Vector3.ONE * 0.5
	else:
		_card.position = spot + Vector3(0, 0.7, 0.1)
		_card.rotation = Vector3(0.6, 0.0, 0.0)
		_card.scale = Vector3.ONE * 0.3
		_card.fly_to(spot, rot, 0.45, 0.5)


# ------------------------------------------------------------------ muerte

## Anima la muerte: avatar al suelo, lápida, carta de muerte y fantasma. Termina al acabar la animación.
func play_die(p_type: String) -> void:
	busy += 1
	death_type = p_type
	state = "dead"
	_built = true
	var tw := avatar.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(avatar, "position", avatar.position - Vector3(0, 0.5, 0), 0.45)
	tw.tween_property(avatar, "modulate:a", 0.0, 0.4)
	await get_tree().create_timer(0.35).timeout
	if not is_inside_tree():
		busy -= 1
		pending = maxi(0, pending - 1)
		return
	_build_tomb(false)
	var rise := _tomb.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rise.tween_property(_tomb, "position:y", 0.0, 0.6)
	var lt := _label.create_tween()
	lt.tween_interval(0.45)
	lt.tween_property(_label, "modulate:a", 1.0, 0.3)
	if not low and not PlusSettings.reduce_motion():
		_dust()
	await get_tree().create_timer(0.35).timeout
	if not is_inside_tree():
		busy -= 1
		pending = maxi(0, pending - 1)
		return
	_build_card(false)
	await get_tree().create_timer(0.45).timeout
	if is_inside_tree():
		avatar.position = position + Vector3(0, TOMB_H * 0.5, 0.04)
		var gt := avatar.create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		gt.tween_property(avatar, "position", ghost_pos(), 0.7)
		gt.tween_property(avatar, "modulate", GHOST_TINT, 0.7)
		await gt.finished
	busy -= 1
	pending = maxi(0, pending - 1)


func _dust() -> void:
	var parent := get_parent()
	if parent is Node3D:
		Vfx.burst(parent as Node3D, position + Vector3(0, 0.05, 0), [Color(0.7, 0.72, 0.75, 0.0), Color(0.62, 0.64, 0.68, 0.35), Color(0.35, 0.36, 0.4, 0.2), Color(0.2, 0.2, 0.25, 0.0)], Color(0.7, 0.75, 0.8, 0.8), 0.25)


# ------------------------------------------------------------------ resurrección

func play_revive() -> void:
	while busy > 0:
		await get_tree().process_frame
	busy += 1
	state = "revived"
	_built = true
	if not has_tomb():
		# Sin lápida (se perdió el estado): solo la vuelta del avatar
		await _avatar_returns()
		busy -= 1
		pending = maxi(0, pending - 1)
		return
	# Se agrieta: tiembla, aparece una grieta verde y la lápida brilla desde dentro
	var crack := _make_crack()
	add_child(crack)
	var glow_mats: Array = []
	if not low:
		for m in _meshes(_tomb):
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			gm.albedo_color = Color(0.4, 1.0, 0.2, 0.0)
			(m as GeometryInstance3D).material_overlay = gm
			glow_mats.append(gm)
	if not PlusSettings.reduce_motion():       # el temblor de la lápida es movimiento de más
		var shake := _tomb.create_tween()
		for i in 6:
			shake.tween_property(_tomb, "rotation:z", 0.06 * (1.0 if i % 2 == 0 else -1.0), 0.05)
		shake.tween_property(_tomb, "rotation:z", 0.0, 0.05)
	for gm: StandardMaterial3D in glow_mats:
		var g := _tomb.create_tween()
		g.tween_property(gm, "albedo_color:a", 0.5, 0.35)
	await get_tree().create_timer(0.42).timeout
	if not is_inside_tree():
		busy -= 1
		pending = maxi(0, pending - 1)
		return
	# Se parte y se hunde; sale la mano
	var hand := _build_hand()
	hand.position = Vector3(0, -0.4, 0.02)
	add_child(hand)
	var sink := _tomb.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	sink.tween_property(_tomb, "position:y", -TOMB_H - 0.15, 0.55)
	sink.tween_property(_tomb, "rotation:x", 0.35, 0.55)
	var ft := crack.create_tween()
	ft.tween_interval(0.3)
	ft.tween_callback(crack.queue_free)
	var ht := hand.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ht.tween_property(hand, "position:y", 0.04, 0.45)
	for i in 3:
		ht.tween_property(hand, "rotation:z", 0.18, 0.12)
		ht.tween_property(hand, "rotation:z", -0.18, 0.12)
	ht.tween_property(hand, "rotation:z", 0.0, 0.08)
	if _label != null and is_instance_valid(_label):
		var lt := _label.create_tween()
		lt.tween_property(_label, "modulate:a", 0.0, 0.3)
	if card_node() != null:
		var ct := _card.create_tween()
		ct.tween_interval(0.5)
		ct.tween_property(_card, "scale", Vector3.ONE * 0.01, 0.3)
	await get_tree().create_timer(1.1).timeout
	if is_inside_tree():
		var down := hand.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		down.tween_property(hand, "position:y", -0.45, 0.3)
		await _avatar_returns()
	hand.queue_free()
	_clear_stage()
	busy -= 1
	pending = maxi(0, pending - 1)


func _avatar_returns() -> void:
	if not is_inside_tree():
		return
	avatar.position = position + Vector3(0, 0.1, 0.04)
	avatar.modulate = Color(ZOMBIE_TINT.r, ZOMBIE_TINT.g, ZOMBIE_TINT.b, 0.0)
	var t := avatar.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(avatar, "position", home, 0.7)
	t.tween_property(avatar, "modulate", ZOMBIE_TINT, 0.5)
	await t.finished


func _make_crack() -> MeshInstance3D:
	var pts := [Vector2(0.0, 0.92), Vector2(-0.05, 0.75), Vector2(0.04, 0.6), Vector2(-0.04, 0.45), Vector2(0.03, 0.3), Vector2(0.0, 0.12)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.014
	for i in pts.size() - 1:
		var a: Vector2 = pts[i] * Vector2(1.0, TOMB_H)
		var b: Vector2 = pts[i + 1] * Vector2(1.0, TOMB_H)
		var v: Array = [Vector3(a.x - w, a.y, 0), Vector3(a.x + w, a.y, 0), Vector3(b.x - w, b.y, 0), Vector3(b.x + w, b.y, 0)]
		for idx: int in [0, 1, 2, 2, 1, 3]:
			st.add_vertex(v[idx])
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.62, 1.0, 0.3)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.position = Vector3(0, 0, _face_z + 0.02)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Un brazo verde con mano de cuatro dedos y pulgar, hecho con formas simples.
func _build_hand() -> Node3D:
	var h := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.44, 0.72, 0.24)
	mat.roughness = 0.85
	mat.emission_enabled = not low
	mat.emission = Color(0.18, 0.5, 0.08)
	mat.emission_energy_multiplier = 0.7
	var arm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.026
	cm.bottom_radius = 0.04
	cm.height = 0.36
	cm.radial_segments = 8
	arm.mesh = cm
	arm.position = Vector3(0, 0.18, 0)
	h.add_child(arm)
	var palm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.1
	sm.radial_segments = 10
	sm.rings = 5
	palm.mesh = sm
	palm.position = Vector3(0, 0.37, 0)
	palm.scale = Vector3(1.0, 0.9, 0.6)
	h.add_child(palm)
	for i in 4:
		var f := MeshInstance3D.new()
		var fm := CapsuleMesh.new()
		fm.radius = 0.013
		fm.height = 0.12
		fm.radial_segments = 6
		fm.rings = 2
		f.mesh = fm
		var off := float(i) - 1.5
		f.position = Vector3(off * 0.028, 0.45 + (0.01 if i == 1 or i == 2 else 0.0), 0)
		f.rotation.z = -off * 0.16
		h.add_child(f)
	var th := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.014
	tm.height = 0.09
	tm.radial_segments = 6
	tm.rings = 2
	th.mesh = tm
	th.position = Vector3(0.07, 0.38, 0)
	th.rotation.z = -1.0
	h.add_child(th)
	for c in h.get_children():
		(c as GeometryInstance3D).material_override = mat
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.rotation.x = 0.35       # inclinada hacia la cámara
	return h
