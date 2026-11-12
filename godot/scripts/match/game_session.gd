class_name GameSession
extends Node
## Lo que la pantalla de juego necesita de una partida, sea local (LocalMatch) o en red (ClientSession):
## el estado visible para este jugador, una forma de enviar acciones y avisos cuando algo cambia.

signal updated
signal error(message: String)

var me_id := ""


func now() -> int:
	return Time.get_ticks_msec()


## Estado visible para este jugador (mismo formato que ZKGame.view).
func view() -> Dictionary:
	return {}


## Envía una acción. Devuelve "" o el motivo del rechazo (en red el rechazo llega después por `error`).
func act(_a: Dictionary) -> String:
	return ""


## Dificultad de un bot ("" si no es bot).
func level_of(_id: String) -> String:
	return ""


## ¿La partida es de Zombie Kittens Plus? (decide qué pantalla de juego se abre)
func is_plus() -> bool:
	return false


func is_network() -> bool:
	return false


func is_host() -> bool:
	return true


## Victorias por jugador en la sala ({id: n}); vacío fuera de salas Plus.
func scores() -> Dictionary:
	return {}
