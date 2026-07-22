class_name GameController
extends Control

enum FieldState { READY, PLAYING, TARGET_REACHED, WON, LOST, TRANSITIONING }

const MAX_DISPLAY_TIME := 999

@onready var game_screen: Control = %GameScreen
@onready var start_screen: Control = %StartScreen
@onready var start_run_button: Button = %StartRunButton
@onready var board_view: BoardView = %BoardView
@onready var score_feedback: ScoreFeedback = %ScoreFeedback
@onready var field_label: Label = %FieldLabel
@onready var score_label: Label = %ScoreLabel
@onready var target_label: Label = %TargetLabel
@onready var run_score_label: Label = %RunScoreLabel
@onready var streak_label: Label = %StreakLabel
@onready var multiplier_label: Label = %MultiplierLabel
@onready var actions_label: Label = %ActionsLabel
@onready var mines_label: Label = %MinesLabel
@onready var time_label: Label = %TimeLabel
@onready var state_label: Label = %StateLabel
@onready var target_progress: ProgressBar = %TargetProgress
@onready var field_panel: PanelContainer = %FieldPanel
@onready var coordinates_label: Label = %Coordinates
@onready var restart_field_button: Button = %RestartFieldButton
@onready var shift_field_button: Button = %ShiftFieldButton
@onready var abandon_button: Button = %AbandonButton
@onready var result_panel: PanelContainer = %ResultPanel
@onready var result_title: Label = %ResultTitle
@onready var result_body: Label = %ResultBody
@onready var result_button: Button = %ResultButton
@onready var run_summary_screen: Control = %RunSummaryScreen
@onready var run_summary_title: Label = %RunSummaryTitle
@onready var run_summary_body: Label = %RunSummaryBody
@onready var run_primary_button: Button = %RunPrimaryButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var abandon_overlay: Control = %AbandonOverlay
@onready var confirm_abandon_button: Button = %ConfirmAbandonButton
@onready var cancel_abandon_button: Button = %CancelAbandonButton

var board: BoardModel
var scoring := ScoreController.new()
var run := RunController.new()
var state := FieldState.READY
var elapsed_time := 0.0
var _displayed_second := -1
var _last_field_result: FieldResult


func _ready() -> void:
	board_view.cell_reveal_requested.connect(_on_reveal_requested)
	board_view.cell_flag_requested.connect(_on_flag_requested)
	start_run_button.pressed.connect(start_new_run)
	restart_field_button.pressed.connect(restart_current_field)
	shift_field_button.pressed.connect(shift_current_field)
	abandon_button.pressed.connect(_show_abandon_confirmation)
	result_button.pressed.connect(_on_result_button_pressed)
	run_primary_button.pressed.connect(start_new_run)
	main_menu_button.pressed.connect(return_to_main_menu)
	confirm_abandon_button.pressed.connect(return_to_main_menu)
	cancel_abandon_button.pressed.connect(abandon_overlay.hide)
	scoring.score_event_created.connect(_on_score_event_created)
	scoring.metrics_changed.connect(_on_score_metrics_changed)
	_show_main_menu()


func _process(delta: float) -> void:
	if state != FieldState.PLAYING and state != FieldState.TARGET_REACHED:
		return
	elapsed_time += delta
	var current_second := mini(int(elapsed_time), MAX_DISPLAY_TIME)
	if current_second != _displayed_second:
		_displayed_second = current_second
		_update_time_label()


func _unhandled_input(event: InputEvent) -> void:
	if abandon_overlay.visible:
		return
	if start_screen.visible and event.is_action_pressed("ui_accept"):
		start_new_run()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("new_field") and run.state == RunController.RunState.IN_PROGRESS:
		if state != FieldState.TRANSITIONING and state != FieldState.LOST:
			restart_current_field()
			get_viewport().set_input_as_handled()


func start_new_run() -> void:
	run.start_run()
	run_summary_screen.hide()
	start_screen.hide()
	game_screen.show()
	abandon_overlay.hide()
	_load_current_field()


func start_new_field() -> void:
	if run.state == RunController.RunState.NOT_STARTED:
		start_new_run()
	else:
		restart_current_field()


func restart_current_field() -> void:
	if run.state != RunController.RunState.IN_PROGRESS:
		return
	run.restart_current_field()
	_load_current_field()


func shift_current_field() -> void:
	if state != FieldState.TARGET_REACHED:
		return
	_confirm_current_field(false)


func return_to_main_menu() -> void:
	run.abandon_run()
	scoring.reset()
	board_view.clear()
	score_feedback.clear_feedback()
	_show_main_menu()


func _show_main_menu() -> void:
	game_screen.hide()
	run_summary_screen.hide()
	abandon_overlay.hide()
	result_panel.hide()
	start_screen.show()
	start_run_button.grab_focus()


func _load_current_field() -> void:
	var config := run.current_config()
	state = FieldState.READY
	elapsed_time = 0.0
	_displayed_second = 0
	_last_field_result = null
	board = BoardModel.new(config.width, config.height, config.mine_count)
	scoring.reset()
	board_view.build(config.width, config.height)
	coordinates_label.text = "GRID %02d×%02d" % [config.width, config.height]
	score_feedback.clear_feedback()
	result_panel.hide()
	shift_field_button.disabled = true
	restart_field_button.disabled = false
	abandon_button.disabled = false
	field_panel.remove_theme_stylebox_override("panel")
	field_panel.modulate.a = 0.0
	field_panel.create_tween().tween_property(field_panel, "modulate:a", 1.0, 0.2)
	_update_hud()


func _on_reveal_requested(position: Vector2i) -> void:
	if not _field_accepts_input() or board.is_flagged(position):
		return
	if board.is_revealed(position):
		_try_chord(position)
		return
	if state == FieldState.READY:
		board.place_mines(position)
		state = FieldState.PLAYING

	var clicked_adjacent := board.adjacent_mines(position)
	var result: Dictionary = board.reveal(position)
	var changed: Array[Vector2i] = result["changed"]
	_refresh_changed_cells(changed)
	var automatic_counts := _get_safe_adjacent_counts(changed, position)
	scoring.record_manual_reveal(position, clicked_adjacent, automatic_counts, result["hit_mine"])

	if result["hit_mine"]:
		_finish_loss(position)
	elif board.all_safe_cells_revealed():
		_confirm_current_field(true)
	else:
		_update_hud()


func _try_chord(position: Vector2i) -> void:
	if state != FieldState.PLAYING and state != FieldState.TARGET_REACHED:
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
		_confirm_current_field(true)
	else:
		_update_hud()


func _on_flag_requested(position: Vector2i) -> void:
	if not _field_accepts_input():
		return
	if board.toggle_flag(position):
		scoring.record_flag_action(board.is_flagged(position))
		board_view.refresh_cell(board, position)
		for neighbor in board.get_neighbors(position):
			if board.is_revealed(neighbor):
				board_view.refresh_cell(board, neighbor)
		_update_hud()


func _field_accepts_input() -> bool:
	return state == FieldState.READY or state == FieldState.PLAYING or state == FieldState.TARGET_REACHED


func _on_score_metrics_changed() -> void:
	if not is_node_ready() or run.state != RunController.RunState.IN_PROGRESS:
		return
	if _field_accepts_input():
		run.update_provisional_score(scoring.current_score)
		var config := run.current_config()
		if (state == FieldState.PLAYING or state == FieldState.TARGET_REACHED) and scoring.current_score >= config.target_score:
			state = FieldState.TARGET_REACHED
			shift_field_button.disabled = false
	_update_hud()


func _confirm_current_field(full_clear: bool) -> void:
	if state == FieldState.TRANSITIONING or state == FieldState.LOST:
		return
	var config := run.current_config()
	var normal_score := scoring.current_score
	var flag_counts := _count_flags()
	state = FieldState.WON if full_clear else FieldState.TRANSITIONING
	if full_clear:
		board_view.show_win(board)
		scoring.apply_victory_bonuses(flag_counts.x, flag_counts.y)
	else:
		board_view.lock_board(board)
		scoring.apply_shift_bonuses(flag_counts.x, flag_counts.y)

	var result := _build_field_result(config, normal_score, flag_counts, full_clear)
	_last_field_result = result
	run.confirm_field(result)
	state = FieldState.TRANSITIONING
	shift_field_button.disabled = true
	restart_field_button.disabled = true
	abandon_button.disabled = run.state == RunController.RunState.RUN_WON
	field_panel.add_theme_stylebox_override("panel", _make_outcome_style(Color("255d54")))
	_show_field_transition(result)
	_update_hud()


func _build_field_result(config: FieldConfig, normal_score: int, flag_counts: Vector2i, full_clear: bool) -> FieldResult:
	var result := FieldResult.new()
	result.field_number = config.field_number
	result.width = config.width
	result.height = config.height
	result.mine_count = config.mine_count
	result.target_score = config.target_score
	result.normal_field_score = normal_score
	result.manual_base_points = scoring.manual_base_points
	result.streak_bonus_points = scoring.streak_bonus_points
	result.cascade_cell_points = scoring.cascade_cell_points
	result.cascade_bonus_points = scoring.cascade_bonus_points
	result.flag_bonus_points = scoring.flag_bonus_points
	result.clear_bonus_points = scoring.clear_bonus_points
	result.accuracy_bonus_points = scoring.accuracy_bonus_points
	result.efficiency_bonus_points = scoring.efficiency_bonus_points
	result.full_clear_bonus = RunController.FULL_CLEAR_BONUS if full_clear else 0
	result.overscore_bonus = run.get_overscore_bonus(normal_score, config.target_score)
	result.confirmed_total = scoring.current_score + result.full_clear_bonus + result.overscore_bonus
	result.elapsed_time = elapsed_time
	result.actions = scoring.actions_taken
	result.cells_revealed = scoring.total_cells_revealed
	result.cascade_cells = scoring.total_cascade_cells
	result.flags_placed = scoring.flag_placements
	result.correct_flags = flag_counts.x
	result.highest_streak = scoring.highest_safe_reveal_streak
	result.full_clear = full_clear
	return result


func _finish_loss(exploded_position: Vector2i) -> void:
	state = FieldState.LOST
	board_view.show_loss(board, exploded_position)
	field_panel.add_theme_stylebox_override("panel", _make_outcome_style(Color("7a3040")))
	run.lose_field(
		scoring.current_score,
		elapsed_time,
		scoring.actions_taken,
		scoring.total_cells_revealed,
		scoring.total_cascade_cells,
		scoring.flag_placements,
		scoring.highest_safe_reveal_streak
	)
	shift_field_button.disabled = true
	restart_field_button.disabled = true
	abandon_button.disabled = true
	_show_field_breach_result()
	_update_hud()
	_present_run_loss.call_deferred()


func _present_run_loss() -> void:
	await get_tree().create_timer(0.75).timeout
	if run.state == RunController.RunState.RUN_LOST:
		_show_run_summary(false)


func _show_field_transition(result: FieldResult) -> void:
	result_title.text = "FIELD %d CLEARED" % result.field_number
	result_title.modulate = Color("67e8a5")
	result_body.text = """FIELD SCORE          %6d
RISK REVEALS        %6d
STREAK BONUS         %6d
CASCADE CELLS        %6d
CASCADE BONUS        %6d
FLAGS                %6d
FIELD CLEAR          %6d
EFFICIENCY           %6d
ACCURACY             %6d
FULL CLEAR           %6d
OVERSCORE            %6d

FIELD CONFIRMED      %6d
RUN SCORE            %6d""" % [
		result.normal_field_score,
		result.manual_base_points,
		result.streak_bonus_points,
		result.cascade_cell_points,
		result.cascade_bonus_points,
		result.flag_bonus_points,
		result.clear_bonus_points,
		result.efficiency_bonus_points,
		result.accuracy_bonus_points,
		result.full_clear_bonus,
		result.overscore_bonus,
		result.confirmed_total,
		run.confirmed_run_score,
	]
	if run.state == RunController.RunState.RUN_WON:
		result_button.text = "VIEW RUN SUMMARY"
	else:
		var next := run.next_config()
		result_body.text += "\n\nNEXT FIELD %d\nGRID %02d×%02d  //  MINES %02d\nTARGET %04d" % [
			next.field_number, next.width, next.height, next.mine_count, next.target_score
		]
		result_button.text = "ENTER FIELD %d" % next.field_number
	result_button.disabled = false
	result_panel.modulate.a = 0.0
	result_panel.show()
	result_panel.create_tween().tween_property(result_panel, "modulate:a", 1.0, 0.2)
	result_button.grab_focus()


func _show_field_breach_result() -> void:
	var config := run.current_config()
	var progress := 100.0 * float(scoring.current_score) / float(config.target_score)
	result_title.text = "FIELD BREACHED"
	result_title.modulate = Color("ff7185")
	result_body.text = """FIELD %d / %d
PROVISIONAL LOST     %6d
TARGET               %6d
TARGET PROGRESS      %5.1f%%
SAFE CELLS           %02d/%02d""" % [
		config.field_number,
		run.stages.size(),
		scoring.current_score,
		config.target_score,
		progress,
		board.revealed_safe_count,
		config.width * config.height - config.mine_count,
	]
	result_button.text = "RUN BREACHED"
	result_button.disabled = true
	result_panel.show()


func _on_result_button_pressed() -> void:
	if run.state == RunController.RunState.RUN_WON:
		_show_run_summary(true)
	elif run.state == RunController.RunState.IN_PROGRESS and state == FieldState.TRANSITIONING:
		run.begin_next_field()
		_load_current_field()


func _show_run_summary(won: bool) -> void:
	score_feedback.clear_feedback()
	var stats := run.stats
	if won:
		run_summary_title.text = "RUN CLEARED"
		run_summary_title.modulate = Color("67e8a5")
		run_summary_body.text = """FINAL SCORE              %06d
FIELDS COMPLETED          %02d
TOTAL TIME               %4d s
TOTAL ACTIONS             %04d
CELLS REVEALED            %04d
CORRECT FLAGS             %03d
FULL CLEARS               %02d
BEST SAFE STREAK          %02d
BEST FIELD SCORE        %06d
AVERAGE OVERSCORE       %6.1f%%""" % [
			run.confirmed_run_score,
			stats.fields_completed,
			int(stats.total_time),
			stats.total_actions,
			stats.cells_revealed,
			stats.correct_flags_on_completion,
			stats.full_clears,
			stats.highest_streak,
			stats.best_field_score,
			stats.average_overscore_percent(),
		]
		run_primary_button.text = "NEW RUN"
	else:
		var config := run.current_config()
		var target_progress_percent := 100.0 * float(stats.lost_provisional_score) / float(config.target_score)
		run_summary_title.text = "RUN BREACHED"
		run_summary_title.modulate = Color("ff7185")
		run_summary_body.text = """FIELD REACHED             %02d / %02d
CONFIRMED SCORE          %06d
PROVISIONAL LOST        %06d
FIELD TARGET            %06d
TARGET PROGRESS         %6.1f%%
TOTAL TIME               %4d s
TOTAL ACTIONS             %04d
CELLS REVEALED            %04d
BEST SAFE STREAK          %02d
FIELDS COMPLETED          %02d
FULL CLEARS               %02d""" % [
			config.field_number,
			run.stages.size(),
			run.confirmed_run_score,
			stats.lost_provisional_score,
			config.target_score,
			target_progress_percent,
			int(stats.total_time),
			stats.total_actions,
			stats.cells_revealed,
			stats.highest_streak,
			stats.fields_completed,
			stats.full_clears,
		]
		run_primary_button.text = "RETRY RUN"
	run_summary_screen.show()
	run_primary_button.grab_focus()


func _show_abandon_confirmation() -> void:
	if run.state != RunController.RunState.IN_PROGRESS:
		return
	score_feedback.clear_feedback()
	abandon_overlay.show()
	cancel_abandon_button.grab_focus()


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


func _update_hud() -> void:
	if board == null or run.current_config() == null:
		return
	var config := run.current_config()
	var displayed_field_score := scoring.current_score
	if state == FieldState.TRANSITIONING and _last_field_result != null:
		displayed_field_score = _last_field_result.normal_field_score
	var displayed_provisional := displayed_field_score if _field_accepts_input() or state == FieldState.LOST else 0
	field_label.text = "FIELD %d / %d" % [config.field_number, run.stages.size()]
	score_label.text = "FIELD SCORE %06d" % displayed_field_score
	streak_label.text = "STREAK %02d" % scoring.safe_reveal_streak
	multiplier_label.text = "×%.2f" % scoring.get_streak_multiplier()
	multiplier_label.modulate = Color("67e8a5") if scoring.get_streak_multiplier() > 1.0 else Color("65738a")
	actions_label.text = "ACTIONS %03d" % scoring.actions_taken
	mines_label.text = "MINES %03d" % (config.mine_count - board.flags_placed)
	run_score_label.text = "RUN SCORE %06d + %06d" % [run.confirmed_run_score, displayed_provisional]
	_update_target_hud(config, displayed_field_score)
	_update_time_label()
	shift_field_button.disabled = state != FieldState.TARGET_REACHED
	match state:
		FieldState.READY:
			state_label.text = "FIELD READY"
			state_label.modulate = Color("9aa8bc")
		FieldState.PLAYING:
			state_label.text = "FIELD ACTIVE"
			state_label.modulate = Color("65ddff")
		FieldState.TARGET_REACHED:
			state_label.text = "TARGET REACHED — SHIFT OR KEEP SWEEPING"
			state_label.modulate = Color("67e8a5")
		FieldState.WON:
			state_label.text = "FIELD CLEARED"
			state_label.modulate = Color("67e8a5")
		FieldState.LOST:
			state_label.text = "FIELD BREACHED"
			state_label.modulate = Color("ff7185")
		FieldState.TRANSITIONING:
			state_label.text = "FIELD CONFIRMED"
			state_label.modulate = Color("67e8a5")


func _update_target_hud(config: FieldConfig, displayed_field_score: int) -> void:
	target_progress.max_value = config.target_score
	target_progress.value = mini(displayed_field_score, config.target_score)
	if displayed_field_score >= config.target_score:
		target_label.text = "TARGET CLEARED +%d" % (displayed_field_score - config.target_score)
		target_progress.modulate = Color("67e8a5")
	else:
		target_label.text = "TARGET %d / %d" % [displayed_field_score, config.target_score]
		target_progress.modulate = Color("65ddff")


func _update_time_label() -> void:
	time_label.text = "TIME %03d" % mini(int(elapsed_time), MAX_DISPLAY_TIME)


func _make_outcome_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111925")
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18.0)
	return style
