class_name AvatarMood
extends RefCounted
## V-08 · Avatares con expresión. Calcula, para cada asiento, cuánto se desvía su Sprite3D de la pose normal
## (escala, desplazamiento y «giro» como estrechamiento horizontal: el sprite siempre mira a la cámara, así que
## girar el nodo no se vería). La pantalla suma ese desvío cada cuadro; este objeto no toca ningún nodo.
##
## Poses: «scare» (se encoge y tiembla), «cheer» (saltito con un giro), «nod» (cabeceo al empezar su turno),
## «jump» (salto largo, Saltar / Súper Salto).

const NEUTRAL := {"sx": 1.0, "sy": 1.0, "dx": 0.0, "dy": 0.0}
const DURATIONS := {"scare": 0.85, "cheer": 0.75, "nod": 0.5, "jump": 0.6}

var _t0 := {}              # id -> {kind, at}
var dbg_count := {}        # tipo de pose -> veces lanzada (prueba)
var _now := 0.0
var reduced := false       # «Reducir movimiento»: los avatares no hacen poses


## Avanza el reloj interno.
func tick(delta: float) -> void:
	_now += delta
	for id: String in _t0.keys():
		if _now - float(_t0[id].at) > float(DURATIONS[_t0[id].kind]):
			_t0.erase(id)


func trigger(id: String, kind: String) -> void:
	if reduced or not DURATIONS.has(kind):
		return
	_t0[id] = {"kind": kind, "at": _now}
	dbg_count[kind] = int(dbg_count.get(kind, 0)) + 1


func kind_of(id: String) -> String:
	return str(_t0[id].kind) if _t0.has(id) else ""


func active() -> int:
	return _t0.size()


## Desvío actual: {sx, sy, dx, dy}. Sin pose en curso devuelve la pose neutra (1, 1, 0, 0).
func sample(id: String) -> Dictionary:
	var out := {"sx": 1.0, "sy": 1.0, "dx": 0.0, "dy": 0.0}
	if not _t0.has(id):
		return out
	var kind: String = _t0[id].kind
	var t := clampf((_now - float(_t0[id].at)) / float(DURATIONS[kind]), 0.0, 1.0)
	match kind:
		"scare":
			var k := minf(1.0, t * 6.0) * (1.0 - smoothstep(0.7, 1.0, t))      # entra deprisa, sale despacio
			out.sx = 1.0 - 0.28 * k
			out.sy = 1.0 - 0.28 * k
			out.dx = sin(t * 95.0) * 0.022 * k
			out.dy = -0.03 * k
		"cheer":
			var hop := absf(sin(t * PI * 2.0)) * (1.0 - t * 0.5)
			out.dy = hop * 0.13
			out.sy = 1.0 + 0.1 * hop - 0.08 * (1.0 - hop) * (1.0 - t)
			out.sx = lerpf(1.0, absf(cos(t * PI * 2.0)) * 0.7 + 0.3, 1.0 - smoothstep(0.6, 0.85, t))      # el giro: se estrecha y se ensancha
		"nod":
			var k2 := sin(t * PI * 2.0) * (1.0 - t)
			out.dy = -0.035 * absf(k2)
			out.sy = 1.0 - 0.1 * absf(k2)
			out.dx = 0.012 * k2
		"jump":
			out.dy = sin(t * PI) * 0.26
			out.sy = 1.0 + 0.1 * sin(t * PI)
			out.sx = 1.0 - 0.06 * sin(t * PI)
	return out
