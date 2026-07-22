class_name BoardModel
extends RefCounted

signal mines_placed
signal cell_revealed(position: Vector2i)
signal flag_changed(position: Vector2i, flagged: bool)

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
var _revealed: PackedByteArray
var _flagged: PackedByteArray
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
	_revealed = PackedByteArray()
	_revealed.resize(cell_count)
	_flagged = PackedByteArray()
	_flagged.resize(cell_count)
	_adjacent_counts = PackedByteArray()
	_adjacent_counts.resize(cell_count)


func place_mines(first_position: Vector2i) -> void:
	if mines_are_placed:
		return
	assert(is_valid_position(first_position))

	var protected := PackedByteArray()
	protected.resize(width * height)
	protected[_index(first_position)] = 1
	for neighbor in get_neighbors(first_position):
		protected[_index(neighbor)] = 1

	var candidates: Array[Vector2i] = []
	for y in height:
		for x in width:
			var position := Vector2i(x, y)
			if protected[_index(position)] == 0:
				candidates.append(position)

	assert(mine_count <= candidates.size(), "Too many mines for the protected opening area.")
	candidates.shuffle()
	for mine_index in mine_count:
		_mines[_index(candidates[mine_index])] = 1

	_calculate_adjacent_counts()
	mines_are_placed = true
	mines_placed.emit()


func reveal(position: Vector2i) -> Dictionary:
	var changed: Array[Vector2i] = []
	if not is_valid_position(position) or is_revealed(position) or is_flagged(position):
		return {"changed": changed, "hit_mine": false}

	if has_mine(position):
		_set_revealed(position, changed)
		return {"changed": changed, "hit_mine": true}

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

	return {"changed": changed, "hit_mine": false}


func chord(position: Vector2i) -> Dictionary:
	var changed: Array[Vector2i] = []
	var exploded_position := Vector2i(-1, -1)
	if not can_chord(position):
		return {"changed": changed, "hit_mine": false, "exploded_position": exploded_position, "performed": false}

	for neighbor in get_neighbors(position):
		if is_revealed(neighbor) or is_flagged(neighbor):
			continue
		if has_mine(neighbor):
			_set_revealed(neighbor, changed)
			if exploded_position.x < 0:
				exploded_position = neighbor
			continue
		var result: Dictionary = reveal(neighbor)
		var neighbor_changes: Array[Vector2i] = result["changed"]
		changed.append_array(neighbor_changes)

	return {
		"changed": changed,
		"hit_mine": exploded_position.x >= 0,
		"exploded_position": exploded_position,
		"performed": true,
	}


func toggle_flag(position: Vector2i) -> bool:
	if not is_valid_position(position) or is_revealed(position):
		return false
	var index := _index(position)
	if _flagged[index] == 1:
		_flagged[index] = 0
		flags_placed -= 1
	else:
		if flags_placed >= mine_count:
			return false
		_flagged[index] = 1
		flags_placed += 1
	flag_changed.emit(position, _flagged[index] == 1)
	return true


func all_safe_cells_revealed() -> bool:
	return mines_are_placed and revealed_safe_count == width * height - mine_count


func has_mine(position: Vector2i) -> bool:
	return is_valid_position(position) and _mines[_index(position)] == 1


func is_revealed(position: Vector2i) -> bool:
	return is_valid_position(position) and _revealed[_index(position)] == 1


func is_flagged(position: Vector2i) -> bool:
	return is_valid_position(position) and _flagged[_index(position)] == 1


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
			var count := 0
			for neighbor in get_neighbors(position):
				if has_mine(neighbor):
					count += 1
			_adjacent_counts[_index(position)] = count
