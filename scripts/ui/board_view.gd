class_name BoardView
extends GridContainer

signal cell_reveal_requested(cell_position: Vector2i)
signal cell_flag_requested(cell_position: Vector2i)

const CELL_SCENE: PackedScene = preload("res://scenes/ui/mine_cell.tscn")

var _cells: Array[MineCell] = []
var _board_width := 0


func build(board_width: int, board_height: int) -> void:
	clear()
	_board_width = board_width
	columns = board_width
	var cell_size := _get_cell_size(maxi(board_width, board_height))
	for y in board_height:
		for x in board_width:
			var cell := CELL_SCENE.instantiate() as MineCell
			var cell_position := Vector2i(x, y)
			cell.configure(cell_position, cell_size)
			cell.reveal_requested.connect(_on_cell_reveal_requested)
			cell.flag_toggle_requested.connect(_on_cell_flag_requested)
			add_child(cell)
			_cells.append(cell)


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cells.clear()
	_board_width = 0


func refresh_cell(model: BoardModel, cell_position: Vector2i, locked: bool = false) -> void:
	var cell := _get_cell(cell_position)
	if cell == null:
		return
	cell.set_visual_state(
		model.is_revealed(cell_position),
		model.is_flagged(cell_position),
		model.has_mine(cell_position),
		model.adjacent_mines(cell_position),
		false,
		false,
		locked,
		model.can_chord(cell_position)
	)


func get_cell_global_center(cell_position: Vector2i) -> Vector2:
	var cell := _get_cell(cell_position)
	if cell == null:
		return global_position
	return cell.global_position + cell.size * 0.5


func show_loss(model: BoardModel, exploded_position: Vector2i) -> void:
	for y in model.height:
		for x in model.width:
			var cell_position := Vector2i(x, y)
			var cell := _get_cell(cell_position)
			cell.set_visual_state(
				model.is_revealed(cell_position),
				model.is_flagged(cell_position),
				model.has_mine(cell_position),
				model.adjacent_mines(cell_position),
				cell_position == exploded_position,
				model.is_flagged(cell_position) and not model.has_mine(cell_position),
				true
			)


func show_win(model: BoardModel) -> void:
	for y in model.height:
		for x in model.width:
			var cell_position := Vector2i(x, y)
			var cell := _get_cell(cell_position)
			cell.set_visual_state(
				model.is_revealed(cell_position),
				model.is_flagged(cell_position) or model.has_mine(cell_position),
				model.has_mine(cell_position),
				model.adjacent_mines(cell_position),
				false,
				false,
				true,
				false,
				true
			)


func lock_board(model: BoardModel) -> void:
	for y in model.height:
		for x in model.width:
			refresh_cell(model, Vector2i(x, y), true)


func _get_cell(cell_position: Vector2i) -> MineCell:
	var index := cell_position.y * _board_width + cell_position.x
	if index < 0 or index >= _cells.size():
		return null
	return _cells[index]


func _on_cell_reveal_requested(cell_position: Vector2i) -> void:
	cell_reveal_requested.emit(cell_position)


func _on_cell_flag_requested(cell_position: Vector2i) -> void:
	cell_flag_requested.emit(cell_position)


func _get_cell_size(largest_dimension: int) -> float:
	if largest_dimension >= 11:
		return 44.0
	if largest_dimension == 10:
		return 49.0
	return 54.0
