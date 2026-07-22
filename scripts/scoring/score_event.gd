class_name ScoreEvent
extends RefCounted

var position := Vector2i.ZERO
var adjacent_mines := 0
var automatic_cells := 0
var manual_base_score := 0
var streak_multiplier := 1.0
var manual_final_score := 0
var cascade_cell_score := 0
var cascade_size_bonus := 0
var total_score := 0
var cascade_message := ""
var is_chord := false
var hit_mine := false


func score_text() -> String:
	var text := "+%d" % total_score
	if not is_chord and streak_multiplier > 1.0:
		text += "  ×%.2f" % streak_multiplier
	return text
