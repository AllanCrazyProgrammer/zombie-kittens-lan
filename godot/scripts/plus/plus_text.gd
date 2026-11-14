class_name PlusText
extends RefCounted
## UX-13 · Tamaño de texto de la interfaz de Plus. Escala `font_size` de rótulos, botones y campos de un árbol de
## controles por un factor (1,0 normal, 1,2 grande). Es idempotente: recuerda el tamaño base de cada control
## (`zk_ts` = [base, aplicado]); si el código cambió el tamaño después, ese pasa a ser el nuevo base.


static func apply(root: Node, factor: float, skip: Array = []) -> void:
	if skip.has(root):
		return
	if root is Control:
		scale_one(root as Control, factor)
	for c in root.get_children():
		apply(c, factor, skip)


static func scale_one(c: Control, factor: float) -> void:
	if not (c is Label or c is Button or c is LineEdit) or c.has_meta("zk_fixed"):
		return
	var cur := c.get_theme_font_size("font_size")
	var has: bool = c.has_meta("zk_ts")
	if not has and is_equal_approx(factor, 1.0):
		return
	var base := cur
	if has:
		var m: Array = c.get_meta("zk_ts")
		if cur == int(m[1]):
			base = int(m[0])
	var want := maxi(1, roundi(float(base) * factor))
	if want != cur:
		c.add_theme_font_size_override("font_size", want)
	c.set_meta("zk_ts", [base, want])


## Tamaño base (sin escala) de un control, para las pruebas.
static func base_of(c: Control) -> int:
	if c.has_meta("zk_ts"):
		return int((c.get_meta("zk_ts") as Array)[0])
	return c.get_theme_font_size("font_size")
