class_name OpeningSignalModuleEffect
extends ModuleEffect


func removes_opening_cascade_penalty(result: PatternResult, context: PatternActionContext) -> bool:
	return context.is_opening_action and result.definition.id == &"cascade"
