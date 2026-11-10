class_name Vfx
extends RefCounted
## Efectos de partículas reutilizables. Cada función crea el efecto, lo añade a `parent` y se limpia solo.

static var _soft: Texture2D


static func soft_dot() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft = t
	return _soft


static func _quad(additive: bool, size: float) -> QuadMesh:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = soft_dot()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	return q


static func _ramp(colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / maxf(1.0, colors.size() - 1))
		cols.append(colors[i])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _emitter(amount: int, life: float, mesh: QuadMesh, pm: ParticleProcessMaterial, one_shot: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.95 if one_shot else 0.0
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Luciérnagas / motas verdes flotando sobre la mesa (efecto continuo).
static func fireflies(parent: Node3D, extents: Vector3, amount: int = 46) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.gravity = Vector3(0, 0.02, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 2.2
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color_ramp = _ramp([Color(0.7, 1.0, 0.25, 0.0), Color(0.75, 1.0, 0.3, 0.9), Color(0.6, 1.0, 0.3, 0.7), Color(0.6, 1.0, 0.3, 0.0)])
	var p := _emitter(amount, 6.0, _quad(true, 0.045), pm, false)
	p.preprocess = 6.0
	p.visibility_aabb = AABB(-extents * 1.5, extents * 3.0)
	parent.add_child(p)
	return p


## Estallido: fuego + chispas + humo. `tint` permite la versión verde (zombi).
static func burst(parent: Node3D, at: Vector3, fire: Array, sparks: Color, power: float = 1.0) -> void:
	var root := Node3D.new()
	root.position = at
	parent.add_child(root)

	var f := ParticleProcessMaterial.new()
	f.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	f.emission_sphere_radius = 0.08
	f.direction = Vector3(0, 1, 0)
	f.spread = 75.0
	f.initial_velocity_min = 0.8 * power
	f.initial_velocity_max = 2.6 * power
	f.gravity = Vector3(0, 0.6, 0)
	f.damping_min = 1.2
	f.damping_max = 2.4
	f.scale_min = 0.6
	f.scale_max = 1.6
	f.color_ramp = _ramp(fire)
	var fe := _emitter(int(70 * power), 0.9, _quad(true, 0.4), f, true)
	root.add_child(fe)

	var s := ParticleProcessMaterial.new()
	s.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = 0.05
	s.direction = Vector3(0, 1, 0)
	s.spread = 110.0
	s.initial_velocity_min = 2.0 * power
	s.initial_velocity_max = 6.0 * power
	s.gravity = Vector3(0, -7.0, 0)
	s.scale_min = 0.5
	s.scale_max = 1.2
	s.color_ramp = _ramp([sparks, sparks, Color(sparks.r, sparks.g, sparks.b, 0.0)])
	var se := _emitter(int(90 * power), 1.1, _quad(true, 0.05), s, true)
	root.add_child(se)

	var k := ParticleProcessMaterial.new()
	k.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	k.emission_sphere_radius = 0.15
	k.direction = Vector3(0, 1, 0)
	k.spread = 50.0
	k.initial_velocity_min = 0.3
	k.initial_velocity_max = 1.1
	k.gravity = Vector3(0, 0.5, 0)
	k.scale_min = 1.0
	k.scale_max = 2.4
	k.color_ramp = _ramp([Color(0.05, 0.04, 0.08, 0.0), Color(0.07, 0.06, 0.1, 0.55), Color(0.1, 0.09, 0.14, 0.0)])
	var ke := _emitter(int(26 * power), 2.0, _quad(false, 0.7), k, true)
	root.add_child(ke)

	var light := OmniLight3D.new()
	light.light_color = fire[1] if fire.size() > 1 else Color.WHITE
	light.light_energy = 14.0 * power
	light.omni_range = 6.0
	light.position = Vector3(0, 0.4, 0)
	root.add_child(light)
	for e: GPUParticles3D in [fe, se, ke]:
		e.emitting = true
	var tw := root.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(2.0)
	tw.tween_callback(root.queue_free)


static func explosion(parent: Node3D, at: Vector3) -> void:
	burst(parent, at, [Color(1, 1, 0.8, 0.5), Color(1, 0.75, 0.15, 0.45), Color(1, 0.3, 0.05, 0.35), Color(0.4, 0.05, 0.0, 0.0)], Color(1, 0.8, 0.3, 1), 1.3)


static func zombie_rise(parent: Node3D, at: Vector3) -> void:
	burst(parent, at, [Color(0.9, 1, 0.6, 0.5), Color(0.6, 1, 0.2, 0.45), Color(0.2, 0.7, 0.1, 0.35), Color(0.0, 0.2, 0.0, 0.0)], Color(0.75, 1, 0.3, 1), 0.9)
