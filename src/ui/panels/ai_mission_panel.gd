extends PanelContainer

signal prompt_submitted(message: String)

var input: TextEdit
var transcript: VBoxContainer


func _ready() -> void:
	_build_ui()


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

	var status := Label.new()
	status.text = "OFFLINE"
	status.custom_minimum_size = Vector2(78, 24)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color.WHITE)
	status.add_theme_stylebox_override("normal", _pill_style(Color(0.02, 0.025, 0.03), Color(0.25, 0.31, 0.38)))
	header.add_child(status)

	var providers := HBoxContainer.new()
	providers.add_theme_constant_override("separation", 6)
	column.add_child(providers)
	for provider in ["Claude", "ChatGPT", "Ollama"]:
		providers.add_child(_provider_chip(provider, provider == "ChatGPT"))

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

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_theme_stylebox_override("panel", _box_style())
	column.add_child(scroll)

	transcript = VBoxContainer.new()
	transcript.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transcript.add_theme_constant_override("separation", 12)
	scroll.add_child(transcript)
	_add_message("RCS routes natural-language commands through RMS chat and shows navigation lifecycle events in one timeline.")

	input = TextEdit.new()
	input.placeholder_text = "Message ChatGPT..."
	input.custom_minimum_size = Vector2(0, 72)
	input.add_theme_stylebox_override("normal", _input_style())
	column.add_child(input)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)

	var hint := Label.new()
	hint.text = "Ctrl+Enter to send"
	hint.add_theme_color_override("font_color", Color(0.45, 0.52, 0.62))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)

	var send := Button.new()
	send.text = "Send to ChatGPT"
	send.custom_minimum_size = Vector2(124, 32)
	send.add_theme_stylebox_override("normal", _button_style(Color(0.16, 0.19, 0.24), Color(0.25, 0.3, 0.38)))
	send.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
	send.pressed.connect(_submit_prompt)
	footer.add_child(send)


func _provider_chip(text: String, active: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = active
	button.custom_minimum_size = Vector2(64, 24)
	var bg := Color(0.09, 0.105, 0.13) if active else Color(0.07, 0.08, 0.1)
	var border := Color(0.38, 0.44, 0.52) if active else Color(0.17, 0.2, 0.25)
	button.add_theme_stylebox_override("normal", _button_style(bg, border))
	button.add_theme_color_override("font_color", Color(0.8, 0.86, 0.94))
	return button


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


func _add_message(text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	transcript.add_child(row)

	var avatar := Label.new()
	avatar.text = "G"
	avatar.custom_minimum_size = Vector2(28, 28)
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.add_theme_color_override("font_color", Color.WHITE)
	avatar.add_theme_stylebox_override("normal", _pill_style(Color(0.12, 0.15, 0.2), Color(0.12, 0.15, 0.2), 14))
	row.add_child(avatar)

	var bubble := Label.new()
	bubble.text = text
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.add_theme_color_override("font_color", Color(0.88, 0.93, 1.0))
	row.add_child(bubble)


func _submit_prompt() -> void:
	var message := input.text.strip_edges()
	if message.is_empty():
		return
	_add_message(message)
	input.text = ""
	prompt_submitted.emit(message)


func _add_section_header(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.42, 0.49, 0.58))
	label.add_theme_font_size_override("font_size", 10)
	parent.add_child(label)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.055, 0.068)
	style.border_color = Color(0.16, 0.19, 0.24)
	style.set_border_width_all(1)
	return style


func _box_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.036, 0.044, 0.055)
	style.border_color = Color(0.13, 0.16, 0.2)
	style.set_border_width_all(1)
	return style


func _input_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.021, 0.026)
	style.border_color = Color(0.18, 0.22, 0.28)
	style.set_border_width_all(1)
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
