extends SceneTree

const EXPECTED_MANUAL_SCORES: Array[int] = [5, 10, 20, 35, 55, 80, 110, 145, 185]

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_risk_scores()
	_test_cascade_scoring()
	_test_safe_streak()
	_test_completion_bonuses()
	_test_score_event_summary()
	_test_chord_scoring()
	_test_board_chords()
	if _failures == 0:
		print("PASS: Mineshift scoring and chord tests completed successfully.")
	quit(_failures)


func _test_risk_scores() -> void:
	for adjacent_mines in 9:
		var scoring := ScoreController.new()
		var event := scoring.record_manual_reveal(Vector2i.ZERO, adjacent_mines, [], false)
		_expect(event.manual_base_score == EXPECTED_MANUAL_SCORES[adjacent_mines], "Manual risk score is incorrect for number %d." % adjacent_mines)
		_expect(event.total_score == EXPECTED_MANUAL_SCORES[adjacent_mines], "A standalone reveal must award only its risk score.")


func _test_cascade_scoring() -> void:
	var cases: Array[Dictionary] = [
		{"counts": [0, 1, 3], "cell_score": 17, "bonus": 0, "message": ""},
		{"counts": [0, 0, 0, 0], "cell_score": 12, "bonus": 15, "message": ""},
		{"counts": _filled_counts(8), "cell_score": 24, "bonus": 40, "message": "CASCADE"},
		{"counts": _filled_counts(15), "cell_score": 45, "bonus": 90, "message": "LARGE CASCADE"},
		{"counts": _filled_counts(25), "cell_score": 75, "bonus": 175, "message": "MASSIVE CASCADE"},
	]
	for test_case in cases:
		var scoring := ScoreController.new()
		var counts: Array[int] = []
		counts.assign(test_case["counts"])
		var event := scoring.record_manual_reveal(Vector2i.ZERO, 0, counts, false)
		_expect(event.cascade_cell_score == test_case["cell_score"], "Cascade cell score is incorrect.")
		_expect(event.cascade_size_bonus == test_case["bonus"], "Cascade size bonus is incorrect.")
		_expect(event.cascade_message == test_case["message"], "Cascade feedback tier is incorrect.")
		_expect(event.total_score == 5 + test_case["cell_score"] + test_case["bonus"], "Cascade action total is incorrect.")


func _test_safe_streak() -> void:
	var scoring := ScoreController.new()
	var expected_multipliers: Array[float] = [1.0, 1.0, 1.15, 1.15, 1.30, 1.30, 1.50, 1.50, 1.50, 1.75]
	for index in expected_multipliers.size():
		var event := scoring.record_manual_reveal(Vector2i(index, 0), 3, [], false)
		_expect(is_equal_approx(event.streak_multiplier, expected_multipliers[index]), "Safe streak multiplier is incorrect at streak %d." % (index + 1))
	_expect(scoring.safe_reveal_streak == 10, "Safe streak must increase once per manual safe reveal.")
	_expect(scoring.highest_safe_reveal_streak == 10, "Highest streak must retain the maximum reached.")
	var actions_before_flag := scoring.actions_taken
	scoring.record_flag_action()
	_expect(scoring.safe_reveal_streak == 10, "Flag actions must not interrupt a safe streak.")
	_expect(scoring.actions_taken == actions_before_flag + 1, "Flag changes must count as actions.")
	var mine_event := scoring.record_manual_reveal(Vector2i.ZERO, 0, [], true)
	_expect(scoring.safe_reveal_streak == 0, "Revealing a mine must reset the current streak.")
	_expect(scoring.highest_safe_reveal_streak == 10, "A loss must preserve the highest streak.")
	_expect(mine_event.hit_mine and scoring.event_history.back() == mine_event, "A mine reveal must still produce an internal action summary.")


func _test_completion_bonuses() -> void:
	var scoring := ScoreController.new()
	scoring.actions_taken = 25
	scoring.apply_victory_bonuses(3, 0)
	_expect(scoring.flag_bonus_points == 45, "Correct flags must award 15 points each on victory.")
	_expect(scoring.clear_bonus_points == 500, "Clearing the field must award 500 points.")
	_expect(scoring.accuracy_bonus_points == 250, "Perfect flag accuracy must award 250 points.")
	_expect(scoring.efficiency_bonus_points == 300, "At most 25 actions must award 300 efficiency points.")
	_expect(scoring.current_score == 1095, "Victory bonus total is incorrect.")
	scoring.apply_victory_bonuses(3, 0)
	_expect(scoring.current_score == 1095, "Completion bonuses must not be applied twice.")
	_expect(scoring.get_accuracy_bonus(1) == 100 and scoring.get_accuracy_bonus(2) == 0, "Accuracy bonus thresholds are incorrect.")
	_expect(scoring.get_efficiency_bonus(26) == 200, "The 26-35 efficiency tier is incorrect.")
	_expect(scoring.get_efficiency_bonus(36) == 100, "The 36-50 efficiency tier is incorrect.")
	_expect(scoring.get_efficiency_bonus(51) == 0, "More than 50 actions must not award efficiency points.")


func _test_score_event_summary() -> void:
	var scoring := ScoreController.new()
	scoring.record_manual_reveal(Vector2i(0, 0), 1, [], false)
	scoring.record_manual_reveal(Vector2i(1, 0), 2, [], false)
	var event := scoring.record_manual_reveal(Vector2i(2, 0), 3, [0, 2], false)
	_expect(event.position == Vector2i(2, 0), "Score event must retain the clicked position.")
	_expect(event.adjacent_mines == 3, "Score event must retain the clicked risk number.")
	_expect(event.automatic_cells == 2, "Score event must retain the automatic cell count.")
	_expect(event.manual_base_score == 35, "Score event must retain the manual base score.")
	_expect(is_equal_approx(event.streak_multiplier, 1.15), "Score event must retain the streak multiplier.")
	_expect(event.manual_final_score == 40, "Score event must retain the rounded manual score.")
	_expect(event.cascade_cell_score == 10, "Score event must retain cascade cell points.")
	_expect(event.cascade_size_bonus == 0, "Score event must retain the cascade size bonus.")
	_expect(event.total_score == 50, "Score event must retain the complete action score.")
	_expect(scoring.event_history.size() == 3, "Every scoring reveal must be retained in the event history.")


func _test_chord_scoring() -> void:
	var scoring := ScoreController.new()
	scoring.record_manual_reveal(Vector2i.ZERO, 1, [], false)
	var streak_before := scoring.safe_reveal_streak
	var event := scoring.record_chord(Vector2i.ZERO, 1, [0, 1, 2, 3], false)
	_expect(event.is_chord, "A chord score event must identify its action type.")
	_expect(event.manual_final_score == 0, "A chord must not receive a manual reveal score.")
	_expect(event.cascade_cell_score == 24 and event.cascade_size_bonus == 15, "Chord cells must use cascade scoring and bonuses.")
	_expect(scoring.safe_reveal_streak == streak_before, "A safe chord must not increase the streak.")
	scoring.record_chord(Vector2i.ZERO, 1, [], true)
	_expect(scoring.safe_reveal_streak == 0, "A chord that hits a mine must reset the streak.")


func _test_board_chords() -> void:
	var correct_setup := _find_chord_setup(false)
	_expect(not correct_setup.is_empty(), "A valid correct chord setup should be discoverable.")
	if not correct_setup.is_empty():
		var correct_board: BoardModel = correct_setup["board"]
		for position: Vector2i in correct_setup["flags"]:
			correct_board.toggle_flag(position)
		var correct_result: Dictionary = correct_board.chord(correct_setup["target"])
		_expect(correct_result["performed"] and not correct_result["hit_mine"], "A correctly flagged chord must safely reveal neighbors.")
		_expect(not (correct_result["changed"] as Array).is_empty(), "A valid chord must reveal at least one cell.")

	var incorrect_setup := _find_chord_setup(true)
	_expect(not incorrect_setup.is_empty(), "A valid incorrect chord setup should be discoverable.")
	if not incorrect_setup.is_empty():
		var incorrect_board: BoardModel = incorrect_setup["board"]
		for position: Vector2i in incorrect_setup["flags"]:
			incorrect_board.toggle_flag(position)
		var incorrect_result: Dictionary = incorrect_board.chord(incorrect_setup["target"])
		_expect(incorrect_result["performed"] and incorrect_result["hit_mine"], "An incorrect flag configuration must let a chord trigger a mine.")
		_expect(incorrect_board.has_mine(incorrect_result["exploded_position"]), "The chord loss must report an actual mine.")


func _find_chord_setup(needs_incorrect_flag: bool) -> Dictionary:
	for attempt in 300:
		var board := BoardModel.new(9, 9, 10)
		var first := Vector2i(4, 4)
		board.place_mines(first)
		board.reveal(first)
		for y in board.height:
			for x in board.width:
				var target := Vector2i(x, y)
				if not board.is_revealed(target) or board.adjacent_mines(target) == 0:
					continue
				var mines: Array[Vector2i] = []
				var closed_safe: Array[Vector2i] = []
				for neighbor in board.get_neighbors(target):
					if board.has_mine(neighbor):
						mines.append(neighbor)
					elif not board.is_revealed(neighbor):
						closed_safe.append(neighbor)
				if closed_safe.is_empty():
					continue
				if not needs_incorrect_flag:
					return {"board": board, "target": target, "flags": mines}
				if mines.is_empty():
					continue
				var wrong_flags: Array[Vector2i] = [closed_safe[0]]
				for mine_index in mines.size() - 1:
					wrong_flags.append(mines[mine_index])
				return {"board": board, "target": target, "flags": wrong_flags}
	return {}


func _filled_counts(size: int) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(size)
	counts.fill(0)
	return counts


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
