class_name PlusSettings
extends RefCounted
## Ajustes locales de Plus (`user://settings.cfg`, sección `[plus]`): orden de la mano (UX-11), accesibilidad (UX-13),
## consejos vistos (UX-14) y tapete (V-09). Todo se lee del archivo en cada consulta (se consultan al abrir la pantalla,
## al lanzar un efecto o al tocar un ajuste, nunca cada cuadro).
##
## Las vibraciones de la pantalla Plus pasan SIEMPRE por `vibrate()`: es el único sitio que respeta «Vibración: no».

const SETTINGS := "user://settings.cfg"
const SECTION := "plus"

const HAND_TYPE := "tipo"
const HAND_USE := "uso"
const TEXT_NORMAL := 1.0
const TEXT_LARGE := 1.2
const MATS := ["verde", "burdeos", "azul"]
const MAT_NAMES := {"verde": "verde", "burdeos": "burdeos", "azul": "azul noche"}

## Prueba: peticiones de vibración recibidas y las que de verdad se enviaron al dispositivo.
static var vibe_requests := 0
static var vibe_fired := 0


static var _cache := {}        # lo ya leído de [plus]: se consulta a menudo (cada vista de la partida) y no hace falta releer el archivo
static var _loaded := false


## Vuelve a leer el archivo (cuando alguien lo cambia por fuera, p. ej. al devolver los ajustes tras una prueba).
static func reload() -> void:
	_cache.clear()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	if cfg.has_section(SECTION):
		for k: String in cfg.get_section_keys(SECTION):
			_cache[k] = cfg.get_value(SECTION, k)
	_loaded = true


static func get_value(key: String, default: Variant) -> Variant:
	if not _loaded:
		reload()
	return _cache.get(key, default)


static func set_value(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value(SECTION, key, value)
	cfg.save(SETTINGS)
	if not _loaded:
		reload()
	else:
		_cache[key] = value


# ---------------------------------------------------------------- UX-11 · orden de la mano

static func hand_order() -> String:
	var v := str(get_value("hand_order", HAND_TYPE))
	return v if v in [HAND_TYPE, HAND_USE] else HAND_TYPE


static func set_hand_order(v: String) -> void:
	set_value("hand_order", v if v in [HAND_TYPE, HAND_USE] else HAND_TYPE)


# ---------------------------------------------------------------- UX-13 · accesibilidad

static func text_large() -> bool:
	return str(get_value("text_size", "normal")) == "grande"


static func set_text_large(on: bool) -> void:
	set_value("text_size", "grande" if on else "normal")


static func text_factor() -> float:
	return TEXT_LARGE if text_large() else TEXT_NORMAL


static func vibration_on() -> bool:
	return bool(get_value("vibration", true))


static func set_vibration(on: bool) -> void:
	set_value("vibration", on)


static func reduce_motion() -> bool:
	return bool(get_value("reduce_motion", false))


static func set_reduce_motion(on: bool) -> void:
	set_value("reduce_motion", on)


## Único punto de vibración de la pantalla Plus.
static func vibrate(ms: int) -> void:
	vibe_requests += 1
	if not vibration_on():
		return
	vibe_fired += 1
	Input.vibrate_handheld(ms)


# ---------------------------------------------------------------- UX-14 · consejos

static func tips_seen() -> Dictionary:
	var out := {}
	var raw: Variant = get_value("tips_seen", [])
	if raw is Array:
		for k: Variant in raw:
			out[str(k)] = true
	return out


static func save_tips_seen(seen: Dictionary) -> void:
	var keys: Array = seen.keys()
	keys.sort()
	set_value("tips_seen", keys)


static func first_game_done() -> bool:
	return bool(get_value("first_game_done", false))


static func set_first_game_done(on: bool) -> void:
	set_value("first_game_done", on)


# ---------------------------------------------------------------- V-09 · tapete

static func mat() -> String:
	var v := str(get_value("mat", "verde"))
	return v if v in MATS else "verde"


static func set_mat(v: String) -> void:
	set_value("mat", v if v in MATS else "verde")


static func next_mat() -> String:
	var n: String = MATS[(MATS.find(mat()) + 1) % MATS.size()]
	set_mat(n)
	return n
