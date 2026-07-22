class_name RunController
extends RefCounted

signal run_state_changed(state: RunState)
signal field_changed(config: FieldConfig)

enum RunState { NOT_STARTED, IN_PROGRESS, RUN_WON, RUN_LOST }

const FULL_CLEAR_BONUS := 300

var stages: Array[FieldConfig] = FieldConfig.create_default_run()
var state := RunState.NOT_STARTED
var current_stage_index := -1
var confirmed_run_score := 0
var stats := RunStats.new()
var field_results: Array[FieldResult] = []
var has_pending_next_field := false


func start_run() -> FieldConfig:
	state = RunState.IN_PROGRESS
	current_stage_index = 0
	confirmed_run_score = 0
	stats = RunStats.new()
	field_results.clear()
	has_pending_next_field = false
	stats.fields_started = 1
	run_state_changed.emit(state)
	field_changed.emit(current_config())
	return current_config()


func restart_current_field() -> FieldConfig:
	assert(state == RunState.IN_PROGRESS)
	stats.current_provisional_score = 0
	stats.fields_started += 1
	field_changed.emit(current_config())
	return current_config()


func begin_next_field() -> FieldConfig:
	assert(state == RunState.IN_PROGRESS)
	assert(has_pending_next_field)
	current_stage_index += 1
	has_pending_next_field = false
	stats.fields_started += 1
	field_changed.emit(current_config())
	return current_config()


func update_provisional_score(score: int) -> void:
	stats.current_provisional_score = score


func confirm_field(result: FieldResult) -> void:
	assert(state == RunState.IN_PROGRESS)
	field_results.append(result)
	confirmed_run_score += result.confirmed_total
	stats.fields_completed += 1
	stats.confirmed_score = confirmed_run_score
	stats.current_provisional_score = 0
	stats.total_time += result.elapsed_time
	stats.total_actions += result.actions
	stats.cells_revealed += result.cells_revealed
	stats.cascade_cells += result.cascade_cells
	stats.flags_placed += result.flags_placed
	stats.correct_flags_on_completion += result.correct_flags
	stats.full_clears += int(result.full_clear)
	stats.highest_streak = maxi(stats.highest_streak, result.highest_streak)
	stats.best_field_score = maxi(stats.best_field_score, result.confirmed_total)
	stats.overscore_ratio_sum += result.overscore_ratio()
	stats.pattern_points += result.pattern_score
	stats.total_patterns += result.pattern_count
	stats.highest_pattern_action_score = maxi(stats.highest_pattern_action_score, result.highest_pattern_action_score)
	stats.best_pattern_field_score = maxi(stats.best_pattern_field_score, result.pattern_score)
	if result.best_pattern_points > stats.best_pattern_points:
		stats.best_pattern_points = result.best_pattern_points
		stats.best_pattern_name = result.best_pattern_name
	for id in result.pattern_activations:
		stats.pattern_activations[id] = int(stats.pattern_activations.get(id, 0)) + int(result.pattern_activations[id])
	for id in result.pattern_best_metrics:
		stats.pattern_best_metrics[id] = maxi(int(stats.pattern_best_metrics.get(id, 0)), int(result.pattern_best_metrics[id]))

	if current_stage_index == stages.size() - 1:
		state = RunState.RUN_WON
		run_state_changed.emit(state)
	else:
		has_pending_next_field = true


func lose_field(
	provisional_score: int,
	elapsed_time: float,
	actions: int,
	cells: int,
	cascade_cell_count: int,
	flags: int,
	highest_streak: int,
	provisional_pattern_points: int = 0
) -> void:
	if state != RunState.IN_PROGRESS:
		return
	state = RunState.RUN_LOST
	stats.current_provisional_score = provisional_score
	stats.lost_provisional_score = provisional_score
	stats.total_time += elapsed_time
	stats.total_actions += actions
	stats.cells_revealed += cells
	stats.cascade_cells += cascade_cell_count
	stats.flags_placed += flags
	stats.highest_streak = maxi(stats.highest_streak, highest_streak)
	stats.lost_provisional_pattern_points = provisional_pattern_points
	run_state_changed.emit(state)


func abandon_run() -> void:
	state = RunState.NOT_STARTED
	current_stage_index = -1
	confirmed_run_score = 0
	stats = RunStats.new()
	field_results.clear()
	has_pending_next_field = false
	run_state_changed.emit(state)


func current_config() -> FieldConfig:
	if current_stage_index < 0 or current_stage_index >= stages.size():
		return null
	return stages[current_stage_index]


func projected_run_score() -> int:
	return confirmed_run_score + stats.current_provisional_score


func next_config() -> FieldConfig:
	var next_index := current_stage_index + 1
	if not has_pending_next_field or next_index >= stages.size():
		return null
	return stages[next_index]


func get_overscore_bonus(field_score: int, target_score: int) -> int:
	if target_score <= 0 or field_score <= target_score:
		return 0
	var ratio := float(field_score - target_score) / float(target_score)
	if ratio >= 1.0:
		return 1000
	if ratio >= 0.5:
		return 500
	if ratio >= 0.25:
		return 250
	if ratio >= 0.10:
		return 100
	return 0
