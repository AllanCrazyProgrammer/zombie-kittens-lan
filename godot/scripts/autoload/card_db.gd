extends Node
## Base de datos de cartas: nombres, textos y texturas. Fuente: data/cards.json (generado desde el juego web).

var defs: Dictionary = {}
var _tex: Dictionary = {}


func _ready() -> void:
	var f := FileAccess.open("res://data/cards.json", FileAccess.READ)
	if f == null:
		push_error("No se pudo abrir data/cards.json")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		defs = parsed


func types() -> Array:
	return defs.keys()   # hoy todas las cartas son base; las de packs llevarán "pack" y no entrarán aquí


## Cartas base (sin `pack`) más las de los packs indicados (p. ej. ["crypt"]).
func types_for(packs: Array) -> Array:
	var out: Array = []
	for k: String in defs:
		var pk: String = defs[k].get("pack", "")
		if pk == "" or packs.has(pk):
			out.append(k)
	return out


## {tipo: nombre} de las cartas de esos packs (el motor no lee CardDB).
func names_for(packs: Array) -> Dictionary:
	var out := {}
	for k: String in defs:
		if packs.has(defs[k].get("pack", "")):
			out[k] = defs[k].get("name", k)
	return out


func display_name(type: String) -> String:
	return defs.get(type, {}).get("name", type)


func texture(type: String) -> Texture2D:
	if not _tex.has(type):
		_tex[type] = load("res://assets/cards/%s.png" % type)
	return _tex[type]
