class_name FieldShiftController
extends RefCounted

signal state_changed(state: ShiftState)

enum ShiftState { UNAVAILABLE, READY, ACTIVE, ANIMATING, USED }

var state := ShiftState.UNAVAILABLE
var charge_available := true
var current_field_number := 0
var tutorial_shown := false
var telemetry: Dictionary = {}


func start_run() -> void:
	tutorial_shown = false
	telemetry = {
		"uses": 0,
		"fields": [],
		"clockwise": 0,
		"counter_clockwise": 0,
		"mines_moved": 0,
		"flags_moved": 0,
		"numbers_changed": 0,
		"stable_shifts": 0,
	}
	start_field(1)


func start_field(field_number: int) -> void:
	current_field_number = field_number
	charge_available = true
	_set_state(ShiftState.UNAVAILABLE)


func end_run() -> void:
	charge_available = false
	_set_state(ShiftState.UNAVAILABLE)


func notify_board_generated() -> void:
	if charge_available:
		_set_state(ShiftState.READY)


func enter_mode(board: BoardModel) -> bool:
	if not charge_available or state == ShiftState.USED or state == ShiftState.ANIMATING:
		return false
	if board == null or not board.mines_are_placed:
		_set_state(ShiftState.UNAVAILABLE)
		return false
	if not has_valid_region(board):
		return false
	_set_state(ShiftState.ACTIVE)
	return true


func cancel_mode() -> bool:
	if state != ShiftState.ACTIVE:
		return false
	_set_state(ShiftState.READY)
	return true


func has_valid_region(board: BoardModel) -> bool:
	if board == null:
		return false
	for y in board.height - 1:
		for x in board.width - 1:
			if board.is_shift_region_valid(Vector2i(x, y)):
				return true
	return false


func execute(board: BoardModel, anchor: Vector2i, clockwise: bool) -> FieldShiftResult:
	var result := FieldShiftResult.new()
	result.anchor = anchor
	result.direction = FieldShiftResult.Direction.CLOCKWISE if clockwise else FieldShiftResult.Direction.COUNTER_CLOCKWISE
	if state != ShiftState.ACTIVE or not charge_available or board == null or not board.is_shift_region_valid(anchor):
		return result
	result = board.rotate_hidden_region(anchor, clockwise)
	if not result.succeeded:
		return result
	charge_available = false
	result.charge_consumed = true
	_set_state(ShiftState.ANIMATING)
	_record(result)
	return result


func complete_animation() -> void:
	if state == ShiftState.ANIMATING:
		_set_state(ShiftState.USED)


func consume_tutorial_prompt() -> bool:
	if tutorial_shown:
		return false
	tutorial_shown = true
	return true


func state_text() -> String:
	match state:
		ShiftState.ACTIVE:
			return "ACTIVE"
		ShiftState.ANIMATING:
			return "SHIFTING"
		ShiftState.USED:
			return "USED"
		ShiftState.READY:
			return "READY"
		_:
			return "UNAVAILABLE"


func telemetry_snapshot() -> Dictionary:
	return telemetry.duplicate(true)


func _record(result: FieldShiftResult) -> void:
	telemetry["uses"] = int(telemetry.get("uses", 0)) + 1
	var fields: Array = telemetry.get("fields", [])
	if not fields.has(current_field_number):
		fields.append(current_field_number)
	telemetry["fields"] = fields
	var direction_key := "clockwise" if result.direction == FieldShiftResult.Direction.CLOCKWISE else "counter_clockwise"
	telemetry[direction_key] = int(telemetry.get(direction_key, 0)) + 1
	telemetry["mines_moved"] = int(telemetry.get("mines_moved", 0)) + result.mines_moved
	telemetry["flags_moved"] = int(telemetry.get("flags_moved", 0)) + result.flags_moved
	telemetry["numbers_changed"] = int(telemetry.get("numbers_changed", 0)) + result.numbers_changed.size()
	telemetry["stable_shifts"] = int(telemetry.get("stable_shifts", 0)) + int(result.stable)


func _set_state(next_state: ShiftState) -> void:
	state = next_state
	state_changed.emit(state)
