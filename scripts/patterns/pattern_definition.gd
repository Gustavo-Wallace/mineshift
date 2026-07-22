class_name PatternDefinition
extends RefCounted

var id: StringName
var display_name: String
var description: String
var condition_text: String
var score_table: String
var base_points: int
var base_multiplier: float
var visual_priority: int
var minimum_condition: int
var can_repeat_per_action: bool


func _init(
	pattern_id: StringName,
	name: String,
	short_description: String,
	condition: String,
	scores: String,
	points: int,
	priority: int,
	minimum: int,
	can_repeat: bool
) -> void:
	id = pattern_id
	display_name = name
	description = short_description
	condition_text = condition
	score_table = scores
	base_points = points
	base_multiplier = 1.0
	visual_priority = priority
	minimum_condition = minimum
	can_repeat_per_action = can_repeat
