extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_no_pattern_and_loss()
	_test_chain()
	_test_matches()
	_test_sequences()
	_test_high_risk()
	_test_cascade_and_opening_reduction()
	_test_multiple_patterns_and_order()
	_test_surrounds()
	_test_pattern_scoring_integration()
	if _failures == 0:
		print("PASS: Mineshift pattern detection tests completed successfully.")
	quit(_failures)


func _test_no_pattern_and_loss() -> void:
	var controller := PatternController.new()
	var context := _context([[Vector2i(0, 0), 1], [Vector2i(2, 0), 2]], 1)
	_expect(controller.detect(context).is_empty(), "An action below every threshold must not create a pattern.")
	context = _context([[Vector2i(0, 0), 8]], 2)
	context.clicked_value = 8
	context.caused_loss = true
	_expect(controller.detect(context).is_empty() and controller.pattern_score == 0, "A mine action must never award patterns.")


func _test_chain() -> void:
	var controller := PatternController.new()
	var cells: Array = []
	for x in 7:
		cells.append([Vector2i(x, 0), 1])
	for x in 4:
		cells.append([Vector2i(x, 3), 2])
	var results := controller.detect(_context(cells, 1))
	var chain := _find_result(results, "chain")
	_expect(chain != null and chain.metric == 7 and chain.total_points == 100, "Only the largest orthogonal numbered chain must score.")
	cells = [[Vector2i(0, 0), 1], [Vector2i(1, 1), 1], [Vector2i(2, 2), 1], [Vector2i(3, 3), 1]]
	_expect(_find_result(PatternController.new().detect(_context(cells, 1)), "chain") == null, "Diagonal cells must not connect a CHAIN.")


func _test_matches() -> void:
	var cells: Array = []
	for x in 3:
		cells.append([Vector2i(x * 2, 0), 1])
	for x in 4:
		cells.append([Vector2i(x * 2, 2), 2])
	var results := PatternController.new().detect(_context(cells, 1))
	var matches := _find_all(results, "match")
	_expect(matches.size() == 2, "Different repeated values must produce multiple MATCH results.")
	_expect(matches[0].total_points + matches[1].total_points == 170, "MATCH groups must use their complete group tiers.")
	cells.clear()
	for x in 6:
		cells.append([Vector2i(x * 2, 0), 3])
	matches = _find_all(PatternController.new().detect(_context(cells, 2)), "match")
	_expect(matches.size() == 1 and matches[0].metric == 6 and matches[0].total_points == 280, "Six equal values must remain one MATCH.")


func _test_sequences() -> void:
	var cells: Array = [[Vector2i(0, 0), 1], [Vector2i(2, 0), 2], [Vector2i(4, 0), 2], [Vector2i(6, 0), 3]]
	var sequence := _find_result(PatternController.new().detect(_context(cells, 1)), "sequence")
	_expect(sequence != null and sequence.metric == 3 and sequence.detail == "SEQUENCE 1–3", "Repeated values must not extend a SEQUENCE.")
	cells = []
	for value in range(2, 8):
		cells.append([Vector2i(value * 2, 0), value])
	sequence = _find_result(PatternController.new().detect(_context(cells, 2)), "sequence")
	_expect(sequence.metric == 6 and sequence.total_points == 400, "A sequence of six or more values must use the longest tier.")
	cells = [[Vector2i(0, 0), 1], [Vector2i(2, 0), 2], [Vector2i(4, 0), 3], [Vector2i(6, 0), 5], [Vector2i(8, 0), 6], [Vector2i(10, 0), 7]]
	sequence = _find_result(PatternController.new().detect(_context(cells, 3)), "sequence")
	_expect(sequence.detail == "SEQUENCE 1–3", "Tied sequences must choose the lowest starting value.")


func _test_high_risk() -> void:
	for value in range(4, 9):
		var context := _context([[Vector2i.ZERO, value]], value)
		context.clicked_value = value
		context.manually_revealed = [Vector2i.ZERO]
		var result := _find_result(PatternController.new().detect(context), "high_risk")
		_expect(result != null and result.metric == value, "Manual values 4-8 must trigger HIGH RISK.")
	var chord := _context([[Vector2i.ZERO, 8]], 20)
	chord.action_type = PatternActionContext.ActionType.CHORD
	chord.clicked_value = 8
	_expect(_find_result(PatternController.new().detect(chord), "high_risk") == null, "Chord and automatic reveals must not trigger HIGH RISK.")


func _test_cascade_and_opening_reduction() -> void:
	var expected: Array[Array] = [[4, 15], [8, 40], [15, 90], [25, 175]]
	for test_case in expected:
		var context := _automatic_context(test_case[0], test_case[0])
		var cascade := _find_result(PatternController.new().detect(context), "cascade")
		_expect(cascade != null and cascade.total_points == test_case[1], "CASCADE tier scoring is incorrect.")
	var opening := _automatic_context(25, 50)
	opening.is_opening_action = true
	var opening_cascade := _find_result(PatternController.new().detect(opening), "cascade")
	_expect(opening_cascade.total_points == 88 and opening_cascade.detail.contains("×0.5"), "The opening CASCADE must receive the centralized 50% reduction.")


func _test_multiple_patterns_and_order() -> void:
	var cells: Array = [
		[Vector2i(0, 0), 1], [Vector2i(1, 0), 2], [Vector2i(2, 0), 2], [Vector2i(3, 0), 2],
		[Vector2i(0, 1), 2], [Vector2i(1, 1), 3], [Vector2i(2, 1), 4], [Vector2i(3, 1), 1],
	]
	var context := _context(cells, 70)
	for cell in cells:
		context.automatically_revealed.append(cell[0])
	var results := PatternController.new().detect(context)
	_expect(_find_result(results, "chain") != null and _find_result(results, "match") != null, "One action must allow CHAIN and MATCH together.")
	_expect(_find_result(results, "sequence") != null and _find_result(results, "cascade") != null, "One action must allow SEQUENCE and CASCADE together.")
	for index in results.size() - 1:
		_expect(results[index].total_points >= results[index + 1].total_points, "Pattern feedback must be ordered by descending points.")


func _test_surrounds() -> void:
	var snapshot := _surround_snapshot(true)
	var context := PatternActionContext.new()
	context.action_id = 80
	context.action_type = PatternActionContext.ActionType.FLAG_PLACED
	context.after_state = snapshot
	var controller := PatternController.new()
	var surrounds := _find_all(controller.detect(context), "surround")
	_expect(surrounds.size() == 2 and surrounds[0].total_points == 50, "One flag action may complete multiple SURROUND patterns.")
	context.action_id = 81
	_expect(_find_all(controller.detect(context), "surround").is_empty(), "A numbered cell may award SURROUND only once per field.")
	context = PatternActionContext.new()
	context.action_id = 82
	context.after_state = _surround_snapshot(false)
	_expect(_find_all(PatternController.new().detect(context), "surround").is_empty(), "Incorrect flags must never trigger or reveal SURROUND information.")


func _test_pattern_scoring_integration() -> void:
	var scoring := ScoreController.new()
	var event := scoring.record_manual_reveal(Vector2i.ZERO, 1, [0, 1, 2, 3], false)
	var normal_score := scoring.current_score
	var controller := PatternController.new()
	var results := controller.detect(_automatic_context(4, 90))
	var pattern_points := controller.total_points(results)
	scoring.apply_pattern_points(pattern_points, event)
	_expect(scoring.current_score == normal_score + 15 and event.pattern_score == 15, "Pattern points must be added separately to provisional field score.")
	scoring.apply_pattern_points(0, event)
	_expect(scoring.current_score == normal_score + 15, "A processed action must not duplicate pattern points.")


func _context(cells: Array, action_id: int) -> PatternActionContext:
	var context := PatternActionContext.new()
	context.action_id = action_id
	for cell in cells:
		context.revealed_cells.append({"position": cell[0], "value": cell[1], "manual": false})
	context.finalize_counts()
	return context


func _automatic_context(size: int, action_id: int) -> PatternActionContext:
	var cells: Array = []
	for index in size:
		cells.append([Vector2i(index * 2, 0), 0])
	var context := _context(cells, action_id)
	for cell in cells:
		context.automatically_revealed.append(cell[0])
	return context


func _surround_snapshot(correct: bool) -> Dictionary:
	var width := 5
	var height := 3
	var count := width * height
	var mines := PackedByteArray()
	var revealed := PackedByteArray()
	var flagged := PackedByteArray()
	var adjacent := PackedByteArray()
	for array in [mines, revealed, flagged, adjacent]:
		array.resize(count)
	for index in count:
		revealed[index] = 1
	for position: Vector2i in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0)]:
		var index: int = position.y * width + position.x
		mines[index] = 1
		revealed[index] = 0
		flagged[index] = 1
	adjacent[1 * width + 1] = 2
	adjacent[1 * width + 3] = 2
	if not correct:
		flagged[0] = 0
		flagged[4] = 0
		flagged[1] = 1
		flagged[3] = 1
		revealed[1] = 0
		revealed[3] = 0
	return {"width": width, "height": height, "mines": mines, "revealed": revealed, "flagged": flagged, "adjacent": adjacent}


func _find_result(results: Array[PatternResult], id: StringName) -> PatternResult:
	for result in results:
		if result.definition.id == id:
			return result
	return null


func _find_all(results: Array[PatternResult], id: StringName) -> Array[PatternResult]:
	var found: Array[PatternResult] = []
	for result in results:
		if result.definition.id == id:
			found.append(result)
	return found


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
