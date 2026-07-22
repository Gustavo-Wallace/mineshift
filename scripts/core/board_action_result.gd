class_name BoardActionResult
extends RefCounted

var performed := false
var safe_revealed: Array[Vector2i] = []
var detonated_mines: Array[Vector2i] = []
var neutralized_mines: Array[Vector2i] = []
var recalculated_positions: Array[Vector2i] = []
var expansion_revealed: Array[Vector2i] = []
var damage := 0
var integrity_before := 0
var integrity_after := 0
var field_completed := false
var run_ended := false


func has_breach() -> bool:
	return not detonated_mines.is_empty()


func all_changed_positions() -> Array[Vector2i]:
	var combined: Array[Vector2i] = []
	_append_unique(combined, safe_revealed)
	_append_unique(combined, detonated_mines)
	_append_unique(combined, neutralized_mines)
	_append_unique(combined, recalculated_positions)
	_append_unique(combined, expansion_revealed)
	return combined


func merge_from(other: BoardActionResult) -> void:
	if other == null:
		return
	performed = performed or other.performed
	_append_unique(safe_revealed, other.safe_revealed)
	_append_unique(detonated_mines, other.detonated_mines)
	_append_unique(neutralized_mines, other.neutralized_mines)
	_append_unique(recalculated_positions, other.recalculated_positions)
	_append_unique(expansion_revealed, other.expansion_revealed)


func _append_unique(target: Array[Vector2i], source: Array[Vector2i]) -> void:
	for cell_position in source:
		if not target.has(cell_position):
			target.append(cell_position)
