extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_stage_configuration()
	_test_overscore_bonuses()
	_test_run_progression_and_stats()
	_test_loss_at_every_field()
	await _test_game_run_flow()
	if _failures == 0:
		print("PASS: Mineshift run structure tests completed successfully.")
	quit(_failures)


func _test_stage_configuration() -> void:
	var run := RunController.new()
	var expected: Array[Array] = [
		[1, 9, 9, 10, 450],
		[2, 9, 9, 12, 700],
		[3, 10, 10, 15, 1000],
		[4, 10, 10, 18, 1350],
		[5, 11, 11, 22, 1750],
	]
	_expect(run.stages.size() == 5, "A run must contain five configured fields.")
	for index in expected.size():
		var config := run.stages[index]
		var values: Array = expected[index]
		_expect(
			config.field_number == values[0]
			and config.width == values[1]
			and config.height == values[2]
			and config.mine_count == values[3]
			and config.target_score == values[4],
			"Field configuration %d is incorrect." % (index + 1)
		)


func _test_overscore_bonuses() -> void:
	var run := RunController.new()
	_expect(run.get_overscore_bonus(109, 100) == 0, "Less than 10% overscore must not award a bonus.")
	_expect(run.get_overscore_bonus(110, 100) == 100, "10% overscore must award 100 points.")
	_expect(run.get_overscore_bonus(124, 100) == 100, "The 10-24% overscore tier is incorrect.")
	_expect(run.get_overscore_bonus(125, 100) == 250, "25% overscore must award 250 points.")
	_expect(run.get_overscore_bonus(150, 100) == 500, "50% overscore must award 500 points.")
	_expect(run.get_overscore_bonus(200, 100) == 1000, "100% overscore must award 1000 points.")


func _test_run_progression_and_stats() -> void:
	var run := RunController.new()
	var first := run.start_run()
	_expect(first.field_number == 1 and run.state == RunController.RunState.IN_PROGRESS, "Starting a run must enter Field 1.")
	run.update_provisional_score(320)
	_expect(run.confirmed_run_score == 0 and run.projected_run_score() == 320, "Provisional score must remain separate from confirmed score.")
	var expected_total := 0
	for field_index in 5:
		var config := run.current_config()
		var result := _make_result(config, 1000 + field_index * 100, config.target_score + 100, field_index % 2 == 0)
		expected_total += result.confirmed_total
		run.confirm_field(result)
		_expect(run.confirmed_run_score == expected_total, "Confirmed run score must accumulate exactly once.")
		if field_index < 4:
			_expect(run.current_config() == config, "The current field must remain active while its report is visible.")
			_expect(run.next_config().field_number == field_index + 2, "The field report must expose the next configuration.")
			run.begin_next_field()
		else:
			_expect(run.state == RunController.RunState.RUN_WON, "Confirming Field 5 must win the run.")
	_expect(run.stats.fields_completed == 5, "All five completed fields must be counted.")
	_expect(run.stats.fields_started == 5, "Each entered field must be counted once.")
	_expect(run.stats.confirmed_score == expected_total, "Run stats must mirror confirmed score.")
	_expect(run.stats.total_actions == 60, "Run actions must accumulate from field results.")
	_expect(run.stats.cells_revealed == 300, "Revealed cells must accumulate from field results.")
	_expect(run.stats.cascade_cells == 200, "Cascade cells must accumulate from field results.")
	_expect(run.stats.flags_placed == 25, "Placed flags must accumulate from field results.")
	_expect(run.stats.correct_flags_on_completion == 20, "Correct completion flags must accumulate.")
	_expect(run.stats.full_clears == 3, "Full clears must accumulate.")
	_expect(run.stats.highest_streak == 11, "The run must retain the highest field streak.")
	_expect(run.stats.best_field_score == 1400, "The run must retain the best field score.")
	_expect(run.stats.pattern_points == 1500 and run.stats.total_patterns == 15, "Confirmed pattern statistics must accumulate across fields.")
	_expect(run.stats.pattern_activations.get("cascade", 0) == 15, "Pattern activations must accumulate by type.")
	_expect(run.stats.pattern_best_metrics.get("cascade", 0) == 5, "Best pattern metrics must retain the run maximum.")
	_expect(run.stats.best_pattern_field_score == 500, "The run must retain the highest field pattern score.")


func _test_loss_at_every_field() -> void:
	for loss_index in 5:
		var run := RunController.new()
		run.start_run()
		var confirmed_before_loss := 0
		for completed_index in loss_index:
			var result := _make_result(run.current_config(), 900, run.current_config().target_score, false)
			confirmed_before_loss += result.confirmed_total
			run.confirm_field(result)
			run.begin_next_field()
		run.update_provisional_score(333)
		run.lose_field(333, 12.0, 7, 18, 10, 2, 4)
		_expect(run.state == RunController.RunState.RUN_LOST, "A mine must end the run at every field.")
		_expect(run.current_config().field_number == loss_index + 1, "The loss summary must retain the reached field.")
		_expect(run.confirmed_run_score == confirmed_before_loss, "A loss must preserve only prior confirmed fields.")
		_expect(run.stats.lost_provisional_score == 333, "The current field score must be recorded as lost.")
		_expect(run.stats.fields_completed == loss_index, "A lost field must not count as completed.")


func _test_game_run_flow() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game := scene.instantiate() as GameController
	root.add_child(game)
	await process_frame
	_expect(game.start_screen.visible and not game.game_screen.visible, "The main menu must be the initial visible screen.")
	game.menu_patterns_button.pressed.emit()
	_expect(game.catalog_screen.visible and game.catalog_body.text.contains("CHAIN") and game.catalog_body.text.contains("SURROUND"), "The menu catalog must explain all patterns.")
	var menu_elapsed := game.elapsed_time
	game._process(2.0)
	_expect(game.elapsed_time == menu_elapsed, "Opening the catalog must pause the field timer.")
	var escape_event := InputEventAction.new()
	escape_event.action = "ui_cancel"
	escape_event.pressed = true
	game._unhandled_input(escape_event)
	_expect(not game.catalog_screen.visible, "Escape must close the pattern catalog.")

	var enter_event := InputEventAction.new()
	enter_event.action = "ui_accept"
	enter_event.pressed = true
	game._unhandled_input(enter_event)
	_expect(game.run.state == RunController.RunState.IN_PROGRESS and game.run.current_config().field_number == 1, "Enter must start a new run at Field 1.")
	_expect(game.shift_field_button.disabled, "SHIFT FIELD must start disabled.")
	game._on_reveal_requested(Vector2i(4, 4))
	var config := game.run.current_config()
	game.state = GameController.FieldState.PLAYING
	game.scoring.current_score = config.target_score - 1
	game._on_score_metrics_changed()
	_expect(game.shift_field_button.disabled, "SHIFT FIELD must remain disabled below the target.")
	game.scoring.current_score = config.target_score
	game._on_score_metrics_changed()
	_expect(game.state == GameController.FieldState.TARGET_REACHED and not game.shift_field_button.disabled, "Reaching the target must unlock SHIFT FIELD.")
	var actions_at_target := game.scoring.actions_taken
	var safe_closed := _find_safe_closed(game.board)
	if safe_closed.x >= 0:
		game._on_flag_requested(safe_closed)
	_expect(game.scoring.actions_taken == actions_at_target + 1, "The player must be able to keep sweeping after reaching the target.")
	var mine := _find_mine(game.board)
	game._on_reveal_requested(mine)
	_expect(game.run.state == RunController.RunState.RUN_LOST, "Dying after reaching the target must still lose the run.")
	_expect(game.run.confirmed_run_score == 0 and game.run.stats.lost_provisional_score >= config.target_score, "Unshifted target score must remain provisional and be lost.")
	await create_timer(0.8).timeout
	_expect(game.run_summary_title.text == "RUN BREACHED", "A fatal field must lead to the run breach screen.")
	game.run_primary_button.pressed.emit()
	_expect(game.run.current_config().field_number == 1 and game.run.confirmed_run_score == 0, "RETRY RUN must restart from Field 1 without score.")

	game._on_reveal_requested(Vector2i(4, 4))
	config = game.run.current_config()
	game.state = GameController.FieldState.PLAYING
	game.scoring.current_score = config.target_score + 50
	game._on_score_metrics_changed()
	game.shift_current_field()
	_expect(game.state == GameController.FieldState.TRANSITIONING, "SHIFT FIELD must lock the completed field.")
	_expect(game.run.confirmed_run_score > config.target_score and game.run.stats.current_provisional_score == 0, "Shifting must confirm field score and clear provisional score.")
	_expect(game._last_field_result.overscore_bonus == 100, "The field report must apply overscore after meeting the target.")
	_expect(game.run_score_label.text.ends_with("+ 000000"), "The HUD must stop showing provisional score after confirmation.")
	var once_confirmed := game.run.confirmed_run_score
	game.shift_current_field()
	_expect(game.run.confirmed_run_score == once_confirmed, "Completion bonuses must never be applied twice.")

	for next_field_number in range(2, 6):
		game.result_button.pressed.emit()
		config = game.run.current_config()
		_expect(config.field_number == next_field_number, "ENTER FIELD must load the next configured field.")
		_expect(game.board.width == config.width and game.board.height == config.height and game.board.mine_count == config.mine_count, "Each field must build its configured board.")
		_expect(game.board_view.get_child_count() == config.width * config.height, "Board view must match the configured dimensions.")
		game.state = GameController.FieldState.PLAYING
		game.scoring.current_score = config.target_score
		game._on_score_metrics_changed()
		game.shift_current_field()
	_expect(game.run.state == RunController.RunState.RUN_WON and game.run.stats.fields_completed == 5, "Confirming all five fields must clear the run.")
	game.result_button.pressed.emit()
	_expect(game.run_summary_screen.visible and game.run_summary_title.text == "RUN CLEARED", "The final field report must lead to RUN CLEARED.")
	_expect(game.run_summary_body.text.contains("AVERAGE OVERSCORE"), "The victory summary must expose accumulated run statistics.")
	game.main_menu_button.pressed.emit()
	_expect(game.start_screen.visible and game.run.state == RunController.RunState.NOT_STARTED, "MAIN MENU must clear the run state.")
	game.start_new_run()
	game.start_new_run()
	game._on_flag_requested(Vector2i(0, 0))
	_expect(game.scoring.actions_taken == 1, "Repeated menu and run cycles must not duplicate signals.")
	game.queue_free()
	await process_frame


func _make_result(config: FieldConfig, confirmed_total: int, normal_score: int, full_clear: bool) -> FieldResult:
	var result := FieldResult.new()
	result.field_number = config.field_number
	result.width = config.width
	result.height = config.height
	result.mine_count = config.mine_count
	result.target_score = config.target_score
	result.normal_field_score = normal_score
	result.confirmed_total = confirmed_total
	result.elapsed_time = 10.0
	result.actions = 12
	result.cells_revealed = 60
	result.cascade_cells = 40
	result.flags_placed = 5
	result.correct_flags = 4
	result.highest_streak = 7 + config.field_number - 1
	result.full_clear = full_clear
	result.pattern_score = config.field_number * 100
	result.pattern_count = config.field_number
	result.best_pattern_name = "CASCADE %d" % config.field_number
	result.best_pattern_points = config.field_number * 20
	result.pattern_activations = {"cascade": config.field_number}
	result.pattern_best_metrics = {"cascade": config.field_number}
	result.highest_pattern_action_score = config.field_number * 20
	return result


func _find_mine(board: BoardModel) -> Vector2i:
	for y in board.height:
		for x in board.width:
			var position := Vector2i(x, y)
			if board.has_mine(position):
				return position
	return Vector2i(-1, -1)


func _find_safe_closed(board: BoardModel) -> Vector2i:
	for y in board.height:
		for x in board.width:
			var position := Vector2i(x, y)
			if not board.has_mine(position) and not board.is_revealed(position) and not board.is_flagged(position):
				return position
	return Vector2i(-1, -1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
