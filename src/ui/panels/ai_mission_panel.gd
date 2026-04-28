extends PanelContainer

class GearButton:
	extends Control

	signal pressed()

	var icon_color := Color(0.42, 0.49, 0.58)
	var hover := false

	func _ready() -> void:
		custom_minimum_size = Vector2(24, 24)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed.emit()
			accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			hover = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			hover = false
			queue_redraw()

	func _draw() -> void:
		var color := Color(0.68, 0.76, 0.88) if hover else icon_color
		var center := size * 0.5
		for index in range(8):
			var angle := TAU * float(index) / 8.0
			var direction := Vector2(cos(angle), sin(angle))
			draw_line(center + direction * 5.5, center + direction * 8.5, color, 1.4)
		draw_arc(center, 6.0, 0.0, TAU, 24, color, 1.5)
		draw_circle(center, 2.3, color)


signal prompt_submitted(message: String)
signal connect_requested(broker_url: String, robot_id: String)
signal disconnect_requested()

var input: TextEdit
var transcript_scroll: ScrollContainer
var transcript_margin: MarginContainer
var transcript: VBoxContainer
var send_button: Button
var chat_status_label: Label
var provider_buttons: Dictionary = {}
var current_provider := "ChatGPT"
var last_navigation_status_keys: Dictionary = {}
var last_navigation_result_keys: Dictionary = {}
var navigation_sessions: Dictionary = {}

var connection_popup: PopupPanel
var chat_endpoint_input: LineEdit
var mqtt_broker_input: LineEdit
var mqtt_robot_id_input: LineEdit

var mcp_endpoint := "ws://127.0.0.1:3001/chat"
var mqtt_broker_url := "ws://192.168.61.35:9001/mqtt"
var mqtt_robot_id := ""

var ws_peer: WebSocketPeer = null
var ws_connected := false


func _ready() -> void:
	mqtt_robot_id = AppState.active_robot_id
	_build_ui()
	resized.connect(_refresh_transcript_width)
	call_deferred("_refresh_transcript_width")


func _process(_delta: float) -> void:
	if ws_peer == null:
		return
	ws_peer.poll()
	match ws_peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not ws_connected:
				ws_connected = true
				_set_chat_status(true)
			while ws_peer.get_available_packet_count() > 0:
				var raw := ws_peer.get_packet().get_string_from_utf8()
				_handle_incoming_message(raw)
		WebSocketPeer.STATE_CLOSED:
			if ws_connected:
				ws_connected = false
				_set_chat_status(false)
			ws_peer = null


func _build_ui() -> void:
	custom_minimum_size = Vector2(520, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", _panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	var title := Label.new()
	title.text = "AI MISSION CONTROL"
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 0.98))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	chat_status_label = Label.new()
	chat_status_label.text = "OFFLINE"
	chat_status_label.custom_minimum_size = Vector2(78, 24)
	chat_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chat_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chat_status_label.add_theme_color_override("font_color", Color.WHITE)
	chat_status_label.add_theme_stylebox_override("normal", _pill_style(Color(0.02, 0.025, 0.03), Color(0.25, 0.31, 0.38)))
	header.add_child(chat_status_label)

	var gear := GearButton.new()
	gear.pressed.connect(_open_connection_settings)
	header.add_child(gear)

	var providers_row := HBoxContainer.new()
	providers_row.add_theme_constant_override("separation", 6)
	column.add_child(providers_row)

	var provider_group := ButtonGroup.new()
	for provider in ["Claude", "ChatGPT", "Ollama"]:
		var chip := _provider_chip(provider, provider == current_provider, provider_group)
		provider_buttons[provider] = chip
		providers_row.add_child(chip)

	_add_section_header(column, "QUICK PROMPTS")
	var prompts := [
		"Summarize the full AMR fleet state.",
		"Send burger1 to x=-1.25, y=0.40 in map.",
		"Explain the procedure for returning burger1 to the charging station.",
		"Suggest a recovery path if the current route is blocked.",
		"Send burger1 goal x=2.00, y=-0.75, yaw=1.57 in map.",
	]
	for prompt in prompts:
		column.add_child(_prompt_button(prompt))

	transcript_scroll = ScrollContainer.new()
	transcript_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	transcript_scroll.add_theme_stylebox_override("panel", _box_style())
	column.add_child(transcript_scroll)

	transcript_margin = MarginContainer.new()
	transcript_margin.add_theme_constant_override("margin_left", 8)
	transcript_margin.add_theme_constant_override("margin_right", 8)
	transcript_margin.add_theme_constant_override("margin_top", 10)
	transcript_margin.add_theme_constant_override("margin_bottom", 10)
	transcript_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transcript_scroll.add_child(transcript_margin)

	transcript = VBoxContainer.new()
	transcript.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transcript.add_theme_constant_override("separation", 14)
	transcript.resized.connect(_on_transcript_resized)
	transcript_margin.add_child(transcript)
	_add_message("RCS routes natural-language commands through RMS chat and shows navigation lifecycle events in one timeline.", "system", "SYS")

	input = TextEdit.new()
	input.placeholder_text = "Message %s..." % current_provider
	input.custom_minimum_size = Vector2(0, 72)
	input.add_theme_stylebox_override("normal", _input_style())
	input.gui_input.connect(_on_input_gui_input)
	column.add_child(input)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)

	var hint := Label.new()
	hint.text = "Ctrl+Enter to send"
	hint.add_theme_color_override("font_color", Color(0.45, 0.52, 0.62))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)

	send_button = Button.new()
	send_button.text = "Send to %s" % current_provider
	send_button.custom_minimum_size = Vector2(140, 32)
	send_button.add_theme_stylebox_override("normal", _button_style(Color(0.16, 0.19, 0.24), Color(0.25, 0.3, 0.38)))
	send_button.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
	send_button.pressed.connect(_submit_prompt)
	footer.add_child(send_button)
	_set_provider(current_provider)


func _provider_chip(text: String, active: bool, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = active
	button.button_group = group
	button.custom_minimum_size = Vector2(72, 24)
	button.pressed.connect(func() -> void:
		_set_provider(text)
	)
	_apply_provider_button_state(button, active)
	return button


func _set_provider(provider: String) -> void:
	current_provider = provider
	if send_button != null:
		send_button.text = "Send to %s" % provider
	if input != null:
		input.placeholder_text = "Message %s..." % provider
	for key in provider_buttons.keys():
		var button_value: Variant = provider_buttons[key]
		if typeof(button_value) != TYPE_OBJECT:
			continue
		var button := button_value as Button
		if button == null:
			continue
		var active := str(key) == current_provider
		button.button_pressed = active
		_apply_provider_button_state(button, active)


func _apply_provider_button_state(button: Button, active: bool) -> void:
	var background := Color(0.09, 0.105, 0.13) if active else Color(0.07, 0.08, 0.1)
	var border := Color(0.38, 0.44, 0.52) if active else Color(0.17, 0.2, 0.25)
	var font_color := Color(0.86, 0.92, 1.0) if active else Color(0.62, 0.69, 0.78)
	button.add_theme_stylebox_override("normal", _button_style(background, border))
	button.add_theme_stylebox_override("hover", _button_style(background.lightened(0.05), border.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.09, 0.105, 0.13), Color(0.38, 0.44, 0.52)))
	button.add_theme_color_override("font_color", font_color)


func _prompt_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 38)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.075, 0.09, 0.11), Color(0.18, 0.22, 0.28)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.09, 0.11, 0.14), Color(0.26, 0.32, 0.4)))
	button.add_theme_color_override("font_color", Color(0.86, 0.92, 1.0))
	button.pressed.connect(func() -> void:
		input.text = text
		input.grab_focus()
	)
	return button


func _add_message(text: String, role := "assistant", badge_override := "") -> void:
	if transcript == null:
		return
	var safe_role := role if role in ["user", "assistant", "system"] else "assistant"
	var badge_text := badge_override if not badge_override.is_empty() else _message_badge(safe_role)
	var message_card := VBoxContainer.new()
	message_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_card.add_theme_constant_override("separation", 4)
	message_card.modulate = Color(1.0, 1.0, 1.0, 0.0)
	message_card.scale = Vector2(0.98, 0.98)
	transcript.add_child(message_card)

	var meta_row := HBoxContainer.new()
	meta_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_card.add_child(meta_row)

	if safe_role == "user":
		var meta_spacer := Control.new()
		meta_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta_row.add_child(meta_spacer)

	var time_label := Label.new()
	time_label.text = _message_timestamp()
	time_label.add_theme_color_override("font_color", Color(0.4, 0.46, 0.56))
	time_label.add_theme_font_size_override("font_size", 10)
	meta_row.add_child(time_label)

	if safe_role != "user":
		var meta_tail_spacer := Control.new()
		meta_tail_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta_row.add_child(meta_tail_spacer)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	message_card.add_child(row)

	var palette := _message_palette(safe_role, badge_text)
	if safe_role == "user":
		var lead_spacer := Control.new()
		lead_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lead_spacer.size_flags_stretch_ratio = 0.22
		row.add_child(lead_spacer)

	var badge := Label.new()
	badge.text = badge_text
	badge.custom_minimum_size = Vector2(34, 34)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_color_override("font_color", palette["badge_fg"])
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_stylebox_override("normal", _pill_style(palette["badge_bg"], palette["badge_border"], 17))

	var bubble_shell := MarginContainer.new()
	bubble_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble_shell.size_flags_stretch_ratio = 0.78 if safe_role == "user" else 0.9
	bubble_shell.custom_minimum_size = Vector2(240, 0)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", _chat_bubble_style(palette["bubble_bg"], palette["bubble_border"]))
	bubble_shell.add_child(bubble)

	var bubble_margin := MarginContainer.new()
	bubble_margin.add_theme_constant_override("margin_left", 14)
	bubble_margin.add_theme_constant_override("margin_right", 14)
	bubble_margin.add_theme_constant_override("margin_top", 10)
	bubble_margin.add_theme_constant_override("margin_bottom", 10)
	bubble.add_child(bubble_margin)

	var bubble_label := Label.new()
	bubble_label.text = text
	bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble_label.add_theme_color_override("font_color", palette["text"])
	bubble_label.add_theme_font_size_override("font_size", 13)
	bubble_margin.add_child(bubble_label)

	if safe_role == "user":
		row.add_child(bubble_shell)
		row.add_child(badge)
	else:
		row.add_child(badge)
		row.add_child(bubble_shell)
		var tail_spacer := Control.new()
		tail_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tail_spacer.size_flags_stretch_ratio = 0.1
		row.add_child(tail_spacer)

	_animate_message_entry(message_card, bubble, safe_role)
	_call_scroll_to_bottom()


func _handle_incoming_message(raw: String) -> void:
	var decoded: Variant = JSON.parse_string(raw)
	if typeof(decoded) != TYPE_DICTIONARY:
		_add_message(raw)
		return
	var payload: Dictionary = decoded
	var category: String = str(payload.get("category", payload.get("type", "")))
	var message: String = _incoming_message_text(payload)
	if message.is_empty():
		message = raw
	_add_message(message, "assistant", _message_badge_from_category(category))


func _incoming_message_text(payload: Dictionary) -> String:
	for key in ["message", "content", "text", "reply"]:
		if payload.has(key):
			return str(payload.get(key, ""))
	var data_value: Variant = payload.get("data", null)
	if typeof(data_value) == TYPE_DICTIONARY:
		var data: Dictionary = data_value
		for key in ["message", "content", "text", "reply"]:
			if data.has(key):
				return str(data.get(key, ""))
	return ""


func _provider_id() -> String:
	match current_provider:
		"Claude":
			return "claude"
		"Ollama":
			return "ollama"
		_:
			return "chatgpt"


func _chat_request_payload(message: String) -> Dictionary:
	return {
		"type": "chat.request",
		"provider": _provider_id(),
		"provider_label": current_provider,
		"robot_id": AppState.active_robot_id,
		"default_frame": "map",
		"message": message,
		"prompt": message,
		"content": message,
		"context": {
			"robot_id": AppState.active_robot_id,
			"default_frame": "map",
		},
		"timestamp": Time.get_datetime_string_from_system(true, true),
	}


func _submit_prompt() -> void:
	var message := input.text.strip_edges()
	if message.is_empty():
		return
	_add_message(message, "user", current_provider.left(3).to_upper())
	input.text = ""
	var local_command: Dictionary = RcsAiPromptParser.parse(message, AppState.active_robot_id)
	if local_command.is_empty() and ws_peer != null and ws_peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_peer.send_text(JSON.stringify(_chat_request_payload(message)))
	prompt_submitted.emit(message)


func begin_navigation_session(robot_id: String, request_id: String) -> void:
	var clean_robot_id := robot_id.strip_edges()
	if clean_robot_id.is_empty():
		clean_robot_id = AppState.active_robot_id
	if clean_robot_id.is_empty():
		clean_robot_id = "burger1"
	navigation_sessions[clean_robot_id] = {
		"request_id": request_id.strip_edges(),
		"goal_id": "",
		"awaiting_goal_id": true,
	}
	last_navigation_status_keys.erase(clean_robot_id)
	last_navigation_result_keys.erase(clean_robot_id)


func note_navigation_feedback(robot_id: String, payload: Dictionary) -> void:
	if payload.is_empty():
		return
	var goal_id := str(payload.get("goal_id", "")).strip_edges()
	if goal_id.is_empty():
		return
	var clean_robot_id := robot_id.strip_edges()
	if clean_robot_id.is_empty():
		return
	var session := _navigation_session(clean_robot_id)
	session["goal_id"] = goal_id
	session["awaiting_goal_id"] = false
	navigation_sessions[clean_robot_id] = session


func add_navigation_status_event(robot_id: String, payload: Dictionary) -> void:
	if payload.is_empty():
		return
	var clean_robot_id := robot_id.strip_edges()
	if clean_robot_id.is_empty():
		return
	var status_list: Array = payload.get("status_list", []) as Array
	if status_list.is_empty():
		return
	var session := _navigation_session(clean_robot_id)
	var goal_id := str(session.get("goal_id", "")).strip_edges()
	var awaiting_goal_id := bool(session.get("awaiting_goal_id", false))
	var matched_status := _matching_navigation_status(status_list, goal_id)
	if matched_status.is_empty():
		if awaiting_goal_id:
			return
		if status_list.size() != 1:
			return
		var only_entry: Variant = status_list[0]
		if typeof(only_entry) != TYPE_DICTIONARY:
			return
		matched_status = only_entry as Dictionary
	var matched_goal_id := str(matched_status.get("goal_id", "")).strip_edges()
	if matched_goal_id.is_empty() and not goal_id.is_empty():
		matched_goal_id = goal_id
	if not matched_goal_id.is_empty():
		session["goal_id"] = matched_goal_id
		session["awaiting_goal_id"] = false
		navigation_sessions[clean_robot_id] = session
	var status_code := int(matched_status.get("status", 0))
	var dedupe_key := "%s:%s:%d" % [clean_robot_id, matched_goal_id, status_code]
	if last_navigation_status_keys.get(clean_robot_id, "") == dedupe_key:
		return
	last_navigation_status_keys[clean_robot_id] = dedupe_key
	var detail := "goal %s" % matched_goal_id.left(8) if not matched_goal_id.is_empty() else "goal pending"
	var message := "[%s] navigation 상태: %s (%s)" % [clean_robot_id, _navigation_status_label(status_code), detail]
	_add_message(message, "assistant", _navigation_status_badge(status_code))


func add_navigation_result_event(robot_id: String, payload: Dictionary) -> void:
	if payload.is_empty():
		return
	var clean_robot_id := robot_id.strip_edges()
	if clean_robot_id.is_empty():
		return
	var session := _navigation_session(clean_robot_id)
	var request_id := str(payload.get("request_id", "")).strip_edges()
	var session_request_id := str(session.get("request_id", "")).strip_edges()
	if not session_request_id.is_empty() and not request_id.is_empty() and request_id != session_request_id:
		return
	var status_code := int(payload.get("status_code", 0))
	var completed_goals := int(payload.get("completed_goals", 0))
	var dedupe_key := "%s:%s:%d:%d:%s" % [
		clean_robot_id,
		request_id,
		status_code,
		completed_goals,
		str(payload.get("success", false)),
	]
	if last_navigation_result_keys.get(clean_robot_id, "") == dedupe_key:
		return
	last_navigation_result_keys[clean_robot_id] = dedupe_key
	var summary := str(payload.get("message", "")).strip_edges()
	if summary.is_empty():
		summary = "request=%s, completed_goals=%d" % [request_id if not request_id.is_empty() else "n/a", completed_goals]
	var message := "[%s] navigation 결과: %s" % [clean_robot_id, summary]
	_add_message(message, "assistant", _navigation_result_badge(payload, status_code))
	if bool(payload.get("completed", false)) or status_code in [5, 6]:
		session["awaiting_goal_id"] = false
		navigation_sessions[clean_robot_id] = session


func _message_badge(role: String) -> String:
	match role:
		"user":
			return current_provider.left(3).to_upper()
		"system":
			return "SYS"
		_:
			return "AI"


func _message_badge_from_category(category: String) -> String:
	var clean := category.strip_edges().to_lower()
	match clean:
		"navigation", "nav":
			return "NAV"
		"ok", "success":
			return "OK"
		"error", "err", "failed", "failure":
			return "ERR"
		"system", "sys":
			return "SYS"
		"warning", "warn":
			return "WARN"
		_:
			return "AI"


func _navigation_session(robot_id: String) -> Dictionary:
	var existing: Variant = navigation_sessions.get(robot_id, {})
	if typeof(existing) == TYPE_DICTIONARY:
		return existing as Dictionary
	return {
		"request_id": "",
		"goal_id": "",
		"awaiting_goal_id": false,
	}


func _matching_navigation_status(status_list: Array, goal_id: String) -> Dictionary:
	if not goal_id.is_empty():
		for entry in status_list:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var status_entry: Dictionary = entry
			if str(status_entry.get("goal_id", "")).strip_edges() == goal_id:
				return status_entry
	return {}


func _navigation_status_label(status: int) -> String:
	match status:
		2:
			return "출발"
		3:
			return "취소 중"
		4:
			return "성공"
		5:
			return "취소 완료"
		6:
			return "실패"
		1:
			return "수락됨"
		_:
			return "대기"


func _navigation_status_badge(status: int) -> String:
	match status:
		2:
			return "NAV"
		3:
			return "WARN"
		4:
			return "OK"
		5:
			return "WARN"
		6:
			return "ERR"
		_:
			return "NAV"


func _navigation_result_badge(payload: Dictionary, status: int) -> String:
	if bool(payload.get("completed", false)) and (bool(payload.get("success", false)) or status == 4):
		return "OK"
	if bool(payload.get("accepted", false)) and not bool(payload.get("completed", false)):
		return "NAV"
	if status == 5:
		return "WARN"
	if status == 6:
		return "ERR"
	return "NAV"


func _message_palette(role: String, badge_text: String) -> Dictionary:
	match role:
		"user":
			return {
				"badge_bg": Color(0.08, 0.25, 0.46),
				"badge_border": Color(0.23, 0.56, 0.94),
				"badge_fg": Color(0.88, 0.95, 1.0),
				"bubble_bg": Color(0.12, 0.2, 0.34),
				"bubble_border": Color(0.2, 0.42, 0.78),
				"text": Color(0.92, 0.97, 1.0),
			}
		"system":
			return {
				"badge_bg": Color(0.2, 0.22, 0.27),
				"badge_border": Color(0.35, 0.38, 0.46),
				"badge_fg": Color(0.88, 0.9, 0.96),
				"bubble_bg": Color(0.08, 0.1, 0.13),
				"bubble_border": Color(0.2, 0.24, 0.31),
				"text": Color(0.8, 0.86, 0.94),
			}
		_:
			match badge_text:
				"NAV":
					return {
						"badge_bg": Color(0.07, 0.47, 0.45),
						"badge_border": Color(0.11, 0.68, 0.64),
						"badge_fg": Color(0.9, 1.0, 0.98),
						"bubble_bg": Color(0.12, 0.17, 0.27),
						"bubble_border": Color(0.18, 0.34, 0.62),
						"text": Color(0.9, 0.95, 1.0),
					}
				"OK":
					return {
						"badge_bg": Color(0.1, 0.44, 0.26),
						"badge_border": Color(0.17, 0.68, 0.4),
						"badge_fg": Color(0.93, 1.0, 0.95),
						"bubble_bg": Color(0.09, 0.23, 0.15),
						"bubble_border": Color(0.16, 0.56, 0.32),
						"text": Color(0.9, 0.98, 0.92),
					}
				"ERR":
					return {
						"badge_bg": Color(0.44, 0.13, 0.14),
						"badge_border": Color(0.78, 0.27, 0.3),
						"badge_fg": Color(1.0, 0.92, 0.93),
						"bubble_bg": Color(0.2, 0.1, 0.12),
						"bubble_border": Color(0.58, 0.21, 0.25),
						"text": Color(1.0, 0.92, 0.93),
					}
				"WARN":
					return {
						"badge_bg": Color(0.48, 0.3, 0.08),
						"badge_border": Color(0.87, 0.59, 0.17),
						"badge_fg": Color(1.0, 0.97, 0.9),
						"bubble_bg": Color(0.23, 0.17, 0.08),
						"bubble_border": Color(0.74, 0.52, 0.15),
						"text": Color(1.0, 0.95, 0.86),
					}
				_:
					return {
						"badge_bg": Color(0.18, 0.22, 0.34),
						"badge_border": Color(0.3, 0.39, 0.62),
						"badge_fg": Color(0.91, 0.95, 1.0),
						"bubble_bg": Color(0.11, 0.14, 0.21),
						"bubble_border": Color(0.22, 0.28, 0.45),
						"text": Color(0.9, 0.94, 1.0),
					}


func _message_timestamp() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%02d시 %02d분 %02d초" % [int(now.get("hour", 0)), int(now.get("minute", 0)), int(now.get("second", 0))]


func _refresh_transcript_width() -> void:
	if transcript_scroll == null or transcript_margin == null or transcript == null:
		return
	var target_width := maxf(0.0, transcript_scroll.size.x - 24.0)
	transcript_margin.custom_minimum_size = Vector2(target_width, 0.0)
	transcript.custom_minimum_size = Vector2(maxf(0.0, target_width - 16.0), 0.0)


func _chat_bubble_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	style.shadow_size = 8
	return style


func _animate_message_entry(message_card: Control, bubble: Control, role: String) -> void:
	var bubble_offset := -18.0 if role == "user" else 18.0
	bubble.position = Vector2(bubble_offset, 4.0)
	bubble.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(message_card, "modulate:a", 1.0, 0.22)
	tween.tween_property(message_card, "scale", Vector2.ONE, 0.26)
	tween.tween_property(bubble, "position:x", 0.0, 0.26)
	tween.tween_property(bubble, "position:y", 0.0, 0.26)
	tween.tween_property(bubble, "modulate:a", 1.0, 0.18)


func _call_scroll_to_bottom() -> void:
	call_deferred("_scroll_to_bottom")
	call_deferred("_scroll_to_bottom_late")


func _scroll_to_bottom() -> void:
	if transcript_scroll == null:
		return
	var bar := transcript_scroll.get_v_scroll_bar()
	if bar == null:
		return
	bar.value = bar.max_value


func _scroll_to_bottom_late() -> void:
	call_deferred("_scroll_to_bottom")


func _on_transcript_resized() -> void:
	_call_scroll_to_bottom()


func _on_input_gui_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if not key_event.ctrl_pressed:
		return
	if key_event.keycode != KEY_ENTER and key_event.keycode != KEY_KP_ENTER:
		return
	_submit_prompt()
	input.accept_event()


func _set_chat_status(connected: bool) -> void:
	if chat_status_label == null:
		return
	if connected:
		chat_status_label.text = "ONLINE"
		chat_status_label.add_theme_stylebox_override("normal", _pill_style(Color(0.04, 0.14, 0.06), Color(0.22, 0.72, 0.38)))
		chat_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	else:
		chat_status_label.text = "OFFLINE"
		chat_status_label.add_theme_stylebox_override("normal", _pill_style(Color(0.02, 0.025, 0.03), Color(0.25, 0.31, 0.38)))
		chat_status_label.add_theme_color_override("font_color", Color.WHITE)


func _connect_chat(endpoint: String) -> void:
	mcp_endpoint = endpoint.strip_edges()
	if mcp_endpoint.is_empty():
		AppState.push_event("MCP WS endpoint is empty")
		return
	if ws_peer != null:
		ws_peer.close()
		ws_peer = null
		ws_connected = false
	ws_peer = WebSocketPeer.new()
	var error := ws_peer.connect_to_url(mcp_endpoint)
	if error != OK:
		AppState.push_event("Chat WS connect failed: %s" % error_string(error))
		ws_peer = null
		_set_chat_status(false)
		return
	AppState.push_event("MCP WS connecting: %s" % mcp_endpoint)


func _disconnect_chat() -> void:
	if ws_peer != null:
		ws_peer.close()
		ws_peer = null
	ws_connected = false
	_set_chat_status(false)


func _open_connection_settings() -> void:
	if connection_popup != null:
		connection_popup.queue_free()

	connection_popup = PopupPanel.new()
	connection_popup.exclusive = true
	connection_popup.add_theme_stylebox_override("panel", _panel_style())
	add_child(connection_popup)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	connection_popup.add_child(root)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 16)
	header_margin.add_theme_constant_override("margin_right", 12)
	header_margin.add_theme_constant_override("margin_top", 14)
	header_margin.add_theme_constant_override("margin_bottom", 12)
	root.add_child(header_margin)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	header_margin.add_child(header_row)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_theme_constant_override("separation", 4)
	header_row.add_child(title_col)

	var title := Label.new()
	title.text = "Connection Settings"
	title.add_theme_color_override("font_color", Color(0.86, 0.9, 0.96))
	title.add_theme_font_size_override("font_size", 15)
	title_col.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "RMS /chat 소켓과 MQTT 연결 설정을 같은 방식으로 관리합니다."
	subtitle.add_theme_color_override("font_color", Color(0.42, 0.49, 0.58))
	subtitle.add_theme_font_size_override("font_size", 11)
	title_col.add_child(subtitle)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.add_theme_color_override("font_color", Color(0.55, 0.61, 0.7))
	close_btn.pressed.connect(func() -> void: connection_popup.hide())
	header_row.add_child(close_btn)

	root.add_child(_separator())

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 16)
	body_margin.add_theme_constant_override("margin_right", 16)
	body_margin.add_theme_constant_override("margin_top", 14)
	body_margin.add_theme_constant_override("margin_bottom", 16)
	root.add_child(body_margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body_margin.add_child(body)

	_add_modal_section_header(body, "CHAT")

	_add_modal_field_label(body, "MCP WebSocket")

	chat_endpoint_input = LineEdit.new()
	chat_endpoint_input.text = mcp_endpoint
	chat_endpoint_input.custom_minimum_size = Vector2(528, 30)
	chat_endpoint_input.add_theme_stylebox_override("normal", _input_style())
	chat_endpoint_input.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96))
	body.add_child(chat_endpoint_input)

	var chat_action_row := HBoxContainer.new()
	chat_action_row.add_theme_constant_override("separation", 8)
	body.add_child(chat_action_row)

	var chat_status_chip := Label.new()
	chat_status_chip.text = "ONLINE" if ws_connected else "OFFLINE"
	chat_status_chip.custom_minimum_size = Vector2(72, 30)
	chat_status_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chat_status_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if ws_connected:
		chat_status_chip.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
		chat_status_chip.add_theme_stylebox_override("normal", _pill_style(Color(0.04, 0.14, 0.06), Color(0.22, 0.72, 0.38)))
	else:
		chat_status_chip.add_theme_color_override("font_color", Color.WHITE)
		chat_status_chip.add_theme_stylebox_override("normal", _pill_style(Color(0.02, 0.025, 0.03), Color(0.25, 0.31, 0.38)))
	chat_action_row.add_child(chat_status_chip)

	var chat_toggle_btn := _dialog_button(
		"Disconnect Chat" if ws_connected else "Connect Chat",
		Color(0.28, 0.07, 0.08) if ws_connected else Color(0.06, 0.13, 0.28),
		Color(1.0, 0.46, 0.46) if ws_connected else Color(0.5, 0.7, 1.0)
	)
	chat_toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_toggle_btn.pressed.connect(func() -> void:
		mcp_endpoint = chat_endpoint_input.text.strip_edges()
		if ws_connected:
			_disconnect_chat()
		else:
			_connect_chat(mcp_endpoint)
		connection_popup.hide()
	)
	chat_action_row.add_child(chat_toggle_btn)

	body.add_child(_separator())

	_add_modal_section_header(body, "MQTT")

	_add_modal_field_label(body, "Broker URL")

	mqtt_broker_input = LineEdit.new()
	mqtt_broker_input.text = mqtt_broker_url
	mqtt_broker_input.placeholder_text = "ws://broker:9001/mqtt"
	mqtt_broker_input.custom_minimum_size = Vector2(528, 30)
	mqtt_broker_input.add_theme_stylebox_override("normal", _input_style())
	mqtt_broker_input.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96))
	body.add_child(mqtt_broker_input)

	_add_modal_field_label(body, "Robot ID")

	mqtt_robot_id_input = LineEdit.new()
	mqtt_robot_id_input.text = mqtt_robot_id if not mqtt_robot_id.is_empty() else AppState.active_robot_id
	mqtt_robot_id_input.placeholder_text = "burger1"
	mqtt_robot_id_input.custom_minimum_size = Vector2(528, 30)
	mqtt_robot_id_input.add_theme_stylebox_override("normal", _input_style())
	mqtt_robot_id_input.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96))
	body.add_child(mqtt_robot_id_input)

	var mqtt_row := HBoxContainer.new()
	mqtt_row.add_theme_constant_override("separation", 6)
	body.add_child(mqtt_row)

	var connect_mqtt_btn := _dialog_button("Connect MQTT", Color(0.05, 0.22, 0.1), Color(0.4, 0.9, 0.56))
	connect_mqtt_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connect_mqtt_btn.pressed.connect(func() -> void:
		mqtt_broker_url = mqtt_broker_input.text.strip_edges()
		mqtt_robot_id = mqtt_robot_id_input.text.strip_edges()
		connect_requested.emit(mqtt_broker_url, mqtt_robot_id)
		connection_popup.hide()
	)
	mqtt_row.add_child(connect_mqtt_btn)

	var disconnect_mqtt_btn := _dialog_button("Disconnect MQTT", Color(0.28, 0.07, 0.08), Color(1.0, 0.46, 0.46))
	disconnect_mqtt_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disconnect_mqtt_btn.pressed.connect(func() -> void:
		disconnect_requested.emit()
		connection_popup.hide()
	)
	mqtt_row.add_child(disconnect_mqtt_btn)

	connection_popup.popup_centered(Vector2i(560, 460))


func _add_section_header(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.42, 0.49, 0.58))
	label.add_theme_font_size_override("font_size", 10)
	parent.add_child(label)


func _add_modal_section_header(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.42, 0.49, 0.58))
	label.add_theme_font_size_override("font_size", 10)
	parent.add_child(label)


func _add_modal_field_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.44, 0.51, 0.6))
	parent.add_child(label)


func _separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	return sep


func _dialog_button(text: String, bg: Color, fg: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 32)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _button_style(bg, bg.lightened(0.18)))
	button.add_theme_stylebox_override("hover", _button_style(bg.lightened(0.06), bg.lightened(0.28)))
	button.add_theme_color_override("font_color", fg)
	return button


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.028, 0.038, 0.055)
	style.border_color = Color(0.13, 0.2, 0.3)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.24)
	style.shadow_size = 16
	return style


func _box_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.022, 0.03, 0.047)
	style.border_color = Color(0.12, 0.19, 0.29)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	style.shadow_size = 10
	return style


func _input_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.036, 0.05, 0.075)
	style.border_color = Color(0.16, 0.28, 0.42)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style


func _pill_style(bg: Color, border: Color, radius := 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
