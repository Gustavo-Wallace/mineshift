class_name FieldShiftResult
extends RefCounted

enum Direction { CLOCKWISE, COUNTER_CLOCKWISE }

var anchor := Vector2i(-1, -1)
var direction := Direction.CLOCKWISE
var affected_positions: Array[Vector2i] = []
var mines_moved := 0
var flags_moved := 0
var confirmed_flags_moved := 0
var numbers_changed: Array[Vector2i] = []
var stable := false
var charge_consumed := false
var succeeded := false

