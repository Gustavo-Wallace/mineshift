extends SceneTree

const BOARD_WIDTH := 9
const BOARD_HEIGHT := 9
const MINE_COUNT := 10
const GENERATION_RUNS := 200

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_generation_and_counts()
	_test_flags()
	_test_empty_region_expansion()
	_test_loss_and_win_conditions()
	await _test_scene_lifecycle()
	if _failures == 0:
		print("PASS: Mineshift board and scene tests completed successfully.")
	quit(_failures)


func _test_generation_and_counts() -> void:
	for run_index in GENERATION_RUNS:
		var board := BoardModel.new(BOARD_WIDTH, BOARD_HEIGHT, MINE_COUNT)
		var first := Vector2i(run_index % BOARD_WIDTH, floori(run_index / float(BOARD_WIDTH)) % BOARD_HEIGHT)
		_expect(not board.mines_are_placed, "Board must begin without mines.")
		board.place_mines(first)
		var protected_positions: Array[Vector2i] = [first]
		protected_positions.append_array(board.get_neighbors(first))
		for position in protected_positions:
			_expect(not board.has_mine(position), "First cell and its neighbors must be safe.")

		var found_mines := 0
		for y in BOARD_HEIGHT:
			for x in BOARD_WIDTH:
				var position := Vector2i(x, y)
				if board.has_mine(position):
					found_mines += 1
					continue
				var manual_count := 0
				for neighbor in board.get_neighbors(position):
					if board.has_mine(neighbor):
						manual_count += 1
				_expect(board.adjacent_mines(position) == manual_count, "Adjacent mine count is incorrect.")
		_expect(found_mines == MINE_COUNT, "Each generated board must contain exactly ten mines.")


func _test_flags() -> void:
	var board := BoardModel.new(BOARD_WIDTH, BOARD_HEIGHT, MINE_COUNT)
	var positions: Array[Vector2i] = []
	for y in BOARD_HEIGHT:
		for x in BOARD_WIDTH:
			positions.append(Vector2i(x, y))
	for index in MINE_COUNT:
		_expect(board.toggle_flag(positions[index]), "A flag within the limit should be accepted.")
	_expect(not board.toggle_flag(positions[MINE_COUNT]), "Flags must be capped at the mine count.")
	_expect(board.flags_placed == MINE_COUNT, "Flag count must track placed flags.")
	_expect(board.toggle_flag(positions[0]), "An existing flag should be removable.")
	_expect(board.flags_placed == MINE_COUNT - 1, "Removing a flag must update the count.")

	var first := Vector2i(4, 4)
	board.reset(BOARD_WIDTH, BOARD_HEIGHT, MINE_COUNT)
	_expect(board.toggle_flag(first), "A closed cell should accept a flag.")
	board.place_mines(first)
	var result: Dictionary = board.reveal(first)
	_expect((result["changed"] as Array).is_empty(), "A flagged cell must not be revealed.")
	board.toggle_flag(first)
	board.reveal(first)
	_expect(board.is_revealed(first), "An unflagged cell should be revealable.")
	_expect(not board.toggle_flag(first), "A revealed cell must reject flags.")


func _test_empty_region_expansion() -> void:
	var board := BoardModel.new(BOARD_WIDTH, BOARD_HEIGHT, MINE_COUNT)
	var first := Vector2i(4, 4)
	board.place_mines(first)
	_expect(board.adjacent_mines(first) == 0, "The protected opening must be an empty cell.")

	var expected: Dictionary = {first: true}
	var queue: Array[Vector2i] = [first]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		if board.adjacent_mines(current) != 0:
			continue
		for neighbor in board.get_neighbors(current):
			if board.has_mine(neighbor):
				continue
			if not expected.has(neighbor):
				expected[neighbor] = true
				if board.adjacent_mines(neighbor) == 0:
					queue.append(neighbor)

	board.reveal(first)
	for y in BOARD_HEIGHT:
		for x in BOARD_WIDTH:
			var position := Vector2i(x, y)
			_expect(board.is_revealed(position) == expected.has(position), "Empty expansion must reveal its zero region and numeric border exactly.")


func _test_loss_and_win_conditions() -> void:
	var losing_board := BoardModel.new(BOARD_WIDTH, BOARD_HEIGHT, MINE_COUNT)
	losing_board.place_mines(Vector2i(4, 4))
	var mine_position := _find_mine(losing_board)
	var loss_result: Dictionary = losing_board.reveal(mine_position)
	_expect(loss_result["hit_mine"], "Revealing a mine must report a loss.")

	var winning_board := BoardModel.new(BOARD_WIDTH, BOARD_HEIGHT, MINE_COUNT)
	winning_board.place_mines(Vector2i(4, 4))
	for y in BOARD_HEIGHT:
		for x in BOARD_WIDTH:
			var position := Vector2i(x, y)
			if not winning_board.has_mine(position):
				winning_board.reveal(position)
	_expect(winning_board.all_safe_cells_revealed(), "Revealing every safe cell must satisfy the win condition.")


func _test_scene_lifecycle() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game := scene.instantiate() as GameController
	root.add_child(game)
	await process_frame
	var pattern_controller := game.get("patterns") as PatternController
	var pattern_feedback := game.get_node("%PatternFeedback") as PatternFeedback
	_expect(game.start_screen.visible, "The scene must open on the main menu.")
	_expect(game.run.state == RunController.RunState.NOT_STARTED, "A run must not start before player input.")
	game.start_new_run()
	_expect(game.state == GameController.FieldState.READY, "A new run must load Field 1 in READY.")
	_expect(game.board_view.get_child_count() == BOARD_WIDTH * BOARD_HEIGHT, "The scene must build 81 cells.")
	var known_safe_flag := Vector2i(3, 3)
	game._on_flag_requested(known_safe_flag)
	_expect(game.mines_label.text == "MINES 009", "The HUD mine counter must react to flags.")
	game._on_reveal_requested(Vector2i(4, 4))
	_expect(game.state == GameController.FieldState.PLAYING or game.state == GameController.FieldState.TARGET_REACHED, "The first reveal must start the field.")
	game._process(1.2)
	_expect(game.elapsed_time >= 1.0, "The timer must advance while playing.")
	var elapsed_before_loss := game.elapsed_time
	var exploded_position := _find_mine(game.board)
	game._on_reveal_requested(exploded_position)
	_expect(game.state == GameController.FieldState.LOST, "Revealing a mine must enter LOST.")
	_expect(game.run.state == RunController.RunState.RUN_LOST, "Revealing a mine must end the run.")
	_expect(game.run.stats.lost_provisional_pattern_points == pattern_controller.pattern_score, "A loss must record but not confirm provisional pattern points.")
	_expect(game.state_label.text == "FIELD BREACHED", "A loss must be clearly labeled.")
	_expect(game.result_panel.visible, "A loss must display the result panel.")
	_expect(game.result_body.text.contains("PROVISIONAL LOST"), "The loss result must identify discarded field score.")
	_expect(game.scoring.safe_reveal_streak == 0, "A loss must reset the current safe streak.")
	_expect(game.board_view._get_cell(exploded_position).exploded, "The triggered mine must have a distinct visual state.")
	_expect(game.board_view._get_cell(known_safe_flag).wrong_flag, "A safe flagged cell must be identified as incorrect.")
	game._process(1.0)
	_expect(game.elapsed_time == elapsed_before_loss, "The timer must stop after a loss.")
	await create_timer(0.8).timeout
	_expect(game.run_summary_screen.visible and game.run_summary_title.text == "RUN BREACHED", "A run loss must present the final breach summary.")

	game.start_new_run()
	for reset_index in 5:
		game.restart_current_field()
		_expect(game.board_view.get_child_count() == BOARD_WIDTH * BOARD_HEIGHT, "Repeated resets must not duplicate cells.")
		_expect(game.state == GameController.FieldState.READY, "Every reset must return to READY.")
		_expect(game.elapsed_time == 0.0, "Every reset must clear the timer.")
		_expect(game.scoring.current_score == 0 and game.scoring.actions_taken == 0, "Every reset must clear scoring and actions.")
		_expect(pattern_controller.pattern_score == 0 and pattern_controller.total_patterns == 0, "Every reset must clear provisional patterns.")

	game._on_reveal_requested(Vector2i(4, 4))
	for y in BOARD_HEIGHT:
		for x in BOARD_WIDTH:
			var position := Vector2i(x, y)
			if not game.board.has_mine(position):
				game._on_reveal_requested(position)
	_expect(game.state == GameController.FieldState.TRANSITIONING, "A full clear must enter the field transition.")
	_expect(game.result_panel.visible, "A full clear must display the field report.")
	_expect(game.result_body.text.contains("FULL CLEAR") and game.result_body.text.contains("OVERSCORE"), "The field report must itemize run bonuses.")
	_expect(game.run.confirmed_run_score > 0 and game.run.stats.full_clears == 1, "A full clear must confirm score and run statistics.")
	_expect(game.run.stats.pattern_points == game._last_field_result.pattern_score, "A completed field must confirm its pattern statistics.")
	var elapsed_before_win_tick := game.elapsed_time
	game._process(1.0)
	_expect(game.elapsed_time == elapsed_before_win_tick, "The timer must stop after a win.")
	var confirmed_before_next_field := game.run.confirmed_run_score
	game.result_button.pressed.emit()
	_expect(game.shop_screen.visible, "A completed non-final field must open the Shift Shop before progression.")
	_expect(game.modules.credits > 0 and game.modules.stock.size() == 3, "The shop must retain awarded credits and three offers.")
	game.enter_field_button.pressed.emit()
	_expect(game.run.current_config().field_number == 2 and game.board.mine_count == 12, "The field report must advance to the configured next field.")

	var reset_event := InputEventAction.new()
	reset_event.action = "new_field"
	reset_event.pressed = true
	game._unhandled_input(reset_event)
	_expect(game.state == GameController.FieldState.READY, "The R action must restart the current field.")
	_expect(game.run.current_config().field_number == 2 and game.run.confirmed_run_score == confirmed_before_next_field, "Restarting must preserve the stage and confirmed run score.")
	game._on_reveal_requested(Vector2i(4, 4))
	game.restart_field_button.pressed.emit()
	_expect(game.state == GameController.FieldState.READY, "The restart button must restart only the current field.")
	await create_timer(1.3).timeout
	_expect(game.score_feedback.overlay.get_child_count() == 0, "Score feedback nodes must not survive a reset.")
	_expect(pattern_feedback.overlay.get_child_count() == 0, "Pattern feedback nodes must not survive a reset.")
	game._show_abandon_confirmation()
	_expect(game.abandon_overlay.visible, "Abandoning a run must require confirmation.")
	game.cancel_abandon_button.pressed.emit()
	_expect(not game.abandon_overlay.visible and game.run.state == RunController.RunState.IN_PROGRESS, "Cancelling abandonment must preserve the run.")
	game._show_abandon_confirmation()
	game.confirm_abandon_button.pressed.emit()
	_expect(game.start_screen.visible and game.run.state == RunController.RunState.NOT_STARTED, "Confirming abandonment must clear the run and return to the menu.")
	game.queue_free()
	await process_frame


func _find_mine(board: BoardModel) -> Vector2i:
	for y in board.height:
		for x in board.width:
			var position := Vector2i(x, y)
			if board.has_mine(position):
				return position
	return Vector2i(-1, -1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
