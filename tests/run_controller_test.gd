extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_stage_configuration()
	_test_run_progression()
	_test_loss_at_every_field()
	await _test_pause_loss_retry_and_complete_run()
	if _failures == 0:
		print("PASS: Mineshift minimal run and interface tests completed successfully.")
	quit(_failures)


func _test_stage_configuration() -> void:
	var run := RunController.new()
	var expected: Array[Array] = [[1, 9, 9, 10], [2, 9, 9, 12], [3, 10, 10, 15], [4, 10, 10, 18], [5, 11, 11, 22]]
	_expect(run.stages.size() == 5, "The run must preserve five data-driven fields.")
	for index in expected.size():
		var config := run.stages[index]
		var values := expected[index]
		_expect(config.field_number == values[0] and config.width == values[1] and config.height == values[2] and config.mine_count == values[3], "Field %d configuration is incorrect." % (index + 1))


func _test_run_progression() -> void:
	var run := RunController.new()
	run.start_run()
	for field_index in 5:
		var config := run.current_config()
		var result := FieldResult.new()
		result.field_number = config.field_number
		result.width = config.width
		result.height = config.height
		result.mine_count = config.mine_count
		result.elapsed_time = 10.0 + field_index
		run.confirm_field(result)
		if field_index < 4:
			_expect(run.has_pending_next_field and run.current_config() == config, "A cleared field must wait for explicit progression.")
			run.begin_next_field()
		else:
			_expect(run.state == RunController.RunState.RUN_WON, "Clearing Field 5 must win the run.")
	_expect(run.stats.fields_completed == 5 and is_equal_approx(run.stats.total_time, 60.0), "Minimal completion statistics must accumulate correctly.")


func _test_loss_at_every_field() -> void:
	for loss_index in 5:
		var run := RunController.new()
		run.start_run()
		for _completed in loss_index:
			var config := run.current_config()
			var result := FieldResult.new()
			result.field_number = config.field_number
			result.elapsed_time = 3.0
			run.confirm_field(result)
			run.begin_next_field()
		run.breach_run(4.0)
		_expect(run.state == RunController.RunState.RUN_LOST and run.stats.fields_completed == loss_index, "A mine must end the run at every field without confirming it.")


func _test_pause_loss_retry_and_complete_run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game := scene.instantiate() as GameController
	root.add_child(game)
	await process_frame
	game.start_new_run()
	var game_minimum := game.game_screen.get_combined_minimum_size()
	_expect(game_minimum.x <= 1024.0 and game_minimum.y <= 640.0, "The game layout minimum size must fit a moderately smaller window.")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	game._unhandled_input(escape)
	_expect(game.pause_screen.visible and game.state_label.text == "PAUSED", "Escape must open the pause panel.")
	var paused_time := game.elapsed_time
	game._process(2.0)
	_expect(game.elapsed_time == paused_time, "The field timer must stop while paused.")
	game._unhandled_input(escape)
	_expect(not game.pause_screen.visible, "Escape must resume from pause.")

	game._on_reveal_requested(Vector2i(4, 4))
	var wrong_flag := _find_closed_safe(game.board)
	game._on_flag_requested(wrong_flag)
	var mine := _find_mine(game.board)
	game._on_reveal_requested(mine)
	_expect(game.run.state == RunController.RunState.RUN_LOST and game.state == GameController.FieldState.LOST, "Revealing a mine must breach the entire run.")
	var exploded_cell := game.board_view.get_child(mine.y * game.board.width + mine.x) as MineCell
	var wrong_flag_cell := game.board_view.get_child(wrong_flag.y * game.board.width + wrong_flag.x) as MineCell
	_expect(exploded_cell.exploded and wrong_flag_cell.wrong_flag and exploded_cell.locked, "Loss rendering must distinguish the triggered mine, wrong flags and locked cells.")
	await create_timer(0.7).timeout
	_expect(game.run_summary_screen.visible and game.run_summary_title.text == "RUN BREACHED", "A compact breach summary must appear after the board reveal.")
	_expect(_inside_viewport(game.retry_run_button) and _inside_viewport(game.summary_menu_button), "Breach actions must fit inside 1280×720.")
	game.retry_run_button.pressed.emit()
	_expect(game.run.current_config().field_number == 1 and game.state == GameController.FieldState.READY, "Retry must create a clean run at Field 1.")

	game.pause_button.pressed.emit()
	game.pause_abandon_button.pressed.emit()
	_expect(game.confirm_overlay.visible, "Leaving a run must require an in-game confirmation panel.")
	game.cancel_leave_button.pressed.emit()
	_expect(game.pause_screen.visible and game.run.state == RunController.RunState.IN_PROGRESS, "Cancelling leave confirmation must preserve the run.")
	game.resume_button.pressed.emit()

	for field_number in range(1, 6):
		_expect(game.run.current_config().field_number == field_number, "The scene must remain on the expected field.")
		var cell := game.board_view.get_child(0) as MineCell
		var expected_size := 54.0 if field_number <= 2 else (49.0 if field_number <= 4 else 44.0)
		_expect(is_equal_approx(cell.custom_minimum_size.x, expected_size) and cell.custom_minimum_size.x == cell.custom_minimum_size.y, "Field %d must use the responsive square cell size." % field_number)
		game._on_reveal_requested(Vector2i(floori(float(game.board.width) / 2.0), floori(float(game.board.height) / 2.0)))
		_clear_all_safe(game)
		await process_frame
		_expect(game.state == GameController.FieldState.CLEARED, "Every field must require all safe cells to be revealed.")
		var resolved_mine := _find_mine(game.board)
		var resolved_cell := game.board_view.get_child(resolved_mine.y * game.board.width + resolved_mine.x) as MineCell
		_expect(resolved_cell.resolved and resolved_cell.locked, "Victory must mark remaining mines as resolved and lock the board.")
		if field_number < 5:
			_expect(game.field_result_screen.visible and _inside_viewport(game.next_field_button), "The compact transition must fit and expose progression.")
			game.next_field_button.pressed.emit()
	_expect(game.run.state == RunController.RunState.RUN_WON and game.run_summary_title.text == "RUN CLEARED", "Clearing the fifth field must show the compact run victory.")
	_expect(_inside_viewport(game.retry_run_button) and _inside_viewport(game.summary_menu_button), "Victory actions must remain visible without resizing.")
	game.summary_menu_button.pressed.emit()
	_expect(game.start_screen.visible and game.run.state == RunController.RunState.NOT_STARTED, "MAIN MENU must clear run state.")
	game.start_new_run()
	game.restart_current_field()
	game.restart_current_field()
	_expect(game.board_view.get_child_count() == 81 and game.run.stats.restarts == 2, "Repeated restarts must not duplicate cells or signals.")
	game.queue_free()
	await process_frame


func _clear_all_safe(game: GameController) -> void:
	for y in game.board.height:
		for x in game.board.width:
			var cell_position := Vector2i(x, y)
			if not game.board.has_mine(cell_position) and not game.board.is_revealed(cell_position):
				game._on_reveal_requested(cell_position)


func _find_mine(board: BoardModel) -> Vector2i:
	for y in board.height:
		for x in board.width:
			var cell_position := Vector2i(x, y)
			if board.has_mine(cell_position):
				return cell_position
	return Vector2i(-1, -1)


func _find_closed_safe(board: BoardModel) -> Vector2i:
	for y in board.height:
		for x in board.width:
			var cell_position := Vector2i(x, y)
			if not board.has_mine(cell_position) and not board.is_revealed(cell_position):
				return cell_position
	return Vector2i(-1, -1)


func _inside_viewport(control: Control) -> bool:
	return Rect2(Vector2.ZERO, control.get_viewport_rect().size).encloses(control.get_global_rect())


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
