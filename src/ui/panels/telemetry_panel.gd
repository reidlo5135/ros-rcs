extends PanelContainer

var connection_value: Label
var event_list: ItemList


func _ready() -> void:
	_build_ui()
	_sync_connection_state(AppState.connection_state)
	AppState.connection_state_changed.connect(_sync_connection_state)
	AppState.event_pushed.connect(_on_event_pushed)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Telemetry"
	column.add_child(title)

	var status := GridContainer.new()
	status.columns = 2
	status.add_theme_constant_override("h_separation", 12)
	status.add_theme_constant_override("v_separation", 8)
	column.add_child(status)

	_add_status_row(status, "Robot", AppState.active_robot_id)
	_add_status_row(status, "Mode", "Navigation")
	connection_value = _add_status_row(status, "Transport", "Disconnected")
	_add_status_row(status, "Scene", "Godot 4.6")

	column.add_child(HSeparator.new())

	event_list = ItemList.new()
	event_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(event_list)

	for entry in AppState.events:
		_add_event_item(entry)


func _add_status_row(parent: Control, key_text: String, value_text: String) -> Label:
	var key := Label.new()
	key.text = key_text
	parent.add_child(key)

	var value := Label.new()
	value.text = value_text
	parent.add_child(value)
	return value


func _sync_connection_state(next_state: String) -> void:
	if connection_value != null:
		connection_value.text = next_state


func _on_event_pushed(entry: Dictionary) -> void:
	_add_event_item(entry)


func _add_event_item(entry: Dictionary) -> void:
	if event_list == null:
		return
	event_list.add_item("%s  %s" % [entry.get("time", "--:--:--"), entry.get("message", "")])
	while event_list.item_count > AppState.max_events:
		event_list.remove_item(0)
	if event_list.item_count > 0:
		event_list.select(event_list.item_count - 1)
	event_list.ensure_current_is_visible()
