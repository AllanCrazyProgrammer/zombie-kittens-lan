extends Node
## Red local: conexión entre teléfonos (ENet) y búsqueda de salas por difusión UDP.
## El anfitrión es siempre el par 1. Los mensajes son diccionarios {t: tipo, ...}.

signal message(peer: int, data: Dictionary)
signal peer_left(peer: int)
signal connected
signal failed
signal server_lost

## Versión del protocolo de red. 3 = Zombie Kittens Plus (las salas Plus exigen proto >= 3; las clásicas no comprueban nada).
const PROTO := 3
const PORT := 8766
const DISCOVERY_PORT := 8767
## Puerto donde el anfitrión responde a quien pregunta directamente "¿hay sala?" (por si la red o el
## teléfono filtran los avisos por difusión)
const PROBE_PORT := 8768
const PROBE := "zk?"
const PROBE_EVERY := 2.0
const BEACON_EVERY := 1.0
const ROOM_TTL_MS := 3500

## Salas vistas en la red: id de sala -> {ip, name, players, started, seen}
var rooms := {}
var _beacon: PacketPeerUDP
var _beacon_info: Callable
var _beacon_t := 0.0
var _beacon_id := ""
var _listener: PacketPeerUDP
var _probe_t := 0.0
## Solo para pruebas: desactiva los avisos por difusión para comprobar la búsqueda directa
var broadcast_enabled := true


func _ready() -> void:
	multiplayer.peer_disconnected.connect(func(id: int) -> void: peer_left.emit(id))
	multiplayer.connected_to_server.connect(func() -> void: connected.emit())
	multiplayer.connection_failed.connect(func() -> void: failed.emit())
	multiplayer.server_disconnected.connect(func() -> void: server_lost.emit())


func host() -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 8)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err


func join(ip: String) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err == OK:
		multiplayer.multiplayer_peer = peer
	return err


func close() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func is_online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func send(peer: int, data: Dictionary) -> void:
	if is_online():
		_msg.rpc_id(peer, data)


@rpc("any_peer", "call_remote", "reliable")
func _msg(data: Dictionary) -> void:
	message.emit(multiplayer.get_remote_sender_id(), data)


## Direcciones IPv4 privadas de este dispositivo (las que sirven para una red local).
func local_ips() -> Array:
	var out: Array = []
	for a: String in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10."):
			out.append(a)
		elif a.begins_with("172."):
			var second := int(a.split(".")[1])
			if second >= 16 and second <= 31:
				out.append(a)
	return out


# ---------------------------------------------------------------- búsqueda de salas

## El anfitrión se anuncia cada segundo. `info` devuelve {name, players, started}.
func start_beacon(info: Callable) -> void:
	stop_beacon()
	_beacon = PacketPeerUDP.new()
	_beacon.bind(PROBE_PORT)      # si falla (puerto ocupado) solo se pierde la respuesta directa
	_beacon.set_broadcast_enabled(true)
	_beacon_info = info
	_beacon_id = "%x" % randi()
	_beacon_t = BEACON_EVERY


func stop_beacon() -> void:
	if _beacon:
		_beacon.close()
	_beacon = null


func start_listening() -> bool:
	stop_listening()
	rooms = {}
	_probe_t = PROBE_EVERY
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null
		return false
	return true


func is_listening() -> bool:
	return _listener != null


func stop_listening() -> void:
	if _listener:
		_listener.close()
	_listener = null


func _process(delta: float) -> void:
	if _beacon:
		var info: Dictionary = _beacon_info.call()
		info["zk"] = 1
		info["id"] = _beacon_id
		info["port"] = PORT
		var data := JSON.stringify(info).to_utf8_buffer()
		# Responde a quien pregunta directamente
		while _beacon.get_available_packet_count() > 0:
			var q := _beacon.get_packet()
			if q.get_string_from_utf8() == PROBE:
				_beacon.set_dest_address(_beacon.get_packet_ip(), _beacon.get_packet_port())
				_beacon.put_packet(data)
		_beacon_t += delta
		if _beacon_t >= BEACON_EVERY and broadcast_enabled:
			_beacon_t = 0.0
			# Difusión general + la de cada subred (algunos routers solo dejan pasar esta última)
			var targets := {"255.255.255.255": true, "127.0.0.1": true}
			for ip: String in local_ips():
				var parts := ip.split(".")
				targets["%s.%s.%s.255" % [parts[0], parts[1], parts[2]]] = true
			for t: String in targets:
				_beacon.set_dest_address(t, DISCOVERY_PORT)
				_beacon.put_packet(data)
	if _listener:
		# Además de escuchar avisos, pregunta una por una a las direcciones de la red local
		_probe_t += delta
		if _probe_t >= PROBE_EVERY:
			_probe_t = 0.0
			var probe := PROBE.to_utf8_buffer()
			var mine := local_ips()
			var targets := ["127.0.0.1"]
			for ip: String in mine:
				var parts := ip.split(".")
				for n in range(1, 255):
					var t := "%s.%s.%s.%d" % [parts[0], parts[1], parts[2], n]
					if t != ip:
						targets.append(t)
			for t: String in targets:
				_listener.set_dest_address(t, PROBE_PORT)
				_listener.put_packet(probe)
		while _listener.get_available_packet_count() > 0:
			var raw := _listener.get_packet()
			var ip := _listener.get_packet_ip()
			var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
			if parsed is Dictionary and parsed.get("zk", 0) == 1:
				# La misma sala puede oírse por varias direcciones: se guarda una sola vez (mejor la de la red que 127.0.0.1)
				var key := str(parsed.get("id", ip))
				if rooms.has(key) and ip == "127.0.0.1" and rooms[key].ip != "127.0.0.1":
					ip = rooms[key].ip
				parsed["ip"] = ip
				parsed["seen"] = Time.get_ticks_msec()
				rooms[key] = parsed
		var now := Time.get_ticks_msec()
		for key: String in rooms.keys():
			if now - int(rooms[key].seen) > ROOM_TTL_MS:
				rooms.erase(key)
