extends Node
class_name RcsMqttTransport

signal connected()
signal disconnected(reason: String)
signal message_received(topic: String, payload: Variant)
signal subscribed(topic_count: int)
signal publish_failed(topic: String, reason: String)

@export var broker_url := "ws://192.168.61.35:9001/mqtt"
@export var secure_required := false
@export var inbound_buffer_size := 64 * 1024 * 1024
@export var outbound_buffer_size := 8 * 1024 * 1024
@export var max_queued_packets := 4096
@export var auto_reconnect := true
@export var reconnect_delay_msec := 2000

var connected_state := false
var keepalive_seconds := 300
var client_id := ""

var _socket := WebSocketPeer.new()
var _connect_packet_sent := false
var _packet_id := 1
var _disconnect_emitted := false
var _last_outbound_msec := 0
var _last_inbound_msec := 0
var _manual_disconnect := false
var _reconnect_pending := false


func connect_transport() -> void:
	if secure_required and broker_url.begins_with("ws://"):
		disconnected.emit("Plaintext MQTT over WebSocket is blocked")
		return

	_disconnect_emitted = false
	_connect_packet_sent = false
	connected_state = false
	_manual_disconnect = false
	_reconnect_pending = false
	client_id = "rcs-godot-%d" % Time.get_ticks_msec()
	_touch_inbound()
	_touch_outbound()

	_socket = WebSocketPeer.new()
	_socket.supported_protocols = PackedStringArray(["mqtt"])
	_socket.inbound_buffer_size = inbound_buffer_size
	_socket.outbound_buffer_size = outbound_buffer_size
	_socket.max_queued_packets = max_queued_packets
	var error := _socket.connect_to_url(broker_url)
	if error != OK:
		disconnected.emit("WebSocket connect failed: %s" % error)
		_schedule_reconnect()
		return

	set_process(true)


func connect_secure() -> void:
	connect_transport()


func disconnect_transport() -> void:
	_manual_disconnect = true
	_reconnect_pending = false
	if connected_state:
		_send_packet(_build_fixed_packet(0xE0, PackedByteArray()))
	_socket.close()
	connected_state = false
	_connect_packet_sent = false
	set_process(false)
	disconnected.emit("Disconnected")


func publish(topic: String, payload: Variant) -> void:
	if not connected_state:
		publish_failed.emit(topic, "MQTT is not connected")
		return
	var packet := _build_publish_packet(topic, payload)
	var error := _send_packet(packet)
	if error != OK:
		publish_failed.emit(topic, "Publish failed: %s" % error)


func subscribe(topics: PackedStringArray) -> void:
	if not connected_state:
		return
	if topics.is_empty():
		return

	var packet := _build_subscribe_packet(topics)
	_send_packet(packet)


func _process(_delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _connect_packet_sent:
			_send_packet(_build_connect_packet())
			_connect_packet_sent = true
		_send_keepalive_if_needed()
		while _socket.get_available_packet_count() > 0:
			_handle_packet(_socket.get_packet())
		return

	if state == WebSocketPeer.STATE_CLOSED:
		set_process(false)
		if not _disconnect_emitted:
			_disconnect_emitted = true
			var code := _socket.get_close_code()
			var reason := _socket.get_close_reason()
			if reason.is_empty():
				reason = "WebSocket closed (%d)" % code
			connected_state = false
			disconnected.emit(reason)
			_schedule_reconnect()


func _handle_packet(packet: PackedByteArray) -> void:
	if packet.size() < 2:
		return
	_touch_inbound()

	var packet_type := packet[0] >> 4
	var decoded: Dictionary = _decode_remaining_length(packet, 1)
	if decoded.is_empty():
		return
	var body_start: int = int(decoded["next_index"])
	var remaining_length: int = int(decoded["remaining_length"])

	match packet_type:
		2:
			_handle_connack(packet, body_start)
		3:
			_handle_publish(packet, body_start, packet[0] & 0x0F)
		9:
			subscribed.emit(max(0, remaining_length - 2))
		13:
			pass
		_:
			pass


func _send_keepalive_if_needed() -> void:
	if not connected_state:
		return
	var now := Time.get_ticks_msec()
	var interval_msec: int = min(20000, max(5000, int(keepalive_seconds * 1000 * 0.45)))
	if now - _last_outbound_msec >= interval_msec:
		_send_packet(_build_fixed_packet(0xC0, PackedByteArray()))


func _send_packet(packet: PackedByteArray) -> Error:
	var error := _socket.send(packet)
	if error == OK:
		_touch_outbound()
	return error


func _touch_outbound() -> void:
	_last_outbound_msec = Time.get_ticks_msec()


func _touch_inbound() -> void:
	_last_inbound_msec = Time.get_ticks_msec()


func _schedule_reconnect() -> void:
	if _manual_disconnect or not auto_reconnect or _reconnect_pending:
		return
	_reconnect_pending = true
	_reconnect_after_delay()


func _reconnect_after_delay() -> void:
	await get_tree().create_timer(float(reconnect_delay_msec) / 1000.0).timeout
	if _manual_disconnect:
		_reconnect_pending = false
		return
	AppState.push_event("MQTT reconnecting")
	connect_transport()


func _handle_connack(packet: PackedByteArray, body_start: int) -> void:
	if packet.size() < body_start + 2:
		disconnected.emit("Malformed MQTT CONNACK")
		return

	var return_code: int = packet[body_start + 1]
	if return_code == 0:
		connected_state = true
		connected.emit()
	else:
		connected_state = false
		disconnected.emit("MQTT CONNACK rejected: %d" % return_code)


func _handle_publish(packet: PackedByteArray, body_start: int, flags: int) -> void:
	if packet.size() < body_start + 2:
		return

	var topic_length := (packet[body_start] << 8) | packet[body_start + 1]
	var topic_start := body_start + 2
	var topic_end := topic_start + topic_length
	if packet.size() < topic_end:
		return

	var topic := packet.slice(topic_start, topic_end).get_string_from_utf8()
	var qos := (flags & 0x06) >> 1
	var payload_start := topic_end
	if qos > 0:
		payload_start += 2
	if packet.size() < payload_start:
		return

	var payload_bytes := packet.slice(payload_start)
	var payload_text := payload_bytes.get_string_from_utf8()
	message_received.emit(topic, _decode_payload(payload_text, payload_bytes))


func _build_connect_packet() -> PackedByteArray:
	var body := PackedByteArray()
	_append_utf8(body, "MQTT")
	body.append(4)
	body.append(2)
	body.append((keepalive_seconds >> 8) & 0xFF)
	body.append(keepalive_seconds & 0xFF)
	_append_utf8(body, client_id)
	return _build_fixed_packet(0x10, body)


func _build_subscribe_packet(topics: PackedStringArray) -> PackedByteArray:
	var body := PackedByteArray()
	var id := _next_packet_id()
	body.append((id >> 8) & 0xFF)
	body.append(id & 0xFF)
	for topic in topics:
		var clean_topic := topic.strip_edges()
		if clean_topic.is_empty():
			continue
		_append_utf8(body, clean_topic)
		body.append(0)
	return _build_fixed_packet(0x82, body)


func _build_publish_packet(topic: String, payload: Variant) -> PackedByteArray:
	var body := PackedByteArray()
	_append_utf8(body, topic)
	var payload_text: String = str(payload) if typeof(payload) == TYPE_STRING else JSON.stringify(payload)
	body.append_array(str(payload_text).to_utf8_buffer())
	return _build_fixed_packet(0x30, body)


func _build_fixed_packet(header: int, body: PackedByteArray) -> PackedByteArray:
	var packet := PackedByteArray()
	packet.append(header)
	packet.append_array(_encode_remaining_length(body.size()))
	packet.append_array(body)
	return packet


func _append_utf8(target: PackedByteArray, value: String) -> void:
	var bytes := value.to_utf8_buffer()
	target.append((bytes.size() >> 8) & 0xFF)
	target.append(bytes.size() & 0xFF)
	target.append_array(bytes)


func _encode_remaining_length(value: int) -> PackedByteArray:
	var encoded := PackedByteArray()
	var next := value
	while true:
		var byte := next % 128
		next = next >> 7
		if next > 0:
			byte = byte | 128
		encoded.append(byte)
		if next <= 0:
			break
	return encoded


func _decode_remaining_length(packet: PackedByteArray, start_index: int) -> Dictionary:
	var multiplier := 1
	var value := 0
	var index := start_index

	while index < packet.size():
		var byte := packet[index]
		value += (byte & 127) * multiplier
		index += 1
		if (byte & 128) == 0:
			return {
				"remaining_length": value,
				"next_index": index,
			}
		multiplier *= 128
		if multiplier > 128 * 128 * 128:
			return {}

	return {}


func _next_packet_id() -> int:
	var id := _packet_id
	_packet_id += 1
	if _packet_id > 65535:
		_packet_id = 1
	return id


func _decode_payload(payload_text: String, payload_bytes: PackedByteArray) -> Variant:
	var clean_text := payload_text.strip_edges()
	if clean_text.begins_with("{") or clean_text.begins_with("["):
		var json := JSON.new()
		if json.parse(payload_text) == OK:
			return json.data
	if payload_text.is_empty() and payload_bytes.size() > 0:
		return payload_bytes
	return payload_text
