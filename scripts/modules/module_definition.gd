class_name ModuleDefinition
extends RefCounted

# Module design rule: every module must change information, actions, breach consequences,
# board generation, real Minesweeper automation, or the handling of ambiguity.
enum TriggerType { PASSIVE, FIELD_TRIGGER, ACTION_TRIGGER, ACTIVE_TOOL }

var id: StringName
var display_name: String
var short_description: String
var full_description: String
var symbol: String
var tag: String
var activation_moment: String
var priority: int
var trigger_type: TriggerType
var effect_id: StringName


func _init(
	module_id: StringName,
	module_name: String,
	module_symbol: String,
	module_tag: String,
	short_copy: String,
	full_copy: String,
	moment: String,
	resolution_priority: int,
	type: TriggerType
) -> void:
	id = module_id
	display_name = module_name
	symbol = module_symbol
	tag = module_tag
	short_description = short_copy
	full_description = full_copy
	activation_moment = moment
	priority = resolution_priority
	trigger_type = type
	effect_id = module_id


static func create_default_pool() -> Array[ModuleDefinition]:
	return [
		ModuleDefinition.new(
			&"buffer_layer", "BUFFER LAYER", "◇", "DEFENSE",
			"The first breach in each field deals no Integrity damage.",
			"Absorbs one point of damage from the first breach of each field. Detonated mines are still neutralized.",
			"Before breach damage", 10, TriggerType.FIELD_TRIGGER
		),
		ModuleDefinition.new(
			&"auto_chord", "AUTO CHORD", "⌁", "AUTOMATION",
			"Placing a flag automatically chords adjacent numbers when their flag requirement is met.",
			"After a flag is placed, adjacent revealed numbers with matching flags are chorded once in deterministic order. Incorrect flags can trigger breaches.",
			"After a flag is placed", 30, TriggerType.ACTION_TRIGGER
		),
		ModuleDefinition.new(
			&"breach_pulse", "BREACH PULSE", "+", "BREACH",
			"Neutralized mines reveal safe orthogonal neighbors.",
			"After neutralization, safe unflagged cells directly above, below, left, and right are revealed. Zeroes expand normally.",
			"After mine neutralization", 20, TriggerType.ACTION_TRIGGER
		),
		ModuleDefinition.new(
			&"expanded_start", "EXPANDED START", "▦", "OPENING",
			"The first reveal protects a wider region from mine generation.",
			"Protects a Chebyshev radius of two around the first reveal. Dense boards safely fall back to a smaller radius.",
			"Before the first reveal", 5, TriggerType.PASSIVE
		),
		ModuleDefinition.new(
			&"restart_cache", "RESTART CACHE", "↻", "UTILITY",
			"The first field restart of the run costs no Integrity.",
			"Waives the first confirmed restart cost of the run. Cancelling a restart does not consume the cache.",
			"Before a confirmed restart", 5, TriggerType.PASSIVE
		),
		ModuleDefinition.new(
			&"logic_probe", "LOGIC PROBE", "◆", "INFORMATION",
			"Probe one covered cell to safely resolve its contents.",
			"Once per field, use Shift + Left Click on a covered cell. Safe cells are revealed. Active mines are automatically confirmed with a locked flag without causing a breach.",
			"Shift + Left Click on a covered cell", 10, TriggerType.ACTIVE_TOOL
		),
	]
