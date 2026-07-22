class_name PatternActionContext
extends RefCounted

enum ActionType { MANUAL_REVEAL, CHORD, FLAG_PLACED, FLAG_REMOVED }

var action_id := 0
var action_type := ActionType.MANUAL_REVEAL
var clicked_position := Vector2i(-1, -1)
var clicked_value := 0
var revealed_cells: Array[Dictionary] = []
var manually_revealed: Array[Vector2i] = []
var automatically_revealed: Array[Vector2i] = []
var total_revealed := 0
var zero_count := 0
var numbered_count := 0
var distinct_number_count := 0
var relevant_adjacent_flags := 0
var before_state: Dictionary = {}
var after_state: Dictionary = {}
var safe_streak := 0
var caused_win := false
var caused_loss := false
var is_opening_action := false


func finalize_counts() -> void:
	total_revealed = revealed_cells.size()
	zero_count = 0
	numbered_count = 0
	var distinct: Dictionary = {}
	for cell in revealed_cells:
		var value: int = cell["value"]
		if value == 0:
			zero_count += 1
		else:
			numbered_count += 1
			distinct[value] = true
	distinct_number_count = distinct.size()
