class_name RiskMeter
extends Control
## Medidor de riesgo en forma de mecha (V-01): verde < 15 %, amarillo 15–30 %, naranja 30–50 %, rojo > 50 %.
## Porcentaje grande encima, chispa animada en el extremo y «N explosivos en M cartas» debajo.

const TIERS := [0.15, 0.30, 0.50]
const TIER_NAMES := ["verde", "amarillo", "naranja", "rojo"]
const TIER_COLORS := [Color("5bd35b"), Color("ffd23a"), Color("ff8a2a"), Color("ff4055")]
const BAR_H := 20.0

var _pct := 0.0           # 0..1
var _tier := -1
var _eks := 0
var _cards := 0
var _time := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 128)
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


## view: vista de la partida. riesgo = (vivos − 1) / max(1, cartas del mazo).
func update(view: Dictionary) -> void:
	var alive := 0
	for p: Dictionary in view.players:
		alive += 1 if p.alive else 0
	_eks = maxi(0, alive - 1)
	_cards = int(view.draw)
	_pct = clampf(float(_eks) / maxf(1.0, float(_cards)), 0.0, 1.0)
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
	draw_style_box(UIKit.box(Color(0.08, 0.04, 0.16, 0.88), UIKit.C.line, 24, 3, Vector2.ZERO), Rect2(Vector2.ZERO, size))
	var col: Color = TIER_COLORS[tier]
	var w := size.x
	# Porcentaje grande, centrado
	var big := UIKit.TITLE_FONT
	var txt := "%d%%" % int(round(_pct * 100.0))
	var fs := 56
	var ts := big.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	var lab := "RIESGO"
	var lfs := 28
	var ls := UIKit.bold().get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs)
	var total_w := ls.x + 14.0 + ts.x
	var x0 := (w - total_w) / 2.0
	var base := 56.0
	draw_string(UIKit.bold(), Vector2(x0, base - 8.0), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, UIKit.C.dim)
	draw_string_outline(big, Vector2(x0 + ls.x + 14.0, base), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, UIKit.C.dark)
	draw_string(big, Vector2(x0 + ls.x + 14.0, base), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# Mecha: fondo y tramos de color
	var bx := 22.0
	var bw := w - 44.0
	var by := 70.0
	var bar := Rect2(bx, by, bw, BAR_H)
	draw_rect(bar.grow(3.0), UIKit.C.dark, true)
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
		draw_line(Vector2(lx, by), Vector2(lx, by + BAR_H), UIKit.C.dark, 3.0)
	# Chispa en el extremo de lo quemado
	var sp := Vector2(bx + bw * fill, by + BAR_H / 2.0)
	var flick := 0.75 + 0.25 * sin(_time * 23.0) + 0.1 * sin(_time * 37.0)
	draw_circle(sp, 15.0 * flick, Color(col.r, col.g, col.b, 0.28))
	draw_circle(sp, 9.0 * flick, Color(1.0, 0.85, 0.4, 0.8))
	draw_circle(sp, 4.5, Color.WHITE)
	for k in 5:
		var ang := _time * 6.0 + k * TAU / 5.0
		var r := (13.0 + 8.0 * sin(_time * 11.0 + k * 1.7)) * flick
		draw_line(sp + Vector2(cos(ang), sin(ang)) * 6.0, sp + Vector2(cos(ang), sin(ang)) * r, Color(1.0, 0.9, 0.5, 0.9), 2.5)
	# Detalle en pequeño
	var sub := "%d %s en %d cartas" % [_eks, "explosivo" if _eks == 1 else "explosivos", _cards]
	var ss := UIKit.bold().get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, 26)
	draw_string(UIKit.bold(), Vector2((w - ss.x) / 2.0, by + BAR_H + 30.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UIKit.C.dim)
