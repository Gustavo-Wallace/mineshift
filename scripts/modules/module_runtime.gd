class_name ModuleRuntime
extends RefCounted

var definition: ModuleDefinition
var installed_field: int
var field_available := false
var persistent_available := true
var activation_count := 0
var instruction_shown := false


func _init(module_definition: ModuleDefinition, acquired_after_field: int) -> void:
	definition = module_definition
	installed_field = acquired_after_field


func reset_for_field() -> void:
	if definition.id == &"buffer_layer" or definition.id == &"logic_probe":
		field_available = true


func consume_field_charge() -> bool:
	if not field_available:
		return false
	field_available = false
	activation_count += 1
	return true


func consume_persistent_charge() -> bool:
	if not persistent_available:
		return false
	persistent_available = false
	activation_count += 1
	return true


func state_text(board_ready: bool = true) -> String:
	match definition.id:
		&"buffer_layer":
			return "AVAILABLE" if field_available else "USED THIS FIELD"
		&"logic_probe":
			if not board_ready and field_available:
				return "UNAVAILABLE — REVEAL NORMALLY FIRST"
			return "READY" if field_available else "CONSUMED"
		&"restart_cache":
			return "AVAILABLE" if persistent_available else "CONSUMED"
		_:
			return "ACTIVE"
