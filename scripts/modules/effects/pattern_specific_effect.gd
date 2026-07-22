class_name PatternSpecificModuleEffect
extends ModuleEffect

var pattern_id: StringName
var additive_points := 0
var percent := 0.0
var independent_multiplier := 1.0
var additional_only := false
var per_metric_above := 0
var metric_floor := 0
var additive_cap := 0


func _init(id: StringName = &"", additive: int = 0, score_percent: float = 0.0, multiplier: float = 1.0) -> void:
	pattern_id = id
	additive_points = additive
	percent = score_percent
	independent_multiplier = multiplier


func pattern_additive(result: PatternResult, _context: PatternActionContext, _same_pattern_rank: int) -> int:
	if result.definition.id != pattern_id:
		return 0
	if per_metric_above > 0:
		return mini(maxi(0, result.metric - metric_floor) * per_metric_above, additive_cap)
	return additive_points


func pattern_percent(result: PatternResult, _context: PatternActionContext, _same_pattern_rank: int) -> float:
	return percent if result.definition.id == pattern_id else 0.0


func pattern_multiplier(result: PatternResult, _context: PatternActionContext, same_pattern_rank: int) -> float:
	if result.definition.id != pattern_id:
		return 1.0
	if additional_only and same_pattern_rank == 0:
		return 1.0
	return independent_multiplier
