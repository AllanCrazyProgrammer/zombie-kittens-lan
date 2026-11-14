class_name PlusVfx
extends Node3D
## V-04 · Un efecto propio por carta, y V-07 · animación de robo. Cada efecto cuelga de un nodo raíz «Fx_<tipo>» que se
## libera solo al terminar (un `Tween` suyo); si algo lo dejara vivo, `_process` lo retira a los pocos segundos y lo
## cuenta en `dbg_forced` (la prueba exige que sea 0). Solo formas simples, partículas de brillo y tweens.
##
## Se suman a lo que ya hace `PlayStage` (haz y carta flotante): aquí no hay ni haz ni carta flotante, solo lo que ocurre
## al resolverse la jugada. Duran ≤ 1,2 s, no bloquean nada (todo es ajeno a la lógica y a los toques) y con calidad
## baja (`low`) pierden estelas, destellos y partículas.

const MAX_LIVE := 16               # efectos simultáneos como máximo (el resto se descarta: no sirve de nada apilar más)
const GRACE := 2.5                 # segundos de margen antes de retirar a la fuerza un efecto que no terminó
const UP := Vector3.UP

var low := false                   # calidad baja
var reduced := false               # «Reducir movimiento»: versiones breves y quietas (un resplandor que se apaga, sin trayectorias)
var scr                            # la pantalla Plus (posiciones de asientos, mazo, lápidas)
var dbg_launched := {}             # tipo -> veces lanzado
var dbg_forced := 0                # efectos que hubo que retirar a la fuerza (debe ser 0)
var dbg_dropped := 0               # efectos descartados por exceso
var dbg_glows := 0                 # destellos/estelas creados (calidad baja: muchos menos)

var _live: Array = []              # {node, kind, until}
var _time := 0.0
var _dot_mats := {}                # caché de materiales de brillo por color


func setup(screen: Node3D) -> PlusVfx:
	scr = screen
	return self


func _process(delta: float) -> void:
	_time += delta
	_prune()
	for l: Dictionary in _live.duplicate():
		if _time > float(l.until):
			dbg_forced += 1
			(l.node as Node).queue_free()
			_live.erase(l)


func _prune() -> void:
	_live = _live.filter(func(l: Dictionary) -> bool: return is_instance_valid(l.node) and not (l.node as Node).is_queued_for_deletion())


# ------------------------------------------------------------------ consulta (pruebas)

func live_count() -> int:
	_prune()
	return _live.size()


func live_kinds() -> Array:
	_prune()
	return _live.map(func(l: Dictionary) -> String: return l.kind)


func is_live(kind: String) -> bool:
	return live_kinds().has(kind)


func launched(kind: String) -> int:
	return int(dbg_launched.get(kind, 0))


## Tipos de las cartas del primer efecto vivo de ese tipo ("back" si están boca abajo) (prueba).
func faces_of(kind: String) -> Array:
	var out: Array = []
	for l: Dictionary in _live:
		if l.kind == kind and is_instance_valid(l.node):
			for c in (l.node as Node).get_children():
				if c is Card3D:
					out.append((c as Card3D).type if (c as Card3D).face_up else "back")
			break
	return out


## Hijos directos que son raíces de efecto (para comprobar que no queda nada colgando).
func roots() -> int:
	var n := 0
	for c in get_children():
		if c.has_meta("fx"):
			n += 1
	return n


# ------------------------------------------------------------------ utilidades

## Raíz de un efecto: se libera sola a los `life` segundos. Devuelve null si ya hay demasiados.
func _spawn(kind: String, life: float, parent: Node = null) -> Node3D:
	_prune()
	if _live.size() >= MAX_LIVE:
		dbg_dropped += 1
		return null
	var r := Node3D.new()
	r.name = "Fx_" + kind
	r.set_meta("fx", kind)
	(parent if parent != null else self).add_child(r)
	_live.append({"node": r, "kind": kind, "until": _time + life + GRACE})
	dbg_launched[kind] = int(dbg_launched.get(kind, 0)) + 1
	var t := r.create_tween()
	t.tween_interval(life)
	t.tween_callback(r.queue_free)
	return r


## Versión reducida de cualquier efecto: un resplandor quieto que se apaga en 0,45 s (no se mueve ni cambia de tamaño).
func calm(kind: String, at: Vector3, color: Color, size: float = 0.9) -> void:
	var r := _spawn(kind, 0.5)
	if r == null:
		return
	var g := _glow(color, size, 0.55)
	g.position = at + Vector3(0, 0.12, 0)
	r.add_child(g)
	g.create_tween().tween_property(g.mesh.material, "albedo_color:a", 0.0, 0.45)


static func _bez(a: Vector3, m: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(m, t).lerp(m.lerp(b, t), t)


func _glow(color: Color, size: float, alpha: float) -> MeshInstance3D:
	dbg_glows += 1
	var key := "%s%.2f" % [color.to_html(), alpha]
	var m: StandardMaterial3D
	if _dot_mats.has(key):
		m = _dot_mats[key]
	else:
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = Vfx.soft_dot()
		m.albedo_color = Color(color.r, color.g, color.b, alpha)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_dot_mats[key] = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _unshaded(color: Color, additive: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	return m


func _solid(color: Color, rough: float = 0.8, emit: Color = Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emit != Color.BLACK:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = 1.2
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _card(parent: Node3D, type: String, up: bool, sc: float = 0.86) -> Card3D:
	var c := Card3D.new().setup(type, up)
	c.set_pickable(false)
	c.scale = Vector3.ONE * sc
	parent.add_child(c)
	return c


## Anillo plano que crece y se desvanece a ras de la mesa.
func _ring(root: Node3D, at: Vector3, color: Color, end_scale: float, dur: float) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 40 if not low else 20
	torus.ring_segments = 4
	var mat := _unshaded(Color(color.r, color.g, color.b, 0.85))
	var ring := _mesh(torus, mat, Vector3(at.x, 0.035, at.z))
	ring.scale = Vector3(0.1, 0.3, 0.1)
	root.add_child(ring)
	var t := ring.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(ring, "scale", Vector3(end_scale, 0.3, end_scale), dur)
	t.tween_property(mat, "albedo_color:a", 0.0, dur)


## Recorre un camino de Bézier con una cabeza y una estela de destellos que la siguen (`lag` = retraso entre ellos).
func _place(t: float, items: Array, a: Vector3, m: Vector3, b: Vector3, lag: float) -> void:
	for k in items.size():
		var n: Node3D = items[k]
		var tk := t - k * lag
		n.visible = tk >= 0.0
		n.position = _bez(a, m, b, clampf(tk, 0.0, 1.0))


func _trail(root: Node3D, color: Color, a: Vector3, b: Vector3, lift: float, dur: float, size: float = 0.2) -> void:
	var m := (a + b) / 2.0 + Vector3(0, lift + a.distance_to(b) * 0.2, 0)
	var items: Array = []
	var n := 1 if low else 6
	for k in n:
		var g := _glow(color.lightened(0.15 * (1.0 - float(k) / n)), size * (1.0 - 0.1 * k), 1.0 if k == 0 else 0.7 - 0.09 * k)
		root.add_child(g)
		items.append(g)
	root.create_tween().tween_method(_place.bind(items, a, m, b, 0.045), 0.0, 1.0, dur)


func _seat(id: Variant) -> Vector3:
	return scr._pos_of(id) + Vector3(0, 0.3, 0)


func _deck_top() -> Vector3:
	return scr._deck_top()


# ------------------------------------------------------------------ Ver / Alterar el Futuro

## Las 3 cartas de arriba se levantan con brillo morado. `faces`: tipos (de arriba abajo) si quien mira las ve, o vacío = dorsos.
func future(faces: Array) -> void:
	if reduced:
		calm("future", _deck_top(), Color(0.72, 0.3, 1.0), 1.2)
		return
	var r := _spawn("future", 1.2)
	if r == null:
		return
	var base: Vector3 = _deck_top()
	var tw := r.create_tween().set_parallel(true)
	for i in 3:
		var known := faces.size() > i
		var c := _card(r, str(faces[i]) if known else "back", known)
		c.position = base + Vector3(0, 0.012 * i, 0)
		if not low:
			var g := _glow(Color(0.72, 0.3, 1.0), 1.15, 0.5)
			g.position = Vector3(0, -0.015, 0)
			c.add_child(g)
		var up_pos := base + Vector3((i - 1) * 0.36, 0.52 + 0.02 * i, 0.04)
		tw.tween_callback(c.fly_to.bind(up_pos, Vector3(0.95, (i - 1) * -0.1, 0), 0.32, 0.98)).set_delay(0.07 * i)
		tw.tween_callback(c.fly_to.bind(base + Vector3(0, 0.012 * i, 0), Vector3.ZERO, 0.28, 0.86)).set_delay(0.8 + 0.05 * i)
	if not low:
		var halo := _glow(Color(0.72, 0.3, 1.0), 1.3, 0.35)
		halo.position = base + Vector3(0, 0.3, 0)
		r.add_child(halo)


# ------------------------------------------------------------------ Barajar

func _spiral(t: float, items: Array, base: Vector3) -> void:
	var env := sin(t * PI)
	for i in items.size():
		var a := TAU * i / items.size() + t * TAU * 1.6
		var rad := env * 0.58
		var c: Node3D = items[i]
		c.position = base + Vector3(cos(a) * rad, 0.03 + env * (0.16 + 0.03 * i) + i * 0.007 * (1.0 - env), sin(a) * rad * 0.8)
		c.rotation = Vector3(0, -a, 0)


## Las cartas del mazo se abren en espiral y vuelven.
func shuffle() -> void:
	if reduced:
		calm("shuffle", _deck_top(), Color(0.35, 0.95, 0.85), 1.0)
		return
	var r := _spawn("shuffle", 1.05)
	if r == null:
		return
	var base: Vector3 = _deck_top()
	var items: Array = []
	for i in (4 if low else 7):
		var c := _card(r, "back", false, 0.7)
		if not low:
			var g := _glow(Color(0.35, 0.95, 0.85), 0.5, 0.28)
			g.position = Vector3(0, 0.02, 0)
			c.add_child(g)
		items.append(c)
	_spiral(0.0, items, base)
	r.create_tween().tween_method(_spiral.bind(items, base), 0.0, 1.0, 0.98)


# ------------------------------------------------------------------ Saltar / Súper Salto

## Estela azul del que salta hacia el siguiente; `big` (Súper Salto) lleva dos estelas y un anillo.
func skip(from_pos: Vector3, to_pos: Variant, big: bool = false) -> void:
	if reduced:
		calm("super_skip" if big else "skip", from_pos, Color(0.3, 0.62, 1.0))
		return
	var r := _spawn("super_skip" if big else "skip", 1.1)
	if r == null:
		return
	var blue := Color(0.3, 0.62, 1.0) if not big else Color(0.55, 0.45, 1.0)
	_ring(r, from_pos, blue, 0.5, 0.5)
	if to_pos is Vector3:
		_trail(r, blue, from_pos + Vector3(0, 0.3, 0), (to_pos as Vector3) + Vector3(0, 0.3, 0), 0.5, 0.85, 0.24)
		if big:
			_trail(r, blue, from_pos + Vector3(0.12, 0.2, 0.0), (to_pos as Vector3) + Vector3(-0.12, 0.2, 0.0), 0.75, 0.95, 0.18)
		var rt := r.create_tween()
		rt.tween_interval(0.8)
		rt.tween_callback(_ring.bind(r, to_pos, blue, 0.6, 0.3))


# ------------------------------------------------------------------ Favor, pareja, trío: la carta robada viaja en arco

## `face`: tipo de la carta si quien la recibe la ve (se voltea al llegar); vacío = no se ve.
func steal(from_pos: Vector3, to_pos: Vector3, face: String = "") -> void:
	if reduced:
		calm("steal", to_pos, Color(1.0, 0.45, 0.7))
		return
	var r := _spawn("steal", 1.0)
	if r == null:
		return
	var a := from_pos + Vector3(0, 0.25, 0)
	var b := to_pos + Vector3(0, 0.25, 0)
	var m := (a + b) / 2.0 + Vector3(0, 0.75 + a.distance_to(b) * 0.2, 0)
	var c := _card(r, face if face != "" else "back", false, 0.45)
	c.position = a
	r.create_tween().tween_method(_card_arc.bind(c, a, m, b), 0.0, 1.0, 0.75).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	if face != "":
		var ft := r.create_tween()
		ft.tween_interval(0.3)
		ft.tween_callback(c.flip)
	if not low:
		_trail(r, Color(1.0, 0.45, 0.7), a, b, 0.75, 0.75, 0.2)


func _card_arc(t: float, c: Node3D, a: Vector3, m: Vector3, b: Vector3) -> void:
	c.position = _bez(a, m, b, t)
	c.rotation.y = t * 3.0
	c.scale = Vector3.ONE * lerpf(0.45, 0.62, sin(t * PI))


# ------------------------------------------------------------------ Alimenta a los Muertos

func _feed_step(t: float, items: Array, from_pos: Vector3, grave_pos: Vector3) -> void:
	var w := smoothstep(0.0, 0.35, t)
	var center := grave_pos + Vector3(0, 0.34, 0.05)
	for i in items.size():
		var a := TAU * i / items.size() + t * TAU * 1.4
		var rad := lerpf(0.8, 0.03, t)
		var p := center + Vector3(cos(a) * rad, (1.0 - t) * 0.18, sin(a) * rad)
		var c: Node3D = items[i]
		c.position = (from_pos + Vector3(0, 0.25, 0)).lerp(p, w)
		c.rotation = Vector3(0, -a, 0)
		c.scale = Vector3.ONE * lerpf(0.45, 0.12, t * t)


## Las cartas vuelan en círculo hacia la lápida del muerto.
func feed(from_pos: Vector3, grave_pos: Vector3) -> void:
	if reduced:
		calm("feed", grave_pos, Color(0.65, 0.95, 0.25))
		return
	var r := _spawn("feed", 1.1)
	if r == null:
		return
	var items: Array = []
	for i in (1 if low else 3):
		var c := _card(r, "back", false, 0.45)
		if not low:
			var g := _glow(Color(0.65, 0.95, 0.25), 0.55, 0.35)
			g.position = Vector3(0, 0.02, 0)
			c.add_child(g)
		items.append(c)
	_feed_step(0.0, items, from_pos, grave_pos)
	r.create_tween().tween_method(_feed_step.bind(items, from_pos, grave_pos), 0.0, 1.0, 1.0)
	var rt := r.create_tween()
	rt.tween_interval(0.85)
	rt.tween_callback(_ring.bind(r, grave_pos, Color(0.65, 0.95, 0.25), 0.4, 0.25))


# ------------------------------------------------------------------ Cava Más Hondo / Entierro

func dig(kind: String = "dig") -> void:
	if reduced:
		calm(kind, _deck_top(), Color(0.5, 0.33, 0.16))
		return
	var r := _spawn(kind, 1.2)
	if r == null:
		return
	var base: Vector3 = _deck_top()
	var dirt := Color(0.34, 0.2, 0.1) if kind == "dig" else Color(0.2, 0.13, 0.09)
	var sph := SphereMesh.new()
	sph.radius = 0.2
	sph.height = 0.4
	sph.radial_segments = 12
	sph.rings = 6
	var mound := _mesh(sph, _solid(dirt, 0.95), base + Vector3(0, 0.0, 0.02))
	mound.scale = Vector3(0.01, 0.01, 0.01)
	r.add_child(mound)
	var mt := mound.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	mt.tween_property(mound, "scale", Vector3(1.25, 0.5, 1.0), 0.35)
	mt.tween_interval(0.45)
	mt.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	mt.tween_property(mound, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	# La pala: mango de madera y hoja de metal, se clava dos veces
	var shovel := Node3D.new()
	shovel.position = base + Vector3(0.36, 0.42, 0.12)
	shovel.rotation.z = 0.55
	var handle := _mesh(_cyl(0.011, 0.011, 0.5), _solid(Color(0.5, 0.33, 0.16)), Vector3(0, 0.27, 0))
	var blade := _mesh(_box(Vector3(0.12, 0.15, 0.014)), _solid(Color(0.62, 0.65, 0.7), 0.4), Vector3(0, -0.04, 0))
	var grip := _mesh(_box(Vector3(0.1, 0.02, 0.02)), _solid(Color(0.5, 0.33, 0.16)), Vector3(0, 0.52, 0))
	shovel.add_child(handle)
	shovel.add_child(blade)
	shovel.add_child(grip)
	shovel.scale = Vector3.ONE * 1.1
	r.add_child(shovel)
	var home := shovel.position
	var st := shovel.create_tween().set_trans(Tween.TRANS_SINE)
	for k in 2:
		st.tween_property(shovel, "position", home + Vector3(-0.2, -0.3, 0), 0.2)
		st.tween_property(shovel, "position", home + Vector3(-0.1, 0.0, 0), 0.2)
	st.tween_property(shovel, "position", home + Vector3(0.0, 0.5, 0), 0.3)
	if not low:
		for i in 6:
			var clod := _mesh(_box(Vector3(0.035, 0.03, 0.035)), _solid(dirt.darkened(0.1 * (i % 3)), 0.95), base + Vector3(0, 0.1, 0.02))
			clod.visible = false
			r.add_child(clod)
			var ang := TAU * i / 6.0
			var vel := Vector3(cos(ang) * 0.35, 1.5 + 0.2 * (i % 3), sin(ang) * 0.3)
			var ct := clod.create_tween()
			ct.tween_interval(0.25 + 0.06 * i)
			ct.tween_callback(clod.set_visible.bind(true))
			ct.tween_method(_ballistic.bind(clod, base + Vector3(0, 0.15, 0.02), vel), 0.0, 0.5, 0.5)


func _ballistic(t: float, n: Node3D, p0: Vector3, v: Vector3) -> void:
	n.position = p0 + v * t + Vector3(0, -4.9 * t * t * 2.0, 0)
	n.rotation += Vector3(0.2, 0.3, 0.1)


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 10
	m.rings = 5
	return m


# ------------------------------------------------------------------ Ladrón de Tumbas

## Manos que salen del suelo junto a la lápida. `grave`: el SeatGrave de un muerto.
func grave_hands(grave: SeatGrave) -> void:
	if grave == null:
		return
	if reduced:
		calm("grave_robber", grave.position, Color(0.55, 0.9, 0.3))
		return
	var r := _spawn("grave_robber", 1.2)
	if r == null:
		return
	for side in (1 if low else 2):
		var sgn := -1.0 if side == 0 else 1.0
		var hand: Node3D = grave._build_hand()
		hand.position = grave.position + grave.basis * Vector3(sgn * 0.24, -0.5, 0.14)
		hand.rotation.y = grave.rotation.y
		r.add_child(hand)
		var t := hand.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(hand, "position:y", 0.02, 0.35)
		for i in 2:
			t.tween_property(hand, "rotation:z", 0.2, 0.1)
			t.tween_property(hand, "rotation:z", -0.2, 0.1)
		t.tween_property(hand, "rotation:z", 0.0, 0.05)
		t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		t.tween_property(hand, "position:y", -0.5, 0.3)
	if not low:
		var halo := _glow(Color(0.55, 0.9, 0.3), 0.9, 0.3)
		halo.position = grave.position + Vector3(0, 0.15, 0.1)
		r.add_child(halo)


# ------------------------------------------------------------------ Clon

## Efecto de escaneo sobre la carta clonada (cuelga de la propia carta: la sigue mientras se mueve).
func clone_scan(card: Node3D) -> void:
	if card == null or not is_instance_valid(card):
		return
	var r := _spawn("clone", 1.0, card)
	if r == null:
		return
	var cyan := Color(0.3, 0.95, 1.0)
	if not reduced:
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.72, 0.07)
		var bar := _mesh(pm, _unshaded(Color(cyan.r, cyan.g, cyan.b, 0.95)), Vector3(0, 0.008, -0.46))
		r.add_child(bar)
		var bt := bar.create_tween().set_trans(Tween.TRANS_SINE)
		bt.tween_property(bar, "position:z", 0.46, 0.4)
		bt.tween_property(bar, "position:z", -0.46, 0.4)
	var wp := PlaneMesh.new()
	wp.size = Vector2(0.66, 0.92)
	var wm := _unshaded(Color(cyan.r, cyan.g, cyan.b, 0.0))
	var wash := _mesh(wp, wm, Vector3(0, 0.006, 0))
	r.add_child(wash)
	var wt := wash.create_tween()
	wt.tween_property(wm, "albedo_color:a", 0.3, 0.3)
	wt.tween_property(wm, "albedo_color:a", 0.0, 0.5)


# ------------------------------------------------------------------ Ataque Dirigido

## Anillo rojo y destello sobre el asiento del objetivo (los cortes en pantalla los lanza la pantalla, orientados al objetivo).
func targeted(target_pos: Vector3) -> void:
	if reduced:
		calm("targeted", target_pos, Color(1.0, 0.25, 0.15))
		return
	var r := _spawn("targeted", 0.8)
	if r == null:
		return
	var red := Color(1.0, 0.25, 0.15)
	_ring(r, target_pos, red, 0.75, 0.55)
	if not low:
		var g := _glow(red, 0.7, 0.8)
		g.position = target_pos + Vector3(0, 0.3, 0)
		r.add_child(g)
		var t := g.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(g, "scale", Vector3.ONE * 2.8, 0.5)
		t.tween_property(g.mesh.material, "albedo_color:a", 0.0, 0.5)


# ------------------------------------------------------------------ Marcha Atrás

## Un aro de flechas de color turquesa da una vuelta rápida en el nuevo sentido por encima del aro fijo del tapete.
func reverse(new_dir: int) -> void:
	if reduced:
		calm("reverse", Vector3(0, 0.05, -0.2), Color(0.2, 0.95, 0.9), 1.6)
		return
	var r := _spawn("reverse", 1.0)
	if r == null:
		return
	var holder := Node3D.new()
	holder.position = Vector3(0, 0.05, -0.2)
	r.add_child(holder)
	var mat := _unshaded(Color(0.2, 0.95, 0.9, 0.9))
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0
	torus.outer_radius = 1.04
	torus.rings = 60 if not low else 24
	torus.ring_segments = 4
	var band := _mesh(torus, mat)
	band.scale = Vector3(1, 0.08, 1)
	holder.add_child(band)
	for i in 6:
		var a := float(i) / 6.0 * TAU
		var pivot := Node3D.new()
		pivot.position = Vector3(sin(a), 0, cos(a)) * 1.02
		pivot.rotation.y = a
		var cone := _mesh(_cyl(0.0, 0.09, 0.2), mat)
		cone.rotation.z = PI / 2.0
		pivot.add_child(cone)
		holder.add_child(pivot)
	var sgn := -1.0 if new_dir >= 0 else 1.0           # el aro fijo gira en -dir; este da la vuelta al revés primero y luego en su sentido
	var t := holder.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(holder, "rotation:y", sgn * TAU * 1.25, 0.85)
	t.tween_property(holder, "scale", Vector3(1.1, 1.0, 1.1), 0.85)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.85).set_delay(0.2)


# ------------------------------------------------------------------ Ojo de Cuervo

const CROW_SCALE := 1.35
const CROW_RIM := Color(0.86, 0.8, 1.0)        # contorno claro: destaca sobre el tapete verde oscuro

## Ala derecha vista desde arriba (x hacia fuera, z negativo = delante): borde de ataque liso y dedos de plumas atrás.
const WING_PTS := [Vector2(0.0, -0.07), Vector2(0.14, -0.11), Vector2(0.30, -0.10), Vector2(0.45, 0.0), Vector2(0.38, 0.03),
		Vector2(0.40, 0.10), Vector2(0.31, 0.06), Vector2(0.30, 0.14), Vector2(0.22, 0.08), Vector2(0.19, 0.16),
		Vector2(0.11, 0.09), Vector2(0.0, 0.12)]
const TAIL_PTS := [Vector2(-0.03, 0.14), Vector2(0.03, 0.14), Vector2(0.09, 0.36), Vector2(0.045, 0.33), Vector2(0.0, 0.39),
		Vector2(-0.045, 0.33), Vector2(-0.09, 0.36)]


## Polígono plano (en XZ, a altura `y`) con la misma cara por los dos lados.
func _poly_mesh(pts: PackedVector2Array, y: float, mat: Material) -> MeshInstance3D:
	var idx := Geometry2D.triangulate_polygon(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(UP)
	for i in idx:
		st.add_vertex(Vector3(pts[i].x, y, pts[i].y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _flat_pair(pts: Array, mirror: bool, black: Material, rim: Material) -> Node3D:
	var poly := PackedVector2Array()
	for p: Vector2 in pts:
		poly.append(Vector2(-p.x if mirror else p.x, p.y))
	if mirror:
		poly.reverse()
	var holder := Node3D.new()
	var grown := Geometry2D.offset_polygon(poly, 0.022)
	if grown.size() > 0:
		holder.add_child(_poly_mesh(grown[0], -0.004, rim))
	holder.add_child(_poly_mesh(poly, 0.0, black))
	return holder


## Cuervo visto desde arriba: cuerpo ovalado, cabeza con pico y ojos claros, cola en abanico y dos alas con dedos de plumas
## (que baten), todo con un contorno claro y un halo suave detrás para que se lea sobre el tapete.
func _crow_model() -> Node3D:
	var crow := Node3D.new()
	var black := _solid(Color(0.05, 0.05, 0.09), 0.5)
	black.emission_enabled = true
	black.emission = Color(0.2, 0.17, 0.4)
	black.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rim := _unshaded(Color(CROW_RIM.r, CROW_RIM.g, CROW_RIM.b, 0.95), false)
	var rim_hull := _unshaded(Color(CROW_RIM.r, CROW_RIM.g, CROW_RIM.b, 0.95), false)
	rim_hull.cull_mode = BaseMaterial3D.CULL_FRONT
	var body := _mesh(_sphere(0.5), black)
	body.scale = Vector3(0.15, 0.1, 0.34)
	crow.add_child(body)
	var body_rim := _mesh(_sphere(0.5), rim_hull)
	body_rim.scale = Vector3(0.19, 0.14, 0.38)
	crow.add_child(body_rim)
	var head := _mesh(_sphere(0.5), black, Vector3(0, 0.025, -0.21))
	head.scale = Vector3(0.11, 0.1, 0.12)
	crow.add_child(head)
	var head_rim := _mesh(_sphere(0.5), rim_hull, Vector3(0, 0.025, -0.21))
	head_rim.scale = Vector3(0.15, 0.14, 0.16)
	crow.add_child(head_rim)
	var beak := _mesh(_cyl(0.0, 0.03, 0.12), _solid(Color(0.95, 0.62, 0.1), 0.4, Color(0.6, 0.35, 0.0)), Vector3(0, 0.02, -0.34))
	beak.rotation.x = -PI / 2.0
	crow.add_child(beak)
	for sx in [-1.0, 1.0]:
		var eye := _mesh(_sphere(0.022), _unshaded(Color(1.0, 0.97, 0.8), false), Vector3(sx * 0.045, 0.07, -0.235))
		crow.add_child(eye)
		var pupil := _mesh(_sphere(0.011), _unshaded(Color(0.05, 0.02, 0.1), false), Vector3(sx * 0.045, 0.082, -0.248))
		crow.add_child(pupil)
	var tail := _flat_pair(TAIL_PTS, false, black, rim)
	tail.position = Vector3(0, 0.0, 0.1)
	crow.add_child(tail)
	for s in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "Wing_L" if s < 0 else "Wing_R"
		pivot.position = Vector3(s * 0.05, 0.03, 0.0)
		pivot.add_child(_flat_pair(WING_PTS, s < 0, black, rim))
		crow.add_child(pivot)
	if not low:
		var halo := _glow(Color(0.72, 0.6, 1.0), 1.3, 0.3)
		halo.position = Vector3(0, -0.05, 0.05)
		crow.add_child(halo)
	crow.scale = Vector3.ONE * CROW_SCALE
	return crow


func _crow_step(t: float, crow: Node3D, a: Vector3, m: Vector3, b: Vector3) -> void:
	var p := _bez(a, m, b, t)
	var ahead := _bez(a, m, b, minf(1.0, t + 0.03)) - _bez(a, m, b, maxf(0.0, t - 0.03))
	crow.position = p
	if ahead.length() > 0.001:
		crow.basis = Basis.looking_at(ahead.normalized(), UP).scaled(Vector3.ONE * CROW_SCALE)
	var flap := sin(t * 30.0) * 0.75
	(crow.get_node("Wing_L") as Node3D).rotation.z = -flap
	(crow.get_node("Wing_R") as Node3D).rotation.z = flap


## Un cuervo cruza del jugador al objetivo.
func crow(from_pos: Vector3, to_pos: Vector3) -> void:
	if reduced:
		calm("crow", to_pos, Color(0.7, 0.4, 1.0))
		return
	var r := _spawn("crow", 1.15)
	if r == null:
		return
	var a := from_pos + Vector3(0, 0.3, 0)
	var b := to_pos + Vector3(0, 0.3, 0)
	var m := (a + b) / 2.0 + Vector3(0, 0.6 + a.distance_to(b) * 0.15, 0)
	var c := _crow_model()
	r.add_child(c)
	_crow_step(0.0, c, a, m, b)
	r.create_tween().tween_method(_crow_step.bind(c, a, m, b), 0.0, 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not low:
		_ring(r, to_pos, Color(0.7, 0.4, 1.0), 0.45, 0.4)


# ------------------------------------------------------------------ Trueque de Almas

func _swirl_step(t: float, g1: Array, g2: Array, a: Vector3, b: Vector3) -> void:
	var dir := (b - a)
	var side := dir.cross(UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	for gi in 2:
		var items: Array = g1 if gi == 0 else g2
		var from_p := a if gi == 0 else b
		var to_p := b if gi == 0 else a
		for k in items.size():
			var s := clampf(t * 1.15 - k * 0.05, 0.0, 1.0)
			var env := sin(s * PI)
			var ph := s * TAU * 2.0 + TAU * k / items.size() + (PI if gi == 1 else 0.0)
			var c: Node3D = items[k]
			c.position = from_p.lerp(to_p, s) + Vector3(0, 0.3 + env * 0.18, 0) + (side * cos(ph) + UP * sin(ph)) * 0.22 * env
			c.rotation = Vector3(ph, 0, ph * 0.5)
			c.scale = Vector3.ONE * (0.3 + 0.1 * env)


## Dos remolinos de cartas se cruzan entre la lápida y el jugador.
func swirl(a: Vector3, b: Vector3) -> void:
	if reduced:
		calm("swirl", b, Color(0.8, 0.5, 1.0))
		return
	var r := _spawn("swirl", 1.15)
	if r == null:
		return
	var groups: Array = [[], []]
	for gi in 2:
		for k in (2 if low else 5):
			var c := _card(r, "back", false, 0.3)
			if not low:
				var g := _glow(Color(0.5, 0.95, 0.9) if gi == 0 else Color(0.8, 0.5, 1.0), 0.4, 0.3)
				g.position = Vector3(0, 0.02, 0)
				c.add_child(g)
			(groups[gi] as Array).append(c)
	_swirl_step(0.0, groups[0], groups[1], a, b)
	r.create_tween().tween_method(_swirl_step.bind(groups[0], groups[1], a, b), 0.0, 1.0, 1.05)


# ------------------------------------------------------------------ Espanto

func _haunt_step(t: float, sp: Sprite3D, a: Vector3, b: Vector3, beyond: Vector3) -> void:
	sp.position = a.lerp(b, minf(1.0, t * 1.4)) if t < 0.7 else b.lerp(beyond, (t - 0.7) / 0.3)
	var fade := minf(1.0, t * 5.0) * (1.0 - smoothstep(0.8, 1.0, t))
	sp.modulate = Color(0.78, 0.7, 1.0, 0.65 * fade)
	sp.scale = Vector3.ONE * (1.0 + 0.3 * sin(t * PI))


## El fantasma del muerto atraviesa al objetivo.
func haunt(from_pos: Vector3, to_pos: Vector3, tex: Texture2D) -> void:
	if reduced:
		calm("haunt", to_pos, Color(0.6, 0.4, 1.0))
		return
	var r := _spawn("haunt", 1.1)
	if r == null:
		return
	var a := from_pos
	var b := to_pos + Vector3(0, 0.3, 0)
	var beyond := b + (b - a).normalized() * 0.6
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.pixel_size = 0.0017
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.modulate = Color(0.78, 0.7, 1.0, 0.0)
	r.add_child(sp)
	r.create_tween().tween_method(_haunt_step.bind(sp, a, b, beyond), 0.0, 1.0, 1.0)
	if not low:
		var g := _glow(Color(0.6, 0.4, 1.0), 0.8, 0.0)
		g.position = b
		var gm: StandardMaterial3D = g.mesh.material
		r.add_child(g)
		var gt := g.create_tween()
		gt.tween_interval(0.35)
		gt.tween_property(gm, "albedo_color:a", 0.7, 0.15)
		gt.tween_property(gm, "albedo_color:a", 0.0, 0.4)
		_ring(r, to_pos, Color(0.6, 0.4, 1.0), 0.5, 0.5)


# ------------------------------------------------------------------ Apocalipsis Zombi

## Los explosivos emergen del mazo y se apilan arriba (el cielo rojo de 2 s lo pone la pantalla con `world.flash`).
func apocalypse(n: int) -> void:
	if reduced:
		calm("apocalypse", _deck_top(), Color(1.0, 0.15, 0.1), 1.6)
		return
	var r := _spawn("apocalypse", 1.2)
	if r == null:
		return
	var base: Vector3 = _deck_top()
	var k := clampi(n, 1, 3 if low else 6)
	for i in k:
		var c := _card(r, "exploding", true, 0.7)
		c.position = base + Vector3(0, -0.02, 0)
		var ang := TAU * i / k + 0.4
		var out := base + Vector3(cos(ang) * 0.5, 0.45 + 0.04 * i, sin(ang) * 0.35)
		var stack := base + Vector3(0, 0.03 + 0.012 * i, 0)
		var t := r.create_tween().set_parallel(false)
		t.tween_interval(0.08 * i)
		t.tween_callback(c.fly_to.bind(out, Vector3(0.7, ang, 0), 0.3, 0.95))
		t.tween_interval(0.35)
		t.tween_callback(c.fly_to.bind(stack, Vector3.ZERO, 0.3, 0.86))
	if not low:
		var g := _glow(Color(1.0, 0.15, 0.1), 1.6, 0.45)
		g.position = base + Vector3(0, 0.3, 0)
		r.add_child(g)
		var gt := g.create_tween()
		gt.tween_property(g, "scale", Vector3.ONE * 1.6, 0.6)
		gt.tween_property(g.mesh.material, "albedo_color:a", 0.0, 0.5)
		_ring(r, base, Color(1.0, 0.2, 0.1), 1.4, 0.7)


# ------------------------------------------------------------------ V-07 · robar: del mazo a la cámara

const DRAW_VIEW := Vector3(0.0, 0.95, 1.75)

## La carta robada vuela del mazo hacia la cámara, se voltea, se queda 0,4 s en grande y entra en la mano.
## `hand_card` es la carta real (con el modelo oculto mientras tanto) y `done` se llama al terminar.
func draw_fly(type: String, from_global: Vector3, hand_card: Card3D, done: Callable) -> void:
	if reduced:
		done.call()
		return
	var r := _spawn("draw", 1.9)
	if r == null:
		done.call()
		return
	var c := _card(r, type, false, 0.6)
	c.position = to_local(from_global)
	if not low:
		var g := _glow(Color(0.71, 0.95, 0.23), 1.2, 0.3)
		g.position = Vector3(0, -0.012, 0)
		c.add_child(g)
	c.fly_to(DRAW_VIEW, Vector3(0.87, 0, 0), 0.3, 1.05)
	var t := r.create_tween()
	t.tween_interval(0.15)
	t.tween_callback(c.flip)
	t.tween_interval(0.8 + 0.4)                       # el volteo (0,8 s) y 0,4 s quieta en grande
	t.tween_callback(_draw_in.bind(c, hand_card))
	t.tween_interval(0.32)
	t.tween_callback(done)


func _draw_in(c: Card3D, hand_card: Card3D) -> void:
	if not is_instance_valid(c):
		return
	if is_instance_valid(hand_card):
		var dest := to_local(hand_card.global_position)
		c.fly_to(dest, Vector3.ZERO, 0.3, 0.86)
	else:
		c.fly_to(c.position + Vector3(0, 0.0, 0.6), c.rotation, 0.3, 0.1)


# ------------------------------------------------------------------ prueba

## Lanza el efecto `kind` con datos del tablero actual (pruebas y ráfagas).
func demo(kind: String) -> void:
	var ids: Array = scr._seats.keys()
	var a: Vector3 = scr._pos_of(ids[0]) if ids.size() > 0 else Vector3(0, 0.15, -1.4)
	var b: Vector3 = scr._pos_of(ids[1]) if ids.size() > 1 else Vector3(1.0, 0.15, -1.0)
	match kind:
		"future": future(["see_future", "skip", "cat_a"])
		"shuffle": shuffle()
		"skip": skip(a, b)
		"super_skip": skip(a, b, true)
		"steal": steal(b, Vector3(0, 0.15, 1.35), "favor")
		"dig": dig("dig")
		"bury": dig("bury")
		"feed": feed(a, b)
		"grave_robber":
			if ids.size() > 0:
				grave_hands(scr._seats[ids[0]].grave)
		"targeted": targeted(b)
		"reverse": reverse(-1)
		"crow": crow(a, b)
		"swirl": swirl(a, b)
		"haunt":
			if ids.size() > 0:
				haunt(a + Vector3(0, 0.4, 0), b, scr._seats[ids[0]].avatar.texture)
		"apocalypse": apocalypse(4)
		"clone":
			var card := Card3D.new().setup("clone", true)
			card.set_pickable(false)
			add_child(card)
			card.position = Vector3(0, 0.5, 0)
			card.rotation.x = 0.8
			clone_scan(card)
			card.get_tree().create_timer(1.2).timeout.connect(card.queue_free)
