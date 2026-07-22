class_name OverclockModuleEffect
extends ModuleEffect


func action_percent(target_was_reached: bool) -> float:
	return 0.40 if target_was_reached else 0.0
