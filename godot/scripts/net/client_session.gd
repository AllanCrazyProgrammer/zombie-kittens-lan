class_name ClientSession
extends GameSession
## Un jugador dentro de una sala (propia o ajena). Si `room` existe, este dispositivo es el anfitrión y
## los mensajes van directo; si no, viajan por la red al anfitrión.

signal lobby_updated
signal left(reason: String)

var room: RoomHost
var lobby := {}
var host_flag := false
var _view := {}


func setup(p_room: RoomHost = null) -> ClientSession:
	room = p_room
	if room:
		room.local_message.connect(receive)
	else:
		Net.message.connect(_on_net)
	return self


func _on_net(peer: int, data: Dictionary) -> void:
	if peer == 1:
		receive(data)


func send(m: Dictionary) -> void:
	if room:
		room.on_msg(RoomHost.LOCAL, m)
	else:
		Net.send(1, m)


func hello(player_name: String, avatar: int, token: String) -> void:
	send({"t": "hello", "name": player_name, "avatar": avatar, "token": token, "proto": Net.PROTO})


func receive(m: Dictionary) -> void:
	match m.get("t", ""):
		"welcome":
			me_id = m.you
			host_flag = m.host
		"lobby":
			lobby = m
			if not m.get("started", false):
				_view = {}
			lobby_updated.emit()
		"state":
			_view = m.view
			updated.emit()
		"err":
			error.emit(m.get("msg", ""))
		"kicked", "full":
			left.emit(m.get("msg", "Saliste de la sala."))


func in_game() -> bool:
	return not _view.is_empty()


func view() -> Dictionary:
	return _view


func act(a: Dictionary) -> String:
	send({"t": "act", "a": a})
	return ""


func level_of(id: String) -> String:
	for p: Dictionary in lobby.get("players", []):
		if p.id == id and p.bot:
			return p.level
	return ""


func is_plus() -> bool:
	return bool(lobby.get("settings", {}).get("plus", false))


func is_network() -> bool:
	return true


func is_host() -> bool:
	return host_flag
