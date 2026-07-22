class_name FieldConfig
extends RefCounted

var field_number: int
var width: int
var height: int
var mine_count: int
var target_score: int


func _init(number: int, board_width: int, board_height: int, mines: int, target: int) -> void:
	field_number = number
	width = board_width
	height = board_height
	mine_count = mines
	target_score = target


static func create_default_run() -> Array[FieldConfig]:
	return [
		FieldConfig.new(1, 9, 9, 10, 450),
		FieldConfig.new(2, 9, 9, 12, 700),
		FieldConfig.new(3, 10, 10, 15, 1000),
		FieldConfig.new(4, 10, 10, 18, 1350),
		FieldConfig.new(5, 11, 11, 22, 1750),
	]
