class_name ModuleRuntime
extends RefCounted

var definition: ModuleDefinition
var installed_field: int
var field_available := false
var persistent_available := true
var activation_count := 0


func _init(module_definition: ModuleDefinition, acquired_after_field: int) -> void:
	definition = module_definition
	installed_field = acquired_after_field


func reset_for_field() -> void:
	if definition.id == &"buffer_layer" or definition.id == &"flag_verifier":
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


func state_text() -> String:
	match definition.id:
		&"buffer_layer", &"flag_verifier":
			return "AVAILABLE" if field_available else "USED THIS FIELD"
		&"restart_cache":
			return "AVAILABLE" if persistent_available else "CONSUMED"
		_:
			return "ACTIVE"
