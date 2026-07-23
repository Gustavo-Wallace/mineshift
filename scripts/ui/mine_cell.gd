class_name MineCell
extends Control

signal reveal_requested(position: Vector2i, logic_probe_requested: bool)
signal flag_toggle_requested(position: Vector2i)

const DEFAULT_CELL_SIZE := 54.0
const NUMBER_COLORS: Array[Color] = [
	Color.TRANSPARENT,
	Color("62c6ff"),
	Color("67e8a5"),
	Color("ffca5c"),
	Color("ff9f55"),
	Color("ff7185"),
	Color("ff4f61"),
	Color("f06dff"),
	Color("fff0f3"),
]

var board_position := Vector2i.ZERO
var revealed := false
var flagged := false
var confirmed_flag := false
var logic_probe_mode := false
var contains_mine := false
var neutralized := false
var adjacent_count := 0
var exploded := false
var wrong_flag := false
var locked := false
var can_chord := false
var resolved := false

var _hovered := false
var _pressed := false


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		set_cell_size(DEFAULT_CELL_SIZE)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	queue_redraw()


func configure(cell_position: Vector2i, cell_size: float = DEFAULT_CELL_SIZE) -> void:
	board_position = cell_position
	set_cell_size(cell_size)
	tooltip_text = "Cell %d, %d" % [cell_position.x + 1, cell_position.y + 1]


func set_cell_size(cell_size: float) -> void:
	custom_minimum_size = Vector2(cell_size, cell_size)


func set_visual_state(
	is_revealed: bool,
	is_flagged: bool,
	is_confirmed_flag: bool,
	has_mine: bool,
	nearby_mines: int,
	is_neutralized: bool = false,
	is_exploded: bool = false,
	is_wrong_flag: bool = false,
	is_locked: bool = false,
	is_chord_available: bool = false,
	is_resolved: bool = false
) -> void:
	revealed = is_revealed
	flagged = is_flagged
	confirmed_flag = is_confirmed_flag
	contains_mine = has_mine
	neutralized = is_neutralized
	adjacent_count = nearby_mines
	exploded = is_exploded
	wrong_flag = is_wrong_flag
	locked = is_locked
	can_chord = is_chord_available
	resolved = is_resolved
	mouse_default_cursor_shape = Control.CURSOR_ARROW if locked else Control.CURSOR_POINTING_HAND
	queue_redraw()


func pulse_recalculation() -> void:
	pivot_offset = size * 0.5
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func set_logic_probe_mode(enabled: bool) -> void:
	logic_probe_mode = enabled
	mouse_default_cursor_shape = Control.CURSOR_CROSS if enabled and not revealed and not flagged and not neutralized and not locked else (Control.CURSOR_ARROW if locked else Control.CURSOR_POINTING_HAND)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_pressed = mouse_event.pressed
			queue_redraw()
			if not mouse_event.pressed:
				reveal_requested.emit(board_position, mouse_event.shift_pressed)
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			flag_toggle_requested.emit(board_position)
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_SPACE:
			reveal_requested.emit(board_position, key_event.shift_pressed)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		_pressed = false
		queue_redraw()
	elif what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if revealed or neutralized or (contains_mine and locked):
		_draw_revealed(rect)
	else:
		_draw_closed(rect)

	if wrong_flag:
		_draw_wrong_flag(rect)
	elif neutralized:
		_draw_neutralized_mine(rect)
	elif flagged:
		_draw_flag(rect, Color("67e8a5") if resolved or confirmed_flag else Color("65ddff"))
		if confirmed_flag:
			_draw_confirmed_seal(rect)
	elif contains_mine and locked:
		_draw_mine(rect)

	if revealed and not contains_mine and not neutralized and adjacent_count > 0:
		_draw_number(rect)

	if has_focus() and not locked:
		draw_rect(rect.grow(-2.0), Color("a5efff"), false, 1.5)
	elif logic_probe_mode and _hovered and not revealed and not flagged and not neutralized and not locked:
		draw_rect(rect.grow(-3.0), Color("f06dff"), false, 2.5)
		var center := rect.get_center()
		draw_line(center - Vector2(7, 0), center + Vector2(7, 0), Color("f06dff"), 1.5)
		draw_line(center - Vector2(0, 7), center + Vector2(0, 7), Color("f06dff"), 1.5)
	elif can_chord and _hovered and not locked:
		draw_rect(rect.grow(-2.0), Color("67e8a5"), false, 2.0)


func _draw_closed(rect: Rect2) -> void:
	var fill := Color("263145")
	if _pressed:
		fill = Color("1d2738")
	elif _hovered:
		fill = Color("32415a")
	draw_rect(rect.grow(-1.0), fill, true)
	draw_line(Vector2(2, 2), Vector2(size.x - 2, 2), Color("4a5d78"), 2.0)
	draw_line(Vector2(2, 2), Vector2(2, size.y - 2), Color("4a5d78"), 2.0)
	draw_line(Vector2(2, size.y - 2), Vector2(size.x - 2, size.y - 2), Color("151c29"), 2.0)
	draw_line(Vector2(size.x - 2, 2), Vector2(size.x - 2, size.y - 2), Color("151c29"), 2.0)


func _draw_revealed(rect: Rect2) -> void:
	var fill := Color("141c29")
	var border := Color("253247")
	if exploded:
		fill = Color("6b2433")
		border = Color("ff7185")
	elif neutralized:
		fill = Color("1c252d")
		border = Color("7b8da1")
	elif resolved:
		fill = Color("142a27")
		border = Color("67e8a5")
	draw_rect(rect.grow(-1.0), fill, true)
	draw_rect(rect.grow(-1.0), border, false, 1.0)


func _draw_number(rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var font_size := maxi(17, int(minf(size.x, size.y) * 0.52))
	var text := str(adjacent_count)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var origin := Vector2((rect.size.x - text_size.x) * 0.5, (rect.size.y + text_size.y) * 0.5 - 2.0)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, NUMBER_COLORS[adjacent_count])


func _draw_flag(rect: Rect2, color: Color) -> void:
	var center := rect.get_center()
	var unit := minf(size.x, size.y) / 39.0
	var pole_x := center.x - 4.0 * unit
	draw_line(Vector2(pole_x, center.y - 11.0 * unit), Vector2(pole_x, center.y + 10.0 * unit), color, 2.5 * unit)
	var banner := PackedVector2Array([
		Vector2(pole_x, center.y - 11.0 * unit),
		Vector2(pole_x + 13.0 * unit, center.y - 5.0 * unit),
		Vector2(pole_x, center.y + 1.0 * unit),
	])
	draw_colored_polygon(banner, color)
	draw_line(Vector2(pole_x - 7.0 * unit, center.y + 11.0 * unit), Vector2(pole_x + 7.0 * unit, center.y + 11.0 * unit), color, 2.5 * unit)


func _draw_mine(rect: Rect2) -> void:
	var center := rect.get_center()
	var color := Color("ff7185") if exploded else Color("e3e9f3")
	var radius := minf(size.x, size.y) * 0.18
	draw_circle(center, radius, color)
	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_line(center + direction * radius, center + direction * radius * 1.65, color, 2.0)
	for direction in [Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(), Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()]:
		draw_line(center + direction * radius, center + direction * radius * 1.45, color, 1.5)
	draw_circle(center - Vector2(radius * 0.3, radius * 0.3), radius * 0.2, Color("141c29"))


func _draw_neutralized_mine(rect: Rect2) -> void:
	var center := rect.get_center()
	var unit := minf(size.x, size.y) / 44.0
	var color := Color("ff7185") if exploded else Color("8fa0b4")
	var radius := 8.0 * unit
	draw_circle(center, radius, Color("141c29"))
	draw_arc(center, radius, 0.0, TAU, 24, color, 2.2 * unit)
	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_line(center + direction * radius, center + direction * radius * 1.5, color, 1.8 * unit)
	draw_line(center - Vector2(12, 12) * unit, center + Vector2(12, 12) * unit, color, 3.0 * unit)
	draw_line(center + Vector2(-10, 10) * unit, center + Vector2(10, -10) * unit, color.darkened(0.2), 1.5 * unit)


func _draw_wrong_flag(rect: Rect2) -> void:
	_draw_flag(rect, Color("ff7185"))
	var center := rect.get_center()
	draw_line(center - Vector2(12, 12), center + Vector2(12, 12), Color("ff7185"), 2.5)
	draw_line(center + Vector2(-12, 12), center + Vector2(12, -12), Color("ff7185"), 2.5)


func _draw_confirmed_seal(rect: Rect2) -> void:
	var center := rect.get_center()
	var radius := minf(size.x, size.y) * 0.34
	var diamond := PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0),
		center + Vector2(0, -radius),
	])
	draw_polyline(diamond, Color("67e8a5"), 2.0)
