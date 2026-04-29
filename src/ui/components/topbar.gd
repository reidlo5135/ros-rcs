extends PanelContainer

const TOPBAR_BG := Color(0.09, 0.098, 0.114)
const CHIP_BG := Color(0.067, 0.075, 0.094)
const LINE_STRONG := Color(0.2, 0.23, 0.28)
const TEXT_MUTED := Color(0.47, 0.52, 0.62)
const TEXT_PRIMARY := Color(0.88, 0.91, 0.96)
const ACCENT_AMBER := Color(0.95, 0.69, 0.33)
const ACCENT_AMBER_BG := Color(0.28, 0.17, 0.04, 0.9)
const ACCENT_BLUE := Color(0.49, 0.71, 1.0)
const ACCENT_BLUE_BG := Color(0.12, 0.24, 0.55, 0.75)

signal control_mode_changed(mode: String)


class PingWidget:
	extends Control

	var ping_ms := -1.0
	var _style: StyleBoxFlat

	func _ready() -> void:
		custom_minimum_size = Vector2(100, 24)
		_style = StyleBoxFlat.new()
		_style.bg_color = CHIP_BG
		_style.border_color = LINE_STRONG
		_style.set_border_width_all(1)
		_style.corner_radius_top_left = 2
		_style.corner_radius_top_right = 2
		_style.corner_radius_bottom_left = 2
		_style.corner_radius_bottom_right = 2

	func update(ms: float) -> void:
		ping_ms = ms
		queue_redraw()

	func _bars_count() -> int:
		if ping_ms < 0.0: return 0
		if ping_ms < 50.0: return 4
		if ping_ms < 150.0: return 3
		if ping_ms < 300.0: return 2
		if ping_ms < 600.0: return 1
		return 0

	func _quality_color() -> Color:
		if ping_ms < 0.0: return TEXT_MUTED
		if ping_ms < 50.0: return Color(0.33, 0.86, 0.45)
		if ping_ms < 150.0: return Color(0.72, 0.84, 0.27)
		if ping_ms < 300.0: return ACCENT_AMBER
		if ping_ms < 600.0: return Color(0.89, 0.47, 0.26)
		return Color(0.84, 0.3, 0.3)

	func _draw() -> void:
		if _style != null:
			draw_style_box(_style, Rect2(Vector2.ZERO, size))
		var color := _quality_color()
		var count := _bars_count()
		var dim := Color(color.r, color.g, color.b, 0.22)
		for i in range(4):
			var bar_h := 5.0 + float(i) * 3.0
			var bx := 8.0 + float(i) * 7.0
			var by := size.y - bar_h - 4.0
			draw_rect(Rect2(bx, by, 4.0, bar_h), color if i < count else dim)
		var font := ThemeDB.fallback_font
		var text := "--" if ping_ms < 0.0 else "%.0f ms" % ping_ms
		var text_color := color if ping_ms >= 0.0 else TEXT_MUTED
		draw_string(font, Vector2(39.0, size.y - 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_color)


class BatteryWidget:
	extends Control

	var level := -1.0
	var _style: StyleBoxFlat

	func _ready() -> void:
		custom_minimum_size = Vector2(96, 24)
		_style = StyleBoxFlat.new()
		_style.bg_color = CHIP_BG
		_style.border_color = LINE_STRONG
		_style.set_border_width_all(1)
		_style.corner_radius_top_left = 2
		_style.corner_radius_top_right = 2
		_style.corner_radius_bottom_left = 2
		_style.corner_radius_bottom_right = 2

	func update(lv: float) -> void:
		level = lv
		queue_redraw()

	func _fill_color() -> Color:
		if level > 0.5: return Color(0.18, 0.81, 0.43)
		if level > 0.20: return Color(0.83, 0.66, 0.13)
		return Color(0.84, 0.27, 0.27)

	func _draw() -> void:
		if _style != null:
			draw_style_box(_style, Rect2(Vector2.ZERO, size))
		var pad := 8.0
		var bar_w := 30.0
		var bh := 12.0
		var by := (size.y - bh) * 0.5
		var outline := Color(0.6, 0.64, 0.72, 0.48)
		draw_rect(Rect2(pad, by, bar_w, bh), outline, false, 1.2)
		var nub_h := bh * 0.40
		var nub_y := by + (bh - nub_h) * 0.5
		draw_rect(Rect2(pad + bar_w + 1.5, nub_y, 3.0, nub_h), outline)
		if level >= 0.0:
			var fill_w := maxf(0.0, (bar_w - 2.0) * clamp(level, 0.0, 1.0))
			draw_rect(Rect2(pad + 1.0, by + 1.0, fill_w, bh - 2.0), _fill_color())
		var font := ThemeDB.fallback_font
		var text := "--%"  if level < 0.0 else "%.0f%%" % (level * 100.0)
		var text_color := TEXT_MUTED if level < 0.0 else TEXT_PRIMARY
		draw_string(font, Vector2(pad + bar_w + 10.0, size.y - 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_color)

var ping_widget = null
var battery_widget = null
var manual_button: Button
var ai_button: Button
var mode_tabset_panel: Panel
var mode_indicator: Panel
var mode_buttons_row: HBoxContainer
var mode_indicator_tween: Tween
var current_mode := "manual"


func _ready() -> void:
	_build_ui()
	AppState.connection_state_changed.connect(_on_connection_state_changed)
	SessionRegistry.telemetry_updated.connect(_on_telemetry_updated)
	call_deferred("_refresh_mode_button_styles", false)


func _build_ui() -> void:
	custom_minimum_size = Vector2(0, 36)
	add_theme_stylebox_override("panel", _panel_style())

	var accent_strip := ColorRect.new()
	accent_strip.color = ACCENT_AMBER
	accent_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	accent_strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	accent_strip.custom_minimum_size = Vector2(3, 0)
	accent_strip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(accent_strip)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)

	var title := Label.new()
	title.text = "RCS"
	title.add_theme_color_override("font_color", ACCENT_AMBER)
	title.add_theme_font_size_override("font_size", 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	row.add_child(_chip("Fixed Frame: map", 112))

	row.add_child(_chip("Pose -0.40, -0.10, 0.00", 146))

	var mode_group := ButtonGroup.new()
	manual_button = _mode_button("MANUAL", "manual", mode_group)
	ai_button = _mode_button("AI", "ai", mode_group)
	row.add_child(_mode_tabset([manual_button, ai_button]))
	manual_button.button_pressed = true

	ping_widget = PingWidget.new()
	row.add_child(ping_widget)
	battery_widget = BatteryWidget.new()
	row.add_child(battery_widget)
	row.add_child(_chip("v" + AppState.app_version(), 52))


func _mode_button(label_text: String, mode: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = label_text
	button.toggle_mode = true
	button.flat = true
	button.button_group = group
	button.custom_minimum_size = Vector2(82, 20)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("normal", _tab_button_style())
	button.add_theme_stylebox_override("hover", _tab_button_style())
	button.add_theme_stylebox_override("pressed", _tab_button_style())
	button.pressed.connect(func() -> void:
		current_mode = mode
		_refresh_mode_button_styles(true)
		control_mode_changed.emit(mode)
	)
	return button


func _mode_tabset(buttons: Array[Button]) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(167, 24)
	panel.add_theme_stylebox_override("panel", _tabset_style())
	mode_tabset_panel = panel
	panel.clip_contents = true

	mode_indicator = Panel.new()
	mode_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_indicator.position = Vector2.ONE
	mode_indicator.size = Vector2(82, 20)
	panel.add_child(mode_indicator)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	row.offset_left = 1
	row.offset_top = 1
	row.offset_right = -1
	row.offset_bottom = -1
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(row)
	mode_buttons_row = row

	for button in buttons:
		row.add_child(button)

	return panel


func _refresh_mode_button_styles(animated := false) -> void:
	var manual_active := manual_button != null and manual_button.button_pressed
	var ai_active := ai_button != null and ai_button.button_pressed
	_apply_mode_button_state(manual_button, manual_active, ACCENT_BLUE)
	_apply_mode_button_state(ai_button, ai_active, ACCENT_AMBER)
	if manual_active:
		_move_mode_indicator(manual_button, ACCENT_BLUE, ACCENT_BLUE_BG, animated)
	elif ai_active:
		_move_mode_indicator(ai_button, ACCENT_AMBER, ACCENT_AMBER_BG, animated)


func _apply_mode_button_state(button: Button, active: bool, accent: Color) -> void:
	if button == null:
		return
	button.add_theme_color_override("font_color", accent if active else TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", accent if active else TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", accent)


func _move_mode_indicator(button: Button, accent: Color, bg: Color, animated: bool) -> void:
	if button == null or mode_indicator == null or mode_buttons_row == null:
		return
	mode_indicator.add_theme_stylebox_override("panel", _mode_indicator_style(accent, bg))
	var target_position := mode_buttons_row.position + button.position
	var target_size := button.size
	if mode_indicator_tween != null:
		mode_indicator_tween.kill()
		mode_indicator_tween = null
	if not animated:
		mode_indicator.position = target_position
		mode_indicator.size = target_size
		return
	mode_indicator_tween = create_tween()
	mode_indicator_tween.set_parallel(true)
	mode_indicator_tween.set_trans(Tween.TRANS_QUAD)
	mode_indicator_tween.set_ease(Tween.EASE_OUT)
	mode_indicator_tween.tween_property(mode_indicator, "position", target_position, 0.16)
	mode_indicator_tween.tween_property(mode_indicator, "size", target_size, 0.16)


func _chip(text: String, min_width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_stylebox_override("normal", _chip_style())
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = TOPBAR_BG
	style.border_color = LINE_STRONG
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.draw_center = true
	style.shadow_size = 0
	style.border_width_left = 0
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_width_top = 1
	return style


func _chip_style(bg := CHIP_BG, border := LINE_STRONG) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style


func _tabset_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CHIP_BG
	style.border_color = LINE_STRONG
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 1
	style.content_margin_right = 1
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


func _tab_button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style


func _mode_indicator_style(accent: Color, bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = accent
	style.set_border_width_all(1)
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	return style


func _on_connection_state_changed(next_state: String) -> void:
	if next_state != "Connected" and ping_widget != null:
		ping_widget.update(-1.0)


func _on_telemetry_updated(session_id: String, _patch: Dictionary) -> void:
	if session_id != SessionRegistry.active_session_id:
		return
	if not SessionRegistry.sessions.has(session_id):
		return
	var session := SessionRegistry.sessions[session_id] as Dictionary
	var state: Variant = session.get("state")
	if state == null:
		return
	var battery: Variant = state.get("battery_state")
	if typeof(battery) == TYPE_DICTIONARY and not (battery as Dictionary).is_empty():
		var pct := float((battery as Dictionary).get("percentage", -1.0))
		if pct >= 0.0 and battery_widget != null:
			battery_widget.update(pct if pct <= 1.0 else pct / 100.0)
	var sys_result: Variant = state.get("system_result")
	if typeof(sys_result) == TYPE_DICTIONARY and ping_widget != null:
		var ping := _extract_ping_from(sys_result as Dictionary)
		if ping >= 0.0:
			ping_widget.update(ping)


func _extract_ping_from(payload: Dictionary) -> float:
	for key in ["ping_ms", "latency_ms", "rtt_ms"]:
		if payload.has(key):
			return maxf(0.0, float(payload.get(key, -1.0)))
	if payload.has("sent_at_ms"):
		var sent_at_ms := float(payload.get("sent_at_ms", -1.0))
		if sent_at_ms > 0.0:
			return maxf(0.0, float(Time.get_unix_time_from_system() * 1000.0) - sent_at_ms)
	if payload.has("bridge_time_ms"):
		var v := float(payload.get("bridge_time_ms", -1.0))
		if v >= 0.0 and v < 600000.0:
			return v
	return -1.0
