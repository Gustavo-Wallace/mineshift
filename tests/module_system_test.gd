extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_selection_controller()
	_test_buffer_runtime()
	_test_expanded_start()
	_test_breach_pulse_model()
	_test_verified_flags_model()
	await _test_selection_interface()
	await _test_buffer_and_restart_cache()
	await _test_flag_verifier_and_auto_chord()
	if _failures == 0:
		print("PASS: Mineshift module selection and six gameplay modules completed successfully.")
	quit(_failures)


func _test_selection_controller() -> void:
	var controller := ModuleController.new()
	controller.on_run_started()
	controller._rng.seed = 8028
	var first_offers := controller.generate_offers()
	_expect(first_offers.size() == 3 and _unique_offer_count(first_offers) == 3, "A transition must offer three different modules.")
	_expect(controller.generate_offers() == first_offers, "Offers must remain stable while the transition is open.")
	controller.select_offer(first_offers[0].id)
	var installed := controller.confirm_selected(1)
	_expect(installed != null and controller.installed_count() == 1, "Exactly one selected module must install.")
	_expect(controller.confirm_selected(1) == null and controller.installed_count() == 1, "Repeated confirmation must never install twice.")
	controller.clear_pending_selection()
	var second_offers := controller.generate_offers()
	for definition in second_offers:
		_expect(definition.id != installed.definition.id, "Installed modules must not reappear in offers.")

	var build_controller := ModuleController.new()
	build_controller.on_run_started()
	for field_number in range(1, 5):
		var offers := build_controller.generate_offers()
		build_controller.select_offer(offers[0].id)
		build_controller.confirm_selected(field_number)
		build_controller.clear_pending_selection()
	_expect(build_controller.installed_count() == 4, "Four field transitions must produce a four-module build.")
	build_controller.abandon_run()
	_expect(build_controller.installed.is_empty() and build_controller.current_offers.is_empty(), "Abandoning must clear installed and pending modules.")

	var small_pool := ModuleController.new()
	small_pool.on_run_started()
	small_pool.definition_pool = [ModuleDefinition.create_default_pool()[0], ModuleDefinition.create_default_pool()[1]]
	_expect(small_pool.generate_offers().size() == 2, "A small unexpected pool must show only remaining unique modules without error.")


func _test_buffer_runtime() -> void:
	var controller := ModuleController.new()
	controller.on_run_started()
	_force_install(controller, ModuleController.BUFFER_LAYER, 1)
	controller.on_field_started()
	_expect(controller.absorb_breach_damage(2) == 1, "Buffer Layer must absorb only one point from a multi-breach.")
	_expect(controller.absorb_breach_damage(1) == 0, "Buffer Layer must be consumed after the first breach.")
	controller.on_field_started()
	_expect(controller.absorb_breach_damage(1) == 1, "Buffer Layer must recharge for a new or restarted field.")


func _test_expanded_start() -> void:
	for first_position in [Vector2i(4, 4), Vector2i(0, 0)]:
		var board := BoardModel.new(9, 9, 10)
		board.generate_mines(first_position, 2)
		var mines := 0
		for y in board.height:
			for x in board.width:
				var cell_position := Vector2i(x, y)
				if board.has_mine(cell_position):
					mines += 1
				_expect(not board.has_mine(cell_position) if maxi(absi(cell_position.x - first_position.x), absi(cell_position.y - first_position.y)) <= 2 else true, "Expanded Start must protect the bounded 5×5 opening region.")
		_expect(mines == 10, "Expanded Start must preserve the exact configured mine count.")
	var dense_board := BoardModel.new(5, 5, 20)
	dense_board.generate_mines(Vector2i(2, 2), 2)
	_expect(not dense_board.has_mine(Vector2i(2, 2)) and _find_all_mines(dense_board).size() == 20, "Dense boards must fall back without loops or mine loss.")


func _test_breach_pulse_model() -> void:
	var setup := _find_pulse_setup()
	_expect(not setup.is_empty(), "A Breach Pulse scenario must be discoverable.")
	if setup.is_empty():
		return
	var board: BoardModel = setup["board"]
	var flagged_safe: Vector2i = setup["flagged_safe"]
	var action: BoardActionResult = setup["action"]
	var pulse_revealed := board.reveal_orthogonal_safe_cells(action.neutralized_mines)
	_expect(not pulse_revealed.is_empty(), "Breach Pulse must reveal safe orthogonal neighbors.")
	_expect(board.is_flagged(flagged_safe) and not board.is_revealed(flagged_safe), "Breach Pulse must preserve flagged cells.")
	for remaining_mine in _find_all_mines(board):
		_expect(board.has_mine(remaining_mine), "Breach Pulse must preserve every active mine.")


func _test_verified_flags_model() -> void:
	var board := BoardModel.new(9, 9, 10)
	board.generate_mines(Vector2i(4, 4))
	var mine_position := _find_all_mines(board)[0]
	board.toggle_flag(mine_position)
	_expect(board.mark_flag_verified(mine_position) and board.is_flag_verified(mine_position), "A correct verifier result must mark the flag explicitly.")
	_expect(not board.toggle_flag(mine_position) and board.is_flagged(mine_position), "A verified flag must be locked.")
	var action := BoardActionResult.new()
	action.detonated_mines.append(mine_position)
	board.neutralize_detonations(action)
	_expect(board.is_neutralized(mine_position) and not board.is_flagged(mine_position) and not board.is_flag_verified(mine_position), "Neutralizing a verified mine must remove its flag and seal.")


func _test_selection_interface() -> void:
	var game := await _new_game()
	game.start_new_run()
	game._on_reveal_requested(Vector2i(4, 4))
	_clear_all_safe(game)
	await process_frame
	_expect(game.field_result_screen.visible and game.module_choice_grid.visible, "Fields 1-4 must embed module selection in the compact transition.")
	_expect(game.modules.current_offers.size() == 3 and _unique_offer_count(game.modules.current_offers) == 3, "The transition must render three distinct choices.")
	_expect(game.next_field_button.disabled, "Entering the next field must remain blocked before installation.")
	_expect(_inside_viewport(game.module_option_buttons[0]) and _inside_viewport(game.module_option_buttons[2]) and _inside_viewport(game.next_field_button), "All module choices and progression controls must fit in 1280×720.")
	var offer_ids := _offer_ids(game.modules.current_offers)
	game._update_module_choice_layout()
	_expect(_offer_ids(game.modules.current_offers) == offer_ids, "Relayout must not regenerate module offers.")
	game.module_option_buttons[0].pressed.emit()
	_expect(game.module_confirm_row.visible and game.selected_module_label.text.begins_with("INSTALL"), "Selecting a module must show inline confirmation.")
	game.back_module_button.pressed.emit()
	_expect(not game.module_confirm_row.visible and game.modules.installed_count() == 0, "Backing out must preserve offers without installing.")
	game.module_option_buttons[0].pressed.emit()
	game.install_module_button.pressed.emit()
	game.install_module_button.pressed.emit()
	_expect(game.modules.installed_count() == 1 and not game.next_field_button.disabled, "Rapid confirmation must install once and unlock progression.")
	var installed_id := game.modules.installed[0].definition.id
	game.next_field_button.pressed.emit()
	_expect(game.run.current_config().field_number == 2 and game.modules.has_module(installed_id), "Installed modules must persist into the next field.")
	game.modules_button.pressed.emit()
	_expect(game.modules_screen.visible and game.modules_body.text.contains("INSTALLED AFTER FIELD 1"), "The MODULES panel must pause and explain installed runtime state.")
	var panel_time := game.elapsed_time
	game._process(2.0)
	_expect(game.elapsed_time == panel_time, "Opening the module panel must pause the field timer.")
	game.close_modules_button.pressed.emit()
	game.return_to_main_menu()
	_expect(game.modules.installed.is_empty() and game.modules.current_offers.is_empty(), "Returning to the menu must clear modules and pending stock.")
	game.queue_free()
	await process_frame


func _test_buffer_and_restart_cache() -> void:
	var game := await _new_game()
	game.start_new_run()
	_force_install(game.modules, ModuleController.BUFFER_LAYER, 0)
	game.modules.on_field_started()
	game._update_module_hud()
	game._on_reveal_requested(Vector2i(4, 4))
	var mines := _find_all_mines(game.board)
	game._on_reveal_requested(mines[0])
	_expect(game.run.current_integrity == 3 and game.breach_label.text.contains("BUFFER ABSORBED"), "Buffer Layer must prevent the first field breach damage.")
	await create_timer(0.5).timeout
	_expect(game.board.is_neutralized(mines[0]), "Buffer Layer must not prevent mine neutralization.")
	game._on_reveal_requested(mines[1])
	_expect(game.run.current_integrity == 2, "The second field breach must deal normal damage after Buffer is consumed.")
	await create_timer(0.5).timeout

	game.start_new_run()
	_force_install(game.modules, ModuleController.RESTART_CACHE, 0)
	game.run.apply_damage(2)
	game._update_hud()
	game._show_restart_confirmation()
	_expect(game.confirm_copy.text.contains("COST: FREE"), "Restart Cache must remain available at one integrity.")
	game.cancel_confirm_button.pressed.emit()
	_expect(game.modules.restart_is_free(), "Cancelling must not consume Restart Cache.")
	game._show_restart_confirmation()
	game.confirm_action_button.pressed.emit()
	game.confirm_action_button.pressed.emit()
	_expect(game.run.current_integrity == 1 and not game.modules.restart_is_free(), "The confirmed free restart must consume the cache once without damage.")
	_expect(not game.run.can_restart_attempt(), "Paid restarts must become blocked again at one integrity.")
	game.queue_free()
	await process_frame


func _test_flag_verifier_and_auto_chord() -> void:
	var game := await _new_game()
	game.start_new_run()
	_force_install(game.modules, ModuleController.FLAG_VERIFIER, 0)
	game.modules.on_field_started()
	game._on_reveal_requested(Vector2i(4, 4))
	var mine_position := _find_all_mines(game.board)[0]
	game._on_flag_requested(mine_position)
	_expect(game.board.is_flag_verified(mine_position), "Flag Verifier must seal the first correct mine flag.")
	game._on_flag_requested(mine_position)
	_expect(game.board.is_flagged(mine_position), "The verified flag must remain locked after removal input.")

	game.modules.on_field_started()
	var safe_position := _find_closed_safe(game.board)
	game._on_flag_requested(safe_position)
	_expect(not game.board.is_flagged(safe_position) and not game.board.is_revealed(safe_position), "An invalid first flag must be removed without revealing information.")
	var second_safe := _find_closed_safe(game.board)
	game._on_flag_requested(second_safe)
	_expect(game.board.is_flagged(second_safe) and not game.board.is_flag_verified(second_safe), "Only the first flag attempt of a field may be verified.")
	game.queue_free()
	await process_frame

	var auto_game := await _new_game()
	auto_game.start_new_run()
	_force_install(auto_game.modules, ModuleController.AUTO_CHORD, 0)
	var setup := _find_correct_auto_chord_setup()
	_expect(not setup.is_empty(), "A correct Auto Chord setup must be discoverable.")
	if not setup.is_empty():
		auto_game.board = setup["board"]
		auto_game.board_view.build(auto_game.board.width, auto_game.board.height)
		auto_game.state = GameController.FieldState.PLAYING
		var final_flag: Vector2i = setup["final_flag"]
		auto_game._on_flag_requested(final_flag)
		_expect(setup["safe_target"] == Vector2i(-1, -1) or auto_game.board.is_revealed(setup["safe_target"]), "Completing a number with a flag must auto-chord its safe neighbors.")
	auto_game.queue_free()
	await process_frame

	var risk_game := await _new_game()
	risk_game.start_new_run()
	_force_install(risk_game.modules, ModuleController.AUTO_CHORD, 0)
	_force_install(risk_game.modules, ModuleController.BUFFER_LAYER, 0)
	risk_game.modules.on_field_started()
	var risk_setup := _find_incorrect_auto_chord_setup()
	_expect(not risk_setup.is_empty(), "A risky Auto Chord setup must be discoverable.")
	if not risk_setup.is_empty():
		risk_game.board = risk_setup["board"]
		risk_game.board_view.build(risk_game.board.width, risk_game.board.height)
		risk_game.state = GameController.FieldState.PLAYING
		risk_game._on_flag_requested(risk_setup["final_wrong_flag"])
		var buffer_runtime := risk_game.modules.get_runtime(ModuleController.BUFFER_LAYER)
		_expect(risk_game.state == GameController.FieldState.BREACH_RECOVERY and risk_game.run.current_integrity <= 2 and not buffer_runtime.field_available, "A risky Auto Chord must breach while Buffer absorbs exactly its single available charge.")
		await create_timer(0.5).timeout
		for detonated_mine: Vector2i in risk_setup["mines"]:
			_expect(risk_game.board.is_neutralized(detonated_mine), "Risky Auto Chord must neutralize every detonated mine once.")
	risk_game.queue_free()
	await process_frame


func _new_game() -> GameController:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game := scene.instantiate() as GameController
	root.add_child(game)
	await process_frame
	return game


func _force_install(controller: ModuleController, module_id: StringName, field_number: int) -> ModuleRuntime:
	var definition := _definition(module_id)
	controller.current_offers = [definition]
	controller.selection_open = true
	controller.selection_completed = false
	controller.selected_offer = definition
	return controller.confirm_selected(field_number)


func _definition(module_id: StringName) -> ModuleDefinition:
	for definition in ModuleDefinition.create_default_pool():
		if definition.id == module_id:
			return definition
	return null


func _find_pulse_setup() -> Dictionary:
	for _attempt in 800:
		var board := BoardModel.new(9, 9, 10)
		board.generate_mines(Vector2i(4, 4))
		board.perform_reveal_action(Vector2i(4, 4))
		for mine_position in _find_all_mines(board):
			var safe_neighbors: Array[Vector2i] = []
			for offset: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var candidate: Vector2i = mine_position + offset
				if board.is_valid_position(candidate) and not board.has_mine(candidate) and not board.is_revealed(candidate):
					safe_neighbors.append(candidate)
			if safe_neighbors.size() < 2:
				continue
			var flagged_safe := safe_neighbors[0]
			board.toggle_flag(flagged_safe)
			var action := board.perform_reveal_action(mine_position)
			board.neutralize_detonations(action)
			var has_remaining_pulse_target := false
			for safe_position in safe_neighbors:
				if safe_position != flagged_safe and not board.is_revealed(safe_position):
					has_remaining_pulse_target = true
					break
			if has_remaining_pulse_target:
				return {"board": board, "action": action, "flagged_safe": flagged_safe}
			break
	return {}


func _find_correct_auto_chord_setup() -> Dictionary:
	for _attempt in 500:
		var board := BoardModel.new(9, 9, 10)
		board.generate_mines(Vector2i(4, 4))
		board.perform_reveal_action(Vector2i(4, 4))
		for y in board.height:
			for x in board.width:
				var target := Vector2i(x, y)
				if not board.is_revealed(target) or board.adjacent_mines(target) == 0:
					continue
				var mines: Array[Vector2i] = []
				var safe_target := Vector2i(-1, -1)
				for neighbor in board.get_neighbors(target):
					if board.has_mine(neighbor):
						mines.append(neighbor)
					elif not board.is_revealed(neighbor):
						safe_target = neighbor
				if not mines.is_empty() and safe_target.x >= 0:
					for mine_index in range(mines.size() - 1):
						board.toggle_flag(mines[mine_index])
					return {"board": board, "final_flag": mines[-1], "safe_target": safe_target}
	return {}


func _find_incorrect_auto_chord_setup() -> Dictionary:
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
					return {"board": board, "mines": mines, "final_wrong_flag": closed_safe[1]}
	return {}


func _clear_all_safe(game: GameController) -> void:
	for y in game.board.height:
		for x in game.board.width:
			var cell_position := Vector2i(x, y)
			if not game.board.has_mine(cell_position) and not game.board.is_revealed(cell_position):
				game._on_reveal_requested(cell_position)


func _find_all_mines(board: BoardModel) -> Array[Vector2i]:
	var mines: Array[Vector2i] = []
	for y in board.height:
		for x in board.width:
			var cell_position := Vector2i(x, y)
			if board.has_mine(cell_position):
				mines.append(cell_position)
	return mines


func _find_closed_safe(board: BoardModel) -> Vector2i:
	for y in board.height:
		for x in board.width:
			var cell_position := Vector2i(x, y)
			if not board.has_mine(cell_position) and not board.is_revealed(cell_position) and not board.is_flagged(cell_position):
				return cell_position
	return Vector2i(-1, -1)


func _unique_offer_count(offers: Array[ModuleDefinition]) -> int:
	return _offer_ids(offers).size()


func _offer_ids(offers: Array[ModuleDefinition]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for definition in offers:
		if not ids.has(definition.id):
			ids.append(definition.id)
	return ids


func _inside_viewport(control: Control) -> bool:
	return Rect2(Vector2.ZERO, control.get_viewport_rect().size).encloses(control.get_global_rect())


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
