extends Node3D
## Escena base (fase 1): mesa 3D con cartas de prueba. Sirve para validar el motor, los modelos de Blender,
## las texturas y la exportación a Android antes de portar las reglas.

const TABLE := preload("res://assets/models/table.glb")
const TOMB := preload("res://assets/models/tombstone.glb")
const TITLE_FONT := preload("res://assets/fonts/Bangers-Regular.ttf")
const DEMO_HAND := ["zombie", "nope", "attack", "see_future", "exploding"]

var _cam: Camera3D
var _time: float = 0.0
var _hint: Label


func _ready() -> void:
	_build_world()
	_build_cards()
	_build_ui()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i >= 0 and i + 1 < args.size():
		_take_shot(args[i + 1])


func _process(delta: float) -> void:
	_time += delta
	# Cámara con un vaivén suave para que la mesa se sienta viva
	_cam.position = Vector3(sin(_time * 0.35) * 0.18, 3.5 + sin(_time * 0.5) * 0.04, 3.25)
	_cam.look_at(Vector3(0, 0, 0.35))


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0619")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6a5aa8")
	env.ambient_light_energy = 0.18
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color("2a1760")
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color("cfd6ff")
	moon.light_energy = 0.85
	moon.shadow_enabled = true
	moon.shadow_bias = 0.02
	moon.shadow_normal_bias = 0.5
	moon.directional_shadow_max_distance = 14.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.rotation_degrees = Vector3(-58, 28, 0)
	add_child(moon)

	var glow := OmniLight3D.new()
	glow.light_color = Color("b6f23a")
	glow.light_energy = 0.9
	glow.omni_range = 5.0
	glow.position = Vector3(0, 1.6, -1.2)
	add_child(glow)

	# Lámpara cálida sobre la mano del jugador
	var lamp := SpotLight3D.new()
	lamp.light_color = Color("ffe2b0")
	lamp.light_energy = 5.0
	lamp.spot_range = 7.0
	lamp.spot_angle = 38.0
	lamp.shadow_enabled = true
	lamp.position = Vector3(0, 3.6, 1.6)
	lamp.rotation_degrees = Vector3(-82, 0, 0)
	add_child(lamp)

	_cam = Camera3D.new()
	# El ancho de la mesa siempre cabe, sea cual sea la proporción del teléfono
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = 31
	add_child(_cam)
	_cam.position = Vector3(0, 3.5, 3.25)
	_cam.look_at(Vector3(0, 0, 0.35))

	add_child(TABLE.instantiate())
	for p: Array in [[Vector3(-1.25, 0, -1.35), 24.0], [Vector3(1.3, 0, -1.3), -20.0]]:
		var tomb: Node3D = TOMB.instantiate()
		tomb.position = p[0]
		tomb.rotation_degrees.y = p[1]
		add_child(tomb)


func _build_cards() -> void:
	# Mano abierta en abanico frente al jugador
	var n := DEMO_HAND.size()
	for i in n:
		var k := float(i) - (n - 1) / 2.0
		var c := Card3D.new().setup(DEMO_HAND[i])
		c.position = Vector3(k * 0.43, 0.02 + i * 0.008, 1.15 + absf(k) * 0.06)
		c.rotation_degrees.y = -k * 6.0
		c.tapped.connect(_on_card_tapped)
		add_child(c)
	# Mazo boca abajo y pila de descarte
	for i in 14:
		var d := Card3D.new().setup("cat_a", false)
		d.position = Vector3(-0.5, 0.01 + i * 0.007, -0.25)
		d.rotation_degrees.y = randf_range(-3.0, 3.0)
		d.tapped.connect(_on_card_tapped)
		add_child(d)
	var top := Card3D.new().setup("skip")
	top.position = Vector3(0.5, 0.012, -0.25)
	top.rotation_degrees.y = -8
	top.tapped.connect(_on_card_tapped)
	add_child(top)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "ZOMBIE KITTENS"
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 120)
	title.add_theme_color_override("font_color", Color("b6f23a"))
	title.add_theme_color_override("font_outline_color", Color("0d0820"))
	title.add_theme_constant_override("outline_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 90
	layer.add_child(title)

	_hint = Label.new()
	_hint.text = "Toca una carta para voltearla"
	_hint.add_theme_font_size_override("font_size", 44)
	_hint.add_theme_color_override("font_color", Color("f4efff"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -210
	_hint.offset_bottom = -150
	layer.add_child(_hint)

	var ver := Label.new()
	ver.text = "Godot · v%s" % ProjectSettings.get_setting("application/config/version")
	ver.add_theme_font_size_override("font_size", 30)
	ver.add_theme_color_override("font_color", Color("b3a6dc"))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	ver.offset_top = -110
	ver.offset_bottom = -70
	layer.add_child(ver)


func _on_card_tapped(card: Card3D) -> void:
	card.flip()
	_hint.text = CardDB.display_name(card.type) if not card.face_up else "…"
	await get_tree().create_timer(0.45).timeout
	_hint.text = CardDB.display_name(card.type) if card.face_up else "Carta boca abajo"


func _take_shot(path: String) -> void:
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
