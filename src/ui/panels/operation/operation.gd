extends PanelContainer

const TopicCatalogScript := preload("res://src/domain/protocol/topic_catalog.gd")

class LayerIcon:
	extends Control

	var icon_kind := "grid"
	var icon_color := Color.WHITE

	func _init(kind := "grid", color := Color.WHITE) -> void:
		icon_kind = kind
		icon_color = color
		custom_minimum_size = Vector2(18, 18)

	func _draw() -> void:
		match icon_kind:
			"grid":
				for offset in [5.0, 9.0, 13.0]:
					draw_line(Vector2(offset, 2), Vector2(offset, 16), icon_color, 1.2)
					draw_line(Vector2(2, offset), Vector2(16, offset), icon_color, 1.2)
			"map":
				var points := PackedVector2Array([Vector2(3, 5), Vector2(7, 3), Vector2(12, 5), Vector2(15, 3), Vector2(15, 14), Vector2(11, 16), Vector2(6, 14), Vector2(3, 16)])
				draw_polyline(points, icon_color, 1.5, true)
			"costmap_global":
				draw_rect(Rect2(3, 3, 12, 12), icon_color, false, 1.4)
				draw_line(Vector2(9, 3), Vector2(9, 15), icon_color, 1.2)
				draw_line(Vector2(3, 9), Vector2(15, 9), icon_color, 1.2)
			"costmap_local":
				draw_rect(Rect2(5, 5, 8, 8), icon_color, false, 1.5)
				draw_circle(Vector2(9, 9), 2.0, icon_color)
			"footprint":
				var poly := PackedVector2Array([Vector2(5, 4), Vector2(13, 6), Vector2(14, 12), Vector2(8, 15), Vector2(3, 11)])
				draw_polyline(poly, icon_color, 1.5, true)
			"robot":
				draw_rect(Rect2(5, 6, 8, 7), icon_color, false, 1.4)
				draw_line(Vector2(9, 2), Vector2(9, 6), icon_color, 1.2)
				draw_line(Vector2(2, 9), Vector2(5, 9), icon_color, 1.2)
				draw_line(Vector2(13, 9), Vector2(16, 9), icon_color, 1.2)
				draw_circle(Vector2(9, 15), 1.5, icon_color)
			"global_plan":
				draw_line(Vector2(3, 14), Vector2(8, 9), icon_color, 1.4)
				draw_line(Vector2(8, 9), Vector2(14, 4), icon_color, 1.4)
				draw_circle(Vector2(3, 14), 1.6, icon_color)
				draw_circle(Vector2(8, 9), 1.6, icon_color)
				draw_circle(Vector2(14, 4), 1.6, icon_color)
			"local_plan":
				draw_line(Vector2(4, 14), Vector2(7, 10), icon_color, 1.4)
				draw_line(Vector2(7, 10), Vector2(11, 10), icon_color, 1.4)
				draw_line(Vector2(11, 10), Vector2(14, 5), icon_color, 1.4)
				draw_circle(Vector2(4, 14), 1.5, icon_color)
				draw_circle(Vector2(14, 5), 1.5, icon_color)
			"scan":
				draw_arc(Vector2(9, 12), 7, PI, PI * 1.55, 18, icon_color, 1.5)
				draw_line(Vector2(9, 12), Vector2(3, 12), icon_color, 1.0)
				draw_line(Vector2(9, 12), Vector2(7, 5), icon_color, 1.0)
			"tf":
				draw_line(Vector2(9, 13), Vector2(9, 4), icon_color, 1.5)
				draw_line(Vector2(9, 13), Vector2(15, 13), icon_color, 1.5)
				draw_line(Vector2(9, 13), Vector2(5, 16), icon_color, 1.5)
			_:
				draw_circle(Vector2(9, 9), 5, icon_color)

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

signal connect_requested(broker_url: String, robot_id: String)
signal disconnect_requested()
signal navigation_requested(goals: Array)
signal cancel_requested()
signal clear_requested()
signal initial_pose_requested(position: Vector3, yaw: float)
signal waypoint_placing_toggled(enabled: bool)
signal layer_visibility_changed(layer_id: String, enabled: bool)

var broker_input: LineEdit
var robot_id_input: LineEdit
var placing_button: Button
var waypoint_list: ItemList
var waypoints: Array[Dictionary] = []
var placing_enabled := false
var topic_settings_popup: PopupPanel
var topic_editor_fields := {}


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	custom_minimum_size = Vector2(272, 0)
	add_theme_stylebox_override("panel", _panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_add_section_header(column, "GLOBAL OPTIONS")

	_add_field_label(column, "Broker WS")

	broker_input = LineEdit.new()
	broker_input.text = "ws://192.168.61.35:9001/mqtt"
	broker_input.placeholder_text = "ws://broker:9001/mqtt"
	broker_input.add_theme_stylebox_override("normal", _input_style())
	column.add_child(broker_input)

	_add_field_label(column, "Robot ID")

	robot_id_input = LineEdit.new()
	robot_id_input.text = AppState.active_robot_id
	robot_id_input.placeholder_text = "burger1"
	robot_id_input.add_theme_stylebox_override("normal", _input_style())
	column.add_child(robot_id_input)

	var connection_row := HBoxContainer.new()
	connection_row.add_theme_constant_override("separation", 6)
	column.add_child(connection_row)

	_add_button(connection_row, "Connect", Color(0.25, 0.29, 0.35), Color(0.82, 0.88, 0.96), func() -> void:
		connect_requested.emit(broker_input.text, _selected_robot_id())
	)
	_add_button(connection_row, "Disconnect", Color(0.04, 0.25, 0.28), Color(0.28, 0.96, 1.0), func() -> void:
		disconnect_requested.emit()
	)

	column.add_child(_separator())

	_add_section_header(column, "COMMAND", func() -> void:
		_open_topic_settings("command")
	)
	waypoint_list = ItemList.new()
	waypoint_list.custom_minimum_size = Vector2(0, 68)
	waypoint_list.add_theme_stylebox_override("panel", _input_style())
	column.add_child(waypoint_list)

	placing_button = _add_button(column, "+ Add Waypoint", Color(0.06, 0.13, 0.28), Color(0.5, 0.7, 1.0), func() -> void:
		set_placing_enabled(not placing_enabled)
	)

	var command_row := HBoxContainer.new()
	command_row.add_theme_constant_override("separation", 6)
	column.add_child(command_row)

	_add_button(command_row, "Send", Color(0.05, 0.22, 0.1), Color(0.4, 0.9, 0.56), func() -> void:
		if waypoints.is_empty():
			AppState.push_event("Add a waypoint before sending")
			return
		navigation_requested.emit(waypoints.duplicate(true))
	)
	_add_button(command_row, "Cancel", Color(0.28, 0.07, 0.08), Color(1.0, 0.46, 0.46), func() -> void:
		cancel_requested.emit()
	)

	var utility_row := HBoxContainer.new()
	utility_row.add_theme_constant_override("separation", 6)
	column.add_child(utility_row)

	_add_button(utility_row, "Clear", Color(0.15, 0.17, 0.2), Color(0.56, 0.6, 0.66), func() -> void:
		clear_waypoints()
		clear_requested.emit()
	)
	_add_button(utility_row, "Init Pose", Color(0.04, 0.23, 0.25), Color(0.28, 1.0, 0.92), func() -> void:
		var waypoint := _selected_or_last_waypoint()
		if waypoint.is_empty():
			AppState.push_event("Add a waypoint before setting init pose")
			return
		initial_pose_requested.emit(waypoint["position"], waypoint["yaw"])
	)

	column.add_child(_separator())

	_add_section_header(column, "VISUALIZATION", func() -> void:
		_open_topic_settings("viz")
	)
	var layers := [
		["Grid", "grid", "grid", Color(0.42, 0.55, 1.0)],
		["Map", "map", "map", Color(0.66, 0.45, 1.0)],
		["Global Costmap", "global_costmap", "costmap_global", Color(0.0, 0.9, 1.0)],
		["Local Costmap", "local_costmap", "costmap_local", Color(1.0, 0.38, 0.82)],
		["Exact Footprint", "exact_footprint", "footprint", Color(0.42, 0.62, 1.0)],
		["Robot", "robot", "robot", Color(0.7, 0.76, 0.84)],
		["Global Plan", "global_plan", "global_plan", Color(0.0, 0.75, 1.0)],
		["Local Plan", "local_plan", "local_plan", Color(0.48, 1.0, 0.1)],
		["LaserScan", "scan", "scan", Color(0.25, 0.95, 0.35)],
		["TF", "tf", "tf", Color(0.7, 0.48, 1.0)],
	]
	for layer in layers:
		column.add_child(_layer_row(layer[0], layer[1], layer[2], layer[3]))


func _add_section_header(parent: Control, text: String, action := Callable()) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.56, 0.62, 0.64))
	label.add_theme_font_size_override("font_size", 11)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	if action.is_valid():
		var gear := GearButton.new()
		gear.pressed.connect(action)
		row.add_child(gear)


func _add_field_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.62, 0.68, 0.7))
	parent.add_child(label)


func _add_button(parent: Control, label: String, bg: Color, fg: Color, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 34)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _button_style(bg, bg.lightened(0.18)))
	button.add_theme_stylebox_override("hover", _button_style(bg.lightened(0.06), bg.lightened(0.28)))
	button.add_theme_color_override("font_color", fg)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _layer_row(label_text: String, layer_id: String, icon_kind: String, accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)

	var toggle := CheckBox.new()
	toggle.button_pressed = true
	toggle.custom_minimum_size = Vector2(22, 22)
	toggle.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	toggle.toggled.connect(func(enabled: bool) -> void:
		layer_visibility_changed.emit(layer_id, enabled)
	)
	row.add_child(toggle)

	row.add_child(LayerIcon.new(icon_kind, accent))

	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", Color(0.66, 0.72, 0.74))
	row.add_child(label)
	return row


func set_placing_enabled(enabled: bool) -> void:
	placing_enabled = enabled
	if placing_button != null:
		if placing_enabled:
			placing_button.text = "Placing..."
			placing_button.add_theme_stylebox_override("normal", _button_style(Color(0.12, 0.09, 0.04), Color(1.0, 0.78, 0.38)))
			placing_button.add_theme_color_override("font_color", Color(1.0, 0.66, 0.13))
		else:
			placing_button.text = "+ Add Waypoint"
			placing_button.add_theme_stylebox_override("normal", _button_style(Color(0.06, 0.13, 0.28), Color(0.06, 0.13, 0.28).lightened(0.18)))
			placing_button.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	waypoint_placing_toggled.emit(placing_enabled)


func add_waypoint(position: Vector3, yaw: float) -> void:
	waypoints.append({
		"position": position,
		"yaw": yaw,
	})
	_rebuild_waypoint_list()


func clear_waypoints() -> void:
	waypoints.clear()
	if waypoint_list != null:
		waypoint_list.clear()
	if placing_enabled:
		set_placing_enabled(false)


func waypoint_count() -> int:
	return waypoints.size()


func _rebuild_waypoint_list() -> void:
	if waypoint_list == null:
		return
	waypoint_list.clear()
	for index in range(waypoints.size()):
		var waypoint := waypoints[index]
		var position := waypoint["position"] as Vector3
		var yaw := float(waypoint["yaw"])
		waypoint_list.add_item("%d  x %.2f  y %.2f  yaw %.2f" % [index + 1, position.x, position.z, yaw])
	if waypoint_list.item_count > 0:
		waypoint_list.select(waypoint_list.item_count - 1)


func _selected_or_last_waypoint() -> Dictionary:
	if waypoints.is_empty():
		return {}
	var selected := waypoint_list.get_selected_items() if waypoint_list != null else PackedInt32Array()
	if selected.size() > 0 and selected[0] >= 0 and selected[0] < waypoints.size():
		return waypoints[selected[0]]
	return waypoints[waypoints.size() - 1]


func _selected_robot_id() -> String:
	if robot_id_input == null:
		return "burger1"
	var robot_id := robot_id_input.text.strip_edges()
	return robot_id if not robot_id.is_empty() else "burger1"


func _separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 4)
	return separator


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.058, 0.06)
	style.border_color = Color(0.2, 0.24, 0.23)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _input_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.036, 0.039, 0.041)
	style.border_color = Color(0.19, 0.25, 0.24)
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _open_topic_settings(group: String) -> void:
	if topic_settings_popup != null:
		topic_settings_popup.queue_free()

	topic_editor_fields = {}
	topic_settings_popup = PopupPanel.new()
	topic_settings_popup.name = "TopicSettingsPopup"
	topic_settings_popup.exclusive = true
	topic_settings_popup.add_theme_stylebox_override("panel", _panel_style())
	add_child(topic_settings_popup)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(720, 640)
	root.add_theme_constant_override("separation", 0)
	topic_settings_popup.add_child(root)

	var header := MarginContainer.new()
	header.add_theme_constant_override("margin_left", 14)
	header.add_theme_constant_override("margin_right", 10)
	header.add_theme_constant_override("margin_top", 12)
	header.add_theme_constant_override("margin_bottom", 10)
	root.add_child(header)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	header.add_child(header_row)

	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 4)
	header_row.add_child(title_column)

	var title := Label.new()
	title.text = "Command Topic Settings" if group == "command" else "Visualization Topic Settings"
	title.add_theme_color_override("font_color", Color(0.86, 0.9, 0.96))
	title.add_theme_font_size_override("font_size", 15)
	title_column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Edit the command topics used by the operator controls and save them locally." if group == "command" else "Edit the viz topics bound to the Visualization list and save them locally."
	subtitle.add_theme_color_override("font_color", Color(0.42, 0.49, 0.58))
	subtitle.add_theme_font_size_override("font_size", 11)
	title_column.add_child(subtitle)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.flat = true
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_button.add_theme_color_override("font_color", Color(0.55, 0.61, 0.7))
	close_button.pressed.connect(func() -> void:
		topic_settings_popup.hide()
	)
	header_row.add_child(close_button)

	var separator := HSeparator.new()
	root.add_child(separator)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 516)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var body_margin := MarginContainer.new()
	body_margin.custom_minimum_size = Vector2(700, 0)
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 14)
	body_margin.add_theme_constant_override("margin_right", 14)
	body_margin.add_theme_constant_override("margin_top", 12)
	body_margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(body_margin)

	var fields_column := VBoxContainer.new()
	fields_column.custom_minimum_size = Vector2(672, 0)
	fields_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields_column.add_theme_constant_override("separation", 10)
	body_margin.add_child(fields_column)

	for entry in TopicCatalogScript.topic_entries(group):
		_add_topic_field(fields_column, entry)

	var footer := MarginContainer.new()
	footer.add_theme_constant_override("margin_left", 14)
	footer.add_theme_constant_override("margin_right", 14)
	footer.add_theme_constant_override("margin_top", 12)
	footer.add_theme_constant_override("margin_bottom", 12)
	root.add_child(footer)

	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 8)
	footer.add_child(footer_row)

	var status := Label.new()
	status.text = "Saved locally and restored on next launch."
	status.add_theme_color_override("font_color", Color(0.48, 0.55, 0.64))
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(status)

	var cancel := _dialog_button("Cancel", Color(0.28, 0.07, 0.08), Color(1.0, 0.62, 0.62))
	cancel.pressed.connect(func() -> void:
		topic_settings_popup.hide()
	)
	footer_row.add_child(cancel)

	var save := _dialog_button("Save", Color(0.05, 0.22, 0.1), Color(0.4, 0.9, 0.56))
	save.pressed.connect(func() -> void:
		_save_topic_settings(group)
		topic_settings_popup.hide()
	)
	footer_row.add_child(save)

	topic_settings_popup.popup_centered(Vector2i(720, 640))


func _add_topic_field(parent: Control, entry: Dictionary) -> void:
	var field_group := VBoxContainer.new()
	field_group.custom_minimum_size = Vector2(672, 0)
	field_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_group.add_theme_constant_override("separation", 5)
	parent.add_child(field_group)

	var label := Label.new()
	label.text = str(entry.get("label", "Topic"))
	label.add_theme_color_override("font_color", Color(0.42, 0.49, 0.58))
	field_group.add_child(label)

	var input := LineEdit.new()
	input.text = str(entry.get("value", ""))
	input.custom_minimum_size = Vector2(0, 30)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_stylebox_override("normal", _input_style())
	input.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96))
	field_group.add_child(input)
	topic_editor_fields[str(entry.get("key", ""))] = input


func _save_topic_settings(group: String) -> void:
	var values := {}
	for key in topic_editor_fields.keys():
		var input := topic_editor_fields[key] as LineEdit
		values[key] = input.text
	AppState.set_topic_settings(group, values)


func _dialog_button(text: String, bg: Color, fg: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(84, 32)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _button_style(bg, bg.lightened(0.18)))
	button.add_theme_stylebox_override("hover", _button_style(bg.lightened(0.06), bg.lightened(0.28)))
	button.add_theme_color_override("font_color", fg)
	return button
