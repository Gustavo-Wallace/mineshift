class_name BoardModel
extends RefCounted

signal mines_placed
signal cell_revealed(position: Vector2i)
signal flag_changed(position: Vector2i, flagged: bool)
signal mines_neutralized(positions: Array[Vector2i])
signal board_numbers_recalculated(positions: Array[Vector2i])

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

var width: int
var height: int
var mine_count: int
var flags_placed: int = 0
var revealed_safe_count: int = 0
var mines_are_placed: bool = false

var _mines: PackedByteArray
var _neutralized: PackedByteArray
var _revealed: PackedByteArray
var _flagged: PackedByteArray
var _verified_flags: PackedByteArray
var _adjacent_counts: PackedByteArray


func _init(board_width: int = 9, board_height: int = 9, total_mines: int = 10) -> void:
	reset(board_width, board_height, total_mines)


func reset(board_width: int, board_height: int, total_mines: int) -> void:
	assert(board_width > 0 and board_height > 0)
	assert(total_mines >= 0 and total_mines < board_width * board_height)
	width = board_width
	height = board_height
	mine_count = total_mines
	flags_placed = 0
	revealed_safe_count = 0
	mines_are_placed = false
	var cell_count := width * height
	_mines = PackedByteArray()
	_mines.resize(cell_count)
	_neutralized = PackedByteArray()
	_neutralized.resize(cell_count)
	_revealed = PackedByteArray()
	_revealed.resize(cell_count)
	_flagged = PackedByteArray()
	_flagged.resize(cell_count)
	_verified_flags = PackedByteArray()
	_verified_flags.resize(cell_count)
	_adjacent_counts = PackedByteArray()
	_adjacent_counts.resize(cell_count)


func generate_mines(first_position: Vector2i, requested_protection_radius: int = 1) -> void:
	if mines_are_placed:
		return
	assert(is_valid_position(first_position))

	var protection_radius := maxi(0, requested_protection_radius)
	var protected := PackedByteArray()
	var candidates: Array[Vector2i] = []
	while true:
		protected = _build_protected_region(first_position, protection_radius)
		candidates.clear()
		for y in height:
			for x in width:
				var cell_position := Vector2i(x, y)
				if protected[_index(cell_position)] == 0:
					candidates.append(cell_position)
		if candidates.size() >= mine_count or protection_radius == 0:
			break
		protection_radius -= 1

	assert(mine_count <= candidates.size(), "Too many mines for the protected opening area.")
	candidates.shuffle()
	for mine_index in mine_count:
		_mines[_index(candidates[mine_index])] = 1

	_calculate_adjacent_counts()
	mines_are_placed = true
	mines_placed.emit()


func _build_protected_region(center: Vector2i, radius: int) -> PackedByteArray:
	var protected := PackedByteArray()
	protected.resize(width * height)
	for offset_y in range(-radius, radius + 1):
		for offset_x in range(-radius, radius + 1):
			var cell_position := center + Vector2i(offset_x, offset_y)
			if is_valid_position(cell_position):
				protected[_index(cell_position)] = 1
	return protected


func perform_reveal_action(position: Vector2i) -> BoardActionResult:
	var action := BoardActionResult.new()
	if not is_valid_position(position) or is_revealed(position) or is_flagged(position):
		return action
	action.performed = true

	if has_mine(position):
		_set_revealed(position, action.detonated_mines)
		return action

	_reveal_safe_area(position, action.safe_revealed)
	return action


func _reveal_safe_area(position: Vector2i, changed: Array[Vector2i]) -> void:
	var queued := PackedByteArray()
	queued.resize(width * height)
	var queue: Array[Vector2i] = [position]
	queued[_index(position)] = 1
	var cursor := 0

	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		if is_revealed(current) or is_flagged(current) or has_mine(current):
			continue
		_set_revealed(current, changed)
		if adjacent_mines(current) != 0:
			continue
		for neighbor in get_neighbors(current):
			var neighbor_index := _index(neighbor)
			if queued[neighbor_index] == 0 and not is_flagged(neighbor) and not has_mine(neighbor):
				queued[neighbor_index] = 1
				queue.append(neighbor)



func perform_chord_action(position: Vector2i) -> BoardActionResult:
	var action := BoardActionResult.new()
	if not can_chord(position):
		return action
	action.performed = true

	for neighbor in get_neighbors(position):
		if is_revealed(neighbor) or is_flagged(neighbor):
			continue
		if has_mine(neighbor):
			_set_revealed(neighbor, action.detonated_mines)
			continue
		var result: BoardActionResult = perform_reveal_action(neighbor)
		for changed_position in result.safe_revealed:
			if not action.safe_revealed.has(changed_position):
				action.safe_revealed.append(changed_position)

	return action


func neutralize_detonations(action: BoardActionResult) -> void:
	if action == null or action.detonated_mines.is_empty() or not action.neutralized_mines.is_empty():
		return
	var affected: Array[Vector2i] = []
	for mine_position in action.detonated_mines:
		if not has_mine(mine_position):
			continue
		var mine_index := _index(mine_position)
		if _flagged[mine_index] == 1:
			_flagged[mine_index] = 0
			_verified_flags[mine_index] = 0
			flags_placed -= 1
			flag_changed.emit(mine_position, false)
		_mines[mine_index] = 0
		_neutralized[mine_index] = 1
		action.neutralized_mines.append(mine_position)
		for neighbor in get_neighbors(mine_position):
			if not affected.has(neighbor):
				affected.append(neighbor)

	for affected_position in affected:
		if has_mine(affected_position) or is_neutralized(affected_position):
			continue
		var affected_index := _index(affected_position)
		var previous_count := int(_adjacent_counts[affected_index])
		var updated_count := _count_adjacent_active_mines(affected_position)
		_adjacent_counts[affected_index] = updated_count
		if updated_count != previous_count:
			action.recalculated_positions.append(affected_position)

	_expand_recalculated_zeros(action.recalculated_positions, action.expansion_revealed)
	if not action.neutralized_mines.is_empty():
		mines_neutralized.emit(action.neutralized_mines)
	if not action.recalculated_positions.is_empty():
		board_numbers_recalculated.emit(action.recalculated_positions)


func reveal_orthogonal_safe_cells(origins: Array[Vector2i]) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	var orthogonal_offsets: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for origin in origins:
		for offset in orthogonal_offsets:
			var cell_position := origin + offset
			if not is_valid_position(cell_position) or is_revealed(cell_position) or is_flagged(cell_position) or has_mine(cell_position) or is_neutralized(cell_position):
				continue
			var local_changes: Array[Vector2i] = []
			_reveal_safe_area(cell_position, local_changes)
			for revealed_position in local_changes:
				if not changed.has(revealed_position):
					changed.append(revealed_position)
	return changed


func _expand_recalculated_zeros(seeds: Array[Vector2i], changed: Array[Vector2i]) -> void:
	var queued := PackedByteArray()
	queued.resize(width * height)
	var queue: Array[Vector2i] = []
	for zero_origin in seeds:
		if is_revealed(zero_origin) and not has_mine(zero_origin) and not is_neutralized(zero_origin) and adjacent_mines(zero_origin) == 0:
			queued[_index(zero_origin)] = 1
			queue.append(zero_origin)
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for neighbor in get_neighbors(current):
			var neighbor_index := _index(neighbor)
			if queued[neighbor_index] == 1 or is_flagged(neighbor) or has_mine(neighbor) or is_neutralized(neighbor):
				continue
			queued[neighbor_index] = 1
			if not is_revealed(neighbor):
				_set_revealed(neighbor, changed)
			if adjacent_mines(neighbor) == 0:
				queue.append(neighbor)


func toggle_flag(position: Vector2i) -> bool:
	if not is_valid_position(position) or is_revealed(position):
		return false
	var index := _index(position)
	if _flagged[index] == 1:
		if _verified_flags[index] == 1:
			return false
		_flagged[index] = 0
		flags_placed -= 1
	else:
		if is_neutralized(position) or flags_placed >= active_mine_count():
			return false
		_flagged[index] = 1
		flags_placed += 1
	flag_changed.emit(position, _flagged[index] == 1)
	return true


func mark_flag_verified(position: Vector2i) -> bool:
	if not is_valid_position(position) or not is_flagged(position) or not has_mine(position):
		return false
	_verified_flags[_index(position)] = 1
	return true


func remove_flag(position: Vector2i) -> bool:
	if not is_valid_position(position) or not is_flagged(position):
		return false
	var cell_index := _index(position)
	_flagged[cell_index] = 0
	_verified_flags[cell_index] = 0
	flags_placed -= 1
	flag_changed.emit(position, false)
	return true


func all_safe_cells_revealed() -> bool:
	return mines_are_placed and revealed_safe_count == width * height - mine_count


func has_mine(position: Vector2i) -> bool:
	return is_valid_position(position) and _mines[_index(position)] == 1


func is_neutralized(position: Vector2i) -> bool:
	return is_valid_position(position) and _neutralized[_index(position)] == 1


func active_mine_count() -> int:
	return mine_count - count_neutralized_mines()


func count_neutralized_mines() -> int:
	var total := 0
	for value in _neutralized:
		total += int(value)
	return total


func is_revealed(position: Vector2i) -> bool:
	return is_valid_position(position) and _revealed[_index(position)] == 1


func is_flagged(position: Vector2i) -> bool:
	return is_valid_position(position) and _flagged[_index(position)] == 1


func is_flag_verified(position: Vector2i) -> bool:
	return is_valid_position(position) and _verified_flags[_index(position)] == 1


func adjacent_mines(position: Vector2i) -> int:
	if not is_valid_position(position):
		return 0
	return _adjacent_counts[_index(position)]


func count_adjacent_flags(position: Vector2i) -> int:
	var count := 0
	for neighbor in get_neighbors(position):
		if is_flagged(neighbor):
			count += 1
	return count


func create_snapshot() -> Dictionary:
	return {
		"width": width,
		"height": height,
		"mines": _mines.duplicate(),
		"neutralized": _neutralized.duplicate(),
		"revealed": _revealed.duplicate(),
		"flagged": _flagged.duplicate(),
		"verified_flags": _verified_flags.duplicate(),
		"adjacent": _adjacent_counts.duplicate(),
	}


func can_chord(position: Vector2i) -> bool:
	if not is_valid_position(position) or not is_revealed(position) or adjacent_mines(position) == 0:
		return false
	if count_adjacent_flags(position) != adjacent_mines(position):
		return false
	for neighbor in get_neighbors(position):
		if not is_revealed(neighbor) and not is_flagged(neighbor):
			return true
	return false


func get_neighbors(position: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for offset in NEIGHBOR_OFFSETS:
		var neighbor := position + offset
		if is_valid_position(neighbor):
			neighbors.append(neighbor)
	return neighbors


func is_valid_position(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < width and position.y >= 0 and position.y < height


func _index(position: Vector2i) -> int:
	return position.y * width + position.x


func _set_revealed(position: Vector2i, changed: Array[Vector2i]) -> void:
	var index := _index(position)
	if _revealed[index] == 1:
		return
	_revealed[index] = 1
	if _mines[index] == 0:
		revealed_safe_count += 1
	changed.append(position)
	cell_revealed.emit(position)


func _calculate_adjacent_counts() -> void:
	for y in height:
		for x in width:
			var position := Vector2i(x, y)
			if has_mine(position):
				continue
			_adjacent_counts[_index(position)] = _count_adjacent_active_mines(position)


func _count_adjacent_active_mines(position: Vector2i) -> int:
	var count := 0
	for neighbor in get_neighbors(position):
		if has_mine(neighbor):
			count += 1
	return count
