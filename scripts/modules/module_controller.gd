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
const LOGIC_PROBE := &"logic_probe"

var definition_pool: Array[ModuleDefinition] = ModuleDefinition.create_default_pool()
var installed: Array[ModuleRuntime] = []
var current_offers: Array[ModuleDefinition] = []
var selected_offer: ModuleDefinition
var selection_open := false
var selection_completed := false
var current_field_number := 0
var telemetry: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func on_run_started() -> void:
	installed.clear()
	clear_pending_selection()
	_rng.randomize()
	_reset_telemetry()
	field_state_changed.emit()


func on_run_ended() -> void:
	clear_pending_selection()


func abandon_run() -> void:
	installed.clear()
	clear_pending_selection()
	field_state_changed.emit()


func on_field_started(field_number: int = 0) -> void:
	current_field_number = field_number
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
	record_activation(BUFFER_LAYER, 1, "damage_blocked")
	return 1


func consume_logic_probe() -> bool:
	var runtime := get_runtime(LOGIC_PROBE)
	if runtime == null or not runtime.consume_field_charge():
		return false
	field_state_changed.emit()
	record_activation(LOGIC_PROBE)
	return true


func restart_is_free() -> bool:
	var runtime := get_runtime(RESTART_CACHE)
	return runtime != null and runtime.persistent_available


func consume_restart_cache() -> bool:
	var runtime := get_runtime(RESTART_CACHE)
	if runtime == null or not runtime.consume_persistent_charge():
		return false
	field_state_changed.emit()
	record_activation(RESTART_CACHE, 1, "restarts_saved")
	return true


func opening_protection_radius() -> int:
	return 2 if has_module(EXPANDED_START) else 1


func module_state_summary(board_ready: bool = true) -> String:
	if installed.is_empty():
		return "NO MODULES INSTALLED"
	var sections: Array[String] = []
	for runtime in installed:
		sections.append("%s  %s\n%s\nACTIVATES: %s\nSTATE: %s\nINSTALLED AFTER FIELD %d" % [
			runtime.definition.symbol,
			runtime.definition.display_name,
			runtime.definition.full_description,
			runtime.definition.activation_moment,
			runtime.state_text(board_ready),
			runtime.installed_field,
		])
	return "\n\n".join(sections)


func record_activation(module_id: StringName, amount: int = 1, metric: String = "activations") -> void:
	if not telemetry.has(module_id):
		telemetry[module_id] = _new_telemetry_entry()
	var entry: Dictionary = telemetry[module_id]
	entry[metric] = int(entry.get(metric, 0)) + amount
	var useful_fields: Array = entry.get("useful_fields", [])
	if current_field_number > 0 and not useful_fields.has(current_field_number):
		useful_fields.append(current_field_number)
	entry["useful_fields"] = useful_fields
	telemetry[module_id] = entry


func record_probe_result(safe_result: bool) -> void:
	record_activation(LOGIC_PROBE, 1, "safe_probes" if safe_result else "mine_probes")


func record_expanded_opening(revealed_cells: int) -> void:
	record_activation(EXPANDED_START)
	record_activation(EXPANDED_START, revealed_cells, "opening_cells_total")
	record_activation(EXPANDED_START, 1, "opening_samples")


func telemetry_snapshot() -> Dictionary:
	return telemetry.duplicate(true)


## Debug builds only: call from a test or the remote inspector to start with chosen modules.
## Example: modules.install_debug_modules([ModuleController.LOGIC_PROBE, ModuleController.AUTO_CHORD])
func install_debug_modules(module_ids: Array[StringName], installed_after_field: int = 0) -> void:
	if not OS.is_debug_build():
		return
	for module_id in module_ids:
		if has_module(module_id):
			continue
		for definition in definition_pool:
			if definition.id == module_id:
				installed.append(ModuleRuntime.new(definition, installed_after_field))
				break
	field_state_changed.emit()


func _reset_telemetry() -> void:
	telemetry.clear()
	for definition in definition_pool:
		telemetry[definition.id] = _new_telemetry_entry()


func _new_telemetry_entry() -> Dictionary:
	return {
		"activations": 0,
		"useful_fields": [],
		"damage_blocked": 0,
		"cells_revealed": 0,
		"opening_cells_total": 0,
		"opening_samples": 0,
		"restarts_saved": 0,
		"safe_probes": 0,
		"mine_probes": 0,
	}
