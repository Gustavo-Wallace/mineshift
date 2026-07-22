class_name GameController
extends Control

enum GameState { READY, PLAYING, WON, LOST }

const BOARD_WIDTH := 9
const BOARD_HEIGHT := 9
const MINE_COUNT := 10
const MAX_DISPLAY_TIME := 999
const SAFE_CELL_COUNT := BOARD_WIDTH * BOARD_HEIGHT - MINE_COUNT

@onready var board_view: BoardView = %BoardView
@onready var score_feedback: ScoreFeedback = %ScoreFeedback
@onready var score_label: Label = %ScoreLabel
@onready var streak_label: Label = %StreakLabel
@onready var multiplier_label: Label = %MultiplierLabel
@onready var actions_label: Label = %ActionsLabel
@onready var mines_label: Label = %MinesLabel
@onready var time_label: Label = %TimeLabel
@onready var state_label: Label = %StateLabel
@onready var field_panel: PanelContainer = %FieldPanel
@onready var new_field_button: Button = %NewFieldButton
@onready var result_panel: PanelContainer = %ResultPanel
@onready var result_title: Label = %ResultTitle
@onready var result_body: Label = %ResultBody
@onready var result_button: Button = %ResultButton

var board: BoardModel
var scoring := ScoreController.new()
var state := GameState.READY
var elapsed_time := 0.0
var _displayed_second := -1


func _ready() -> void:
	board_view.cell_reveal_requested.connect(_on_reveal_requested)
	board_view.cell_flag_requested.connect(_on_flag_requested)
	new_field_button.pressed.connect(start_new_field)
	result_button.pressed.connect(start_new_field)
	scoring.score_event_created.connect(_on_score_event_created)
	scoring.metrics_changed.connect(_update_score_hud)
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
	scoring.reset()
	board_view.build(BOARD_WIDTH, BOARD_HEIGHT)
	score_feedback.clear_feedback()
	result_panel.hide()
	field_panel.remove_theme_stylebox_override("panel")
	_update_hud()


func _on_reveal_requested(position: Vector2i) -> void:
	if state == GameState.WON or state == GameState.LOST or board.is_flagged(position):
		return
	if board.is_revealed(position):
		_try_chord(position)
		return
	if state == GameState.READY:
		board.place_mines(position)
		state = GameState.PLAYING

	var clicked_adjacent := board.adjacent_mines(position)
	var result: Dictionary = board.reveal(position)
	var changed: Array[Vector2i] = result["changed"]
	_refresh_changed_cells(changed)
	var automatic_counts := _get_safe_adjacent_counts(changed, position)
	scoring.record_manual_reveal(position, clicked_adjacent, automatic_counts, result["hit_mine"])

	if result["hit_mine"]:
		_finish_loss(position)
	elif board.all_safe_cells_revealed():
		_finish_win()
	else:
		_update_hud()


func _try_chord(position: Vector2i) -> void:
	if state != GameState.PLAYING:
		return
	var result: Dictionary = board.chord(position)
	if not result["performed"]:
		return
	var changed: Array[Vector2i] = result["changed"]
	_refresh_changed_cells(changed)
	var automatic_counts := _get_safe_adjacent_counts(changed)
	scoring.record_chord(position, board.adjacent_mines(position), automatic_counts, result["hit_mine"])
	if result["hit_mine"]:
		_finish_loss(result["exploded_position"])
	elif board.all_safe_cells_revealed():
		_finish_win()
	else:
		_update_hud()


func _on_flag_requested(position: Vector2i) -> void:
	if state == GameState.WON or state == GameState.LOST:
		return
	if board.toggle_flag(position):
		scoring.record_flag_action()
		board_view.refresh_cell(board, position)
		for neighbor in board.get_neighbors(position):
			if board.is_revealed(neighbor):
				board_view.refresh_cell(board, neighbor)
		_update_hud()


func _finish_win() -> void:
	state = GameState.WON
	var flag_counts := _count_flags()
	scoring.apply_victory_bonuses(flag_counts.x, flag_counts.y)
	board_view.show_win(board)
	field_panel.add_theme_stylebox_override("panel", _make_outcome_style(Color("255d54")))
	_show_win_result()
	_update_hud()


func _finish_loss(exploded_position: Vector2i) -> void:
	state = GameState.LOST
	board_view.show_loss(board, exploded_position)
	field_panel.add_theme_stylebox_override("panel", _make_outcome_style(Color("7a3040")))
	_show_loss_result()
	_update_hud()


func _refresh_changed_cells(changed: Array[Vector2i]) -> void:
	for changed_position in changed:
		board_view.refresh_cell(board, changed_position)


func _get_safe_adjacent_counts(changed: Array[Vector2i], excluded_position := Vector2i(-1, -1)) -> Array[int]:
	var counts: Array[int] = []
	for position in changed:
		if position != excluded_position and not board.has_mine(position):
			counts.append(board.adjacent_mines(position))
	return counts


func _count_flags() -> Vector2i:
	var correct := 0
	var incorrect := 0
	for y in board.height:
		for x in board.width:
			var position := Vector2i(x, y)
			if not board.is_flagged(position):
				continue
			if board.has_mine(position):
				correct += 1
			else:
				incorrect += 1
	return Vector2i(correct, incorrect)


func _on_score_event_created(event: ScoreEvent) -> void:
	score_feedback.show_score_feedback(board_view.get_cell_global_center(event.position), event)


func _show_win_result() -> void:
	result_title.text = "FIELD CLEARED"
	result_title.modulate = Color("67e8a5")
	result_body.text = """REVEALS             %6d
CASCADE CELLS        %6d
CASCADE BONUS        %6d
FLAGS                %6d
FIELD CLEAR          %6d
ACCURACY             %6d
EFFICIENCY           %6d

TOTAL                %6d
TIME                   %03d
ACTIONS                %03d
BEST SAFE STREAK        %02d""" % [
		scoring.manual_reveal_points,
		scoring.cascade_cell_points,
		scoring.cascade_bonus_points,
		scoring.flag_bonus_points,
		scoring.clear_bonus_points,
		scoring.accuracy_bonus_points,
		scoring.efficiency_bonus_points,
		scoring.current_score,
		mini(int(elapsed_time), MAX_DISPLAY_TIME),
		scoring.actions_taken,
		scoring.highest_safe_reveal_streak,
	]
	result_button.text = "NEW FIELD"
	result_panel.show()


func _show_loss_result() -> void:
	var completion := 100.0 * float(board.revealed_safe_count) / float(SAFE_CELL_COUNT)
	result_title.text = "FIELD BREACHED"
	result_title.modulate = Color("ff7185")
	result_body.text = """SCORE                %6d
TIME                   %03d
ACTIONS                %03d
BEST SAFE STREAK        %02d
SAFE CELLS             %02d/%02d
FIELD COMPLETE        %5.1f%%""" % [
		scoring.current_score,
		mini(int(elapsed_time), MAX_DISPLAY_TIME),
		scoring.actions_taken,
		scoring.highest_safe_reveal_streak,
		board.revealed_safe_count,
		SAFE_CELL_COUNT,
		completion,
	]
	result_button.text = "TRY AGAIN"
	result_panel.show()


func _update_hud() -> void:
	_update_score_hud()
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


func _update_score_hud() -> void:
	if not is_node_ready():
		return
	score_label.text = "SCORE %06d" % scoring.current_score
	streak_label.text = "STREAK %02d" % scoring.safe_reveal_streak
	multiplier_label.text = "×%.2f" % scoring.get_streak_multiplier()
	multiplier_label.modulate = Color("67e8a5") if scoring.get_streak_multiplier() > 1.0 else Color("65738a")
	actions_label.text = "ACTIONS %03d" % scoring.actions_taken


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
