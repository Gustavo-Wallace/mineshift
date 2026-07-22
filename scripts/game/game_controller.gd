class_name GameController
extends Control

enum FieldState { READY, PLAYING, CLEARED, LOST }

@onready var game_screen: Control = %GameScreen
@onready var start_screen: Control = %StartScreen
@onready var start_run_button: Button = %StartRunButton
@onready var board_view: BoardView = %BoardView
@onready var field_label: Label = %FieldLabel
@onready var state_label: Label = %StateLabel
@onready var mines_label: Label = %MinesLabel
@onready var time_label: Label = %TimeLabel
@onready var restart_button: Button = %RestartButton
@onready var pause_button: Button = %PauseButton
@onready var abandon_button: Button = %AbandonButton

@onready var field_result_screen: Control = %FieldResultScreen
@onready var field_result_title: Label = %FieldResultTitle
@onready var field_result_body: Label = %FieldResultBody
@onready var next_field_button: Button = %NextFieldButton

@onready var run_summary_screen: Control = %RunSummaryScreen
@onready var run_summary_title: Label = %RunSummaryTitle
@onready var run_summary_body: Label = %RunSummaryBody
@onready var retry_run_button: Button = %RetryRunButton
@onready var summary_menu_button: Button = %SummaryMenuButton

@onready var pause_screen: Control = %PauseScreen
@onready var resume_button: Button = %ResumeButton
@onready var pause_restart_button: Button = %PauseRestartButton
@onready var pause_abandon_button: Button = %PauseAbandonButton
@onready var pause_menu_button: Button = %PauseMenuButton

@onready var confirm_overlay: Control = %ConfirmOverlay
@onready var confirm_title: Label = %ConfirmTitle
@onready var confirm_copy: Label = %ConfirmCopy
@onready var confirm_leave_button: Button = %ConfirmLeaveButton
@onready var cancel_leave_button: Button = %CancelLeaveButton

var board: BoardModel
var run: RunController = RunController.new()
var state := FieldState.READY
var elapsed_time := 0.0
var _displayed_second := -1
var _paused := false


func _ready() -> void:
	board_view.cell_reveal_requested.connect(_on_reveal_requested)
	board_view.cell_flag_requested.connect(_on_flag_requested)
	start_run_button.pressed.connect(start_new_run)
	restart_button.pressed.connect(restart_current_field)
	pause_button.pressed.connect(_show_pause)
	abandon_button.pressed.connect(_show_leave_confirmation)
	next_field_button.pressed.connect(_enter_next_field)
	retry_run_button.pressed.connect(start_new_run)
	summary_menu_button.pressed.connect(return_to_main_menu)
	resume_button.pressed.connect(_resume_game)
	pause_restart_button.pressed.connect(restart_current_field)
	pause_abandon_button.pressed.connect(_show_leave_confirmation)
	pause_menu_button.pressed.connect(_show_leave_confirmation)
	confirm_leave_button.pressed.connect(return_to_main_menu)
	cancel_leave_button.pressed.connect(_cancel_leave_confirmation)
	_show_main_menu()


func _process(delta: float) -> void:
	if _paused or state != FieldState.PLAYING:
		return
	elapsed_time += delta
	var current_second := int(elapsed_time)
	if current_second != _displayed_second:
		_displayed_second = current_second
		_update_time_label()


func _unhandled_input(event: InputEvent) -> void:
	if confirm_overlay.visible:
		if event.is_action_pressed("ui_cancel"):
			_cancel_leave_confirmation()
			get_viewport().set_input_as_handled()
		return
	if pause_screen.visible:
		if event.is_action_pressed("ui_cancel"):
			_resume_game()
			get_viewport().set_input_as_handled()
		return
	if start_screen.visible and event.is_action_pressed("ui_accept"):
		start_new_run()
		get_viewport().set_input_as_handled()
		return
	if run.state != RunController.RunState.IN_PROGRESS:
		return
	if event.is_action_pressed("ui_cancel") and (state == FieldState.READY or state == FieldState.PLAYING):
		_show_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("new_field") and (state == FieldState.READY or state == FieldState.PLAYING):
		restart_current_field()
		get_viewport().set_input_as_handled()


func start_new_run() -> void:
	_paused = false
	run.start_run()
	start_screen.hide()
	run_summary_screen.hide()
	field_result_screen.hide()
	pause_screen.hide()
	confirm_overlay.hide()
	game_screen.show()
	_load_current_field()


func restart_current_field() -> void:
	if run.state != RunController.RunState.IN_PROGRESS:
		return
	_paused = false
	pause_screen.hide()
	confirm_overlay.hide()
	run.restart_current_field()
	_load_current_field()


func return_to_main_menu() -> void:
	_paused = false
	run.abandon_run()
	if board != null:
		board_view.clear()
	_show_main_menu()


func _show_main_menu() -> void:
	game_screen.hide()
	field_result_screen.hide()
	run_summary_screen.hide()
	pause_screen.hide()
	confirm_overlay.hide()
	start_screen.show()
	start_run_button.grab_focus()


func _load_current_field() -> void:
	var config := run.current_config()
	state = FieldState.READY
	elapsed_time = 0.0
	_displayed_second = 0
	board = BoardModel.new(config.width, config.height, config.mine_count)
	board_view.build(config.width, config.height)
	field_result_screen.hide()
	restart_button.disabled = false
	pause_button.disabled = false
	abandon_button.disabled = false
	_update_hud()


func _on_reveal_requested(cell_position: Vector2i) -> void:
	if _paused or (state != FieldState.READY and state != FieldState.PLAYING) or board.is_flagged(cell_position):
		return
	if board.is_revealed(cell_position):
		_try_chord(cell_position)
		return
	if state == FieldState.READY:
		board.place_mines(cell_position)
		state = FieldState.PLAYING
	var result: Dictionary = board.reveal(cell_position)
	var changed: Array[Vector2i] = result["changed"]
	_refresh_changed_cells(changed)
	if bool(result["hit_mine"]):
		_finish_loss(cell_position)
	elif board.all_safe_cells_revealed():
		_finish_field()
	else:
		_update_hud()


func _try_chord(cell_position: Vector2i) -> void:
	if _paused or state != FieldState.PLAYING:
		return
	var result: Dictionary = board.chord(cell_position)
	if not bool(result["performed"]):
		return
	var changed: Array[Vector2i] = result["changed"]
	_refresh_changed_cells(changed)
	if bool(result["hit_mine"]):
		_finish_loss(result["exploded_position"])
	elif board.all_safe_cells_revealed():
		_finish_field()
	else:
		_update_hud()


func _on_flag_requested(cell_position: Vector2i) -> void:
	if _paused or (state != FieldState.READY and state != FieldState.PLAYING):
		return
	if board.toggle_flag(cell_position):
		board_view.refresh_cell(board, cell_position)
		for neighbor in board.get_neighbors(cell_position):
			if board.is_revealed(neighbor):
				board_view.refresh_cell(board, neighbor)
		_update_hud()


func _refresh_changed_cells(changed: Array[Vector2i]) -> void:
	for changed_position in changed:
		board_view.refresh_cell(board, changed_position)


func _finish_field() -> void:
	if state == FieldState.CLEARED or state == FieldState.LOST:
		return
	state = FieldState.CLEARED
	board_view.show_win(board)
	var config := run.current_config()
	var result := FieldResult.new()
	result.field_number = config.field_number
	result.width = config.width
	result.height = config.height
	result.mine_count = config.mine_count
	result.elapsed_time = elapsed_time
	run.confirm_field(result)
	restart_button.disabled = true
	pause_button.disabled = true
	abandon_button.disabled = true
	_update_hud()
	if run.state == RunController.RunState.RUN_WON:
		_show_run_summary(true)
	else:
		_show_field_transition(result)


func _show_field_transition(result: FieldResult) -> void:
	var next := run.next_config()
	field_result_title.text = "FIELD %d CLEARED" % result.field_number
	field_result_title.modulate = Color("67e8a5")
	field_result_body.text = "TIME  %s\nMINES  %d\n\nNEXT  %d×%d · %d MINES" % [
		_format_time(result.elapsed_time),
		result.mine_count,
		next.width,
		next.height,
		next.mine_count,
	]
	next_field_button.text = "ENTER FIELD %d" % next.field_number
	field_result_screen.show()
	next_field_button.grab_focus()


func _enter_next_field() -> void:
	if run.state != RunController.RunState.IN_PROGRESS or not run.has_pending_next_field:
		return
	run.begin_next_field()
	_load_current_field()


func _finish_loss(exploded_position: Vector2i) -> void:
	if state == FieldState.LOST:
		return
	state = FieldState.LOST
	board_view.show_loss(board, exploded_position)
	run.breach_run(elapsed_time)
	restart_button.disabled = true
	pause_button.disabled = true
	abandon_button.disabled = true
	_update_hud()
	_present_run_loss.call_deferred()


func _present_run_loss() -> void:
	await get_tree().create_timer(0.65).timeout
	if run.state == RunController.RunState.RUN_LOST:
		_show_run_summary(false)


func _show_run_summary(won: bool) -> void:
	field_result_screen.hide()
	if won:
		run_summary_title.text = "RUN CLEARED"
		run_summary_title.modulate = Color("67e8a5")
		run_summary_body.text = "5 FIELDS CLEARED\nTOTAL TIME  %s" % _format_time(run.stats.total_time)
		retry_run_button.text = "NEW RUN"
	else:
		run_summary_title.text = "RUN BREACHED"
		run_summary_title.modulate = Color("ff7185")
		run_summary_body.text = "FIELD REACHED  %d / %d\nFIELDS CLEARED  %d\nTOTAL TIME  %s" % [
			run.current_config().field_number,
			run.stages.size(),
			run.stats.fields_completed,
			_format_time(run.stats.total_time),
		]
		retry_run_button.text = "RETRY RUN"
	run_summary_screen.show()
	retry_run_button.grab_focus()


func _show_pause() -> void:
	if run.state != RunController.RunState.IN_PROGRESS or (state != FieldState.READY and state != FieldState.PLAYING):
		return
	_paused = true
	pause_screen.show()
	_update_hud()
	resume_button.grab_focus()


func _resume_game() -> void:
	_paused = false
	pause_screen.hide()
	_update_hud()


func _show_leave_confirmation() -> void:
	if run.state != RunController.RunState.IN_PROGRESS:
		return
	_paused = true
	pause_screen.hide()
	confirm_title.text = "LEAVE THIS RUN?"
	confirm_copy.text = "Current field progress will be discarded."
	confirm_overlay.show()
	confirm_leave_button.grab_focus()
	_update_hud()


func _cancel_leave_confirmation() -> void:
	confirm_overlay.hide()
	pause_screen.show()
	resume_button.grab_focus()


func _update_hud() -> void:
	if board == null or run.current_config() == null:
		return
	var config := run.current_config()
	field_label.text = "FIELD %d / %d" % [config.field_number, run.stages.size()]
	mines_label.text = "MINES %d" % (config.mine_count - board.flags_placed)
	_update_time_label()
	if _paused:
		state_label.text = "PAUSED"
		state_label.modulate = Color("ffca5c")
		return
	match state:
		FieldState.READY:
			state_label.text = "READY"
			state_label.modulate = Color("9aa8bc")
		FieldState.PLAYING:
			state_label.text = "ACTIVE"
			state_label.modulate = Color("65ddff")
		FieldState.CLEARED:
			state_label.text = "CLEARED"
			state_label.modulate = Color("67e8a5")
		FieldState.LOST:
			state_label.text = "BREACHED"
			state_label.modulate = Color("ff7185")


func _update_time_label() -> void:
	time_label.text = "TIME %s" % _format_time(elapsed_time)


func _format_time(seconds: float) -> String:
	var whole_seconds := maxi(0, int(seconds))
	return "%d:%02d" % [floori(float(whole_seconds) / 60.0), whole_seconds % 60]
