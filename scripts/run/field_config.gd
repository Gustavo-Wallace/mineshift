class_name FieldConfig
extends RefCounted

var field_number: int
var width: int
var height: int
var mine_count: int


func _init(number: int, board_width: int, board_height: int, mines: int) -> void:
	field_number = number
	width = board_width
	height = board_height
	mine_count = mines


static func create_default_run() -> Array[FieldConfig]:
	return [
		FieldConfig.new(1, 9, 9, 10),
		FieldConfig.new(2, 9, 9, 12),
		FieldConfig.new(3, 10, 10, 15),
		FieldConfig.new(4, 10, 10, 18),
		FieldConfig.new(5, 11, 11, 22),
	]
