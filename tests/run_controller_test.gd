extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_stage_configuration()
	_test_integrity_lifecycle()
	_test_integrity_persistence_and_progression()
	_test_paid_restart_accounting()
	await _test_game_breach_flow()
	await _test_multi_breach_and_complete_run()
	if _failures == 0:
		print("PASS: Mineshift persistent integrity and run tests completed successfully.")
	quit(_failures)


func _test_stage_configuration() -> void:
	var run := RunController.new()
	var expected: Array[Array] = [[1, 9, 9, 10], [2, 9, 9, 12], [3, 10, 10, 15], [4, 10, 10, 18], [5, 11, 11, 22]]
	_expect(run.config.max_integrity == 3 and run.config.restart_integrity_cost == 1, "Integrity values must be centralized in run configuration.")
	_expect(run.stages.size() == 5, "The run must preserve five data-driven fields.")
	for index in expected.size():
		var field_config := run.stages[index]
		var values := expected[index]
		_expect(field_config.field_number == values[0] and field_config.width == values[1] and field_config.height == values[2] and field_config.mine_count == values[3], "Field %d configuration is incorrect." % (index + 1))


func _test_integrity_lifecycle() -> void:
	var run := RunController.new()
	run.start_run()
	_expect(run.current_integrity == 3, "A new run must start at 3 / 3 integrity.")
	_expect(run.apply_damage(1) == 1 and run.current_integrity == 2, "One breach must remove exactly one integrity.")
	_expect(run.apply_damage(1) == 1 and run.current_integrity == 1, "A second breach must leave one integrity.")
	_expect(run.apply_damage(4) == 1 and run.current_integrity == 0, "Integrity damage must clamp at zero.")
	_expect(run.apply_damage(1) == 0 and run.current_integrity == 0, "Integrity can never become negative.")
	run.breach_run(4.0)
	_expect(run.state == RunController.RunState.RUN_LOST, "The run must enter loss only after integrity depletion is resolved.")
	run.start_run()
	_expect(run.current_integrity == 3 and run.stats.damage_taken == 0, "Retrying must restore integrity and clear old damage.")
	run.apply_damage(1)
	run.abandon_run()
	_expect(run.state == RunController.RunState.NOT_STARTED and run.current_integrity == 3, "Abandoning must clear the prior integrity state.")


func _test_integrity_persistence_and_progression() -> void:
	var run := RunController.new()
	run.start_run()
	run.apply_damage(1)
	for field_index in 5:
		var field_config := run.current_config()
		var result := FieldResult.new()
		result.field_number = field_config.field_number
		result.width = field_config.width
		result.height = field_config.height
		result.mine_count = field_config.mine_count
		result.elapsed_time = 10.0 + field_index
		if field_index == 0:
			run.record_neutralized(1)
		run.confirm_field(result)
		_expect(result.integrity_remaining == 2, "Field results must retain current run integrity.")
		if field_index < 4:
			run.begin_next_field()
			_expect(run.current_integrity == 2, "Integrity must not regenerate between fields.")
	_expect(run.state == RunController.RunState.RUN_WON and run.stats.fields_completed == 5, "Five cleared fields must still win the run.")
	_expect(run.stats.neutralized_mines == 1 and is_equal_approx(run.stats.total_time, 60.0), "Confirmed minimal run statistics must accumulate exactly once.")


func _test_paid_restart_accounting() -> void:
	var run := RunController.new()
	run.start_run()
	var original_field := run.current_config()
	run.record_neutralized(2)
	_expect(run.can_restart_attempt(), "Three integrity must allow a paid restart.")
	var restarted := run.restart_field_attempt(6.0)
	_expect(restarted == original_field and run.current_integrity == 2, "A paid restart must preserve the field and charge one integrity.")
	_expect(run.current_field_neutralized == 0 and run.stats.neutralized_mines == 0, "Neutralizations from a discarded board must not be confirmed.")
	_expect(run.stats.paid_restarts == 1 and run.stats.damage_taken == 1 and is_equal_approx(run.stats.total_time, 6.0), "Paid restart statistics and discarded time must be recorded.")
	run.restart_field_attempt()
	_expect(run.current_integrity == 1 and not run.can_restart_attempt(), "One remaining integrity must disable restarts.")
	_expect(run.restart_field_attempt() == null and run.current_integrity == 1, "A blocked restart must never consume integrity.")


func _test_game_breach_flow() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game := scene.instantiate() as GameController
	root.add_child(game)
	await process_frame
	game.start_new_run()
	var game_minimum := game.game_screen.get_combined_minimum_size()
	_expect(game_minimum.x <= 1024.0 and game_minimum.y <= 640.0, "The integrity HUD must fit a moderately smaller 1024×640 window (minimum is %s)." % game_minimum)
	_expect(game.run.current_integrity == 3 and game.integrity_label.tooltip_text.contains("3 / 3"), "The integrity HUD must be visible and accessible.")
	game._on_reveal_requested(Vector2i(4, 4))
	var mines := _find_all_mines(game.board)
	_expect(mines.size() >= 3, "The first field must provide three breach targets.")

	game._on_reveal_requested(mines[0])
	_expect(game.state == GameController.FieldState.BREACH_RECOVERY and game.run.current_integrity == 2, "A direct mine must enter recovery and leave the run active at 2 / 3.")
	game._on_reveal_requested(mines[1])
	_expect(game.run.current_integrity == 2, "Input during recovery must not apply duplicate or additional damage.")
	await create_timer(0.5).timeout
	_expect(game.state == GameController.FieldState.PLAYING and game.board.is_neutralized(mines[0]), "The first mine must become neutralized and return control.")
	var first_cell := game.board_view.get_child(mines[0].y * game.board.width + mines[0].x) as MineCell
	_expect(first_cell.neutralized and not first_cell.contains_mine, "A neutralized mine must have a distinct persistent visual state.")
	game._on_reveal_requested(mines[0])
	_expect(game.run.current_integrity == 2, "Selecting a neutralized mine again must cause no damage.")

	game._on_reveal_requested(mines[1])
	await create_timer(0.5).timeout
	_expect(game.run.current_integrity == 1 and game.state == GameController.FieldState.PLAYING, "A second direct breach must leave the run active at 1 / 3.")
	game._on_reveal_requested(mines[2])
	await create_timer(0.5).timeout
	_expect(game.run.current_integrity == 0 and game.run.state == RunController.RunState.RUN_LOST, "The third breach must end the run at exactly zero integrity.")
	_expect(game.run_summary_screen.visible and game.run_summary_title.text == "RUN BREACHED", "Depletion must show the compact run breach summary.")
	_expect(game.run_summary_body.text.contains("NEUTRALIZED  3"), "The loss summary must include neutralized mines from the fatal field.")
	var fatal_cell := game.board_view.get_child(mines[2].y * game.board.width + mines[2].x) as MineCell
	_expect(fatal_cell.neutralized and fatal_cell.exploded and fatal_cell.locked, "The fatal neutralized mine must remain distinguished and locked.")
	game.retry_run_button.pressed.emit()
	_expect(game.run.current_integrity == 3 and game.state == GameController.FieldState.READY, "Retry must start a clean 3 / 3 run.")
	game.queue_free()
	await process_frame


func _test_multi_breach_and_complete_run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game := scene.instantiate() as GameController
	root.add_child(game)
	await process_frame
	game.start_new_run()
	var setup := _find_incorrect_chord_setup()
	_expect(not setup.is_empty(), "An integrated two-mine chord setup must be discoverable.")
	if not setup.is_empty():
		game.board = setup["board"]
		game.board_view.build(game.board.width, game.board.height)
		game.state = GameController.FieldState.PLAYING
		game._update_hud()
		game._on_reveal_requested(setup["target"])
		_expect(game.state == GameController.FieldState.BREACH_RECOVERY and game.run.current_integrity == 1, "A two-mine chord must apply two integrity damage in one recovery.")
		_expect(game.breach_label.text.contains("MULTI BREACH ×2"), "A multi-breach must use one compact combined message.")
		await create_timer(0.5).timeout
		for mine_position: Vector2i in setup["mines"]:
			_expect(game.board.is_neutralized(mine_position), "Every mine from the chord must be neutralized.")
		_expect(game.run.current_field_neutralized == 2, "The current field must track both neutralizations.")

	game.start_new_run()
	game.pause_button.pressed.emit()
	var paused_time := game.elapsed_time
	game._process(2.0)
	_expect(game.pause_screen.visible and game.elapsed_time == paused_time, "Pause must continue to stop the timer.")
	game.resume_button.pressed.emit()
	for field_number in range(1, 6):
		_expect(game.run.current_config().field_number == field_number, "The run must remain on the expected progressive field.")
		game._on_reveal_requested(Vector2i(floori(float(game.board.width) / 2.0), floori(float(game.board.height) / 2.0)))
		_clear_all_safe(game)
		await process_frame
		_expect(game.state == GameController.FieldState.CLEARED, "Every field must still require all safe cells to be revealed.")
		if field_number < 5:
			_expect(game.field_result_screen.visible and _inside_viewport(game.next_field_button), "The compact integrity transition must fit in 1280×720.")
			game.module_option_buttons[0].pressed.emit()
			game.install_module_button.pressed.emit()
			game.next_field_button.pressed.emit()
	_expect(game.run.state == RunController.RunState.RUN_WON and game.run_summary_title.text == "RUN CLEARED", "Clearing Field 5 must preserve the normal run victory.")
	_expect(game.modules.installed_count() == 4 and not game.field_result_screen.visible, "The run must end with four unique modules and no fifth-field choice.")
	_expect(game.run_summary_body.text.contains("INTEGRITY  3 / 3") and _inside_viewport(game.retry_run_button), "The compact victory must show remaining integrity and visible actions.")
	game.summary_menu_button.pressed.emit()
	_expect(game.start_screen.visible and game.run.state == RunController.RunState.NOT_STARTED, "Main menu must clear the completed run.")
	game.queue_free()
	await process_frame


func _clear_all_safe(game: GameController) -> void:
	for y in game.board.height:
		for x in game.board.width:
			var cell_position := Vector2i(x, y)
			if not game.board.has_mine(cell_position) and not game.board.is_neutralized(cell_position) and not game.board.is_revealed(cell_position):
				game._on_reveal_requested(cell_position)


func _find_all_mines(board: BoardModel) -> Array[Vector2i]:
	var mines: Array[Vector2i] = []
	for y in board.height:
		for x in board.width:
			var cell_position := Vector2i(x, y)
			if board.has_mine(cell_position):
				mines.append(cell_position)
	return mines


func _find_incorrect_chord_setup() -> Dictionary:
	for _attempt in 700:
		var board := BoardModel.new(9, 9, 10)
		board.generate_mines(Vector2i(4, 4))
		board.perform_reveal_action(Vector2i(4, 4))
		for y in board.height:
			for x in board.width:
				var target := Vector2i(x, y)
				if not board.is_revealed(target) or board.adjacent_mines(target) != 2:
					continue
				var mines: Array[Vector2i] = []
				var closed_safe: Array[Vector2i] = []
				for neighbor in board.get_neighbors(target):
					if board.has_mine(neighbor):
						mines.append(neighbor)
					elif not board.is_revealed(neighbor):
						closed_safe.append(neighbor)
				if mines.size() == 2 and closed_safe.size() >= 2:
					board.toggle_flag(closed_safe[0])
					board.toggle_flag(closed_safe[1])
					return {"board": board, "target": target, "mines": mines}
	return {}


func _inside_viewport(control: Control) -> bool:
	return Rect2(Vector2.ZERO, control.get_viewport_rect().size).encloses(control.get_global_rect())


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
