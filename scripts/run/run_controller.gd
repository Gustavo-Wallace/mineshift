class_name RunController
extends RefCounted

signal run_state_changed(state: RunState)
signal field_changed(config: FieldConfig)

enum RunState { NOT_STARTED, IN_PROGRESS, RUN_WON, RUN_LOST }

var stages: Array[FieldConfig] = FieldConfig.create_default_run()
var state := RunState.NOT_STARTED
var current_stage_index := -1
var stats := RunStats.new()
var field_results: Array[FieldResult] = []
var has_pending_next_field := false


func start_run() -> FieldConfig:
	state = RunState.IN_PROGRESS
	current_stage_index = 0
	stats = RunStats.new()
	field_results.clear()
	has_pending_next_field = false
	stats.fields_started = 1
	run_state_changed.emit(state)
	field_changed.emit(current_config())
	return current_config()


func restart_current_field() -> FieldConfig:
	assert(state == RunState.IN_PROGRESS)
	stats.restarts += 1
	stats.fields_started += 1
	field_changed.emit(current_config())
	return current_config()


func confirm_field(result: FieldResult) -> void:
	assert(state == RunState.IN_PROGRESS)
	field_results.append(result)
	stats.fields_completed += 1
	stats.total_time += result.elapsed_time
	if current_stage_index == stages.size() - 1:
		state = RunState.RUN_WON
		run_state_changed.emit(state)
	else:
		has_pending_next_field = true


func begin_next_field() -> FieldConfig:
	assert(state == RunState.IN_PROGRESS)
	assert(has_pending_next_field)
	current_stage_index += 1
	has_pending_next_field = false
	stats.fields_started += 1
	field_changed.emit(current_config())
	return current_config()


func breach_run(field_time: float) -> void:
	if state != RunState.IN_PROGRESS:
		return
	stats.total_time += field_time
	state = RunState.RUN_LOST
	run_state_changed.emit(state)


func abandon_run() -> void:
	state = RunState.NOT_STARTED
	current_stage_index = -1
	stats = RunStats.new()
	field_results.clear()
	has_pending_next_field = false
	run_state_changed.emit(state)


func current_config() -> FieldConfig:
	if current_stage_index < 0 or current_stage_index >= stages.size():
		return null
	return stages[current_stage_index]


func next_config() -> FieldConfig:
	var next_index := current_stage_index + 1
	if not has_pending_next_field or next_index >= stages.size():
		return null
	return stages[next_index]
