extends Node
## Lightweight WebSocket client for the Render-hosted game server.
## Protocol is documented in docs/PROTOCOL.md (compact JSON arrays, 20 Hz).
## Yukkuri Strike - created by ゆっくりP

signal connected(welcome: Dictionary)
signal connection_failed
signal disconnected
signal message(msg: Dictionary)

const PROTOCOL_VERSION := 1
const SEND_RATE := 20.0

var ws: WebSocketPeer
var online := false
var my_id := -1
var ping_ms := 0
var _state := WebSocketPeer.STATE_CLOSED
var _ping_timer := 0.0
var _connect_timeout := 0.0

func connect_to(url: String, player_name: String) -> void:
	close()
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 18
	var err := ws.connect_to_url(url)
	if err != OK:
		connection_failed.emit()
		ws = null
		return
	_connect_timeout = 75.0
	set_meta("pending_name", player_name)

func close() -> void:
	if ws:
		ws.close()
	ws = null
	online = false
	my_id = -1

func send(msg: Dictionary) -> void:
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))

func _process(delta: float) -> void:
	if ws == null:
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st != _state:
		_state = st
		if st == WebSocketPeer.STATE_OPEN:
			send({"t": "hello", "name": get_meta("pending_name", "Player"), "ver": PROTOCOL_VERSION})
		elif st == WebSocketPeer.STATE_CLOSED:
			var was_online := online
			ws = null
			online = false
			if was_online:
				disconnected.emit()
			else:
				connection_failed.emit()
			return
	if st == WebSocketPeer.STATE_CONNECTING:
		_connect_timeout -= delta
		if _connect_timeout <= 0.0:
			close()
			connection_failed.emit()
		return
	while ws and ws.get_available_packet_count() > 0:
		var raw := ws.get_packet().get_string_from_utf8()
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		_handle(parsed)
	if online:
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = 2.0
			send({"t": "ping", "c": Time.get_ticks_msec()})

func _handle(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"welcome":
			online = true
			my_id = int(msg.get("id", -1))
			connected.emit(msg)
		"pong":
			ping_ms = Time.get_ticks_msec() - int(msg.get("c", 0))
		_:
			message.emit(msg)
