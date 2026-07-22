class_name ModuleRuntime
extends RefCounted

var definition: ModuleDefinition
var confirmed_activations := 0
var confirmed_points := 0
var confirmed_best_contribution := 0
var provisional_activations := 0
var provisional_points := 0
var provisional_best_contribution := 0


func _init(module_definition: ModuleDefinition = null) -> void:
	definition = module_definition


func record(points: int, count_activation: bool = true) -> void:
	if count_activation:
		provisional_activations += 1
	provisional_points += maxi(0, points)
	provisional_best_contribution = maxi(provisional_best_contribution, points)


func confirm_field() -> void:
	confirmed_activations += provisional_activations
	confirmed_points += provisional_points
	confirmed_best_contribution = maxi(confirmed_best_contribution, provisional_best_contribution)
	reset_field()


func reset_field() -> void:
	provisional_activations = 0
	provisional_points = 0
	provisional_best_contribution = 0


func total_activations() -> int:
	return confirmed_activations + provisional_activations


func total_points() -> int:
	return confirmed_points + provisional_points


func best_contribution() -> int:
	return maxi(confirmed_best_contribution, provisional_best_contribution)
