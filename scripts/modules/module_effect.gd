class_name ModuleEffect
extends RefCounted


func manual_percent(_number: int) -> float:
	return 0.0


func streak_threshold_offset() -> int:
	return 0


func pattern_additive(_result: PatternResult, _context: PatternActionContext, _same_pattern_rank: int) -> int:
	return 0


func pattern_percent(_result: PatternResult, _context: PatternActionContext, _same_pattern_rank: int) -> float:
	return 0.0


func pattern_multiplier(_result: PatternResult, _context: PatternActionContext, _same_pattern_rank: int) -> float:
	return 1.0


func removes_opening_cascade_penalty(_result: PatternResult, _context: PatternActionContext) -> bool:
	return false


func action_percent(_target_was_reached: bool) -> float:
	return 0.0


func mirrors_highest_pattern() -> bool:
	return false
