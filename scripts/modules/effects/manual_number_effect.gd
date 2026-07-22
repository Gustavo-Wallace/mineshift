class_name ManualNumberModuleEffect
extends ModuleEffect

var affected_numbers: Array[int] = []
var percent := 0.0


func _init(numbers: Array[int] = [], score_percent: float = 0.0) -> void:
	affected_numbers = numbers
	percent = score_percent


func manual_percent(number: int) -> float:
	return percent if affected_numbers.has(number) else 0.0
