class_name ModuleController
extends RefCounted

signal module_installed(runtime: ModuleRuntime)
signal offers_generated(offers: Array[ModuleDefinition])
signal field_state_changed

const BUFFER_LAYER := &"buffer_layer"
const AUTO_CHORD := &"auto_chord"
const BREACH_PULSE := &"breach_pulse"
const EXPANDED_START := &"expanded_start"
const RESTART_CACHE := &"restart_cache"
const FLAG_VERIFIER := &"flag_verifier"

var definition_pool: Array[ModuleDefinition] = ModuleDefinition.create_default_pool()
var installed: Array[ModuleRuntime] = []
var current_offers: Array[ModuleDefinition] = []
var selected_offer: ModuleDefinition
var selection_open := false
var selection_completed := false
var _rng := RandomNumberGenerator.new()


func on_run_started() -> void:
	installed.clear()
	clear_pending_selection()
	_rng.randomize()
	field_state_changed.emit()


func on_run_ended() -> void:
	clear_pending_selection()


func abandon_run() -> void:
	installed.clear()
	clear_pending_selection()
	field_state_changed.emit()


func on_field_started() -> void:
	for runtime in installed:
		runtime.reset_for_field()
	field_state_changed.emit()


func on_field_completed() -> void:
	pass


func generate_offers() -> Array[ModuleDefinition]:
	if selection_open:
		return current_offers
	var candidates: Array[ModuleDefinition] = []
	for definition in definition_pool:
		if not has_module(definition.id):
			candidates.append(definition)
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var held := candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = held
	current_offers.clear()
	for index in mini(3, candidates.size()):
		current_offers.append(candidates[index])
	selected_offer = null
	selection_open = true
	selection_completed = false
	offers_generated.emit(current_offers)
	return current_offers


func select_offer(module_id: StringName) -> bool:
	if not selection_open or selection_completed:
		return false
	for definition in current_offers:
		if definition.id == module_id:
			selected_offer = definition
			return true
	return false


func confirm_selected(field_number: int) -> ModuleRuntime:
	if not selection_open or selection_completed or selected_offer == null or has_module(selected_offer.id):
		return null
	var runtime := ModuleRuntime.new(selected_offer, field_number)
	installed.append(runtime)
	selection_completed = true
	module_installed.emit(runtime)
	field_state_changed.emit()
	return runtime


func clear_pending_selection() -> void:
	current_offers.clear()
	selected_offer = null
	selection_open = false
	selection_completed = false


func has_module(module_id: StringName) -> bool:
	return get_runtime(module_id) != null


func get_runtime(module_id: StringName) -> ModuleRuntime:
	for runtime in installed:
		if runtime.definition.id == module_id:
			return runtime
	return null


func installed_count() -> int:
	return installed.size()


func installed_names() -> String:
	var names: Array[String] = []
	for runtime in installed:
		names.append(runtime.definition.display_name)
	return ", ".join(names)


func absorb_breach_damage(incoming_damage: int) -> int:
	var runtime := get_runtime(BUFFER_LAYER)
	if incoming_damage <= 0 or runtime == null or not runtime.consume_field_charge():
		return 0
	field_state_changed.emit()
	return 1


func consume_flag_verifier() -> bool:
	var runtime := get_runtime(FLAG_VERIFIER)
	if runtime == null or not runtime.consume_field_charge():
		return false
	field_state_changed.emit()
	return true


func restart_is_free() -> bool:
	var runtime := get_runtime(RESTART_CACHE)
	return runtime != null and runtime.persistent_available


func consume_restart_cache() -> bool:
	var runtime := get_runtime(RESTART_CACHE)
	if runtime == null or not runtime.consume_persistent_charge():
		return false
	field_state_changed.emit()
	return true


func opening_protection_radius() -> int:
	return 2 if has_module(EXPANDED_START) else 1


func module_state_summary() -> String:
	if installed.is_empty():
		return "NO MODULES INSTALLED"
	var sections: Array[String] = []
	for runtime in installed:
		sections.append("%s  %s\n%s\nACTIVATES: %s\nSTATE: %s\nINSTALLED AFTER FIELD %d" % [
			runtime.definition.symbol,
			runtime.definition.display_name,
			runtime.definition.full_description,
			runtime.definition.activation_moment,
			runtime.state_text(),
			runtime.installed_field,
		])
	return "\n\n".join(sections)
