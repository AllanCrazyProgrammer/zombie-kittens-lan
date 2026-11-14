class_name PlusAmbient
extends Node3D
## V-09 · Ambiente de Plus: niebla baja que se desliza por el cementerio, relámpago de fondo ocasional con riesgo alto,
## luna distinta en cada partida y tapete elegible (recoloreado por código). Solo existe en la pantalla Plus; al salir
## devuelve el tapete, la luna y el cielo a su valor normal para que la pantalla clásica no note nada.
##
## Respeta la calidad gráfica (alta: 3 capas de niebla, media: 2, baja: ninguna) y «Reducir movimiento»
## (niebla quieta y sin relámpagos).

const FOG_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(0.5, 0.56, 0.78, 1.0);
uniform float density = 0.4;
uniform float speed = 0.012;
uniform vec2 dir = vec2(1.0, 0.3);
uniform float scale = 3.0;
void fragment() {
	vec2 uv = UV * vec2(scale * 1.4, scale * 0.6) + dir * TIME * speed;
	float n = texture(noise_tex, uv).r * 0.65 + texture(noise_tex, uv * 2.3 - dir * TIME * speed * 1.7).r * 0.35;
	float a = smoothstep(0.38, 0.85, n);
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.22, min(e.x * 1.4, e.y * 2.2));
	ALBEDO = tint.rgb;
	ALPHA = a * edge * density;
}
"""

const GROUND_Y := -1.72
const MIN_GAP := 12.0              # segundos mínimos entre dos relámpagos
const RISK_AT := 50                # % de riesgo desde el que cae algún relámpago
const MATS := {"verde": Color("16463a"), "burdeos": Color("4f1526"), "azul": Color("17305c")}
const MOONS := [
	[Color("9fb2ff"), Vector3(-38, 160, 0)],
	[Color("bfe6ff"), Vector3(-33, 172, 0)],
	[Color("c7b0ff"), Vector3(-44, 148, 0)],
	[Color("ffe2bd"), Vector3(-36, 180, 0)],
	[Color("a9ffe3"), Vector3(-41, 154, 0)],
]

var world: TableWorld
var low := false
var reduced := false
var risk := 0
var dbg_risk := -1                 # prueba: riesgo forzado (-1 = el real)
var dbg_bolts := 0                 # relámpagos lanzados
var moon_index := 0
static var _last_moon := -1        # la luna de la partida anterior: dos partidas seguidas nunca repiten
static var _live := 0              # pantallas Plus vivas: en una revancha la nueva nace antes de que muera la vieja

var _layers: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _noise: NoiseTexture2D
var _since := 99.0                 # segundos desde el último relámpago
var _next := 0.0
var _armed := false


func setup(p_world: TableWorld) -> PlusAmbient:
	world = p_world
	return self


func _ready() -> void:
	_live += 1
	apply_mat(PlusSettings.mat())
	pick_moon(next_moon())
	_build_fog()


func _exit_tree() -> void:
	_live -= 1
	if _live > 0:
		return            # otra pantalla Plus ya tomó el relevo (revancha): no se le pisa el tapete ni la luna
	if is_instance_valid(world):
		world.sway_scale = 1.0
		world.set_felt_color(MATS["verde"])
		world.set_moon(TableWorld.MOON_DEFAULT_COLOR, TableWorld.MOON_DEFAULT_ROT)
		world.lightning_reset()


## Tapete elegido en Ajustes.
func apply_mat(name: String) -> void:
	if is_instance_valid(world):
		world.set_felt_color(MATS.get(name, MATS["verde"]))


## Luna de esta partida: siempre distinta de la anterior.
static func next_moon() -> int:
	var i := (maxi(0, _last_moon) + 1 + randi() % (MOONS.size() - 1)) % MOONS.size() if _last_moon >= 0 else randi() % MOONS.size()
	_last_moon = i
	return i


func pick_moon(i: int) -> void:
	moon_index = clampi(i, 0, MOONS.size() - 1)
	if is_instance_valid(world):
		world.set_moon(MOONS[moon_index][0], MOONS[moon_index][1])


func _build_fog() -> void:
	for l in _layers:
		l.queue_free()
	_layers.clear()
	_mats.clear()
	var n := 0 if low else 3
	if n == 0:
		return
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.seed = 4
		fn.frequency = 0.012
		fn.fractal_octaves = 4
		_noise = NoiseTexture2D.new()
		_noise.noise = fn
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
	var sh := Shader.new()
	sh.code = FOG_SHADER
	var specs := [
		{"y": GROUND_Y + 0.22, "z": -7.5, "w": 40.0, "d": 12.0, "den": 0.34, "dir": Vector2(1.0, 0.25), "sp": 0.010},
		{"y": GROUND_Y + 0.62, "z": -10.5, "w": 52.0, "d": 12.0, "den": 0.28, "dir": Vector2(-0.8, 0.4), "sp": 0.008},
		{"y": GROUND_Y + 1.05, "z": -13.5, "w": 64.0, "d": 12.0, "den": 0.22, "dir": Vector2(0.6, -0.3), "sp": 0.006},
	]
	for i in n:
		var sp: Dictionary = specs[i]
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("noise_tex", _noise)
		m.set_shader_parameter("density", sp.den)
		m.set_shader_parameter("dir", sp.dir)
		m.set_shader_parameter("speed", 0.0 if reduced else sp.sp)
		m.set_shader_parameter("scale", 2.0 + i * 0.5)
		var q := QuadMesh.new()
		q.size = Vector2(sp.w, sp.d)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.rotation_degrees = Vector3(-90, 0, 0)
		mi.position = Vector3(0, sp.y, sp.z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_layers.append(mi)
		_mats.append(m)


func fog_layers() -> int:
	return _layers.size()


## Vuelve a construir lo que depende de la calidad gráfica o de «Reducir movimiento».
func refresh(p_low: bool, p_reduced: bool) -> void:
	var rebuild := p_low != low
	low = p_low
	reduced = p_reduced
	if is_instance_valid(world):
		world.sway_scale = 0.0 if reduced else 1.0         # cámara quieta con «Reducir movimiento»
	if rebuild:
		_build_fog()
	var speeds := [0.010, 0.008, 0.006]
	for i in _mats.size():
		_mats[i].set_shader_parameter("speed", 0.0 if reduced else speeds[i])


func fog_speed() -> float:
	return float(_mats[0].get_shader_parameter("speed")) if not _mats.is_empty() else -1.0


func set_risk(pct: int) -> void:
	risk = pct


func shown_risk() -> int:
	return dbg_risk if dbg_risk >= 0 else risk


## Relámpago ahora mismo (false si «Reducir movimiento» lo impide).
func bolt() -> bool:
	if reduced or not is_instance_valid(world):
		return false
	world.lightning()
	dbg_bolts += 1
	_since = 0.0
	return true


func _process(delta: float) -> void:
	_since += delta
	var r := shown_risk()
	if r > RISK_AT and not reduced:
		if not _armed:
			_armed = true
			_next = randf_range(1.5, 4.0)
		_next -= delta
		if _next <= 0.0 and _since >= MIN_GAP:
			bolt()
			_next = randf_range(MIN_GAP + 0.5, MIN_GAP + 8.0)
	else:
		_armed = false
