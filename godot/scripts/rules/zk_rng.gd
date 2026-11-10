class_name ZKRng
extends RefCounted
## Generador pseudoaleatorio "mulberry32", idéntico bit a bit al de las pruebas en JavaScript.
## Permite repetir exactamente la misma partida en ambos motores a partir de una semilla.

const M := 0xFFFFFFFF
var _s: int


func _init(seed_value: int) -> void:
	_s = seed_value & M


static func _imul(a: int, b: int) -> int:
	# Producto de 32 bits sin desbordar los enteros de 64 bits
	return ((a & 0xFFFF) * b + ((((a >> 16) * b) & 0xFFFF) << 16)) & M


func next() -> float:
	_s = (_s + 0x6D2B79F5) & M
	var t := _imul(_s ^ (_s >> 15), 1 | _s)
	t = ((t + _imul(t ^ (t >> 7), 61 | t)) & M) ^ t
	return float((t ^ (t >> 14)) & M) / 4294967296.0


## FNV-1a de 32 bits sobre texto ASCII (para comparar estados entre motores).
static func fnv(text: String) -> int:
	var h := 2166136261
	for b in text.to_ascii_buffer():
		h = ((h ^ b) * 16777619) & M
	return h
