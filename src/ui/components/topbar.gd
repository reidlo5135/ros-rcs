extends PanelContainer

const APP_VERSION := "0.2.0"

var connection_label: Label


func _ready() -> void:
	_build_ui()
	connection_label.text = AppState.connection_state
	AppState.connection_state_changed.connect(_on_connection_state_changed)


func _build_ui() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)

	var title := Label.new()
	title.text = "RCS Operator Runtime"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var version := Label.new()
	version.text = "v" + APP_VERSION
	row.add_child(version)

	connection_label = Label.new()
	row.add_child(connection_label)


func _on_connection_state_changed(next_state: String) -> void:
	connection_label.text = next_state
