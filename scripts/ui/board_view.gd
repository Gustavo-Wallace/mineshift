class_name BoardView
extends GridContainer

signal cell_reveal_requested(position: Vector2i)
signal cell_flag_requested(position: Vector2i)

const CELL_SCENE: PackedScene = preload("res://scenes/ui/mine_cell.tscn")

var _cells: Array[MineCell] = []
var _board_width := 0


func build(board_width: int, board_height: int) -> void:
	clear()
	_board_width = board_width
	columns = board_width
	for y in board_height:
		for x in board_width:
			var cell := CELL_SCENE.instantiate() as MineCell
			var position := Vector2i(x, y)
			cell.configure(position)
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


func refresh_cell(model: BoardModel, position: Vector2i, locked: bool = false) -> void:
	var cell := _get_cell(position)
	if cell == null:
		return
	cell.set_visual_state(
		model.is_revealed(position),
		model.is_flagged(position),
		model.has_mine(position),
		model.adjacent_mines(position),
		false,
		false,
		locked,
		model.can_chord(position)
	)


func get_cell_global_center(position: Vector2i) -> Vector2:
	var cell := _get_cell(position)
	if cell == null:
		return global_position
	return cell.global_position + cell.size * 0.5


func show_loss(model: BoardModel, exploded_position: Vector2i) -> void:
	for y in model.height:
		for x in model.width:
			var position := Vector2i(x, y)
			var cell := _get_cell(position)
			cell.set_visual_state(
				model.is_revealed(position),
				model.is_flagged(position),
				model.has_mine(position),
				model.adjacent_mines(position),
				position == exploded_position,
				model.is_flagged(position) and not model.has_mine(position),
				true
			)


func show_win(model: BoardModel) -> void:
	for y in model.height:
		for x in model.width:
			var position := Vector2i(x, y)
			var cell := _get_cell(position)
			cell.set_visual_state(
				model.is_revealed(position),
				model.is_flagged(position) or model.has_mine(position),
				model.has_mine(position),
				model.adjacent_mines(position),
				false,
				false,
				true
			)


func _get_cell(position: Vector2i) -> MineCell:
	var index := position.y * _board_width + position.x
	if index < 0 or index >= _cells.size():
		return null
	return _cells[index]


func _on_cell_reveal_requested(position: Vector2i) -> void:
	cell_reveal_requested.emit(position)


func _on_cell_flag_requested(position: Vector2i) -> void:
	cell_flag_requested.emit(position)
