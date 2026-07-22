class_name ModuleContribution
extends RefCounted

var module_id: StringName
var module_name := ""
var phase := 0
var before_value := 0
var modifier_type := ""
var modifier_text := ""
var after_value := 0
var points_added := 0


func configure(
	id: StringName,
	display_name: String,
	resolution_phase: int,
	before: int,
	type: String,
	text: String,
	after: int
) -> ModuleContribution:
	module_id = id
	module_name = display_name
	phase = resolution_phase
	before_value = before
	modifier_type = type
	modifier_text = text
	after_value = after
	points_added = maxi(0, after - before)
	return self


func feedback_text() -> String:
	if modifier_type == "GLOBAL_MULTIPLIER":
		return "%s %s" % [module_name, modifier_text]
	return "%s +%d" % [module_name, points_added]
