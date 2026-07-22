class_name RunController
extends RefCounted

signal run_state_changed(state: RunState)
signal field_changed(config: FieldConfig)
signal integrity_changed(current: int, maximum: int)
signal integrity_depleted
signal field_restart_confirmed

enum RunState { NOT_STARTED, IN_PROGRESS, RUN_WON, RUN_LOST }

var stages: Array[FieldConfig] = FieldConfig.create_default_run()
var config := RunConfig.new()
var state := RunState.NOT_STARTED
var current_stage_index := -1
var stats := RunStats.new()
var field_results: Array[FieldResult] = []
var has_pending_next_field := false
var current_integrity := 0
var current_field_neutralized := 0
var current_field_damage := 0
var current_field_paid_restarts := 0


func start_run() -> FieldConfig:
	state = RunState.IN_PROGRESS
	current_stage_index = 0
	stats = RunStats.new()
	field_results.clear()
	has_pending_next_field = false
	current_integrity = config.max_integrity
	_reset_field_stats(true)
	stats.fields_started = 1
	run_state_changed.emit(state)
	integrity_changed.emit(current_integrity, config.max_integrity)
	field_changed.emit(current_config())
	return current_config()


func can_restart_field() -> bool:
	return state == RunState.IN_PROGRESS and current_integrity > config.restart_integrity_cost


func restart_current_field(discarded_time: float = 0.0) -> FieldConfig:
	if not can_restart_field():
		return null
	current_integrity -= config.restart_integrity_cost
	stats.damage_taken += config.restart_integrity_cost
	stats.paid_restarts += 1
	stats.restarts += 1
	stats.fields_started += 1
	stats.total_time += maxf(0.0, discarded_time)
	current_field_damage += config.restart_integrity_cost
	current_field_paid_restarts += 1
	current_field_neutralized = 0
	integrity_changed.emit(current_integrity, config.max_integrity)
	field_restart_confirmed.emit()
	field_changed.emit(current_config())
	return current_config()


func apply_damage(amount: int) -> int:
	if state != RunState.IN_PROGRESS or amount <= 0:
		return 0
	var previous := current_integrity
	current_integrity = maxi(0, current_integrity - amount)
	var applied := previous - current_integrity
	stats.damage_taken += applied
	current_field_damage += applied
	integrity_changed.emit(current_integrity, config.max_integrity)
	if current_integrity == 0:
		integrity_depleted.emit()
	return applied


func record_neutralized(amount: int) -> void:
	if state == RunState.IN_PROGRESS:
		current_field_neutralized += maxi(0, amount)


func confirm_field(result: FieldResult) -> void:
	assert(state == RunState.IN_PROGRESS)
	result.integrity_remaining = current_integrity
	result.neutralized_mines = current_field_neutralized
	result.damage_taken = current_field_damage
	result.paid_restarts = current_field_paid_restarts
	field_results.append(result)
	stats.fields_completed += 1
	stats.total_time += result.elapsed_time
	stats.neutralized_mines += current_field_neutralized
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
	_reset_field_stats(true)
	field_changed.emit(current_config())
	return current_config()


func breach_run(field_time: float) -> void:
	if state != RunState.IN_PROGRESS:
		return
	stats.total_time += field_time
	stats.neutralized_mines += current_field_neutralized
	state = RunState.RUN_LOST
	run_state_changed.emit(state)


func abandon_run() -> void:
	state = RunState.NOT_STARTED
	current_stage_index = -1
	stats = RunStats.new()
	field_results.clear()
	has_pending_next_field = false
	current_integrity = config.max_integrity
	_reset_field_stats(true)
	run_state_changed.emit(state)
	integrity_changed.emit(current_integrity, config.max_integrity)


func current_config() -> FieldConfig:
	if current_stage_index < 0 or current_stage_index >= stages.size():
		return null
	return stages[current_stage_index]


func next_config() -> FieldConfig:
	var next_index := current_stage_index + 1
	if not has_pending_next_field or next_index >= stages.size():
		return null
	return stages[next_index]


func _reset_field_stats(reset_restarts: bool) -> void:
	current_field_neutralized = 0
	current_field_damage = 0
	if reset_restarts:
		current_field_paid_restarts = 0
