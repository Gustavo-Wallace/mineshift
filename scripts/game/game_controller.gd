class_name GameController
extends Control

signal breach_started(positions: Array[Vector2i])
signal breach_recovered
signal field_restart_requested

enum FieldState { READY, PLAYING, BREACH_RECOVERY, CLEARED, LOST }
enum ConfirmationMode { NONE, LEAVE_RUN, RESTART_FIELD }

const BREACH_SETTLE_TIME := 0.16
const BREACH_RECOVERY_TIME := 0.26

@onready var game_screen: Control = %GameScreen
@onready var start_screen: Control = %StartScreen
@onready var start_run_button: Button = %StartRunButton
@onready var board_view: BoardView = %BoardView
@onready var field_label: Label = %FieldLabel
@onready var state_label: Label = %StateLabel
@onready var integrity_label: Label = %IntegrityLabel
@onready var mines_label: Label = %MinesLabel
@onready var time_label: Label = %TimeLabel
@onready var restart_button: Button = %RestartButton
@onready var pause_button: Button = %PauseButton
@onready var abandon_button: Button = %AbandonButton
@onready var breach_label: Label = %BreachLabel
@onready var modules_button: Button = %ModulesButton
@onready var module_slots: Array[Label] = [%ModuleSlot1, %ModuleSlot2, %ModuleSlot3, %ModuleSlot4]

@onready var field_result_screen: Control = %FieldResultScreen
@onready var field_result_title: Label = %FieldResultTitle
@onready var field_result_body: Label = %FieldResultBody
@onready var next_field_button: Button = %NextFieldButton
@onready var field_result_panel: PanelContainer = $FieldResultScreen/Center/Panel
@onready var module_prompt_label: Label = %ModulePromptLabel
@onready var module_choice_grid: GridContainer = %ModuleChoiceGrid
@onready var module_option_buttons: Array[Button] = [%ModuleOption1, %ModuleOption2, %ModuleOption3]
@onready var module_confirm_row: HBoxContainer = %ModuleConfirmRow
@onready var selected_module_label: Label = %SelectedModuleLabel
@onready var install_module_button: Button = %InstallModuleButton
@onready var back_module_button: Button = %BackModuleButton

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
@onready var confirm_action_button: Button = %ConfirmLeaveButton
@onready var cancel_confirm_button: Button = %CancelLeaveButton
@onready var modules_screen: Control = %ModulesScreen
@onready var modules_body: Label = %ModulesBody
@onready var close_modules_button: Button = %CloseModulesButton

var board: BoardModel
var run := RunController.new()
var modules := ModuleController.new()
var state := FieldState.READY
var elapsed_time := 0.0
var _displayed_second := -1
var _paused := false
var _confirmation_mode := ConfirmationMode.NONE
var _confirmation_returns_to_pause := false
var _breach_sequence := 0


func _ready() -> void:
	board_view.cell_reveal_requested.connect(_on_reveal_requested)
	board_view.cell_flag_requested.connect(_on_flag_requested)
	start_run_button.pressed.connect(start_new_run)
	restart_button.pressed.connect(_show_restart_confirmation)
	pause_button.pressed.connect(_show_pause)
	abandon_button.pressed.connect(_show_leave_confirmation)
	next_field_button.pressed.connect(_enter_next_field)
	retry_run_button.pressed.connect(start_new_run)
	summary_menu_button.pressed.connect(return_to_main_menu)
	resume_button.pressed.connect(_resume_game)
	pause_restart_button.pressed.connect(_show_restart_confirmation)
	pause_abandon_button.pressed.connect(_show_leave_confirmation)
	pause_menu_button.pressed.connect(_show_leave_confirmation)
	confirm_action_button.pressed.connect(_confirm_current_dialog)
	cancel_confirm_button.pressed.connect(_cancel_confirmation)
	modules_button.pressed.connect(_show_modules_panel)
	close_modules_button.pressed.connect(_close_modules_panel)
	for option_index in module_option_buttons.size():
		module_option_buttons[option_index].pressed.connect(_on_module_option_pressed.bind(option_index))
	install_module_button.pressed.connect(_confirm_module_installation)
	back_module_button.pressed.connect(_cancel_module_confirmation)
	run.integrity_changed.connect(_on_integrity_changed)
	modules.field_state_changed.connect(_update_module_hud)
	get_viewport().size_changed.connect(_update_module_choice_layout)
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
	if modules_screen.visible:
		if event.is_action_pressed("ui_cancel"):
			_close_modules_panel()
			get_viewport().set_input_as_handled()
		return
	if confirm_overlay.visible:
		if event.is_action_pressed("ui_cancel"):
			_cancel_confirmation()
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
		_show_restart_confirmation()
		get_viewport().set_input_as_handled()


func start_new_run() -> void:
	_breach_sequence += 1
	_paused = false
	_confirmation_mode = ConfirmationMode.NONE
	modules.on_run_started()
	run.start_run()
	start_screen.hide()
	run_summary_screen.hide()
	field_result_screen.hide()
	pause_screen.hide()
	confirm_overlay.hide()
	game_screen.show()
	_load_current_field()


func restart_current_field() -> bool:
	var waive_cost := modules.restart_is_free()
	if state == FieldState.BREACH_RECOVERY or not run.can_restart_attempt(waive_cost):
		return false
	if waive_cost and not modules.consume_restart_cache():
		return false
	var restarted_config := run.restart_field_attempt(elapsed_time, waive_cost)
	if restarted_config == null:
		return false
	_breach_sequence += 1
	_paused = false
	_confirmation_mode = ConfirmationMode.NONE
	pause_screen.hide()
	confirm_overlay.hide()
	_load_current_field()
	if waive_cost:
		_show_temporary_feedback("RESTART CACHE CONSUMED")
	return true


func return_to_main_menu() -> void:
	_breach_sequence += 1
	_paused = false
	_confirmation_mode = ConfirmationMode.NONE
	modules.abandon_run()
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
	modules_screen.hide()
	breach_label.hide()
	start_screen.show()
	start_run_button.grab_focus()


func _load_current_field() -> void:
	_breach_sequence += 1
	var field_config := run.current_config()
	state = FieldState.READY
	elapsed_time = 0.0
	_displayed_second = 0
	board = BoardModel.new(field_config.width, field_config.height, field_config.mine_count)
	board_view.build(field_config.width, field_config.height)
	modules.on_field_started()
	field_result_screen.hide()
	breach_label.hide()
	restart_button.disabled = not run.can_restart_attempt(modules.restart_is_free())
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
		board.generate_mines(cell_position, modules.opening_protection_radius())
		state = FieldState.PLAYING
		if modules.has_module(ModuleController.EXPANDED_START):
			_show_temporary_feedback("EXPANDED SAFE START")
	var action: BoardActionResult = board.perform_reveal_action(cell_position)
	_handle_board_action(action)


func _try_chord(cell_position: Vector2i) -> void:
	if _paused or state != FieldState.PLAYING:
		return
	var action: BoardActionResult = board.perform_chord_action(cell_position)
	if not action.performed:
		return
	_handle_board_action(action)


func _handle_board_action(action: BoardActionResult) -> void:
	_refresh_changed_cells(action.safe_revealed)
	_refresh_changed_cells(action.detonated_mines)
	if action.has_breach():
		_recover_from_breach(action)
	elif board.all_safe_cells_revealed():
		action.field_completed = true
		_finish_field()
	else:
		_update_hud()


func _recover_from_breach(action: BoardActionResult) -> void:
	if state == FieldState.BREACH_RECOVERY or state == FieldState.LOST:
		return
	state = FieldState.BREACH_RECOVERY
	_breach_sequence += 1
	var recovery_id := _breach_sequence
	action.damage = action.detonated_mines.size()
	action.integrity_before = run.current_integrity
	breach_started.emit(action.detonated_mines)
	board_view.show_breach(board, action.detonated_mines)
	var blocked_damage := modules.absorb_breach_damage(action.damage)
	_show_breach_feedback(action.damage, blocked_damage)
	run.apply_damage(action.damage - blocked_damage)
	action.integrity_after = run.current_integrity
	_pulse_integrity()
	_update_hud()

	await get_tree().create_timer(BREACH_SETTLE_TIME).timeout
	if recovery_id != _breach_sequence or board == null:
		return
	board.neutralize_detonations(action)
	run.record_neutralized(action.neutralized_mines.size())
	if modules.has_module(ModuleController.BREACH_PULSE):
		var pulse_revealed := board.reveal_orthogonal_safe_cells(action.neutralized_mines)
		for revealed_position in pulse_revealed:
			if not action.expansion_revealed.has(revealed_position):
				action.expansion_revealed.append(revealed_position)
		board_view.pulse_neutralized(action.neutralized_mines)
		breach_label.text = "BREACH PULSE"
	_refresh_changed_cells(action.all_changed_positions())
	board_view.refresh_recalculated(board, action.recalculated_positions)
	board_view.show_breach(board, action.neutralized_mines)
	_update_hud()

	await get_tree().create_timer(BREACH_RECOVERY_TIME).timeout
	if recovery_id != _breach_sequence or board == null:
		return
	action.field_completed = board.all_safe_cells_revealed()
	if run.current_integrity == 0:
		action.run_ended = true
		_finish_loss(action.neutralized_mines)
	elif action.field_completed:
		breach_label.hide()
		_finish_field()
	else:
		state = FieldState.PLAYING
		breach_label.hide()
		_refresh_changed_cells(action.all_changed_positions())
		breach_recovered.emit()
		_update_hud()


func _on_flag_requested(cell_position: Vector2i) -> void:
	if _paused or (state != FieldState.READY and state != FieldState.PLAYING):
		return
	var was_flagged := board.is_flagged(cell_position)
	var verifier_runtime := modules.get_runtime(ModuleController.FLAG_VERIFIER)
	if state == FieldState.READY and not was_flagged and verifier_runtime != null and verifier_runtime.field_available:
		_show_temporary_feedback("REVEAL FIELD BEFORE VERIFYING")
		return
	if board.toggle_flag(cell_position):
		var is_now_flagged := board.is_flagged(cell_position)
		if not was_flagged and is_now_flagged and modules.consume_flag_verifier():
			if board.has_mine(cell_position):
				board.mark_flag_verified(cell_position)
				_show_temporary_feedback("FLAG VERIFIED")
			else:
				board.remove_flag(cell_position)
				board_view.refresh_cell(board, cell_position)
				_update_hud()
				_show_temporary_feedback("INVALID FLAG")
				return
		board_view.refresh_cell(board, cell_position)
		for neighbor in board.get_neighbors(cell_position):
			if board.is_revealed(neighbor):
				board_view.refresh_cell(board, neighbor)
		if modules.has_module(ModuleController.AUTO_CHORD):
			var auto_action := _resolve_auto_chords(cell_position)
			if auto_action.performed:
				_show_temporary_feedback("AUTO CHORD")
				_handle_board_action(auto_action)
				return
		_update_hud()


func _resolve_auto_chords(changed_flag_position: Vector2i) -> BoardActionResult:
	var targets: Array[Vector2i] = []
	for neighbor in board.get_neighbors(changed_flag_position):
		if board.is_revealed(neighbor) and board.can_chord(neighbor):
			targets.append(neighbor)
	targets.sort_custom(_position_precedes)
	var combined := BoardActionResult.new()
	for target in targets:
		if board.can_chord(target):
			combined.merge_from(board.perform_chord_action(target))
	return combined


func _position_precedes(first: Vector2i, second: Vector2i) -> bool:
	return first.y < second.y or (first.y == second.y and first.x < second.x)


func _refresh_changed_cells(changed: Array[Vector2i]) -> void:
	for changed_position in changed:
		board_view.refresh_cell(board, changed_position, state == FieldState.BREACH_RECOVERY)


func _finish_field() -> void:
	if state == FieldState.CLEARED or state == FieldState.LOST:
		return
	state = FieldState.CLEARED
	board_view.show_win(board)
	var field_config := run.current_config()
	var result := FieldResult.new()
	result.field_number = field_config.field_number
	result.width = field_config.width
	result.height = field_config.height
	result.mine_count = field_config.mine_count
	result.elapsed_time = elapsed_time
	run.confirm_field(result)
	modules.on_field_completed()
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
	field_result_body.text = "TIME  %s    INTEGRITY  %d / %d    NEUTRALIZED  %d\nNEXT  %d×%d · %d MINES" % [
		_format_time(result.elapsed_time),
		result.integrity_remaining,
		run.config.max_integrity,
		result.neutralized_mines,
		next.width,
		next.height,
		next.mine_count,
	]
	next_field_button.text = "ENTER FIELD %d" % next.field_number
	next_field_button.disabled = true
	module_prompt_label.text = "INSTALL ONE MODULE"
	module_choice_grid.show()
	module_confirm_row.hide()
	var offers := modules.generate_offers()
	for option_index in module_option_buttons.size():
		var option_button := module_option_buttons[option_index]
		if option_index < offers.size():
			var definition := offers[option_index]
			option_button.text = "%s  %s\n%s\n%s" % [definition.symbol, definition.display_name, definition.tag, definition.short_description]
			option_button.tooltip_text = definition.full_description
			option_button.disabled = false
			option_button.show()
		else:
			option_button.hide()
	_update_module_choice_layout()
	field_result_screen.show()
	if not offers.is_empty():
		module_option_buttons[0].grab_focus()


func _enter_next_field() -> void:
	if run.state != RunController.RunState.IN_PROGRESS or not run.has_pending_next_field or not modules.selection_completed:
		return
	modules.clear_pending_selection()
	run.begin_next_field()
	_load_current_field()


func _finish_loss(fatal_positions: Array[Vector2i]) -> void:
	if state == FieldState.LOST:
		return
	state = FieldState.LOST
	board_view.present_run_loss(board, fatal_positions)
	run.breach_run(elapsed_time)
	restart_button.disabled = true
	pause_button.disabled = true
	abandon_button.disabled = true
	_update_hud()
	_show_run_summary(false)


func _show_run_summary(won: bool) -> void:
	modules.on_run_ended()
	field_result_screen.hide()
	breach_label.hide()
	if won:
		run_summary_title.text = "RUN CLEARED"
		run_summary_title.modulate = Color("67e8a5")
		run_summary_body.text = "TOTAL TIME  %s\nINTEGRITY  %d / %d\nNEUTRALIZED  %d\nFIELDS CLEARED  %d\nMODULES INSTALLED  %d" % [
			_format_time(run.stats.total_time),
			run.current_integrity,
			run.config.max_integrity,
			run.stats.neutralized_mines,
			run.stats.fields_completed,
			modules.installed_count(),
		]
		retry_run_button.text = "NEW RUN"
	else:
		run_summary_title.text = "RUN BREACHED"
		run_summary_title.modulate = Color("ff7185")
		run_summary_body.text = "FIELD REACHED  %d / %d\nTOTAL TIME  %s\nFIELDS CLEARED  %d\nNEUTRALIZED  %d\nMODULES INSTALLED  %d" % [
			run.current_config().field_number,
			run.stages.size(),
			_format_time(run.stats.total_time),
			run.stats.fields_completed,
			run.stats.neutralized_mines,
			modules.installed_count(),
		]
		retry_run_button.text = "RETRY RUN"
	run_summary_screen.show()
	retry_run_button.grab_focus()


func _show_pause() -> void:
	if run.state != RunController.RunState.IN_PROGRESS or (state != FieldState.READY and state != FieldState.PLAYING):
		return
	_paused = true
	pause_screen.show()
	_update_restart_controls()
	_update_hud()
	resume_button.grab_focus()


func _resume_game() -> void:
	_paused = false
	pause_screen.hide()
	_update_hud()


func _show_restart_confirmation() -> void:
	if run.state != RunController.RunState.IN_PROGRESS or (state != FieldState.READY and state != FieldState.PLAYING):
		return
	field_restart_requested.emit()
	_confirmation_mode = ConfirmationMode.RESTART_FIELD
	_confirmation_returns_to_pause = pause_screen.visible
	_paused = true
	pause_screen.hide()
	confirm_title.text = "RESTART FIELD?"
	confirm_action_button.text = "RESTART"
	var waive_cost := modules.restart_is_free()
	if run.can_restart_attempt(waive_cost):
		confirm_copy.text = "COST: FREE\nCurrent field progress will be discarded." if waive_cost else "COST: %d INTEGRITY\nCurrent field progress will be discarded." % run.config.restart_integrity_cost
		confirm_action_button.disabled = false
		confirm_action_button.grab_focus()
	else:
		confirm_copy.text = "COST: %d INTEGRITY\nINSUFFICIENT INTEGRITY" % run.config.restart_integrity_cost
		confirm_action_button.disabled = true
		cancel_confirm_button.grab_focus()
	confirm_overlay.show()
	_update_hud()


func _show_leave_confirmation() -> void:
	if run.state != RunController.RunState.IN_PROGRESS:
		return
	_confirmation_mode = ConfirmationMode.LEAVE_RUN
	_confirmation_returns_to_pause = pause_screen.visible
	_paused = true
	pause_screen.hide()
	confirm_title.text = "LEAVE THIS RUN?"
	confirm_copy.text = "Current field progress will be discarded."
	confirm_action_button.text = "LEAVE RUN"
	confirm_action_button.disabled = false
	confirm_overlay.show()
	confirm_action_button.grab_focus()
	_update_hud()


func _confirm_current_dialog() -> void:
	match _confirmation_mode:
		ConfirmationMode.RESTART_FIELD:
			confirm_action_button.disabled = true
			restart_current_field()
		ConfirmationMode.LEAVE_RUN:
			return_to_main_menu()


func _cancel_confirmation() -> void:
	confirm_overlay.hide()
	_confirmation_mode = ConfirmationMode.NONE
	if _confirmation_returns_to_pause:
		pause_screen.show()
		_update_restart_controls()
		resume_button.grab_focus()
	else:
		_paused = false
	_update_hud()


func _on_integrity_changed(_current: int, _maximum: int) -> void:
	if is_node_ready():
		_update_hud()


func _on_module_option_pressed(option_index: int) -> void:
	if option_index < 0 or option_index >= modules.current_offers.size() or modules.selection_completed:
		return
	var definition := modules.current_offers[option_index]
	if not modules.select_offer(definition.id):
		return
	selected_module_label.text = "INSTALL %s?" % definition.display_name
	module_confirm_row.show()
	for button_index in module_option_buttons.size():
		module_option_buttons[button_index].disabled = button_index != option_index
	install_module_button.disabled = false
	install_module_button.grab_focus()


func _confirm_module_installation() -> void:
	install_module_button.disabled = true
	var runtime := modules.confirm_selected(run.current_config().field_number)
	if runtime == null:
		return
	for option_button in module_option_buttons:
		option_button.disabled = true
	module_choice_grid.hide()
	module_confirm_row.hide()
	module_prompt_label.text = "MODULE INSTALLED\n%s  %s" % [runtime.definition.symbol, runtime.definition.display_name]
	next_field_button.disabled = false
	next_field_button.grab_focus()


func _cancel_module_confirmation() -> void:
	if modules.selection_completed:
		return
	modules.selected_offer = null
	module_confirm_row.hide()
	for option_index in module_option_buttons.size():
		module_option_buttons[option_index].disabled = option_index >= modules.current_offers.size()
	if not modules.current_offers.is_empty():
		module_option_buttons[0].grab_focus()


func _show_modules_panel() -> void:
	if run.state != RunController.RunState.IN_PROGRESS or state == FieldState.BREACH_RECOVERY or field_result_screen.visible:
		return
	_paused = true
	modules_body.text = modules.module_state_summary()
	modules_screen.show()
	close_modules_button.grab_focus()
	_update_hud()


func _close_modules_panel() -> void:
	modules_screen.hide()
	_paused = false
	modules_button.grab_focus()
	_update_hud()


func _update_module_hud() -> void:
	if not is_node_ready():
		return
	var short_names := {
		ModuleController.BUFFER_LAYER: "BUFFER",
		ModuleController.AUTO_CHORD: "AUTO",
		ModuleController.BREACH_PULSE: "PULSE",
		ModuleController.EXPANDED_START: "START",
		ModuleController.RESTART_CACHE: "CACHE",
		ModuleController.FLAG_VERIFIER: "VERIFY",
	}
	for slot_index in module_slots.size():
		var slot := module_slots[slot_index]
		if slot_index < modules.installed.size():
			var runtime := modules.installed[slot_index]
			slot.text = "%s %s" % [runtime.definition.symbol, short_names.get(runtime.definition.id, runtime.definition.display_name)]
			slot.tooltip_text = "%s\n%s\nSTATE: %s" % [runtime.definition.display_name, runtime.definition.full_description, runtime.state_text()]
			slot.modulate = Color.WHITE if runtime.state_text() == "ACTIVE" or runtime.state_text() == "AVAILABLE" else Color("7b8da1")
			slot.show()
		else:
			slot.hide()
	modules_button.tooltip_text = "%d active module%s" % [modules.installed_count(), "" if modules.installed_count() == 1 else "s"]
	if modules_screen.visible:
		modules_body.text = modules.module_state_summary()


func _update_module_choice_layout() -> void:
	if not is_node_ready():
		return
	var compact := get_viewport_rect().size.x < 1100.0
	module_choice_grid.columns = 1 if compact else 3
	field_result_panel.custom_minimum_size = Vector2(820, 610) if compact else Vector2(980, 550)
	for option_button in module_option_buttons:
		option_button.custom_minimum_size = Vector2(748, 82) if compact else Vector2(292, 132)


func _update_restart_controls() -> void:
	var field_accepts_restart := state == FieldState.READY or state == FieldState.PLAYING
	var waive_cost := modules.restart_is_free()
	var available := field_accepts_restart and run.can_restart_attempt(waive_cost)
	restart_button.disabled = not available
	restart_button.tooltip_text = "Restart field for free." if waive_cost else ("Restart field for %d integrity." % run.config.restart_integrity_cost if available else "INSUFFICIENT INTEGRITY")
	pause_restart_button.disabled = not available
	pause_restart_button.text = "RESTART FIELD — FREE" if waive_cost else "RESTART FIELD — COST %d INTEGRITY" % run.config.restart_integrity_cost
	pause_restart_button.tooltip_text = "Free restart cache available." if waive_cost else ("Costs %d integrity." % run.config.restart_integrity_cost if available else "INSUFFICIENT INTEGRITY")


func _update_hud() -> void:
	if board == null or run.current_config() == null:
		return
	var field_config := run.current_config()
	field_label.text = "FIELD %d / %d" % [field_config.field_number, run.stages.size()]
	mines_label.text = "MINES %d" % maxi(0, board.active_mine_count() - board.flags_placed)
	_update_integrity_label()
	_update_module_hud()
	_update_restart_controls()
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
		FieldState.BREACH_RECOVERY:
			state_label.text = "BREACH"
			state_label.modulate = Color("ff7185")
		FieldState.CLEARED:
			state_label.text = "CLEARED"
			state_label.modulate = Color("67e8a5")
		FieldState.LOST:
			state_label.text = "BREACHED"
			state_label.modulate = Color("ff7185")


func _update_integrity_label() -> void:
	var segments := ""
	for index in run.config.max_integrity:
		segments += "■ " if index < run.current_integrity else "□ "
	integrity_label.text = "INTEGRITY  %s" % segments.strip_edges()
	integrity_label.tooltip_text = "Integrity: %d / %d" % [run.current_integrity, run.config.max_integrity]


func _show_breach_feedback(damage: int, blocked_damage: int = 0) -> void:
	var applied_damage := damage - blocked_damage
	if blocked_damage > 0 and applied_damage == 0:
		breach_label.text = "BUFFER ABSORBED BREACH"
	elif blocked_damage > 0:
		breach_label.text = "BUFFER ABSORBED 1 · INTEGRITY -%d" % applied_damage
	else:
		breach_label.text = "BREACH — INTEGRITY -1" if damage == 1 else "MULTI BREACH ×%d — INTEGRITY -%d" % [damage, damage]
	breach_label.modulate = Color("ff7185")
	breach_label.show()
	breach_label.pivot_offset = breach_label.size * 0.5
	breach_label.scale = Vector2(0.94, 0.94)
	var tween := create_tween()
	tween.tween_property(breach_label, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_temporary_feedback(message: String) -> void:
	breach_label.text = message
	breach_label.modulate = Color("65ddff")
	breach_label.show()
	var feedback_marker := _breach_sequence
	_hide_temporary_feedback.call_deferred(feedback_marker)


func _hide_temporary_feedback(feedback_marker: int) -> void:
	await get_tree().create_timer(0.7).timeout
	if feedback_marker == _breach_sequence and state != FieldState.BREACH_RECOVERY:
		breach_label.hide()


func _pulse_integrity() -> void:
	integrity_label.pivot_offset = integrity_label.size * 0.5
	var tween := create_tween()
	tween.tween_property(integrity_label, "scale", Vector2(1.09, 1.09), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(integrity_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _update_time_label() -> void:
	time_label.text = "TIME %s" % _format_time(elapsed_time)


func _format_time(seconds: float) -> String:
	var whole_seconds := maxi(0, int(seconds))
	return "%d:%02d" % [floori(float(whole_seconds) / 60.0), whole_seconds % 60]
