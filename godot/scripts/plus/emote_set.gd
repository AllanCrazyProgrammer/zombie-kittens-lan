class_name EmoteSet
extends RefCounted
## Las 6 reacciones rápidas de Plus (UX-08) y el ajuste local «Reacciones: sí/no».
## Índice 0-5 = 😹 🙀 😾 💀 🙏 👏. En pantalla no se dibuja el emoji (según el sistema puede faltar su fuente,
## sobre todo en Android): cada reacción es una palabra corta de color junto al gato de quien la envía.

const COUNT := 6
## Referencia: el emoji de cada índice (el contrato de red habla de índices, no de emojis).
const EMOJI: Array[String] = ["😹", "🙀", "😾", "💀", "🙏", "👏"]
const WORDS: Array[String] = ["JAJA", "¡NO!", "GRR", "RIP", "PORFA", "BRAVO"]
const COLORS: Array[Color] = [Color("ffd23a"), Color("49e0e6"), Color("ff4055"), Color("d9d4ec"), Color("ff9ad5"), Color("b6f23a")]
## Límite de envío por jugador (ms): lo aplica la sala y el botón lo muestra como enfriamiento.
const COOLDOWN_MS := 3000
## Tiempo visible del globo (s), sin contar la aparición ni el desvanecido.
const SHOW_S := 2.0

const SETTINGS := "user://settings.cfg"
const SECTION := "plus"
const KEY := "emotes"


static func valid(index: Variant) -> bool:
	return (index is int and index >= 0 and index < COUNT) or (index is float and is_finite(index) and index == floorf(index) and index >= 0.0 and index < float(COUNT))


static func word(index: int) -> String:
	return WORDS[clampi(index, 0, COUNT - 1)]


static func color(index: int) -> Color:
	return COLORS[clampi(index, 0, COUNT - 1)]


static func load_enabled() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return bool(cfg.get_value(SECTION, KEY, true))


static func save_enabled(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value(SECTION, KEY, on)
	cfg.save(SETTINGS)
