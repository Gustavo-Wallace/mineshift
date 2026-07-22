class_name PatternResult
extends RefCounted

var definition: PatternDefinition
var base_points := 0
var multiplier := 1.0
var occurrences := 1
var total_points := 0
var metric := 0
var detail := ""
var source_position := Vector2i(-1, -1)
var counts_as_activation := true
var module_source_id: StringName = &""


func configure(pattern: PatternDefinition, points: int, result_metric: int, result_detail: String) -> PatternResult:
	definition = pattern
	base_points = points
	multiplier = pattern.base_multiplier
	metric = result_metric
	detail = result_detail
	recalculate()
	return self


func recalculate() -> void:
	total_points = int(round(base_points * multiplier * occurrences))


func feedback_text() -> String:
	return detail if not detail.is_empty() else definition.display_name
