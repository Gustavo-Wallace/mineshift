class_name GameController
extends Control

enum FieldState { READY, PLAYING, TARGET_REACHED, WON, LOST, TRANSITIONING }

const MAX_DISPLAY_TIME := 999

@onready var game_screen: Control = %GameScreen
@onready var start_screen: Control = %StartScreen
@onready var start_run_button: Button = %StartRunButton
@onready var board_view: BoardView = %BoardView
@onready var score_feedback: ScoreFeedback = %ScoreFeedback
@onready var pattern_feedback: PatternFeedback = %PatternFeedback
@onready var pattern_score_label: Label = %PatternScoreLabel
@onready var pattern_count_label: Label = %PatternCountLabel
@onready var last_pattern_label: Label = %LastPatternLabel
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
@onready var menu_patterns_button: Button = %MenuPatternsButton
@onready var run_patterns_button: Button = %RunPatternsButton
@onready var catalog_screen: Control = %CatalogScreen
@onready var catalog_body: Label = %CatalogBody
@onready var close_catalog_button: Button = %CloseCatalogButton

var board: BoardModel
var scoring: ScoreController = ScoreController.new()
var patterns: PatternController = PatternController.new()
var run: RunController = RunController.new()
var modules: ModuleController = ModuleController.new()
var state := FieldState.READY
var elapsed_time := 0.0
var _displayed_second := -1
var _last_field_result: FieldResult
var _action_id := 0
var _resolving_action := false
var _catalog_open := false
var _module_panel_open := false
var _shop_open := false

var credits_label: Label
var modules_label: Label
var modules_button: Button
var module_slot_strip: HBoxContainer
var module_slot_labels: Array[Label] = []
var modules_screen: Control
var modules_body: Label
var close_modules_button: Button
var shop_screen: Control
var shop_header: Label
var shop_offers: HBoxContainer
var shop_build_slots: HBoxContainer
var shop_feedback: Label
var reroll_button: Button
var enter_field_button: Button
var shop_back_button: Button
var sale_confirmation: VBoxContainer
var sale_confirmation_label: Label
var confirm_sale_button: Button
var cancel_sale_button: Button
var shop_offer_buttons: Array[Button] = []


func _ready() -> void:
	scoring.set_module_controller(modules)
	patterns.set_module_controller(modules)
	_build_module_interface()
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
	menu_patterns_button.pressed.connect(_show_pattern_catalog)
	run_patterns_button.pressed.connect(_show_pattern_catalog)
	close_catalog_button.pressed.connect(_close_pattern_catalog)
	modules.economy_changed.connect(_refresh_module_hud)
	modules.build_changed.connect(_refresh_module_hud)
	scoring.score_event_created.connect(_on_score_event_created)
	scoring.metrics_changed.connect(_on_score_metrics_changed)
	_show_main_menu()


func _process(delta: float) -> void:
	if _catalog_open or _module_panel_open or _shop_open:
		return
	if state != FieldState.PLAYING and state != FieldState.TARGET_REACHED:
		return
	elapsed_time += delta
	var current_second := mini(int(elapsed_time), MAX_DISPLAY_TIME)
	if current_second != _displayed_second:
		_displayed_second = current_second
		_update_time_label()


func _unhandled_input(event: InputEvent) -> void:
	if _module_panel_open:
		if event.is_action_pressed("ui_cancel"):
			_close_module_panel()
			get_viewport().set_input_as_handled()
		return
	if _shop_open:
		if event.is_action_pressed("ui_cancel"):
			_close_shop_to_report()
			get_viewport().set_input_as_handled()
		return
	if _catalog_open:
		if event.is_action_pressed("ui_cancel"):
			_close_pattern_catalog()
			get_viewport().set_input_as_handled()
		return
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
	_close_pattern_catalog()
	_close_module_panel()
	_hide_shop()
	modules.start_run()
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
	_hide_shop()
	_close_module_panel()
	run.abandon_run()
	modules.abandon_run()
	scoring.reset()
	board_view.clear()
	score_feedback.clear_feedback()
	pattern_feedback.clear_feedback()
	_show_main_menu()


func _show_main_menu() -> void:
	_catalog_open = false
	_module_panel_open = false
	_shop_open = false
	catalog_screen.hide()
	if modules_screen != null:
		modules_screen.hide()
	if shop_screen != null:
		shop_screen.hide()
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
	_action_id = 0
	board = BoardModel.new(config.width, config.height, config.mine_count)
	scoring.reset()
	patterns.reset_field()
	modules.reset_field()
	board_view.build(config.width, config.height)
	coordinates_label.text = "GRID %02d×%02d" % [config.width, config.height]
	score_feedback.clear_feedback()
	pattern_feedback.clear_feedback()
	result_panel.hide()
	shift_field_button.disabled = true
	restart_field_button.disabled = false
	abandon_button.disabled = false
	field_panel.remove_theme_stylebox_override("panel")
	field_panel.modulate.a = 0.0
	field_panel.create_tween().tween_property(field_panel, "modulate:a", 1.0, 0.2)
	_update_hud()


func _on_reveal_requested(cell_position: Vector2i) -> void:
	if not _field_accepts_input() or board.is_flagged(cell_position):
		return
	if board.is_revealed(cell_position):
		_try_chord(cell_position)
		return
	var target_was_reached := state == FieldState.TARGET_REACHED
	var is_opening := state == FieldState.READY
	if is_opening:
		board.place_mines(cell_position)
		state = FieldState.PLAYING

	var before_state: Dictionary = board.create_snapshot()
	var clicked_adjacent := board.adjacent_mines(cell_position)
	var result: Dictionary = board.reveal(cell_position)
	var changed: Array[Vector2i] = result["changed"]
	_refresh_changed_cells(changed)
	var automatic_counts := _get_safe_adjacent_counts(changed, cell_position)
	_resolving_action = true
	var score_event := scoring.record_manual_reveal(cell_position, clicked_adjacent, automatic_counts, result["hit_mine"])
	var won: bool = not bool(result["hit_mine"]) and board.all_safe_cells_revealed()
	var context := _make_reveal_context(
		PatternActionContext.ActionType.MANUAL_REVEAL, cell_position, clicked_adjacent, changed,
		[cell_position] if not result["hit_mine"] else [], before_state, is_opening, result["hit_mine"], won
	)
	_resolve_patterns(context, score_event)
	var global_bonus := modules.apply_global_action(score_event.action_total(), target_was_reached)
	scoring.apply_global_module_points(global_bonus, score_event)
	scoring.finalize_event(score_event)
	_resolving_action = false
	_on_score_metrics_changed()

	if result["hit_mine"]:
		_finish_loss(cell_position)
	elif won:
		_confirm_current_field(true)
	else:
		_update_hud()


func _try_chord(cell_position: Vector2i) -> void:
	if state != FieldState.PLAYING and state != FieldState.TARGET_REACHED:
		return
	var target_was_reached := state == FieldState.TARGET_REACHED
	var before_state: Dictionary = board.create_snapshot()
	var result: Dictionary = board.chord(cell_position)
	if not result["performed"]:
		return
	var changed: Array[Vector2i] = result["changed"]
	_refresh_changed_cells(changed)
	var automatic_counts := _get_safe_adjacent_counts(changed)
	_resolving_action = true
	var score_event := scoring.record_chord(cell_position, board.adjacent_mines(cell_position), automatic_counts, result["hit_mine"])
	var won: bool = not bool(result["hit_mine"]) and board.all_safe_cells_revealed()
	var context := _make_reveal_context(
		PatternActionContext.ActionType.CHORD, cell_position, board.adjacent_mines(cell_position), changed,
		[], before_state, false, result["hit_mine"], won
	)
	_resolve_patterns(context, score_event)
	var global_bonus := modules.apply_global_action(score_event.action_total(), target_was_reached)
	scoring.apply_global_module_points(global_bonus, score_event)
	scoring.finalize_event(score_event)
	_resolving_action = false
	_on_score_metrics_changed()
	if result["hit_mine"]:
		_finish_loss(result["exploded_position"])
	elif won:
		_confirm_current_field(true)
	else:
		_update_hud()


func _on_flag_requested(cell_position: Vector2i) -> void:
	if not _field_accepts_input():
		return
	var target_was_reached := state == FieldState.TARGET_REACHED
	var before_state: Dictionary = board.create_snapshot()
	if board.toggle_flag(cell_position):
		modules.begin_action()
		var placed := board.is_flagged(cell_position)
		_resolving_action = true
		scoring.record_flag_action(placed)
		board_view.refresh_cell(board, cell_position)
		for neighbor in board.get_neighbors(cell_position):
			if board.is_revealed(neighbor):
				board_view.refresh_cell(board, neighbor)
		_action_id += 1
		var context := PatternActionContext.new()
		context.action_id = _action_id
		context.action_type = PatternActionContext.ActionType.FLAG_PLACED if placed else PatternActionContext.ActionType.FLAG_REMOVED
		context.clicked_position = cell_position
		context.before_state = before_state
		context.after_state = board.create_snapshot()
		context.safe_streak = scoring.safe_reveal_streak
		var flag_event := ScoreEvent.new()
		flag_event.position = cell_position
		_resolve_patterns(context, flag_event)
		var global_bonus := modules.apply_global_action(flag_event.action_total(), target_was_reached)
		scoring.apply_global_module_points(global_bonus, flag_event)
		if flag_event.action_total() > 0:
			scoring.finalize_event(flag_event)
		_resolving_action = false
		_on_score_metrics_changed()
		_update_hud()


func _field_accepts_input() -> bool:
	return state == FieldState.READY or state == FieldState.PLAYING or state == FieldState.TARGET_REACHED


func _on_score_metrics_changed() -> void:
	if not is_node_ready() or run.state != RunController.RunState.IN_PROGRESS:
		return
	if _resolving_action:
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
	score_feedback.clear_feedback()
	pattern_feedback.clear_feedback()
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
	modules.confirm_field(result)
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
	result.normal_field_score = normal_score - patterns.pattern_score
	result.provisional_total_score = normal_score
	result.manual_base_points = scoring.manual_base_points
	result.streak_bonus_points = scoring.streak_bonus_points
	result.cascade_cell_points = scoring.cascade_cell_points
	result.pattern_score = patterns.pattern_score
	result.pattern_count = patterns.total_patterns
	result.best_pattern_name = patterns.best_pattern_name
	result.best_pattern_points = patterns.best_pattern_points
	result.pattern_activations = patterns.activations.duplicate(true)
	result.pattern_best_metrics = patterns.best_metrics.duplicate(true)
	result.highest_pattern_action_score = patterns.highest_action_pattern_score
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
	result.incorrect_flags = flag_counts.y
	result.highest_streak = scoring.highest_safe_reveal_streak
	result.full_clear = full_clear
	return result


func _finish_loss(exploded_position: Vector2i) -> void:
	state = FieldState.LOST
	score_feedback.clear_feedback()
	pattern_feedback.clear_feedback()
	board_view.show_loss(board, exploded_position)
	field_panel.add_theme_stylebox_override("panel", _make_outcome_style(Color("7a3040")))
	run.lose_field(
		scoring.current_score,
		elapsed_time,
		scoring.actions_taken,
		scoring.total_cells_revealed,
		scoring.total_cascade_cells,
		scoring.flag_placements,
		scoring.highest_safe_reveal_streak,
		patterns.pattern_score
	)
	modules.lose_field()
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
	result_body.text = """NORMAL SCORE         %6d
PATTERN SCORE        %6d
PATTERNS             %6d
BEST PATTERN     %10s
RISK REVEALS        %6d
STREAK BONUS         %6d
AUTO CELL SCORE      %6d
FLAGS                %6d
FIELD CLEAR          %6d
EFFICIENCY           %6d
ACCURACY             %6d
FULL CLEAR           %6d
OVERSCORE            %6d

FIELD CONFIRMED      %6d
RUN SCORE            %6d""" % [
		result.normal_field_score,
		result.pattern_score,
		result.pattern_count,
		result.best_pattern_name,
		result.manual_base_points,
		result.streak_bonus_points,
		result.cascade_cell_points,
		result.flag_bonus_points,
		result.clear_bonus_points,
		result.efficiency_bonus_points,
		result.accuracy_bonus_points,
		result.full_clear_bonus,
		result.overscore_bonus,
		result.confirmed_total,
		run.confirmed_run_score,
	]
	result_body.text += """

CREDIT REPORT
FIELD CLEAR           +%2d
OVERSCORE             +%2d
FULL CLEAR            +%2d
PRECISION             +%2d
TOTAL                 +%2d
CREDITS                %02d

MODULE SCORE          +%6d
CONTRIBUTORS      %11s""" % [
		result.credit_base,
		result.credit_overscore,
		result.credit_full_clear,
		result.credit_precision,
		result.credits_earned,
		result.credits_after,
		result.module_points,
		_field_module_contributors(result),
	]
	if run.state == RunController.RunState.RUN_WON:
		result_button.text = "VIEW RUN SUMMARY"
	else:
		var next := run.next_config()
		result_body.text += "\n\nNEXT FIELD %d\nGRID %02d×%02d  //  MINES %02d\nTARGET %04d" % [
			next.field_number, next.width, next.height, next.mine_count, next.target_score
		]
		result_button.text = "OPEN SHIFT SHOP"
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
SAFE CELLS           %02d/%02d
CREDITS RETAINED        %02d
MODULE POINTS LOST   %6d""" % [
		config.field_number,
		run.stages.size(),
		scoring.current_score,
		config.target_score,
		progress,
		board.revealed_safe_count,
		config.width * config.height - config.mine_count,
		modules.credits,
		modules.lost_provisional_points,
	]
	result_button.text = "RUN BREACHED"
	result_button.disabled = true
	result_panel.show()


func _on_result_button_pressed() -> void:
	if run.state == RunController.RunState.RUN_WON:
		_show_run_summary(true)
	elif run.state == RunController.RunState.IN_PROGRESS and state == FieldState.TRANSITIONING:
		_show_shift_shop()


func _show_run_summary(won: bool) -> void:
	score_feedback.clear_feedback()
	var stats := run.stats
	if won:
		run_summary_title.text = "RUN CLEARED"
		run_summary_title.modulate = Color("67e8a5")
		run_summary_body.text = """FINAL SCORE              %06d
FIELDS COMPLETED          %02d
CREDITS REMAINING          %02d
FINAL MODULES       %12s
TOP MODULE ACT.     %12s
TOP MODULE SCORE    %12s
MODULE POINTS            %06d
PATTERN SCORE           %06d
MOST ACTIVATED     %12s
TOP PATTERN        %12s
LARGEST CASCADE          %02d
LARGEST CHAIN            %02d
LONGEST SEQUENCE         %02d
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
			modules.credits,
			modules.installed_names(),
			modules.most_activated_module(),
			modules.highest_scoring_module(),
			modules.confirmed_points(),
			stats.pattern_points,
			stats.most_activated_pattern(),
			stats.best_pattern_name,
			int(stats.pattern_best_metrics.get("cascade", 0)),
			int(stats.pattern_best_metrics.get("chain", 0)),
			int(stats.pattern_best_metrics.get("sequence", 0)),
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
CREDITS REMAINING          %02d
INSTALLED MODULES  %12s
CONFIRMED MODULE PTS     %06d
LOST MODULE POINTS      %06d
CONFIRMED PATTERNS      %06d
LOST PATTERN SCORE     %06d
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
			modules.credits,
			modules.installed_names(),
			modules.confirmed_points(),
			modules.lost_provisional_points,
			stats.pattern_points,
			stats.lost_provisional_pattern_points,
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


func _show_pattern_catalog() -> void:
	_catalog_open = true
	score_feedback.clear_feedback()
	pattern_feedback.clear_feedback()
	var lines: Array[String] = []
	for definition in patterns.definitions:
		var confirmed_count := int(run.stats.pattern_activations.get(definition.id, 0))
		var provisional_count := int(patterns.activations.get(definition.id, 0))
		var best := maxi(
			int(run.stats.pattern_best_metrics.get(definition.id, 0)),
			int(patterns.best_metrics.get(definition.id, 0))
		)
		lines.append("%s  //  RUN %02d  //  BEST %02d" % [definition.display_name, confirmed_count + provisional_count, best])
		lines.append(definition.description)
		lines.append(definition.condition_text)
		lines.append(definition.score_table)
		lines.append("")
	catalog_body.text = "\n".join(lines)
	catalog_screen.show()
	close_catalog_button.grab_focus()


func _close_pattern_catalog() -> void:
	_catalog_open = false
	catalog_screen.hide()


func _refresh_changed_cells(changed: Array[Vector2i]) -> void:
	for changed_position in changed:
		board_view.refresh_cell(board, changed_position)


func _make_reveal_context(
	action_type: PatternActionContext.ActionType,
	cell_position: Vector2i,
	clicked_value: int,
	changed: Array[Vector2i],
	manual_positions: Array,
	before_state: Dictionary,
	is_opening: bool,
	hit_mine: bool,
	won: bool
) -> PatternActionContext:
	_action_id += 1
	var context := PatternActionContext.new()
	context.action_id = _action_id
	context.action_type = action_type
	context.clicked_position = cell_position
	context.clicked_value = clicked_value
	context.before_state = before_state
	context.after_state = board.create_snapshot()
	context.safe_streak = scoring.safe_reveal_streak
	context.relevant_adjacent_flags = board.count_adjacent_flags(cell_position)
	context.caused_loss = hit_mine
	context.caused_win = won
	context.is_opening_action = is_opening
	for manual_position: Vector2i in manual_positions:
		context.manually_revealed.append(manual_position)
	for changed_position in changed:
		var is_manual := context.manually_revealed.has(changed_position)
		context.revealed_cells.append({
			"position": changed_position,
			"value": board.adjacent_mines(changed_position),
			"manual": is_manual,
		})
		if not is_manual:
			context.automatically_revealed.append(changed_position)
	context.finalize_counts()
	return context


func _resolve_patterns(context: PatternActionContext, score_event: ScoreEvent) -> void:
	var results := patterns.detect(context)
	if results.is_empty():
		return
	var points := patterns.total_points(results)
	scoring.apply_pattern_points(points, score_event)
	pattern_feedback.show_patterns(
		board_view.global_position + Vector2(board_view.size.x + 18.0, 16.0),
		board_view.get_cell_global_center(context.clicked_position),
		results
	)


func _get_safe_adjacent_counts(changed: Array[Vector2i], excluded_position := Vector2i(-1, -1)) -> Array[int]:
	var counts: Array[int] = []
	for cell_position in changed:
		if cell_position != excluded_position and not board.has_mine(cell_position):
			counts.append(board.adjacent_mines(cell_position))
	return counts


func _count_flags() -> Vector2i:
	var correct := 0
	var incorrect := 0
	for y in board.height:
		for x in board.width:
			var cell_position := Vector2i(x, y)
			if not board.is_flagged(cell_position):
				continue
			if board.has_mine(cell_position):
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
		displayed_field_score = _last_field_result.provisional_total_score
	var displayed_provisional := displayed_field_score if _field_accepts_input() or state == FieldState.LOST else 0
	field_label.text = "FIELD %d / %d" % [config.field_number, run.stages.size()]
	score_label.text = "FIELD SCORE %06d" % displayed_field_score
	streak_label.text = "STREAK %02d" % scoring.safe_reveal_streak
	multiplier_label.text = "×%.2f" % scoring.get_streak_multiplier()
	multiplier_label.modulate = Color("67e8a5") if scoring.get_streak_multiplier() > 1.0 else Color("65738a")
	actions_label.text = "ACTIONS %03d" % scoring.actions_taken
	mines_label.text = "MINES %03d" % (config.mine_count - board.flags_placed)
	pattern_score_label.text = "PATTERN SCORE %06d" % patterns.pattern_score
	pattern_count_label.text = "PATTERNS %02d" % patterns.total_patterns
	last_pattern_label.text = "LAST %s" % patterns.last_pattern
	run_score_label.text = "RUN SCORE %06d + %06d" % [run.confirmed_run_score, displayed_provisional]
	modules_label.text = "MODULES %d / %d" % [modules.installed.size(), ModuleController.SLOT_LIMIT]
	var active_module_status: String = modules.active_global_status(state == FieldState.TARGET_REACHED)
	if not active_module_status.is_empty():
		modules_label.text += "  //  %s" % active_module_status
		modules_label.modulate = Color("67e8a5")
	else:
		modules_label.modulate = Color("ffca5c") if modules.installed.size() == ModuleController.SLOT_LIMIT else Color.WHITE
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


func _build_module_interface() -> void:
	var action_row := get_node("GameScreen/SafeArea/Layout/HeaderPanel/HeaderLayout/TopRow/Actions") as HBoxContainer
	modules_button = Button.new()
	modules_button.name = "ModulesButton"
	modules_button.text = "MODULES"
	modules_button.pressed.connect(_show_module_panel)
	action_row.add_child(modules_button)

	var pattern_metrics := get_node("GameScreen/SafeArea/Layout/HeaderPanel/HeaderLayout/PatternMetrics") as HBoxContainer
	credits_label = Label.new()
	credits_label.name = "CreditsLabel"
	credits_label.text = "CREDITS 00"
	credits_label.add_theme_color_override("font_color", Color("65ddff"))
	pattern_metrics.add_child(credits_label)
	modules_label = Label.new()
	modules_label.name = "ModulesLabel"
	modules_label.text = "MODULES 0 / 5"
	modules_label.add_theme_color_override("font_color", Color("9aa8bc"))
	pattern_metrics.add_child(modules_label)
	var header_layout := get_node("GameScreen/SafeArea/Layout/HeaderPanel/HeaderLayout") as VBoxContainer
	module_slot_strip = HBoxContainer.new()
	module_slot_strip.name = "ModuleSlotStrip"
	module_slot_strip.add_theme_constant_override("separation", 6)
	header_layout.add_child(module_slot_strip)
	for slot_index in ModuleController.SLOT_LIMIT:
		var slot_label := Label.new()
		slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_label.add_theme_font_size_override("font_size", 11)
		module_slot_strip.add_child(slot_label)
		module_slot_labels.append(slot_label)

	_build_modules_screen()
	_build_shop_screen()
	_refresh_module_hud()


func _build_modules_screen() -> void:
	modules_screen = Control.new()
	modules_screen.name = "ModulesScreen"
	modules_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modules_screen.z_index = 80
	add_child(modules_screen)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.035, 0.06, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modules_screen.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modules_screen.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820.0, 560.0)
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)
	var title := Label.new()
	title.text = "MODULE BUILD // FIVE-SLOT ARRAY"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("67e8a5"))
	layout.add_child(title)
	modules_body = Label.new()
	modules_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modules_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modules_body.add_theme_font_size_override("font_size", 14)
	layout.add_child(modules_body)
	close_modules_button = Button.new()
	close_modules_button.text = "CLOSE"
	close_modules_button.pressed.connect(_close_module_panel)
	layout.add_child(close_modules_button)
	modules_screen.hide()


func _build_shop_screen() -> void:
	shop_screen = Control.new()
	shop_screen.name = "ShiftShopScreen"
	shop_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_screen.z_index = 85
	add_child(shop_screen)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.03, 0.055, 0.97)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_screen.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 22)
	shop_screen.add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)
	shop_header = Label.new()
	shop_header.add_theme_font_size_override("font_size", 22)
	shop_header.add_theme_color_override("font_color", Color("65ddff"))
	layout.add_child(shop_header)
	var divider := HSeparator.new()
	layout.add_child(divider)
	shop_offers = HBoxContainer.new()
	shop_offers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_offers.add_theme_constant_override("separation", 12)
	layout.add_child(shop_offers)
	var build_title := Label.new()
	build_title.text = "CURRENT BUILD // SELECT AN INSTALLED MODULE TO SELL"
	build_title.add_theme_color_override("font_color", Color("9aa8bc"))
	layout.add_child(build_title)
	shop_build_slots = HBoxContainer.new()
	shop_build_slots.add_theme_constant_override("separation", 8)
	layout.add_child(shop_build_slots)
	sale_confirmation = VBoxContainer.new()
	sale_confirmation_label = Label.new()
	sale_confirmation_label.add_theme_color_override("font_color", Color("ffca5c"))
	sale_confirmation.add_child(sale_confirmation_label)
	var sale_buttons := HBoxContainer.new()
	confirm_sale_button = Button.new()
	confirm_sale_button.text = "CONFIRM SALE"
	confirm_sale_button.pressed.connect(_confirm_module_sale)
	sale_buttons.add_child(confirm_sale_button)
	cancel_sale_button = Button.new()
	cancel_sale_button.text = "CANCEL"
	cancel_sale_button.pressed.connect(_cancel_module_sale)
	sale_buttons.add_child(cancel_sale_button)
	sale_confirmation.add_child(sale_buttons)
	layout.add_child(sale_confirmation)
	shop_feedback = Label.new()
	shop_feedback.add_theme_color_override("font_color", Color("67e8a5"))
	shop_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(shop_feedback)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	reroll_button = Button.new()
	reroll_button.pressed.connect(_reroll_shop)
	footer.add_child(reroll_button)
	shop_back_button = Button.new()
	shop_back_button.text = "BACK TO REPORT"
	shop_back_button.pressed.connect(_close_shop_to_report)
	footer.add_child(shop_back_button)
	enter_field_button = Button.new()
	enter_field_button.pressed.connect(_enter_next_field_from_shop)
	footer.add_child(enter_field_button)
	layout.add_child(footer)
	shop_screen.hide()


func _refresh_module_hud() -> void:
	if credits_label == null:
		return
	credits_label.text = "CREDITS %02d" % modules.credits
	modules_label.text = "MODULES %d / %d" % [modules.installed.size(), ModuleController.SLOT_LIMIT]
	modules_label.modulate = Color("ffca5c") if modules.installed.size() == ModuleController.SLOT_LIMIT else Color.WHITE
	for slot_index in module_slot_labels.size():
		var slot_label := module_slot_labels[slot_index]
		if slot_index < modules.installed.size():
			var definition := modules.installed[slot_index].definition
			slot_label.text = "%d %s %s [%s]" % [slot_index + 1, definition.icon_text, definition.short_name, definition.rarity_name()]
			slot_label.tooltip_text = "%s\n%s\n%s" % [definition.display_name, definition.trigger_text, definition.effect_text]
			slot_label.modulate = definition.rarity_color()
		else:
			slot_label.text = "%d ◇ EMPTY" % (slot_index + 1)
			slot_label.tooltip_text = "EMPTY MODULE SLOT"
			slot_label.modulate = Color("65738a")
	if _module_panel_open:
		_refresh_module_panel()
	if _shop_open:
		_refresh_shop_ui()


func _show_module_panel() -> void:
	if run.state != RunController.RunState.IN_PROGRESS or _shop_open:
		return
	_module_panel_open = true
	score_feedback.clear_feedback()
	pattern_feedback.clear_feedback()
	_refresh_module_panel()
	modules_screen.show()
	close_modules_button.grab_focus()


func _close_module_panel() -> void:
	_module_panel_open = false
	if modules_screen != null:
		modules_screen.hide()


func _refresh_module_panel() -> void:
	var lines: Array[String] = ["CREDITS %02d  //  MODULES %d / %d", ""]
	lines[0] = lines[0] % [modules.credits, modules.installed.size(), ModuleController.SLOT_LIMIT]
	for slot_index in ModuleController.SLOT_LIMIT:
		if slot_index >= modules.installed.size():
			lines.append("SLOT %d  ◇  EMPTY" % (slot_index + 1))
			lines.append("")
			continue
		var runtime := modules.installed[slot_index]
		var definition := runtime.definition
		lines.append("SLOT %d  %s  %s  //  %s" % [slot_index + 1, definition.icon_text, definition.display_name, definition.rarity_name()])
		lines.append("%s  //  COST %d  //  SELL %d" % [definition.description, definition.cost, definition.sell_value()])
		lines.append("TRIGGER: %s" % definition.trigger_text)
		lines.append("CONFIRMED: %d ACT.  //  +%d PTS  //  BEST +%d" % [runtime.confirmed_activations, runtime.confirmed_points, runtime.confirmed_best_contribution])
		lines.append("CURRENT FIELD: %d ACT.  //  +%d PTS  //  BEST +%d" % [runtime.provisional_activations, runtime.provisional_points, runtime.provisional_best_contribution])
		lines.append("")
	modules_body.text = "\n".join(lines)


func _show_shift_shop() -> void:
	if _last_field_result == null or run.state != RunController.RunState.IN_PROGRESS:
		return
	modules.prepare_shop(_last_field_result.field_number)
	_shop_open = true
	result_panel.hide()
	_refresh_shop_ui()
	shop_screen.show()
	reroll_button.grab_focus()


func _hide_shop() -> void:
	_shop_open = false
	if shop_screen != null:
		shop_screen.hide()


func _close_shop_to_report() -> void:
	if not _shop_open:
		return
	_hide_shop()
	result_panel.show()
	result_button.grab_focus()


func _enter_next_field_from_shop() -> void:
	if not _shop_open or not run.has_pending_next_field:
		return
	_hide_shop()
	run.begin_next_field()
	_load_current_field()


func _refresh_shop_ui() -> void:
	if not _shop_open:
		return
	var next := run.next_config()
	if next == null:
		_hide_shop()
		return
	shop_header.text = "SHIFT SHOP  //  CREDITS %02d  //  FIELD %d CLEARED  →  FIELD %d" % [modules.credits, modules.shop_field_number, next.field_number]
	_clear_control_children(shop_offers)
	shop_offer_buttons.clear()
	for offer_index in modules.stock.size():
		var definition := modules.stock[offer_index]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0.0, 250.0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_offers.add_child(card)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 6)
		card.add_child(content)
		if definition == null:
			var sold := Label.new()
			sold.text = "◇\nMODULE INSTALLED\nOFFER CLOSED"
			sold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			sold.size_flags_vertical = Control.SIZE_EXPAND_FILL
			content.add_child(sold)
			continue
		var rarity := Label.new()
		rarity.text = "%s  //  %s" % [definition.icon_text, definition.rarity_name()]
		rarity.add_theme_color_override("font_color", definition.rarity_color())
		content.add_child(rarity)
		var name_label := Label.new()
		name_label.text = definition.display_name
		name_label.add_theme_font_size_override("font_size", 18)
		content.add_child(name_label)
		var description := Label.new()
		description.text = "%s\n\nTRIGGER\n%s\n\nEFFECT\n%s" % [definition.description, definition.trigger_text, definition.effect_text]
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(description)
		var buy := Button.new()
		buy.text = "BUY — %d CREDITS" % definition.cost
		buy.disabled = modules.credits < definition.cost or modules.installed.size() >= ModuleController.SLOT_LIMIT
		buy.pressed.connect(_buy_shop_offer.bind(offer_index))
		content.add_child(buy)
		shop_offer_buttons.append(buy)
	_clear_control_children(shop_build_slots)
	for slot_index in ModuleController.SLOT_LIMIT:
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(0.0, 54.0)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if slot_index < modules.installed.size():
			var runtime := modules.installed[slot_index]
			slot.text = "%s\n%s  //  SELL %d" % [runtime.definition.icon_text, runtime.definition.short_name, runtime.definition.sell_value()]
			slot.tooltip_text = runtime.definition.description
			slot.pressed.connect(_request_module_sale.bind(runtime.definition.id))
		else:
			slot.text = "◇\nEMPTY SLOT"
			slot.disabled = true
		shop_build_slots.add_child(slot)
	reroll_button.text = "REROLL — %d CREDITS" % modules.reroll_cost()
	reroll_button.disabled = not modules.can_reroll()
	enter_field_button.text = "ENTER FIELD %d" % next.field_number
	sale_confirmation.visible = modules.pending_sale_id != &""
	if modules.installed.size() >= ModuleController.SLOT_LIMIT:
		shop_feedback.text = "MODULE SLOTS FULL — SELL A MODULE TO INSTALL ANOTHER"
	elif not modules.last_transaction_message.is_empty():
		shop_feedback.text = modules.last_transaction_message
	else:
		shop_feedback.text = "STOCK LOCKED UNTIL REROLL"


func _buy_shop_offer(index: int) -> void:
	var result := modules.buy_offer(index)
	match result:
		ModuleController.PurchaseResult.SUCCESS:
			shop_feedback.text = "MODULE INSTALLED"
		ModuleController.PurchaseResult.INSUFFICIENT_CREDITS:
			shop_feedback.text = "INSUFFICIENT CREDITS"
		ModuleController.PurchaseResult.SLOTS_FULL:
			shop_feedback.text = "MODULE SLOTS FULL"
	_refresh_shop_ui()


func _reroll_shop() -> void:
	modules.reroll()
	_refresh_shop_ui()


func _request_module_sale(id: StringName) -> void:
	if not modules.request_sale(id):
		return
	var definition := modules.get_definition(id)
	sale_confirmation_label.text = "SELL %s FOR %d CREDITS?" % [definition.display_name, definition.sell_value()]
	sale_confirmation.show()
	confirm_sale_button.grab_focus()


func _confirm_module_sale() -> void:
	modules.confirm_sale()
	_refresh_shop_ui()


func _cancel_module_sale() -> void:
	modules.cancel_sale()
	sale_confirmation.hide()


func _field_module_contributors(result: FieldResult) -> String:
	var names: Array[String] = []
	for id in result.module_stats:
		var data: Dictionary = result.module_stats[id]
		if int(data.get("points", 0)) > 0:
			var definition := modules.get_definition(id)
			if definition != null:
				names.append(definition.short_name)
	return "NONE" if names.is_empty() else ", ".join(names)


func _clear_control_children(container: Control) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _make_outcome_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111925")
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18.0)
	return style
