class_name MineCell
extends Control

signal reveal_requested(position: Vector2i)
signal flag_toggle_requested(position: Vector2i)

const CELL_SIZE := Vector2(42.0, 42.0)
const NUMBER_COLORS: Array[Color] = [
	Color.TRANSPARENT,
	Color("62c6ff"),
	Color("67e8a5"),
	Color("ffca5c"),
	Color("ad8cff"),
	Color("ff7185"),
	Color("54dfda"),
	Color("f0a3ff"),
	Color("d7dce8"),
]

var board_position := Vector2i.ZERO
var revealed := false
var flagged := false
var contains_mine := false
var adjacent_count := 0
var exploded := false
var wrong_flag := false
var locked := false

var _hovered := false
var _pressed := false


func _ready() -> void:
	custom_minimum_size = CELL_SIZE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	queue_redraw()


func configure(position: Vector2i) -> void:
	board_position = position
	tooltip_text = "Cell %d, %d" % [position.x + 1, position.y + 1]


func set_visual_state(
	is_revealed: bool,
	is_flagged: bool,
	has_mine: bool,
	nearby_mines: int,
	is_exploded: bool = false,
	is_wrong_flag: bool = false,
	is_locked: bool = false
) -> void:
	revealed = is_revealed
	flagged = is_flagged
	contains_mine = has_mine
	adjacent_count = nearby_mines
	exploded = is_exploded
	wrong_flag = is_wrong_flag
	locked = is_locked
	mouse_default_cursor_shape = Control.CURSOR_ARROW if locked else Control.CURSOR_POINTING_HAND
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
				reveal_requested.emit(board_position)
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			flag_toggle_requested.emit(board_position)
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_SPACE:
			reveal_requested.emit(board_position)
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
	if revealed or (contains_mine and locked):
		_draw_revealed(rect)
	else:
		_draw_closed(rect)

	if wrong_flag:
		_draw_wrong_flag(rect)
	elif flagged:
		_draw_flag(rect, Color("65ddff"))
	elif contains_mine and locked:
		_draw_mine(rect)

	if revealed and not contains_mine and adjacent_count > 0:
		_draw_number(rect)

	if has_focus() and not locked:
		draw_rect(rect.grow(-2.0), Color("a5efff"), false, 1.5)


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
	draw_rect(rect.grow(-1.0), fill, true)
	draw_rect(rect.grow(-1.0), border, false, 1.0)


func _draw_number(rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 22
	var text := str(adjacent_count)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var origin := Vector2((rect.size.x - text_size.x) * 0.5, (rect.size.y + text_size.y) * 0.5 - 2.0)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, NUMBER_COLORS[adjacent_count])


func _draw_flag(rect: Rect2, color: Color) -> void:
	var center := rect.get_center()
	var pole_x := center.x - 4.0
	draw_line(Vector2(pole_x, center.y - 11.0), Vector2(pole_x, center.y + 10.0), color, 2.5)
	var banner := PackedVector2Array([
		Vector2(pole_x, center.y - 11.0),
		Vector2(pole_x + 13.0, center.y - 5.0),
		Vector2(pole_x, center.y + 1.0),
	])
	draw_colored_polygon(banner, color)
	draw_line(Vector2(pole_x - 7.0, center.y + 11.0), Vector2(pole_x + 7.0, center.y + 11.0), color, 2.5)


func _draw_mine(rect: Rect2) -> void:
	var center := rect.get_center()
	var color := Color("ff7185") if exploded else Color("e3e9f3")
	draw_circle(center, 7.0, color)
	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_line(center + direction * 7.0, center + direction * 12.0, color, 2.0)
	for direction in [Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(), Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()]:
		draw_line(center + direction * 7.0, center + direction * 10.5, color, 1.5)
	draw_circle(center - Vector2(2.0, 2.0), 1.5, Color("141c29"))


func _draw_wrong_flag(rect: Rect2) -> void:
	_draw_flag(rect, Color("ff7185"))
	var center := rect.get_center()
	draw_line(center - Vector2(12, 12), center + Vector2(12, 12), Color("ff7185"), 2.5)
	draw_line(center + Vector2(-12, 12), center + Vector2(12, -12), Color("ff7185"), 2.5)
