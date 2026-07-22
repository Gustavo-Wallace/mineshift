class_name PatternController
extends RefCounted

signal patterns_detected(results: Array[PatternResult], total_points: int)

const OPENING_CASCADE_MULTIPLIER := 0.5
const ORTHOGONAL_OFFSETS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const ALL_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

var definitions: Array[PatternDefinition] = []
var pattern_score := 0
var total_patterns := 0
var last_pattern := "NONE"
var activations: Dictionary = {}
var best_metrics: Dictionary = {}
var highest_action_pattern_score := 0
var best_pattern_name := "NONE"
var best_pattern_points := 0
var result_history: Array[PatternResult] = []

var _definitions_by_id: Dictionary = {}
var _surround_awarded: Dictionary = {}
var _last_processed_action_id := -1


func _init() -> void:
	_create_definitions()
	reset_field()


func reset_field() -> void:
	pattern_score = 0
	total_patterns = 0
	last_pattern = "NONE"
	activations.clear()
	best_metrics.clear()
	highest_action_pattern_score = 0
	best_pattern_name = "NONE"
	best_pattern_points = 0
	result_history.clear()
	_surround_awarded.clear()
	_last_processed_action_id = -1
	for definition in definitions:
		activations[definition.id] = 0
		best_metrics[definition.id] = 0


func detect(context: PatternActionContext) -> Array[PatternResult]:
	var results: Array[PatternResult] = []
	if context.caused_loss or context.action_id == _last_processed_action_id:
		return results
	_last_processed_action_id = context.action_id
	_detect_chain(context, results)
	_detect_matches(context, results)
	_detect_sequence(context, results)
	_detect_surrounds(context, results)
	_detect_high_risk(context, results)
	_detect_cascade(context, results)
	results.sort_custom(_sort_results)
	var action_points := 0
	for result in results:
		action_points += result.total_points
		pattern_score += result.total_points
		total_patterns += result.occurrences
		activations[result.definition.id] = int(activations[result.definition.id]) + result.occurrences
		best_metrics[result.definition.id] = maxi(int(best_metrics[result.definition.id]), result.metric)
		if result.total_points > best_pattern_points:
			best_pattern_points = result.total_points
			best_pattern_name = result.definition.display_name
		result_history.append(result)
	if not results.is_empty():
		last_pattern = results[0].definition.display_name
		highest_action_pattern_score = maxi(highest_action_pattern_score, action_points)
		patterns_detected.emit(results, action_points)
	return results


func total_points(results: Array[PatternResult]) -> int:
	var points := 0
	for result in results:
		points += result.total_points
	return points


func _detect_chain(context: PatternActionContext, results: Array[PatternResult]) -> void:
	var numbered: Dictionary = {}
	for cell in context.revealed_cells:
		if int(cell["value"]) > 0:
			numbered[cell["position"]] = true
	var visited: Dictionary = {}
	var largest := 0
	for start: Vector2i in numbered:
		if visited.has(start):
			continue
		var queue: Array[Vector2i] = [start]
		visited[start] = true
		var cursor := 0
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			for offset in ORTHOGONAL_OFFSETS:
				var neighbor := current + offset
				if numbered.has(neighbor) and not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
		largest = maxi(largest, queue.size())
	if largest >= 4:
		results.append(_result("chain", _chain_points(largest), largest, "CHAIN %d" % largest))


func _detect_matches(context: PatternActionContext, results: Array[PatternResult]) -> void:
	var counts: Dictionary = {}
	for cell in context.revealed_cells:
		var value: int = cell["value"]
		if value > 0:
			counts[value] = int(counts.get(value, 0)) + 1
	for value in range(1, 9):
		var count := int(counts.get(value, 0))
		if count >= 3:
			results.append(_result("match", _match_points(count), count, "MATCH %d ×%d" % [value, count]))


func _detect_sequence(context: PatternActionContext, results: Array[PatternResult]) -> void:
	var present := PackedByteArray()
	present.resize(9)
	for cell in context.revealed_cells:
		var value: int = cell["value"]
		if value > 0:
			present[value] = 1
	var best_start := 0
	var best_length := 0
	var current_start := 0
	var current_length := 0
	for value in range(1, 9):
		if present[value] == 1:
			if current_length == 0:
				current_start = value
			current_length += 1
			if current_length > best_length:
				best_length = current_length
				best_start = current_start
		else:
			current_length = 0
	if best_length >= 3:
		var end := best_start + best_length - 1
		results.append(_result("sequence", _sequence_points(best_length), best_length, "SEQUENCE %d–%d" % [best_start, end]))


func _detect_surrounds(context: PatternActionContext, results: Array[PatternResult]) -> void:
	if context.after_state.is_empty():
		return
	var width: int = context.after_state["width"]
	var height: int = context.after_state["height"]
	var mines: PackedByteArray = context.after_state["mines"]
	var revealed: PackedByteArray = context.after_state["revealed"]
	var flagged: PackedByteArray = context.after_state["flagged"]
	var values: PackedByteArray = context.after_state["adjacent"]
	for y in height:
		for x in width:
			var position := Vector2i(x, y)
			var index := y * width + x
			var value := int(values[index])
			if revealed[index] == 0 or value < 2 or _surround_awarded.has(position):
				continue
			var complete := true
			var mine_count := 0
			for offset in ALL_OFFSETS:
				var neighbor := position + offset
				if neighbor.x < 0 or neighbor.x >= width or neighbor.y < 0 or neighbor.y >= height:
					continue
				var neighbor_index := neighbor.y * width + neighbor.x
				if mines[neighbor_index] == 1:
					mine_count += 1
					if flagged[neighbor_index] == 0:
						complete = false
				elif revealed[neighbor_index] == 0:
					complete = false
			if complete and mine_count == value:
				_surround_awarded[position] = true
				var result := _result("surround", _surround_points(value), value, "SURROUND %d" % value)
				result.source_position = position
				results.append(result)


func _detect_high_risk(context: PatternActionContext, results: Array[PatternResult]) -> void:
	if context.action_type == PatternActionContext.ActionType.MANUAL_REVEAL and context.clicked_value >= 4:
		results.append(_result("high_risk", _high_risk_points(context.clicked_value), context.clicked_value, "HIGH RISK %d" % context.clicked_value))


func _detect_cascade(context: PatternActionContext, results: Array[PatternResult]) -> void:
	var size := context.automatically_revealed.size()
	if size < 4:
		return
	var label := "CASCADE %d" % size
	if size >= 25:
		label = "MASSIVE CASCADE %d" % size
	elif size >= 15:
		label = "LARGE CASCADE %d" % size
	var result := _result("cascade", _cascade_points(size), size, label)
	if context.is_opening_action:
		result.multiplier *= OPENING_CASCADE_MULTIPLIER
		result.detail = "OPENING CASCADE %d ×0.5" % size
		result.recalculate()
	results.append(result)


func _result(id: StringName, points: int, metric: int, detail: String) -> PatternResult:
	return PatternResult.new().configure(_definitions_by_id[id], points, metric, detail)


func _sort_results(a: PatternResult, b: PatternResult) -> bool:
	if a.total_points != b.total_points:
		return a.total_points > b.total_points
	if a.definition.visual_priority != b.definition.visual_priority:
		return a.definition.visual_priority > b.definition.visual_priority
	return a.definition.display_name < b.definition.display_name


func _chain_points(size: int) -> int:
	if size >= 13: return 300
	if size >= 9: return 180
	if size >= 6: return 100
	return 50


func _match_points(size: int) -> int:
	if size >= 6: return 280
	if size == 5: return 180
	if size == 4: return 110
	return 60


func _sequence_points(size: int) -> int:
	if size >= 6: return 400
	if size == 5: return 260
	if size == 4: return 160
	return 90


func _surround_points(value: int) -> int:
	return [0, 0, 50, 80, 125, 190, 270, 370, 500][value]


func _high_risk_points(value: int) -> int:
	return [0, 0, 0, 0, 75, 130, 210, 320, 480][value]


func _cascade_points(size: int) -> int:
	if size >= 25: return 175
	if size >= 15: return 90
	if size >= 8: return 40
	return 15


func _create_definitions() -> void:
	definitions = [
		PatternDefinition.new("chain", "CHAIN", "Connected numbered cells in one action.", "4+ orthogonally connected numbered cells.", "4–5:50  6–8:100  9–12:180  13+:300", 50, 30, 4, false),
		PatternDefinition.new("match", "MATCH", "Repeated equal numbers in one action.", "3+ equal values from 1 to 8.", "3:60  4:110  5:180  6+:280", 60, 40, 3, true),
		PatternDefinition.new("sequence", "SEQUENCE", "Consecutive distinct values in one action.", "3+ consecutive values from 1 to 8.", "3:90  4:160  5:260  6+:400", 90, 50, 3, false),
		PatternDefinition.new("surround", "SURROUND", "Correctly flag every mine around a solved number.", "Number 2+; all mines flagged and safe neighbors open.", "2:50  3:80  4:125  5:190  6:270  7:370  8:500", 50, 60, 2, true),
		PatternDefinition.new("high_risk", "HIGH RISK", "Directly reveal a dangerous numbered cell.", "Manual reveal of a value from 4 to 8.", "4:75  5:130  6:210  7:320  8:480", 75, 70, 4, true),
		PatternDefinition.new("cascade", "CASCADE", "Open multiple automatic cells in one action.", "4+ automatically revealed cells.", "4–7:15  8–14:40  15–24:90  25+:175", 15, 20, 4, false),
	]
	_definitions_by_id.clear()
	for definition in definitions:
		_definitions_by_id[definition.id] = definition
