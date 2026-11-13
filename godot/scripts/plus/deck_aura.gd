class_name DeckAura
extends Node3D
## V-05 · Mazo vivo. Con riesgo de robar > 30 % el mazo echa humo leve; con > 50 % tiembla cada pocos segundos y la
## luz de turno de la pantalla (y una luz roja propia sobre el mazo) vira a rojo. También da la altura del mazo: el
## número de modelos se limita (la pantalla pone 14), pero la altura crece con las cartas reales.
##
## No toca el mundo: la pantalla le pasa su luz de turno y sus cartas del mazo. En calidad baja no hay humo ni luz extra.

const SMOKE_AT := 30
const SHAKE_AT := 50
const RED := Color(1.0, 0.16, 0.1)
const STEP_BASE := 0.007            # separación entre modelos con 14 cartas o menos
const MODELS := 14

var low := false
var risk := 0                       # % de riesgo de robar (0..100)
var turn_light: OmniLight3D         # la luz de turno de la pantalla (se tiñe)
var base_color := Color.WHITE       # su color normal
var cards: Array = []               # modelos del mazo (Card3D) que tiemblan
var dbg_tremors := 0                # prueba: temblores lanzados
var dbg_forced := -1                # prueba: riesgo forzado (-1 = el real)

var _smoke: GPUParticles3D
var _red: OmniLight3D
var _next_shake := 2.5
var _time := 0.0
var _tween: Tween
var _tint := 0.0                    # 0..1 cuánto ha virado a rojo


func setup(deck_pos: Vector3) -> DeckAura:
	position = deck_pos
	_red = OmniLight3D.new()
	_red.light_color = RED
	_red.light_energy = 0.0
	_red.omni_range = 1.8
	_red.position = Vector3(0, 0.55, 0.1)
	_red.visible = false
	add_child(_red)
	return self


## Altura de cada hueco entre modelos para `n` cartas reales mostradas con `models` modelos.
## Hasta 14 cartas se queda como siempre; por encima la pila crece (3,5 mm por carta de más) repartida en los modelos.
static func step_for(n: int, models: int) -> float:
	if models <= 0:
		return STEP_BASE
	var total := float(models) * STEP_BASE + maxf(0.0, float(n - MODELS)) * 0.0035
	return total / float(models)


func set_risk(pct: int) -> void:
	risk = pct


func shown_risk() -> int:
	return dbg_forced if dbg_forced >= 0 else risk


func smoking() -> bool:
	return _smoke != null and is_instance_valid(_smoke) and _smoke.emitting


func red_energy() -> float:
	return _red.light_energy if _red.visible else 0.0


func tint_amount() -> float:
	return _tint


func _make_smoke() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.22, 0.01, 0.3)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.06
	pm.initial_velocity_max = 0.14
	pm.gravity = Vector3(0, 0.03, 0)
	pm.damping_min = 0.1
	pm.damping_max = 0.2
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.3
	pm.color_ramp = Vfx._ramp([Color(0.55, 0.62, 0.5, 0.0), Color(0.55, 0.62, 0.5, 0.2), Color(0.35, 0.4, 0.35, 0.0)])
	_smoke = Vfx._emitter(14, 2.6, Vfx._quad(false, 0.42), pm, false)
	_smoke.position = Vector3(0, 0.12, 0)
	_smoke.visibility_aabb = AABB(Vector3(-1, -0.3, -1), Vector3(2, 2, 2))
	_smoke.emitting = false
	add_child(_smoke)


func _process(delta: float) -> void:
	_time += delta
	var r := shown_risk()
	# Humo leve
	var want_smoke := r > SMOKE_AT and not low
	if want_smoke and _smoke == null:
		_make_smoke()
	if _smoke != null and is_instance_valid(_smoke):
		if want_smoke != _smoke.emitting:
			_smoke.emitting = want_smoke
		_smoke.amount_ratio = 1.0 if r > SHAKE_AT else 0.5
	elif not want_smoke and _smoke != null:
		_smoke = null
	# Luz que vira a rojo
	var goal := clampf(float(r - SHAKE_AT) / 30.0, 0.0, 1.0) if r > SHAKE_AT else 0.0
	_tint = move_toward(_tint, goal, delta * 1.4)
	if turn_light != null and is_instance_valid(turn_light):
		turn_light.light_color = base_color.lerp(RED, _tint)
	var pulse := 0.8 + 0.2 * sin(_time * 5.0)
	_red.visible = _tint > 0.01 and not low
	_red.light_energy = 1.7 * _tint * pulse
	# Temblor cada pocos segundos
	if r > SHAKE_AT:
		_next_shake -= delta
		if _next_shake <= 0.0:
			_next_shake = randf_range(2.6, 4.2)
			tremble()
	else:
		_next_shake = minf(_next_shake, 2.5)


## Sacudida breve de las cartas del mazo (no desplaza el mazo: cada carta vuelve exactamente a su sitio).
func tremble() -> void:
	if trembling() or cards.is_empty():
		return
	dbg_tremors += 1
	var homes: Array = []
	for c: Card3D in cards:
		homes.append(c.position)
	_tween = create_tween()
	_tween.tween_method(func(k: float) -> void:
		for i in mini(cards.size(), homes.size()):
			var c: Card3D = cards[i]
			if is_instance_valid(c):
				var a := 1.0 - k
				c.position = (homes[i] as Vector3) + Vector3(sin(k * 70.0 + i * 1.7) * 0.012 * a, 0, cos(k * 83.0 + i) * 0.009 * a),
		0.0, 1.0, 0.45)
	_tween.tween_callback(func() -> void:
		for i in mini(cards.size(), homes.size()):
			if is_instance_valid(cards[i]):
				(cards[i] as Card3D).position = homes[i])


func trembling() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


func cancel_tremble() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
