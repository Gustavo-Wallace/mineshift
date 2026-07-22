extends SceneTree

const BOARD_WIDTH := 9
const BOARD_HEIGHT := 9
const MINE_COUNT := 10

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_generation_and_opening_safety()
	_test_flags_and_limit()
	_test_empty_region()
	_test_chords()
	_test_neutralization_and_recalculation()
	_test_zero_expansion_and_flag_protection()
	_test_multiple_detonations()
	await _test_scene_field_and_paid_restart()
	if _failures == 0:
		print("PASS: Mineshift board, neutralization, and restart tests completed successfully.")
	quit(_failures)


func _test_generation_and_opening_safety() -> void:
	for run_index in 150:
		var board := BoardModel.new(BOARD_WIDTH, BOARD_HEIGHT, MINE_COUNT)
		var first := Vector2i(run_index % BOARD_WIDTH, floori(run_index / float(BOARD_WIDTH)) % BOARD_HEIGHT)
		board.generate_mines(first)
		_expect(not board.has_mine(first), "The opening cell must always be safe.")
		for neighbor in board.get_neighbors(first):
			_expect(not board.has_mine(neighbor), "Every neighbor of the opening cell must be protected.")
		var mines := 0
		for y in board.height:
			for x in board.width:
				var cell_position := Vector2i(x, y)
				if board.has_mine(cell_position):
					mines += 1
				else:
					var adjacent := 0
					for neighbor in board.get_neighbors(cell_position):
						adjacent += int(board.has_mine(neighbor))
					_expect(board.adjacent_mines(cell_position) == adjacent, "Adjacent mine counts must match the generated board.")
		_expect(mines == MINE_COUNT, "Generation must place the configured mine count.")


func _test_flags_and_limit() -> void:
	var board := BoardModel.new(5, 5, 3)
	for index in 3:
		_expect(board.toggle_flag(Vector2i(index, 0)), "Flags below the mine limit must be accepted.")
	_expect(not board.toggle_flag(Vector2i(3, 0)), "Flags must be capped by active mines.")
	_expect(board.toggle_flag(Vector2i(1, 0)) and board.flags_placed == 2, "Removing a flag must always remain possible.")
	board.generate_mines(Vector2i(2, 2))
	var opening: BoardActionResult = board.perform_reveal_action(Vector2i(2, 2))
	if not opening.safe_revealed.is_empty():
		_expect(not board.toggle_flag(opening.safe_revealed[0]), "Revealed cells cannot be flagged.")


func _test_empty_region() -> void:
	var board := BoardModel.new(9, 9, 10)
	board.generate_mines(Vector2i(4, 4))
	var opening: BoardActionResult = board.perform_reveal_action(Vector2i(4, 4))
	_expect(not opening.has_breach() and not opening.safe_revealed.is_empty(), "A safe opening must reveal a region without damage.")


func _test_chords() -> void:
	var setup := _find_correct_chord_setup()
	_expect(not setup.is_empty(), "A valid chord scenario must be discoverable.")
	if setup.is_empty():
		return
	var board: BoardModel = setup["board"]
	for mine_position: Vector2i in setup["mines"]:
		board.toggle_flag(mine_position)
	var action: BoardActionResult = board.perform_chord_action(setup["target"])
	_expect(action.performed and not action.has_breach(), "Correct flags must permit a safe chord.")
	_expect(not action.safe_revealed.is_empty(), "A successful chord must reveal closed neighbors.")


func _test_neutralization_and_recalculation() -> void:
	var setup := _find_recalculation_setup(false)
	_expect(not setup.is_empty(), "A mine adjacent to a revealed number must be discoverable.")
	if setup.is_empty():
		return
	var board: BoardModel = setup["board"]
	var mine_position: Vector2i = setup["mine"]
	var affected: Vector2i = setup["revealed_neighbor"]
	var unrelated: Vector2i = setup["unrelated"]
	var previous_affected := board.adjacent_mines(affected)
	var previous_unrelated := board.adjacent_mines(unrelated) if unrelated.x >= 0 else -1
	var active_before: int = board.active_mine_count()
	var action: BoardActionResult = board.perform_reveal_action(mine_position)
	_expect(action.detonated_mines == [mine_position], "A direct mine reveal must report exactly that detonation.")
	board.neutralize_detonations(action)
	_expect(board.is_neutralized(mine_position) and not board.has_mine(mine_position), "A detonated mine must retain explicit neutralized history and stop being active.")
	_expect(board.active_mine_count() == active_before - 1, "Neutralization must reduce active mines by one.")
	_expect(board.adjacent_mines(affected) == previous_affected - 1, "An affected revealed number must be recalculated.")
	if unrelated.x >= 0:
		_expect(board.adjacent_mines(unrelated) == previous_unrelated, "Numbers outside the affected region must remain unchanged.")
	_expect(not board.toggle_flag(mine_position), "A neutralized mine cannot receive a flag.")
	var second_action: BoardActionResult = board.perform_reveal_action(mine_position)
	_expect(not second_action.performed and second_action.detonated_mines.is_empty(), "A neutralized mine cannot detonate twice.")

	var flags_added := 0
	for y in board.height:
		for x in board.width:
			var cell_position := Vector2i(x, y)
			if flags_added < board.active_mine_count() and not board.is_revealed(cell_position) and board.toggle_flag(cell_position):
				flags_added += 1
	_expect(flags_added == board.active_mine_count(), "The flag limit must follow the current active mine count.")
	_expect(not board.toggle_flag(_find_closed_unflagged(board)), "No new flag may exceed the active mine count.")


func _test_zero_expansion_and_flag_protection() -> void:
	var setup := _find_recalculation_setup(true)
	_expect(not setup.is_empty(), "A neutralization that turns a revealed number into zero must be discoverable.")
	if setup.is_empty():
		return
	var board: BoardModel = setup["board"]
	var zero_origin: Vector2i = setup["revealed_neighbor"]
	var protected_safe: Vector2i = setup["closed_safe"]
	_expect(board.toggle_flag(protected_safe), "The expansion protection cell must accept a flag.")
	var action: BoardActionResult = board.perform_reveal_action(setup["mine"])
	board.neutralize_detonations(action)
	_expect(board.adjacent_mines(zero_origin) == 0 and action.recalculated_positions.has(zero_origin), "The revealed number must visibly become zero.")
	_expect(board.is_flagged(protected_safe) and not board.is_revealed(protected_safe), "Zero expansion must respect existing flags.")
	_expect(board.toggle_flag(protected_safe), "The protected flag must be removable.")
	var follow_up: BoardActionResult = board.perform_reveal_action(protected_safe)
	_expect(not follow_up.safe_revealed.is_empty(), "The protected safe cell must remain playable after recalculation.")

	var expansion_setup := _find_recalculation_setup(true)
	if not expansion_setup.is_empty():
		var expansion_board: BoardModel = expansion_setup["board"]
		var expansion_action: BoardActionResult = expansion_board.perform_reveal_action(expansion_setup["mine"])
		expansion_board.neutralize_detonations(expansion_action)
		_expect(not expansion_action.expansion_revealed.is_empty(), "A newly revealed zero must propagate into connected safe cells.")


func _test_multiple_detonations() -> void:
	var setup := _find_incorrect_chord_setup()
	_expect(not setup.is_empty(), "An incorrect two-mine chord scenario must be discoverable.")
	if setup.is_empty():
		return
	var board: BoardModel = setup["board"]
	var safe_before: Array[Vector2i] = setup["unflagged_safe"]
	var active_before: int = board.active_mine_count()
	var action: BoardActionResult = board.perform_chord_action(setup["target"])
	_expect(action.performed and action.detonated_mines.size() == 2, "One incorrect chord must report both detonated mines.")
	board.neutralize_detonations(action)
	_expect(action.neutralized_mines.size() == 2 and board.active_mine_count() == active_before - 2, "Both mines from a multi-breach must be neutralized together.")
	for safe_position in safe_before:
		_expect(board.is_revealed(safe_position), "Safe cells opened by the same chord must remain revealed.")
	for remaining_mine in _find_all_mines(board):
		_expect(board.has_mine(remaining_mine), "Unrelated active mines must remain active.")


func _test_scene_field_and_paid_restart() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game := scene.instantiate() as GameController
	root.add_child(game)
	await process_frame
	game.start_new_run()
	_expect(game.run.current_integrity == 3 and game.integrity_label.text.contains("■ ■ ■"), "A new run must expose three active integrity segments.")
	game._on_reveal_requested(Vector2i(4, 4))
	_clear_all_safe(game)
	await process_frame
	_expect(game.state == GameController.FieldState.CLEARED and game.field_result_body.text.contains("INTEGRITY  3 / 3"), "A clean field must preserve integrity in the compact result.")
	_install_non_cache_offer(game)
	game.next_field_button.pressed.emit()
	_expect(game.run.current_integrity == 3 and game.run.current_config().field_number == 2, "Integrity must persist between fields.")

	game.restart_button.pressed.emit()
	_expect(game.confirm_overlay.visible and game.confirm_copy.text.contains("COST: 1 INTEGRITY"), "The HUD restart button must open a cost confirmation.")
	game.cancel_confirm_button.pressed.emit()
	_expect(game.run.current_integrity == 3 and not game.confirm_overlay.visible, "Cancelling a restart must not charge integrity.")

	var restart_key := InputEventAction.new()
	restart_key.action = "new_field"
	restart_key.pressed = true
	game._unhandled_input(restart_key)
	_expect(game.confirm_overlay.visible, "R must open the restart confirmation.")
	game.confirm_action_button.pressed.emit()
	game.confirm_action_button.pressed.emit()
	_expect(game.run.current_integrity == 2 and game.run.current_config().field_number == 2, "Confirming once must charge exactly one integrity and preserve the field index.")
	_expect(game.elapsed_time == 0.0 and game.state == GameController.FieldState.READY, "A paid restart must regenerate and reset the current field timer.")

	game._show_restart_confirmation()
	game.confirm_action_button.pressed.emit()
	_expect(game.run.current_integrity == 1 and not game.run.can_restart_attempt(), "A second paid restart must leave one integrity and disable further restarts.")
	game._show_restart_confirmation()
	_expect(game.confirm_copy.text.contains("INSUFFICIENT INTEGRITY") and game.confirm_action_button.disabled, "Restart confirmation must clearly reject one remaining integrity.")
	game.cancel_confirm_button.pressed.emit()
	game.queue_free()
	await process_frame


func _clear_all_safe(game: GameController) -> void:
	for y in game.board.height:
		for x in game.board.width:
			var cell_position := Vector2i(x, y)
			if not game.board.has_mine(cell_position) and not game.board.is_revealed(cell_position):
				game._on_reveal_requested(cell_position)


func _install_non_cache_offer(game: GameController) -> void:
	for option_index in game.modules.current_offers.size():
		if game.modules.current_offers[option_index].id != ModuleController.RESTART_CACHE:
			game.module_option_buttons[option_index].pressed.emit()
			game.install_module_button.pressed.emit()
			return


func _find_correct_chord_setup() -> Dictionary:
	for _attempt in 300:
		var board := BoardModel.new(9, 9, 10)
		board.generate_mines(Vector2i(4, 4))
		board.perform_reveal_action(Vector2i(4, 4))
		for y in board.height:
			for x in board.width:
				var target := Vector2i(x, y)
				if not board.is_revealed(target) or board.adjacent_mines(target) == 0:
					continue
				var mines: Array[Vector2i] = []
				var closed_safe := false
				for neighbor in board.get_neighbors(target):
					if board.has_mine(neighbor):
						mines.append(neighbor)
					elif not board.is_revealed(neighbor):
						closed_safe = true
				if closed_safe and mines.size() == board.adjacent_mines(target):
					return {"board": board, "target": target, "mines": mines}
	return {}


func _find_incorrect_chord_setup() -> Dictionary:
	for _attempt in 600:
		var board := BoardModel.new(9, 9, 10)
		board.generate_mines(Vector2i(4, 4))
		board.perform_reveal_action(Vector2i(4, 4))
		for y in board.height:
			for x in board.width:
				var target := Vector2i(x, y)
				if not board.is_revealed(target) or board.adjacent_mines(target) != 2:
					continue
				var closed_safe: Array[Vector2i] = []
				var mines: Array[Vector2i] = []
				for neighbor in board.get_neighbors(target):
					if board.has_mine(neighbor):
						mines.append(neighbor)
					elif not board.is_revealed(neighbor):
						closed_safe.append(neighbor)
				if mines.size() == 2 and closed_safe.size() >= 2:
					board.toggle_flag(closed_safe[0])
					board.toggle_flag(closed_safe[1])
					var unflagged_safe: Array[Vector2i] = []
					for safe_position in closed_safe:
						if not board.is_flagged(safe_position):
							unflagged_safe.append(safe_position)
					return {"board": board, "target": target, "mines": mines, "unflagged_safe": unflagged_safe}
	return {}


func _find_recalculation_setup(require_zero: bool) -> Dictionary:
	for _attempt in 800:
		var board := BoardModel.new(9, 9, 10)
		board.generate_mines(Vector2i(4, 4))
		board.perform_reveal_action(Vector2i(4, 4))
		for mine_position in _find_all_mines(board):
			for neighbor in board.get_neighbors(mine_position):
				if not board.is_revealed(neighbor):
					continue
				if require_zero and board.adjacent_mines(neighbor) != 1:
					continue
				var closed_safe := Vector2i(-1, -1)
				for seed_neighbor in board.get_neighbors(neighbor):
					if not board.has_mine(seed_neighbor) and not board.is_revealed(seed_neighbor):
						closed_safe = seed_neighbor
						break
				if require_zero and closed_safe.x < 0:
					continue
				return {
					"board": board,
					"mine": mine_position,
					"revealed_neighbor": neighbor,
					"closed_safe": closed_safe,
					"unrelated": _find_unrelated_safe(board, mine_position),
				}
	return {}


func _find_unrelated_safe(board: BoardModel, mine_position: Vector2i) -> Vector2i:
	for y in board.height:
		for x in board.width:
			var candidate := Vector2i(x, y)
			if not board.has_mine(candidate) and candidate.distance_squared_to(mine_position) > 2:
				return candidate
	return Vector2i(-1, -1)


func _find_all_mines(board: BoardModel) -> Array[Vector2i]:
	var mines: Array[Vector2i] = []
	for y in board.height:
		for x in board.width:
			var cell_position := Vector2i(x, y)
			if board.has_mine(cell_position):
				mines.append(cell_position)
	return mines


func _find_closed_unflagged(board: BoardModel) -> Vector2i:
	for y in board.height:
		for x in board.width:
			var cell_position := Vector2i(x, y)
			if not board.is_revealed(cell_position) and not board.is_flagged(cell_position):
				return cell_position
	return Vector2i(-1, -1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
