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
	_test_empty_region_and_loss()
	_test_chords()
	await _test_scene_field_lifecycle()
	if _failures == 0:
		print("PASS: Mineshift board and field lifecycle tests completed successfully.")
	quit(_failures)


func _test_generation_and_opening_safety() -> void:
	for run_index in 150:
		var board := BoardModel.new(BOARD_WIDTH, BOARD_HEIGHT, MINE_COUNT)
		var first := Vector2i(run_index % BOARD_WIDTH, floori(run_index / float(BOARD_WIDTH)) % BOARD_HEIGHT)
		board.place_mines(first)
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
	_expect(not board.toggle_flag(Vector2i(3, 0)), "Flags must be capped by the configured mine count.")
	_expect(board.flags_placed == 3, "The model must track placed flags.")
	_expect(board.toggle_flag(Vector2i(1, 0)) and board.flags_placed == 2, "Removing a flag must free one mark.")
	board.place_mines(Vector2i(2, 2))
	var revealed := board.reveal(Vector2i(2, 2))
	var changed: Array[Vector2i] = revealed["changed"]
	if not changed.is_empty():
		_expect(not board.toggle_flag(changed[0]), "Revealed cells cannot be flagged.")


func _test_empty_region_and_loss() -> void:
	var board := BoardModel.new(9, 9, 10)
	board.place_mines(Vector2i(4, 4))
	var opening := board.reveal(Vector2i(4, 4))
	_expect(not bool(opening["hit_mine"]) and not (opening["changed"] as Array).is_empty(), "A safe reveal must open at least one cell.")
	var mine := _find_mine(board)
	var loss := board.reveal(mine)
	_expect(bool(loss["hit_mine"]) and board.is_revealed(mine), "Revealing a mine must report and retain the triggered mine.")


func _test_chords() -> void:
	var setup := _find_chord_setup()
	_expect(not setup.is_empty(), "A valid chord scenario must be discoverable.")
	if setup.is_empty():
		return
	var board: BoardModel = setup["board"]
	for mine_position: Vector2i in setup["mines"]:
		board.toggle_flag(mine_position)
	var result: Dictionary = board.chord(setup["target"])
	_expect(result["performed"] and not result["hit_mine"], "Correct flags must permit a safe chord.")
	_expect(not (result["changed"] as Array).is_empty(), "A successful chord must reveal closed neighbors.")


func _test_scene_field_lifecycle() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game := scene.instantiate() as GameController
	root.add_child(game)
	await process_frame
	_expect(game.start_screen.visible and not game.game_screen.visible, "The simplified main menu must be the initial screen.")
	_expect(not _visible_text(game).contains("PATTERN") and not _visible_text(game).contains("SCORE"), "Removed systems must not appear on the initial screen.")
	game.start_new_run()
	_expect(game.run.current_config().field_number == 1 and game.board_view.get_child_count() == 81, "A run must begin with the 9×9 first field.")
	var first_cell := game.board_view.get_child(0) as MineCell
	_expect(is_equal_approx(first_cell.custom_minimum_size.x, 54.0) and first_cell.custom_minimum_size.x == first_cell.custom_minimum_size.y, "The 9×9 field must use enlarged square cells.")
	game._on_reveal_requested(Vector2i(4, 4))
	_expect(not game.board.has_mine(Vector2i(4, 4)) and game.state == GameController.FieldState.PLAYING, "The scene opening move must be safe and activate the field.")
	game._process(1.2)
	_expect(game.elapsed_time >= 1.0, "The field timer must advance only during active play.")

	var final_safe := _find_closed_safe(game.board)
	_expect(final_safe.x >= 0, "A protected final safe cell must be available for the completion test.")
	game._on_flag_requested(final_safe)
	for y in game.board.height:
		for x in game.board.width:
			var cell_position := Vector2i(x, y)
			if not game.board.has_mine(cell_position) and not game.board.is_revealed(cell_position) and cell_position != final_safe:
				game._on_reveal_requested(cell_position)
	_expect(game.state == GameController.FieldState.PLAYING and not game.field_result_screen.visible, "A field cannot finish while any safe cell remains closed.")
	game._on_flag_requested(final_safe)
	game._on_reveal_requested(final_safe)
	await process_frame
	_expect(game.state == GameController.FieldState.CLEARED and game.field_result_screen.visible, "Revealing every safe cell must show the compact field transition.")
	_expect(game.field_result_body.text.contains("NEXT") and not game.field_result_body.text.contains("SCORE"), "The field transition must contain only compact progression information.")
	_expect(_inside_viewport(game.next_field_button), "The required next-field button must remain inside 1280×720.")
	game.next_field_button.pressed.emit()
	_expect(game.run.current_config().field_number == 2 and game.board.mine_count == 12, "The transition button must enter Field 2.")

	game._on_reveal_requested(Vector2i(4, 4))
	var field_before_restart := game.run.current_config().field_number
	game.restart_current_field()
	_expect(game.run.current_config().field_number == field_before_restart and game.state == GameController.FieldState.READY, "Restarting must preserve the field index and reset its state.")
	_expect(game.elapsed_time == 0.0 and game.board_view.get_child_count() == 81, "Restarting must reset time without duplicating cells.")
	game.queue_free()
	await process_frame


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


func _find_chord_setup() -> Dictionary:
	for _attempt in 250:
		var board := BoardModel.new(9, 9, 10)
		board.place_mines(Vector2i(4, 4))
		board.reveal(Vector2i(4, 4))
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


func _visible_text(node: Node) -> String:
	var lines: Array[String] = []
	_collect_visible_text(node, lines)
	return "\n".join(lines)


func _collect_visible_text(node: Node, lines: Array[String]) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label:
		lines.append((node as Label).text)
	elif node is Button:
		lines.append((node as Button).text)
	for child in node.get_children():
		_collect_visible_text(child, lines)


func _inside_viewport(control: Control) -> bool:
	var rect := control.get_global_rect()
	var viewport_rect := Rect2(Vector2.ZERO, control.get_viewport_rect().size)
	return viewport_rect.encloses(rect)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
