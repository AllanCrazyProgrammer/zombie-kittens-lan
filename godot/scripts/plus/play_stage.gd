class_name PlayStage
extends Node3D
## V-02 · Carta jugada en escena. Mientras una jugada espera en la pila, sus cartas (una, o 2-3 en abanico si es un
## combo) flotan sobre el centro de la mesa, inclinadas hacia la cámara, a ~×1,4 de la mano. Si la jugada tiene
## objetivo, un haz del color de la carta une los asientos. Si la anulan, la carta se parte en dos mitades con un
## sello «NOP»; si otro Nop la restaura, se recompone con un destello verde.
##
## No es dueña de las cartas: son hijas de la pantalla y solo se las mueve (`fly_to`). Lo que sí crea (haz, halo,
## mitades, sello) cuelga de ella o de la propia carta, así que `queue_free` de cualquiera lo limpia todo.
## `low` (calidad baja) quita partículas, halos y destellos: la carta, el haz plano y la rotura quedan.

const CENTER := Vector3(0.0, 0.5, 0.02)
const TILT := 0.8                    # rad: inclinación hacia la cámara (la mesa se ve desde arriba y de frente)
const FLOAT_SCALE := 1.2             # la mano usa 0.86; ×1,4
const RISE_T := 0.4
const RED := Color(0.95, 0.12, 0.2)

const HALF_SHADER := """
shader_type spatial;
// Mitad de una carta rota: la misma textura recortada por una línea de rasgado irregular.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float side = 1.0;
float tear(vec2 uv) {
	return (uv.x - 0.5) + (uv.y - 0.5) * 0.28 + 0.03 * sin(uv.y * 26.0) + 0.018 * sin(uv.y * 71.0 + 1.7);
}
void fragment() {
	float f = tear(UV) * side;
	if (f < 0.0) { discard; }
	ALBEDO = texture(albedo_tex, UV).rgb;
	ROUGHNESS = 0.55;
	EMISSION = vec3(0.95, 0.9, 0.75) * smoothstep(0.02, 0.0, f) * 0.6;
}
"""

static var _half_shader: Shader

var low := false                     # calidad baja: sin partículas ni brillos
var _plays: Dictionary = {}          # id de la jugada -> {cards, color, broken, by, target, beam, halo, stamp, halves, tweens}
var _sparks: Array = []
var _unbreaks: Array = []        # cartas rotas que ya caen al descarte: al posarse vuelven enteras
var _time := 0.0
var dbg_breaks := 0
var dbg_restores := 0


func _process(delta: float) -> void:
	_time += delta
	for u: Dictionary in _unbreaks.duplicate():
		if _time >= float(u.at) or not is_instance_valid(u.card):
			_unbreaks.erase(u)
			_unbreak_card(u.card, u.play)
	if _sparks.is_empty():
		return
	var keep: Array = []
	for sp: Dictionary in _sparks:
		if is_instance_valid(sp.node):
			(sp.node as Node3D).position = _bezier(sp.a, sp.mid, sp.b, fposmod(_time * 1.15 + float(sp.phase), 1.0))
			keep.append(sp)
	_sparks = keep


# ------------------------------------------------------------------ consulta

func play_count() -> int:
	return _plays.size()


func has_play(sid: int) -> bool:
	return _plays.has(sid)


## Ids de las cartas que flotan ahora mismo.
func held_ids() -> Dictionary:
	var out := {}
	for sid: int in _plays:
		for c: Card3D in _plays[sid].cards:
			out[c.card_id] = true
	return out


func holds(card_id: String) -> bool:
	return held_ids().has(card_id)


## Dónde se coloca un Nop que vuela hacia la carta anulada (arriba de la pila).
func nop_target() -> Vector3:
	return CENTER + Vector3(0.52, 0.12, 0.1)


func is_broken(sid: int) -> bool:
	return _plays.has(sid) and _plays[sid].broken


func half_count() -> int:
	var n := 0
	for sid: int in _plays:
		n += (_plays[sid].halves as Array).size()
	return n


func has_stamp(sid: int) -> bool:
	return _plays.has(sid) and _plays[sid].stamp != null and is_instance_valid(_plays[sid].stamp)


func has_beam(sid: int) -> bool:
	return _plays.has(sid) and _plays[sid].beam != null and is_instance_valid(_plays[sid].beam)


## Número de mallas del haz (1 en calidad baja; más con brillo y chispas).
func beam_parts(sid: int) -> int:
	if not has_beam(sid):
		return 0
	return (_plays[sid].beam as Node3D).get_child_count() + 1


func has_halo(sid: int) -> bool:
	return _plays.has(sid) and _plays[sid].halo != null and is_instance_valid(_plays[sid].halo)


func color_of(sid: int) -> Color:
	return _plays[sid].color if _plays.has(sid) else Color.BLACK


## Color del tubo central del haz (para comprobar que es el de la carta).
func beam_color(sid: int) -> Color:
	if not has_beam(sid):
		return Color.BLACK
	var c: Color = ((_plays[sid].beam as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	return Color(c.r, c.g, c.b)


func ids() -> Array:
	return _plays.keys()


## Todas las cartas flotantes, de la jugada más antigua a la más reciente.
func cards_of(sid: int) -> Array:
	return (_plays[sid].cards as Array).duplicate() if _plays.has(sid) else []


# ------------------------------------------------------------------ alta y baja de jugadas

## La jugada `sid` entra en la pila: sus cartas (ya existen en la pantalla) suben al centro.
## `target_pos` es null si no hay objetivo. Con `quiet` (pantalla abierta a mitad de partida) se colocan sin animar.
func add_play(sid: int, cards: Array, color: Color, from_pos: Vector3, target_pos: Variant, quiet: bool = false) -> void:
	if _plays.has(sid) or cards.is_empty():
		return
	var play := {"cards": cards, "color": color, "broken": false, "beam": null, "halo": null, "stamp": null, "halves": [], "tweens": [], "center": CENTER}
	_plays[sid] = play
	for c: Card3D in cards:
		c.set_meta("floating", sid)
		c.set_pickable(false)
	if not low and not quiet:
		_glow_pulse(play)
	if target_pos != null:
		_build_beam(play, from_pos, target_pos)
	if not low:
		play.halo = _glow_quad(color.lightened(0.2), 1.7, 0.32)
		add_child(play.halo)
	layout(quiet)


## Sincroniza con la pila de la vista: crea nada (eso lo hace la pantalla), pero aplica los Nop y suelta lo que ya no está.
## Devuelve las cartas liberadas (la pantalla las lleva al descarte).
func sync(stack: Array) -> Array:
	var live := {}
	for s: Dictionary in stack:
		live[int(s.id)] = s
	var released: Array = []
	for sid: int in _plays.keys():
		if not live.has(sid):
			released.append_array(_release(sid))
	for sid: int in _plays.keys():
		_set_nopes(_plays[sid], int(live[sid].nopes), true)
	layout(false)
	return released


## Suelta todo (fin de partida, pantalla cerrada...).
func clear_all() -> Array:
	var released: Array = []
	for sid: int in _plays.keys():
		released.append_array(_release(sid))
	return released


func _release(sid: int) -> Array:
	var play: Dictionary = _plays[sid]
	_plays.erase(sid)
	for t: Tween in play.tweens:
		if t and t.is_valid():
			t.kill()
	for key: String in ["beam", "halo", "stamp"]:
		var n: Variant = play[key]
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	var out: Array = []
	for c: Card3D in play.cards:
		if not is_instance_valid(c):
			continue
		c.set_glow(0.0)
		c.set_pickable(true)
		c.remove_meta("floating")
		c.set_meta("rel", true)
		out.append(c)
		if play.broken:
			# Las mitades caen con la carta y, al posarse, vuelve la carta entera
			_unbreaks.append({"card": c, "play": play, "at": _time + 0.62})
	return out


# ------------------------------------------------------------------ colocación

## Abanico de cada jugada sobre el centro; las anteriores quedan detrás, más arriba y a un lado.
func layout(quiet: bool = false) -> void:
	var order: Array = _plays.keys()
	order.sort()
	for idx in order.size():
		var play: Dictionary = _plays[order[idx]]
		var depth := order.size() - 1 - idx
		var center := CENTER + Vector3(-0.3 * depth, 0.05 * depth, -0.14 * depth)
		play.center = center
		var sc := FLOAT_SCALE * (1.0 - 0.1 * depth)
		var cards: Array = play.cards
		var n := cards.size()
		for i in n:
			var c: Card3D = cards[i]
			if not is_instance_valid(c):
				continue
			var off := float(i) - (n - 1) / 2.0
			var spread := 0.36 if n == 2 else 0.31
			var b := Basis(Vector3.RIGHT, TILT) * Basis(Vector3.UP, -off * 0.2)
			var pos := center + Basis(Vector3.RIGHT, TILT) * Vector3(off * spread * sc / FLOAT_SCALE, 0.0, 0.0) + Vector3(0, 0.002 * i, 0)
			var rot := b.get_euler()
			if quiet:
				c.kill_motion()
				c.position = pos
				c.rotation = rot
				c.scale = Vector3.ONE * sc
			else:
				c.fly_to(pos, rot, RISE_T, sc)
		var normal := Basis(Vector3.RIGHT, TILT) * Vector3.UP
		if is_instance_valid(play.halo):
			(play.halo as Node3D).position = center - Vector3(0, 0.0, 0.14)
		if is_instance_valid(play.stamp):
			(play.stamp as Node3D).position = center + normal * 0.06


# ------------------------------------------------------------------ anulación y restauración

func _set_nopes(play: Dictionary, nopes: int, animate: bool) -> void:
	var want := nopes % 2 == 1
	if want == play.broken:
		return
	if want:
		_break(play, animate)
	else:
		_restore(play, animate)


func _half_mat(tex: Texture2D, side: float) -> ShaderMaterial:
	if _half_shader == null:
		_half_shader = Shader.new()
		_half_shader.code = HALF_SHADER
	var m := ShaderMaterial.new()
	m.shader = _half_shader
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("side", side)
	return m


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null


func _make_half(type: String, side: float) -> Node3D:
	var n: Node3D = Card3D.MODEL.instantiate()
	var mesh := _find_mesh(n)
	if mesh:
		mesh.set_surface_override_material(0, _half_mat(CardDB.texture(type), side))
		mesh.set_surface_override_material(1, _half_mat(CardDB.texture("back"), side))
	return n


func _break(play: Dictionary, animate: bool) -> void:
	play.broken = true
	dbg_breaks += 1
	for t: Tween in play.tweens:
		if t and t.is_valid():
			t.kill()
	play.tweens.clear()
	for c: Card3D in play.cards:
		if not is_instance_valid(c):
			continue
		c.set_glow(0.0)
		c.set_body_visible(false)
		var pair: Array[Node3D] = []
		for k in 2:
			var side := 1.0 if k == 0 else -1.0
			var h := _make_half(c.type, side)
			c.add_child(h)
			pair.append(h)
			(play.halves as Array).append(h)
			var to_pos := Vector3(side * 0.13, 0.0, 0.03 * side)
			var to_rot := Vector3(0.0, -side * 0.16, side * 0.1)
			if animate:
				var t := h.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				t.tween_property(h, "position", to_pos, 0.32)
				t.tween_property(h, "rotation", to_rot, 0.32)
				play.tweens.append(t)
			else:
				h.position = to_pos
				h.rotation = to_rot
	_make_stamp(play, animate)
	if not low and animate:
		_flash(play.center, RED, 0.9)


func _make_stamp(play: Dictionary, animate: bool) -> void:
	if is_instance_valid(play.stamp):
		(play.stamp as Node).queue_free()
	var s := Label3D.new()
	s.text = "NOP"
	s.font = UIKit.TITLE_FONT
	s.font_size = 200
	s.pixel_size = 0.0021
	s.outline_size = 26
	s.modulate = RED
	s.outline_modulate = Color(1, 0.96, 0.88)
	s.render_priority = 5
	s.outline_render_priority = 4
	var base := Basis(Vector3.RIGHT, TILT - PI / 2.0) * Basis(Vector3.BACK, deg_to_rad(-16.0))
	s.basis = base
	s.position = (play.center as Vector3) + Basis(Vector3.RIGHT, TILT) * Vector3.UP * 0.06
	add_child(s)
	play.stamp = s
	if animate:
		s.scale = Vector3.ONE * 2.6
		s.modulate.a = 0.0
		var t := s.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(s, "scale", Vector3.ONE, 0.24)
		t.tween_property(s, "modulate:a", 1.0, 0.1)
		play.tweens.append(t)


func _restore(play: Dictionary, animate: bool) -> void:
	play.broken = false
	dbg_restores += 1
	for t: Tween in play.tweens:
		if t and t.is_valid():
			t.kill()
	play.tweens.clear()
	var halves: Array = play.halves
	for h: Node3D in halves:
		if not is_instance_valid(h):
			continue
		if animate:
			var t := h.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			t.tween_property(h, "position", Vector3.ZERO, 0.22)
			t.tween_property(h, "rotation", Vector3.ZERO, 0.22)
	if is_instance_valid(play.stamp):
		var st: Label3D = play.stamp
		play.stamp = null
		var ft := st.create_tween()
		ft.tween_property(st, "modulate:a", 0.0, 0.18)
		ft.tween_callback(st.queue_free)
	var cards: Array = play.cards
	var finish := func() -> void:
		for h: Node3D in halves:
			if is_instance_valid(h):
				h.queue_free()
		halves.clear()
		for c: Card3D in cards:
			if is_instance_valid(c):
				c.set_body_visible(true)
				if animate:
					c.set_glow(1.0)
					var g := c.create_tween()
					g.tween_method(c.set_glow, 1.0, 0.0, 0.5)
	if animate:
		get_tree().create_timer(0.24).timeout.connect(finish)
		if not low:
			_flash(play.center, Color(0.45, 1.0, 0.3), 1.0, true)
	else:
		finish.call()


## Cuando la carta rota se posa en el descarte vuelve entera.
func _unbreak_card(c: Variant, play: Dictionary) -> void:
	if not is_instance_valid(c):
		for h: Variant in play.halves:
			if is_instance_valid(h):
				(h as Node).queue_free()
		return
	c.set_body_visible(true)
	for h: Variant in play.halves:
		if is_instance_valid(h) and (h as Node).get_parent() == c:
			(h as Node).queue_free()


# ------------------------------------------------------------------ brillos

## Cuadrado aditivo que mira a la cámara (halo, destello, chispa).
func _glow_quad(color: Color, size: float, alpha: float) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Vfx.soft_dot()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = false
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _flash(at: Vector3, color: Color, power: float, with_particles: bool = false) -> void:
	var f := _glow_quad(color, 0.5, 0.9)
	f.position = at + Vector3(0, 0.05, 0.1)
	add_child(f)
	var t := f.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(f, "scale", Vector3.ONE * (3.4 * power), 0.5)
	t.tween_property(f.mesh.material, "albedo_color:a", 0.0, 0.5)
	t.chain().tween_callback(f.queue_free)
	if with_particles:
		Vfx.zombie_rise(self, at)


func _glow_pulse(play: Dictionary) -> void:
	for c: Card3D in play.cards:
		var t := c.create_tween().set_loops()
		t.tween_method(c.set_glow, 0.12, 0.42, 0.7).set_trans(Tween.TRANS_SINE)
		t.tween_method(c.set_glow, 0.42, 0.12, 0.7).set_trans(Tween.TRANS_SINE)
		play.tweens.append(t)


# ------------------------------------------------------------------ haz

static func _bezier(a: Vector3, mid: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(mid, t).lerp(mid.lerp(b, t), t)


func _tube(a: Vector3, b: Vector3, radius: float, color: Color, sides: int, segs: int) -> MeshInstance3D:
	var mid := (a + b) / 2.0 + Vector3(0, 0.28 + a.distance_to(b) * 0.2, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in segs + 1:
		var t := float(i) / segs
		var p := _bezier(a, mid, b, t)
		var tang := (_bezier(a, mid, b, minf(1.0, t + 0.02)) - _bezier(a, mid, b, maxf(0.0, t - 0.02))).normalized()
		var nrm := tang.cross(Vector3.UP)
		if nrm.length() < 0.01:
			nrm = tang.cross(Vector3.RIGHT)
		nrm = nrm.normalized()
		var bin := tang.cross(nrm).normalized()
		var ring: Array = []
		for k in sides:
			var ang := TAU * k / sides
			ring.append(p + (nrm * cos(ang) + bin * sin(ang)) * radius)
		rings.append(ring)
	for i in segs:
		for k in sides:
			var k2 := (k + 1) % sides
			var a0: Vector3 = rings[i][k]
			var a1: Vector3 = rings[i][k2]
			var b0: Vector3 = rings[i + 1][k]
			var b1: Vector3 = rings[i + 1][k2]
			for v: Vector3 in [a0, b0, a1, a1, b0, b1]:
				st.add_vertex(v)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if not low else BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build_beam(play: Dictionary, from_pos: Vector3, to_pos: Vector3) -> void:
	var col: Color = (play.color as Color).lightened(0.2)
	var a := from_pos + Vector3(0, 0.2, 0)
	var b := to_pos + Vector3(0, 0.2, 0)
	var core := _tube(a, b, 0.012 if not low else 0.016, Color(col.r, col.g, col.b, 0.95 if not low else 0.85), 4 if low else 6, 10 if low else 20)
	add_child(core)
	play.beam = core
	if low:
		return          # calidad baja: un solo tubo plano, sin brillo ni chispas
	var glow := _tube(a, b, 0.05, Color(col.r, col.g, col.b, 0.2), 6, 20)
	core.add_child(glow)
	var pulse := core.create_tween().set_loops()
	var cm: StandardMaterial3D = core.material_override
	pulse.tween_property(cm, "albedo_color:a", 0.55, 0.45).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(cm, "albedo_color:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	# Chispas que corren por el haz hacia el objetivo (las mueve _process: sin lambdas que capturen nodos)
	var mid := (a + b) / 2.0 + Vector3(0, 0.28 + a.distance_to(b) * 0.2, 0)
	for i in 3:
		var sp := _glow_quad(col.lightened(0.3), 0.16, 1.0)
		core.add_child(sp)
		_sparks.append({"node": sp, "a": a, "mid": mid, "b": b, "phase": i / 3.0})
	var end := _glow_quad(col, 0.5, 0.5)
	end.position = b
	core.add_child(end)
