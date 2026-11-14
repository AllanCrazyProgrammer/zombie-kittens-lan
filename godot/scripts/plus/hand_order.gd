class_name HandOrder
extends RefCounted
## UX-11 · Orden de la mano y marcas de pareja/trío. Funciones puras sobre la lista de cartas de la vista
## (`{id, type}`), para poder probarlas sin pantalla.

## Grupo de uso de un tipo: 0 Zombi y Nop, 1 acciones, 2 cartas ⚡, 3 gatos, 4 peligros.
static func group_of(type: String) -> int:
	if type == "zombie" or type == "nope":
		return 0
	var d: Dictionary = CardDB.defs.get(type, {})
	if d.get("cat", false):
		return 3
	if type == "exploding" or type == "rotten":
		return 4
	if d.get("now", false):
		return 2
	return 1


## Mano ordenada. `order`: tipos en el orden del mazo (`CardDB.types_for`). Modo «tipo» = el de siempre.
static func sorted(hand: Array, order: Array, mode: String) -> Array:
	var out := hand.duplicate()
	var by_use := mode == PlusSettings.HAND_USE
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if by_use:
			var ga := group_of(a.type)
			var gb := group_of(b.type)
			if ga != gb:
				return ga < gb
		var ia := order.find(a.type)
		var ib := order.find(b.type)
		return ia < ib if ia != ib else int(str(a.id).substr(1)) < int(str(b.id).substr(1)))
	return out


## id -> 2 o 3: cartas que forman pareja o trío con otras de la mano (el Clon cuenta como comodín y lleva la marca
## más alta de las que podría completar). Las demás no aparecen.
static func marks(hand: Array) -> Dictionary:
	var by_type := {}
	var clones: Array = []
	for c: Dictionary in hand:
		if c.type == "clone":
			clones.append(c.id)
		elif CardDB.defs.get(c.type, {}).get("cat", false):
			if not by_type.has(c.type):
				by_type[c.type] = []
			(by_type[c.type] as Array).append(c.id)
	var out := {}
	var clone_mark := 0
	for t: String in by_type:
		var n: int = (by_type[t] as Array).size() + clones.size()
		if n < 2:
			continue
		var m := 3 if n >= 3 else 2
		for id: String in by_type[t]:
			out[id] = m
		clone_mark = maxi(clone_mark, m)
	if clone_mark > 0:
		for id: String in clones:
			out[id] = clone_mark
	return out
