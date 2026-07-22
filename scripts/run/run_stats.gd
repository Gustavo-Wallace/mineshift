class_name RunStats
extends RefCounted

var fields_started := 0
var fields_completed := 0
var confirmed_score := 0
var current_provisional_score := 0
var lost_provisional_score := 0
var total_time := 0.0
var total_actions := 0
var cells_revealed := 0
var cascade_cells := 0
var flags_placed := 0
var correct_flags_on_completion := 0
var full_clears := 0
var highest_streak := 0
var best_field_score := 0
var overscore_ratio_sum := 0.0


func average_overscore_percent() -> float:
	if fields_completed == 0:
		return 0.0
	return overscore_ratio_sum * 100.0 / float(fields_completed)
