class_name FieldResult
extends RefCounted

var field_number := 0
var width := 0
var height := 0
var mine_count := 0
var target_score := 0
var normal_field_score := 0
var provisional_total_score := 0
var manual_base_points := 0
var streak_bonus_points := 0
var cascade_cell_points := 0
var pattern_score := 0
var pattern_count := 0
var best_pattern_name := "NONE"
var best_pattern_points := 0
var pattern_activations: Dictionary = {}
var pattern_best_metrics: Dictionary = {}
var highest_pattern_action_score := 0
var flag_bonus_points := 0
var clear_bonus_points := 0
var accuracy_bonus_points := 0
var efficiency_bonus_points := 0
var full_clear_bonus := 0
var overscore_bonus := 0
var confirmed_total := 0
var elapsed_time := 0.0
var actions := 0
var cells_revealed := 0
var cascade_cells := 0
var flags_placed := 0
var correct_flags := 0
var highest_streak := 0
var full_clear := false


func overscore_ratio() -> float:
	if target_score <= 0:
		return 0.0
	var target_score_value := provisional_total_score if provisional_total_score > 0 else normal_field_score
	return maxf(0.0, float(target_score_value - target_score) / float(target_score))
