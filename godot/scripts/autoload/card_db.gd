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
	return defs.keys()


func display_name(type: String) -> String:
	return defs.get(type, {}).get("name", type)


func texture(type: String) -> Texture2D:
	if not _tex.has(type):
		_tex[type] = load("res://assets/cards/%s.png" % type)
	return _tex[type]
