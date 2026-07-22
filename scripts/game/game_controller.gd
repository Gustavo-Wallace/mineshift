class_name GameController
extends Control

enum GameState { READY, PLAYING, WON, LOST }

const BOARD_WIDTH := 9
const BOARD_HEIGHT := 9
const MINE_COUNT := 10
const MAX_DISPLAY_TIME := 999

@onready var board_view: BoardView = %BoardView
@onready var mines_label: Label = %MinesLabel
@onready var time_label: Label = %TimeLabel
@onready var state_label: Label = %StateLabel
@onready var field_panel: PanelContainer = %FieldPanel
@onready var new_field_button: Button = %NewFieldButton

var board: BoardModel
var state := GameState.READY
var elapsed_time := 0.0
var _displayed_second := -1


func _ready() -> void:
	board_view.cell_reveal_requested.connect(_on_reveal_requested)
	board_view.cell_flag_requested.connect(_on_flag_requested)
	new_field_button.pressed.connect(start_new_field)
	start_new_field()


func _process(delta: float) -> void:
	if state != GameState.PLAYING:
		return
	elapsed_time += delta
	var current_second := mini(int(elapsed_time), MAX_DISPLAY_TIME)
	if current_second != _displayed_second:
		_displayed_second = current_second
		_update_time_label()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("new_field"):
		start_new_field()
		get_viewport().set_input_as_handled()


func start_new_field() -> void:
	state = GameState.READY
	elapsed_time = 0.0
	_displayed_second = 0
	board = BoardModel.new(BOARD_WIDTH, BOARD_HEIGHT, MINE_COUNT)
	board_view.build(BOARD_WIDTH, BOARD_HEIGHT)
	field_panel.remove_theme_stylebox_override("panel")
	_update_hud()


func _on_reveal_requested(position: Vector2i) -> void:
	if state == GameState.WON or state == GameState.LOST or board.is_flagged(position):
		return
	if state == GameState.READY:
		board.place_mines(position)
		state = GameState.PLAYING

	var result: Dictionary = board.reveal(position)
	var changed: Array[Vector2i] = result["changed"]
	for changed_position in changed:
		board_view.refresh_cell(board, changed_position)

	if result["hit_mine"]:
		_finish_loss(position)
	elif board.all_safe_cells_revealed():
		_finish_win()
	else:
		_update_hud()


func _on_flag_requested(position: Vector2i) -> void:
	if state == GameState.WON or state == GameState.LOST:
		return
	if board.toggle_flag(position):
		board_view.refresh_cell(board, position)
		_update_mines_label()


func _finish_win() -> void:
	state = GameState.WON
	board_view.show_win(board)
	field_panel.add_theme_stylebox_override("panel", _make_outcome_style(Color("255d54")))
	_update_hud()


func _finish_loss(exploded_position: Vector2i) -> void:
	state = GameState.LOST
	board_view.show_loss(board, exploded_position)
	field_panel.add_theme_stylebox_override("panel", _make_outcome_style(Color("7a3040")))
	_update_hud()


func _update_hud() -> void:
	_update_mines_label()
	_update_time_label()
	match state:
		GameState.READY:
			state_label.text = "FIELD READY"
			state_label.modulate = Color("9aa8bc")
		GameState.PLAYING:
			state_label.text = "FIELD ACTIVE"
			state_label.modulate = Color("65ddff")
		GameState.WON:
			state_label.text = "FIELD CLEARED"
			state_label.modulate = Color("67e8a5")
		GameState.LOST:
			state_label.text = "FIELD BREACHED"
			state_label.modulate = Color("ff7185")


func _update_mines_label() -> void:
	mines_label.text = "MINES %03d" % (MINE_COUNT - board.flags_placed)


func _update_time_label() -> void:
	time_label.text = "TIME %03d" % mini(int(elapsed_time), MAX_DISPLAY_TIME)


func _make_outcome_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111925")
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20.0)
	return style
