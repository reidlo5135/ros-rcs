extends PanelContainer

const APP_VERSION := "0.2.0"

signal control_mode_changed(mode: String)

var connection_label: Label
var battery_label: Label
var manual_button: Button
var ai_button: Button
var current_mode := "manual"


func _ready() -> void:
	_build_ui()
	connection_label.text = AppState.connection_state
	AppState.connection_state_changed.connect(_on_connection_state_changed)
	SessionRegistry.telemetry_updated.connect(_on_telemetry_updated)


func _build_ui() -> void:
	custom_minimum_size = Vector2(0, 46)
	add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.058, 0.06), Color(0.2, 0.24, 0.23)))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var title := Label.new()
	title.text = "RCS"
	title.add_theme_color_override("font_color", Color(0.95, 0.74, 0.29))
	title.add_theme_font_size_override("font_size", 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	row.add_child(_chip("Fixed Frame: map", 122))

	connection_label = Label.new()
	connection_label.custom_minimum_size = Vector2(98, 24)
	connection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connection_label.add_theme_color_override("font_color", Color(0.84, 0.92, 0.92))
	connection_label.add_theme_stylebox_override("normal", _chip_style())
	row.add_child(connection_label)

	row.add_child(_chip("Pose -0.40, -0.10, 0.00", 150))

	var mode_group := ButtonGroup.new()
	manual_button = _mode_button("MANUAL", "manual", mode_group)
	ai_button = _mode_button("AI", "ai", mode_group)
	row.add_child(manual_button)
	row.add_child(ai_button)
	manual_button.button_pressed = true

	row.add_child(_chip("signal --", 82))
	battery_label = _chip("battery --%", 98)
	row.add_child(battery_label)
	row.add_child(_chip("v" + APP_VERSION, 54))


func _mode_button(label_text: String, mode: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = label_text
	button.toggle_mode = true
	button.button_group = group
	button.custom_minimum_size = Vector2(88, 24)
	button.add_theme_stylebox_override("normal", _chip_style())
	button.add_theme_stylebox_override("hover", _chip_style(Color(0.1, 0.12, 0.12), Color(0.29, 0.36, 0.34)))
	button.add_theme_stylebox_override("pressed", _chip_style(Color(0.15, 0.18, 0.15), Color(0.95, 0.74, 0.29)))
	button.add_theme_color_override("font_color", Color(0.82, 0.88, 0.9))
	button.add_theme_color_override("font_pressed_color", Color(0.98, 0.89, 0.66))
	button.pressed.connect(func() -> void:
		current_mode = mode
		control_mode_changed.emit(mode)
	)
	return button


func _chip(text: String, min_width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.66, 0.72, 0.74))
	label.add_theme_stylebox_override("normal", _chip_style())
	return label


func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_bottom = 1
	style.border_width_top = 1
	return style


func _chip_style(bg := Color(0.037, 0.041, 0.042), border := Color(0.2, 0.25, 0.24)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style


func _on_connection_state_changed(next_state: String) -> void:
	connection_label.text = next_state


func _on_telemetry_updated(session_id: String, _patch: Dictionary) -> void:
	if session_id != SessionRegistry.active_session_id or battery_label == null:
		return
	if not SessionRegistry.sessions.has(session_id):
		return
	var session := SessionRegistry.sessions[session_id] as Dictionary
	var state: Variant = session.get("state")
	if state == null:
		return
	var battery: Variant = state.get("battery_state")
	if typeof(battery) != TYPE_DICTIONARY or (battery as Dictionary).is_empty():
		return
	var pct := float((battery as Dictionary).get("percentage", -1.0))
	if pct < 0.0:
		return
	battery_label.text = "battery %.0f%%" % (pct * 100.0 if pct <= 1.0 else pct)
