extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_rotation_and_preservation(true)
	_test_rotation_and_preservation(false)
	_test_validation_and_stable_shift()
	await _test_field_shift_interface()
	if _failures == 0:
		print("PASS: Mineshift Field Shift model, controller, and interface tests completed successfully.")
	quit(_failures)


func _test_rotation_and_preservation(clockwise: bool) -> void:
	var board := _configured_board()
	var anchor := Vector2i(2, 2)
	var positions := board.shift_region_positions(anchor)
	var outside := Vector2i(0, 4)
	var outside_mine := board.has_mine(outside)
	var flags_before := board.flags_placed
	var mines_before := board.active_mine_count()
	var revealed_before := board.revealed_safe_count
	var old_mines: Array[bool] = []
	var old_flags: Array[bool] = []
	var old_confirmed: Array[bool] = []
	for cell_position in positions:
		old_mines.append(board.has_mine(cell_position))
		old_flags.append(board.is_flagged(cell_position))
		old_confirmed.append(board.is_flag_confirmed(cell_position))
	var source_indices: Array[int] = []
	if clockwise:
		source_indices.assign([2, 0, 3, 1])
	else:
		source_indices.assign([1, 3, 0, 2])
	var result := board.rotate_hidden_region(anchor, clockwise)
	_expect(result.succeeded and result.affected_positions == positions, "A valid covered 2×2 region must produce a structured result.")
	_expect(result.direction == (FieldShiftResult.Direction.CLOCKWISE if clockwise else FieldShiftResult.Direction.COUNTER_CLOCKWISE), "The result must preserve the selected rotation direction.")
	for destination_index in positions.size():
		var source_index := source_indices[destination_index]
		var destination := positions[destination_index]
		_expect(board.has_mine(destination) == old_mines[source_index], "Mines and safe contents must follow the exact rotation mapping.")
		_expect(board.is_flagged(destination) == old_flags[source_index], "Normal and incorrect flags must rotate with their hidden contents.")
		_expect(board.is_flag_confirmed(destination) == old_confirmed[source_index], "Confirmed flags must rotate with their confirmed mines.")
	_expect(board.flags_placed == flags_before and board.active_mine_count() == mines_before, "Field Shift must preserve global flag and mine totals.")
	_expect(board.has_mine(outside) == outside_mine, "Cells outside the selected region must remain unchanged.")
	_expect(board.revealed_safe_count == revealed_before, "Field Shift must not reveal or propagate any covered cell.")
	for y in board.height:
		for x in board.width:
			var cell_position := Vector2i(x, y)
			if board.has_mine(cell_position):
				continue
			var expected_count := 0
			for neighbor in board.get_neighbors(cell_position):
				expected_count += int(board.has_mine(neighbor))
			_expect(board.adjacent_mines(cell_position) == expected_count, "Every number must be recalculated after a rotation.")


func _test_validation_and_stable_shift() -> void:
	var board := _configured_board()
	_expect(not board.is_shift_region_valid(Vector2i(board.width - 1, 1)), "The last column cannot anchor a 2×2 shift.")
	_expect(not board.is_shift_region_valid(Vector2i(1, board.height - 1)), "The last row cannot anchor a 2×2 shift.")
	_expect(not board.is_shift_region_valid(Vector2i(0, 0)), "A region containing a revealed cell must be invalid.")
	var neutralized_anchor := Vector2i(0, 3)
	board._neutralized[board._index(neutralized_anchor)] = 1
	_expect(not board.is_shift_region_valid(neutralized_anchor), "A region containing a neutralized mine cell must be invalid.")
	var flagged_anchor := Vector2i(2, 2)
	_expect(board.is_shift_region_valid(flagged_anchor), "Normal and confirmed flags must remain valid shift contents.")

	var stable_board := BoardModel.new(5, 5, 2)
	stable_board.generate_mines(Vector2i(0, 0), 0)
	stable_board._mines.fill(0)
	stable_board._mines[stable_board._index(Vector2i(4, 4))] = 1
	stable_board._mines[stable_board._index(Vector2i(4, 3))] = 1
	stable_board._calculate_adjacent_counts()
	var controller := FieldShiftController.new()
	controller.start_run()
	controller.start_field(3)
	controller.notify_board_generated()
	_expect(controller.enter_mode(stable_board), "A generated playable board must enter Field Shift mode.")
	var stable_result := controller.execute(stable_board, Vector2i(0, 0), true)
	_expect(stable_result.succeeded and stable_result.stable and stable_result.charge_consumed, "A visually stable rotation must still succeed and consume its charge.")
	controller.complete_animation()
	_expect(controller.state == FieldShiftController.ShiftState.USED and not controller.enter_mode(stable_board), "A second Field Shift in the same field must be blocked.")
	var telemetry := controller.telemetry_snapshot()
	_expect(telemetry["uses"] == 1 and telemetry["stable_shifts"] == 1 and (telemetry["fields"] as Array).has(3), "Internal telemetry must record use, field, direction, and stable results.")
	controller.start_field(4)
	_expect(controller.charge_available and controller.state == FieldShiftController.ShiftState.UNAVAILABLE, "A new field must restore the charge but wait for normal mine generation.")


func _test_field_shift_interface() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game := scene.instantiate() as GameController
	root.add_child(game)
	await process_frame
	game.start_new_run()
	_force_install_logic_probe(game)
	_expect(game.field_shift_button.text == "SHIFT 1" and game.field_shift_button.tooltip_text.contains("clockwise"), "The compact HUD button must expose its ready charge and controls.")
	game._toggle_field_shift_mode()
	_expect(game.field_shift.state == FieldShiftController.ShiftState.UNAVAILABLE and game.breach_label.text == "REVEAL A CELL FIRST", "Field Shift must reject attempts before the first normal reveal without consuming charge.")
	game._on_reveal_requested(Vector2i(0, 0))
	_expect(game.field_shift.state == FieldShiftController.ShiftState.READY and game.field_shift.charge_available, "The first reveal must unlock Field Shift.")
	var anchor := _find_valid_anchor(game.board)
	_expect(anchor.x >= 0, "A normal generated field must expose at least one valid covered 2×2 region.")
	if anchor.x < 0:
		game.queue_free()
		await process_frame
		return

	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	var shift_key := InputEventKey.new()
	shift_key.keycode = KEY_SHIFT
	shift_key.pressed = true
	game._unhandled_input(shift_key)
	_expect(game._logic_probe_mode, "Logic Probe must remain available normally before Field Shift starts.")
	game._input(space)
	_expect(game.field_shift.state == FieldShiftController.ShiftState.ACTIVE and game.field_shift_button.text == "SHIFT ACTIVE" and not game._logic_probe_mode, "Space must enter Field Shift mode, cancel Logic Probe, and update the HUD.")
	game._unhandled_input(shift_key)
	_expect(not game._logic_probe_mode, "Holding Shift during Field Shift must not reactivate Logic Probe.")
	game._on_shift_hover_changed(anchor, true)
	var highlighted := 0
	for child in game.board_view.get_children():
		if child is MineCell and child.field_shift_highlight:
			highlighted += 1
	_expect(highlighted == 4, "Hovering a valid anchor must coordinate a four-cell overlay.")
	game._on_shift_hover_changed(Vector2i(game.board.width - 1, 0), true)
	highlighted = 0
	for child in game.board_view.get_children():
		if child is MineCell and child.field_shift_highlight:
			highlighted += 1
	_expect(highlighted == 0, "An invalid anchor must not display a valid-region overlay.")

	game._input(space)
	_expect(game.field_shift.state == FieldShiftController.ShiftState.READY and game.field_shift.charge_available, "Pressing Space again must cancel without consuming the charge.")
	game._toggle_field_shift_mode()
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	game._unhandled_input(cancel)
	_expect(game.field_shift.state == FieldShiftController.ShiftState.READY and game.field_shift.charge_available, "Esc must cancel Field Shift without consuming the charge.")

	game._toggle_field_shift_mode()
	await game._on_field_shift_requested(anchor, false)
	_expect(game.field_shift.state == FieldShiftController.ShiftState.USED and game.field_shift_button.text == "SHIFT 0", "A valid rotation must animate, consume the only charge, and leave used state.")
	_expect(game.state == GameController.FieldState.PLAYING, "Normal input must resume after the shift animation completes.")
	game._toggle_field_shift_mode()
	_expect(game.breach_label.text == "FIELD SHIFT ALREADY USED", "A second activation attempt must provide clear feedback without executing.")
	game.restart_current_field()
	_expect(game.field_shift.charge_available and game.field_shift.state == FieldShiftController.ShiftState.UNAVAILABLE, "Restarting the field must restore Field Shift and clear active overlays.")
	game.return_to_main_menu()
	_expect(game.field_shift.state == FieldShiftController.ShiftState.UNAVAILABLE and not game.field_shift.charge_available, "Abandoning the run must clear Field Shift runtime state.")
	game.queue_free()
	await process_frame


func _configured_board() -> BoardModel:
	var board := BoardModel.new(5, 5, 3)
	board.generate_mines(Vector2i(0, 0), 0)
	board._mines.fill(0)
	board._flagged.fill(0)
	board._confirmed_flags.fill(0)
	board._revealed.fill(0)
	board._neutralized.fill(0)
	var anchor := Vector2i(2, 2)
	var positions := board.shift_region_positions(anchor)
	board._mines[board._index(positions[0])] = 1
	board._mines[board._index(Vector2i(0, 4))] = 1
	board._mines[board._index(Vector2i(4, 4))] = 1
	board._flagged[board._index(positions[0])] = 1
	board._confirmed_flags[board._index(positions[0])] = 1
	board._flagged[board._index(positions[1])] = 1
	board.flags_placed = 2
	for revealed_position in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(1, 3)]:
		board._revealed[board._index(revealed_position)] = 1
	board.revealed_safe_count = 5
	board._calculate_adjacent_counts()
	return board


func _find_valid_anchor(board: BoardModel) -> Vector2i:
	for y in board.height - 1:
		for x in board.width - 1:
			var anchor := Vector2i(x, y)
			if board.is_shift_region_valid(anchor):
				return anchor
	return Vector2i(-1, -1)


func _force_install_logic_probe(game: GameController) -> void:
	var probe_definition: ModuleDefinition
	for definition in ModuleDefinition.create_default_pool():
		if definition.id == ModuleController.LOGIC_PROBE:
			probe_definition = definition
			break
	game.modules.current_offers = [probe_definition]
	game.modules.selection_open = true
	game.modules.selection_completed = false
	game.modules.selected_offer = probe_definition
	game.modules.confirm_selected(0)
	game.modules.on_field_started(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
