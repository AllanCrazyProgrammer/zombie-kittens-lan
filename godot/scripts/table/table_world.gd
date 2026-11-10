class_name TableWorld
extends Node3D
## El escenario: mesa en un cementerio de noche. Crea ambiente, luces, niebla, decorado y cámara.
## El resto del juego solo le pide `shake()` y `flash()`.

const TABLE := preload("res://assets/models/table.glb")
const TOMB := preload("res://assets/models/tombstone.glb")
const TREE := preload("res://assets/models/tree.glb")
const LANTERN := preload("res://assets/models/lantern.glb")
const FENCE := preload("res://assets/models/fence.glb")
const EMBLEM := preload("res://assets/textures/emblem.png")
const GROUND_Y := -1.72
const CAM_POS := Vector3(0, 3.1, 4.0)
const CAM_TARGET := Vector3(0, 0, 0.55)

var camera: Camera3D
var _time: float = 0.0
var _shake: float = 0.0
var _lantern_lights: Array[OmniLight3D] = []
var _flash: ColorRect
var _env: Environment
var _moon: DirectionalLight3D
var _lamp: SpotLight3D
var _flies: GPUParticles3D


func _ready() -> void:
	_environment()
	_lights()
	_table()
	_graveyard()
	_camera()
	_overlay()
	_flies = Vfx.fireflies(self, Vector3(2.4, 0.7, 2.0))
	_flies.position = Vector3(0, 0.9, -0.2)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	apply_quality(cfg.get_value("video", "quality", "high"))


func _process(delta: float) -> void:
	_time += delta
	_shake = maxf(0.0, _shake - delta * 2.2)
	var sway := Vector3(sin(_time * 0.31) * 0.14, sin(_time * 0.47) * 0.035, 0)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * _shake * 0.22
	camera.position = CAM_POS + sway + jitter
	camera.look_at(CAM_TARGET + jitter * 0.5)
	for i in _lantern_lights.size():
		var f := 0.82 + 0.18 * sin(_time * 9.0 + i * 2.1) * sin(_time * 5.3 + i) + 0.06 * sin(_time * 23.0 + i * 5.0)
		_lantern_lights[i].light_energy = 2.6 * f


## Calidad gráfica: "high" (todo), "medium" (sin sombras de luna ni suavizado), "low" (sin sombras ni brillo, menor resolución 3D).
func apply_quality(level: String) -> void:
	var vp := get_viewport()
	_moon.shadow_enabled = level == "high"
	_lamp.shadow_enabled = level != "low"
	_env.glow_enabled = level != "low"
	_flies.amount = 46 if level == "high" else (30 if level == "medium" else 14)
	vp.msaa_3d = Viewport.MSAA_2X if level == "high" else Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = 0.75 if level == "low" else 1.0


## Desplaza la vista en vertical (pantallas menos alargadas: sube la mesa para dejar sitio a los controles).
func set_view_offset(v: float) -> void:
	camera.v_offset = v


## Sacudida de cámara (0..1) para explosiones y golpes.
func shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 1.0)


## Destello a pantalla completa.
func flash(color: Color, alpha: float = 0.7, time: float = 0.45) -> void:
	_flash.color = Color(color.r, color.g, color.b, alpha)
	var t := create_tween()
	t.tween_property(_flash, "color:a", 0.0, time).set_ease(Tween.EASE_OUT)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("140a2e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("5a4aa0")
	env.ambient_light_energy = 0.16
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color("1a0d3a")
	env.fog_density = 0.034
	env.fog_sky_affect = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _lights() -> void:
	# Luna: luz fría de contra, desde el fondo
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("9fb2ff")
	moon.light_energy = 0.9
	moon.rotation_degrees = Vector3(-38, 160, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 16.0
	moon.shadow_bias = 0.03
	add_child(moon)
	_moon = moon

	# Lámpara cálida sobre la mesa: es la luz principal y la que proyecta sombras de las cartas
	var lamp := SpotLight3D.new()
	lamp.light_color = Color("ffdca8")
	lamp.light_energy = 5.2
	lamp.spot_range = 8.0
	lamp.spot_angle = 40.0
	lamp.spot_angle_attenuation = 1.6
	lamp.shadow_enabled = true
	lamp.shadow_bias = 0.015
	lamp.shadow_blur = 1.6
	lamp.position = Vector3(0.3, 4.2, 1.0)
	add_child(lamp)
	_lamp = lamp
	lamp.look_at(Vector3(0, 0, 0.3))

	# Resplandor verde tóxico desde el cementerio
	var toxic := OmniLight3D.new()
	toxic.light_color = Color("9be22d")
	toxic.light_energy = 3.2
	toxic.omni_range = 22.0
	toxic.position = Vector3(0, 3.5, -20.0)
	add_child(toxic)


func _find_mesh(n: Node, mesh_name: String) -> MeshInstance3D:
	if n is MeshInstance3D and n.name == mesh_name:
		return n
	for c in n.get_children():
		var r := _find_mesh(c, mesh_name)
		if r:
			return r
	return null


func _noise(freq: float, as_normal: bool, seed_value: int = 1) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 512
	t.height = 512
	t.seamless = true
	t.as_normal_map = as_normal
	t.bump_strength = 6.0
	return t


func _table() -> void:
	var table := TABLE.instantiate()
	add_child(table)

	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color("16463a")
	felt.albedo_texture = _noise(0.09, false, 3)
	felt.roughness = 1.0
	felt.normal_enabled = true
	felt.normal_texture = _noise(0.5, true, 5)
	felt.normal_scale = 0.35
	felt.uv1_scale = Vector3(5, 5, 5)
	var top := _find_mesh(table, "TableTop")
	if top:
		top.set_surface_override_material(0, felt)

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("5a2f16")
	var grain := _noise(0.02, false, 9)
	wood.albedo_texture = grain
	wood.uv1_scale = Vector3(1, 14, 1)
	wood.roughness = 0.32
	wood.metallic_specular = 0.7
	wood.clearcoat_enabled = true
	wood.clearcoat = 0.6
	wood.clearcoat_roughness = 0.2
	for mesh_name: String in ["TableRim", "TableBase"]:
		var m := _find_mesh(table, mesh_name)
		if m:
			m.set_surface_override_material(0, wood)

	# Emblema bordado en el tapete
	var em := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.9, 2.9)
	em.mesh = plane
	var emat := StandardMaterial3D.new()
	emat.albedo_texture = EMBLEM
	emat.albedo_color = Color(1, 1, 1, 0.11)
	emat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	emat.roughness = 1.0
	em.material_override = emat
	em.position = Vector3(0, 0.004, -0.1)
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(em)

	# Faroles sobre la mesa, con luz parpadeante
	for p: Vector3 in [Vector3(-1.82, 0, 0.25), Vector3(1.82, 0, 0.25)]:
		var l: Node3D = LANTERN.instantiate()
		l.position = p
		l.scale = Vector3.ONE * 1.5
		add_child(l)
		var o := OmniLight3D.new()
		o.light_color = Color("ffb04a")
		o.light_energy = 2.6
		o.omni_range = 3.2
		o.position = p + Vector3(0, 0.3, 0)
		add_child(o)
		_lantern_lights.append(o)


func _graveyard() -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("10201a")
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position = Vector3(0, GROUND_Y, 0)
	add_child(ground)

	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Lápidas grandes detrás de la mesa
	for i in 11:
		var t: Node3D = TOMB.instantiate()
		var x := (float(i) - 5.0) * 2.1 + rng.randf_range(-0.5, 0.5)
		t.position = Vector3(x, GROUND_Y, -9.0 - rng.randf_range(0.0, 6.0) + absf(x) * 0.2)
		t.scale = Vector3.ONE * rng.randf_range(2.2, 3.4)
		t.rotation_degrees = Vector3(rng.randf_range(-6, 6), rng.randf_range(-25, 25), rng.randf_range(-8, 8))
		add_child(t)
	# Árboles secos al fondo
	for i in 7:
		var tr: Node3D = TREE.instantiate()
		var x := (float(i) - 3.0) * 4.4 + rng.randf_range(-1.0, 1.0)
		tr.position = Vector3(x, GROUND_Y, -17.0 - rng.randf_range(0.0, 6.0))
		tr.scale = Vector3.ONE * rng.randf_range(2.6, 3.8)
		tr.rotation_degrees.y = rng.randf_range(0, 360)
		add_child(tr)
	# Reja de hierro
	for i in 9:
		var fe: Node3D = FENCE.instantiate()
		fe.position = Vector3((float(i) - 4.0) * 4.75, GROUND_Y, -15.5)
		fe.scale = Vector3.ONE * 2.0
		add_child(fe)


func _camera() -> void:
	camera = Camera3D.new()
	# El ancho de la mesa siempre cabe, sea cual sea la proporción del teléfono
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 33
	add_child(camera)
	camera.position = CAM_POS
	camera.look_at(CAM_TARGET)


func _overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	var vig := ColorRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/vignette.gdshader")
	vig.material = sm
	layer.add_child(vig)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	layer.add_child(_flash)
