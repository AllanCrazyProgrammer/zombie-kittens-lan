class_name RiskMeter
extends Control
## Medidor de riesgo en forma de mecha (V-01): verde < 15 %, amarillo 15–30 %, naranja 30–50 %, rojo > 50 %.
## Compacto (62 px, sin panel): porcentaje a la izquierda, mecha con chispa a la derecha y
## «N explosivos en M cartas» en pequeño debajo de la mecha. Deja ver las cabezas de los avatares.

const TIERS := [0.15, 0.30, 0.50]
const TIER_NAMES := ["verde", "amarillo", "naranja", "rojo"]
const TIER_COLORS := [Color("5bd35b"), Color("ffd23a"), Color("ff8a2a"), Color("ff4055")]
const BAR_H := 18.0

var _pct := 0.0           # 0..1
var _tier := -1
var _eks := 0
var _cards := 0
var _time := 0.0
var _rot0 := false        # el Gatito Putrefacto está boca arriba en la cima: robar es muerte segura
var _sudden := false      # muerte súbita en marcha: regla activa y quedan 2 vivos


func _init() -> void:
	custom_minimum_size = Vector2(0, 62)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func tier_of(pct: float) -> int:
	var t := 0
	for lim: float in TIERS:
		if pct >= lim:
			t += 1
	return t


## Porcentaje (0–100) y tramo actuales: {pct, tier, name}.
func debug_risk() -> Dictionary:
	return {"pct": int(round(_pct * 100.0)), "tier": _tier, "name": TIER_NAMES[maxi(0, _tier)]}


## Rótulo fijo «MUERTE SÚBITA» visible (prueba).
func debug_sudden() -> bool:
	return _sudden


## ¿Muestra el aviso de Putrefacto en la cima? (prueba)
func debug_rot0() -> bool:
	return _rot0


## view: vista de la partida. riesgo = (vivos − 1) / max(1, cartas del mazo); con el Putrefacto boca arriba en la
## cima (`rotDepth == 0`) robar es muerte segura: 100 %.
func update(view: Dictionary) -> void:
	var alive := 0
	for p: Dictionary in view.players:
		alive += 1 if p.alive else 0
	_eks = maxi(0, alive - 1)
	_cards = int(view.draw)
	_pct = clampf(float(_eks) / maxf(1.0, float(_cards)), 0.0, 1.0)
	_rot0 = int(view.get("rotDepth", -1)) == 0 and view.get("over") == null
	if _rot0:
		_pct = 1.0
	var rules: Variant = view.get("rules", {})
	_sudden = rules is Dictionary and bool(rules.get("sudden_death", false)) and alive == 2 and view.get("over") == null
	var tier := tier_of(_pct)
	if _tier >= 0 and tier > _tier:
		Sfx.play("fuse", -10.0)
		_pulse()
	_tier = tier
	queue_redraw()


func _pulse() -> void:
	pivot_offset = size / 2.0
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2(1.07, 1.07), 0.14)
	t.tween_property(self, "scale", Vector2.ONE, 0.26)


func _process(delta: float) -> void:
	_time += delta
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var tier := maxi(0, _tier)
	var col: Color = TIER_COLORS[tier]
	var w := size.x
	# Sin panel: solo un velo mínimo para que el texto se lea sobre la mesa
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.02, 0.1, 0.18), true)
	# Izquierda: porcentaje
	var big := UIKit.TITLE_FONT
	var txt := "%d%%" % int(round(_pct * 100.0))
	var fs := 46
	var ts := big.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pw := maxf(ts.x, 100.0) + 8.0      # + el contorno del texto
	draw_string_outline(big, Vector2(14.0, 46.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, UIKit.C.dark)
	draw_string(big, Vector2(14.0, 46.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# Derecha: mecha con tramos de color
	var bx := 14.0 + pw + 24.0
	var bw := w - bx - 22.0
	var by := 12.0
	var bar := Rect2(bx, by, bw, BAR_H)
	draw_rect(bar.grow(2.0), UIKit.C.dark, true)
	var starts := [0.0, TIERS[0], TIERS[1], TIERS[2], 1.0]
	var fill := clampf(_pct, 0.0, 1.0)
	for i in 4:
		var a: float = starts[i]
		var b: float = minf(starts[i + 1], fill)
		var dim: Color = TIER_COLORS[i] * Color(1, 1, 1, 0.22)
		draw_rect(Rect2(bx + bw * a, by, bw * (starts[i + 1] - a), BAR_H), dim, true)
		if b > a:
			draw_rect(Rect2(bx + bw * a, by, bw * (b - a), BAR_H), TIER_COLORS[i], true)
	for i in range(1, 4):
		var lx: float = bx + bw * starts[i]
		draw_line(Vector2(lx, by), Vector2(lx, by + BAR_H), UIKit.C.dark, 2.0)
	# Chispa en el extremo de lo quemado
	var sp := Vector2(bx + bw * fill, by + BAR_H / 2.0)
	var flick := 0.75 + 0.25 * sin(_time * 23.0) + 0.1 * sin(_time * 37.0)
	draw_circle(sp, 11.0 * flick, Color(col.r, col.g, col.b, 0.28))
	draw_circle(sp, 7.0 * flick, Color(1.0, 0.85, 0.4, 0.8))
	draw_circle(sp, 3.5, Color.WHITE)
	for k in 5:
		var ang := _time * 6.0 + k * TAU / 5.0
		var r := (9.0 + 6.0 * sin(_time * 11.0 + k * 1.7)) * flick
		draw_line(sp + Vector2(cos(ang), sin(ang)) * 4.0, sp + Vector2(cos(ang), sin(ang)) * r, Color(1.0, 0.9, 0.5, 0.9), 2.0)
	# Detalle en pequeño, bajo la mecha: empieza siempre a la derecha del porcentaje y se encoge si no cabe
	var sub := "%d %s en %d cartas" % [_eks, "explosivo" if _eks == 1 else "explosivos", _cards]
	if _rot0:
		sub = "☣ ¡El Putrefacto es el siguiente!"
	var sfont := UIKit.bold()
	var sfs := 26
	var avail := maxf(40.0, w - bx - 8.0)
	if _sudden:
		# Rótulo fijo a la derecha de esa línea; el detalle se encoge para dejarle sitio
		var bt := "MUERTE SÚBITA"
		var bw2 := sfont.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		var pulse := 0.65 + 0.35 * sin(_time * 5.0)
		var bpos := Vector2(w - bw2 - 8.0, by + BAR_H + 27.0)
		draw_string_outline(sfont, bpos, bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, UIKit.C.dark)
		draw_string(sfont, bpos, bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.25 + 0.2 * pulse, 0.3))
		avail = maxf(40.0, w - bx - 8.0 - bw2 - 16.0)
	while sfs > 14 and sfont.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x > avail:
		sfs -= 1
	var sp_pos := Vector2(bx, by + BAR_H + 27.0)
	draw_string_outline(sfont, sp_pos, sub, HORIZONTAL_ALIGNMENT_LEFT, avail, sfs, 6, UIKit.C.dark)
	draw_string(sfont, sp_pos, sub, HORIZONTAL_ALIGNMENT_LEFT, avail, sfs, Color("ece4ff"))
