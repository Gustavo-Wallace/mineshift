class_name RunConfig
extends RefCounted

const DEFAULT_MAX_INTEGRITY := 3
const DEFAULT_RESTART_COST := 1

var max_integrity: int
var restart_integrity_cost: int


func _init(
	configured_max_integrity: int = DEFAULT_MAX_INTEGRITY,
	configured_restart_cost: int = DEFAULT_RESTART_COST
) -> void:
	max_integrity = maxi(1, configured_max_integrity)
	restart_integrity_cost = clampi(configured_restart_cost, 1, max_integrity)
