extends Node3D
## Escena de demostración: mesa 3D con cartas de prueba. Valida motor, modelos, materiales y efectos
## antes de portar las reglas. Tocar una carta la voltea; el Gatito Explosivo y el Zombi tienen su efecto.

const TITLE_FONT := preload("res://assets/fonts/Bangers-Regular.ttf")
const DEMO_HAND := ["zombie", "nope", "attack", "see_future", "exploding"]

var _world: TableWorld
var _hint: Label
var _hand: Array[Card3D] = []
var _time: float = 0.0


func _ready() -> void:
	_world = TableWorld.new()
	add_child(_world)
	_build_cards()
	_build_ui()
	# Compila los shaders de partículas al arrancar (lejos de la vista) para que la primera explosión no dé un tirón
	Vfx.explosion(self, Vector3(0, -60, 0))
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i >= 0 and i + 1 < args.size():
		_take_shot(args[i + 1], args.has("--boom"))


func _process(delta: float) -> void:
	_time += delta
	# La mano "respira": cada carta flota un poco, desfasada de las demás
	for i in _hand.size():
		_hand[i].position.y = 0.03 + i * 0.008 + sin(_time * 1.6 + i * 0.9) * 0.004


func _add_card(type: String, up: bool, pos: Vector3, yaw: float) -> Card3D:
	var c := Card3D.new().setup(type, up)
	c.position = pos
	c.rotation_degrees.y = yaw
	c.tapped.connect(_on_card_tapped)
	add_child(c)
	return c


func _build_cards() -> void:
	var n := DEMO_HAND.size()
	for i in n:
		var k := float(i) - (n - 1) / 2.0
		var c := _add_card(DEMO_HAND[i], true, Vector3(k * 0.4, 0.03 + i * 0.008, 1.3 + absf(k) * 0.07), -k * 7.0)
		c.scale = Vector3.ONE * 0.9
		c.rotation_degrees.x = 7.0
		_hand.append(c)
	for i in 14:
		_add_card("cat_a", false, Vector3(-0.5, 0.01 + i * 0.007, -0.3), randf_range(-3.0, 3.0))
	_add_card("attack_dead", true, Vector3(0.47, 0.012, -0.32), 14)
	_add_card("skip", true, Vector3(0.52, 0.02, -0.28), -8)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var title := Label.new()
	title.text = "ZOMBIE KITTENS"
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 124)
	title.add_theme_color_override("font_color", Color("b6f23a"))
	title.add_theme_color_override("font_outline_color", Color("0d0820"))
	title.add_theme_constant_override("outline_size", 30)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 100
	layer.add_child(title)

	_hint = Label.new()
	_hint.text = "Toca una carta"
	_hint.add_theme_font_override("font", TITLE_FONT)
	_hint.add_theme_font_size_override("font_size", 54)
	_hint.add_theme_color_override("font_color", Color("f4efff"))
	_hint.add_theme_color_override("font_outline_color", Color("0d0820"))
	_hint.add_theme_constant_override("outline_size", 16)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -230
	_hint.offset_bottom = -160
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
	if card.face_up and card.type == "exploding":
		_explode(card)
		return
	if card.face_up and card.type == "zombie":
		Vfx.zombie_rise(self, card.global_position + Vector3(0, 0.1, 0))
		_world.flash(Color("b6f23a"), 0.35)
		_world.shake(0.35)
		_hint.text = "¡Gatito Zombi!"
		return
	card.flip()
	await get_tree().create_timer(0.45).timeout
	_hint.text = CardDB.display_name(card.type) if card.face_up else "Carta boca abajo"


func _explode(card: Card3D) -> void:
	_hint.text = "¡BOOM!"
	Vfx.explosion(self, card.global_position + Vector3(0, 0.1, 0))
	_world.flash(Color("ffd9a0"), 0.8)
	_world.shake(1.0)
	Input.vibrate_handheld(250)


func _take_shot(path: String, boom: bool) -> void:
	await get_tree().create_timer(1.5).timeout
	if boom:
		_explode(_hand[4])
		for _i in 14:
			await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
