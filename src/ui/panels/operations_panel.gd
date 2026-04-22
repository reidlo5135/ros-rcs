extends PanelContainer

signal connect_requested(broker_url: String, robot_id: String)
signal disconnect_requested()
signal goal_requested()
signal cancel_requested()
signal reset_world_requested()

const AVAILABLE_ROBOT_IDS := ["burger1"]

var broker_input: LineEdit
var robot_selector: OptionButton


func _ready() -> void:
	_build_ui()


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
	title.text = "Operations"
	column.add_child(title)

	var broker_label := Label.new()
	broker_label.text = "Broker WS"
	column.add_child(broker_label)

	broker_input = LineEdit.new()
	broker_input.text = "ws://192.168.61.35:9001/mqtt"
	broker_input.placeholder_text = "ws://broker:9001/mqtt"
	column.add_child(broker_input)

	var robot_label := Label.new()
	robot_label.text = "Robot ID"
	column.add_child(robot_label)

	robot_selector = OptionButton.new()
	for robot_id in AVAILABLE_ROBOT_IDS:
		robot_selector.add_item(robot_id)
	robot_selector.select(max(0, AVAILABLE_ROBOT_IDS.find(AppState.active_robot_id)))
	column.add_child(robot_selector)

	_add_button(column, "Connect", func() -> void:
		connect_requested.emit(broker_input.text, _selected_robot_id())
	)
	_add_button(column, "Disconnect", func() -> void:
		disconnect_requested.emit()
	)

	column.add_child(HSeparator.new())

	var command_label := Label.new()
	command_label.text = "Commands"
	column.add_child(command_label)

	_add_button(column, "Set Goal", func() -> void:
		goal_requested.emit()
	)
	_add_button(column, "Cancel", func() -> void:
		cancel_requested.emit()
	)
	_add_button(column, "Reset World", func() -> void:
		reset_world_requested.emit()
	)


func _add_button(parent: Control, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)


func _selected_robot_id() -> String:
	if robot_selector.get_item_count() <= 0:
		return "burger1"
	return robot_selector.get_item_text(robot_selector.get_selected())
