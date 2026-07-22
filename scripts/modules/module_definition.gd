class_name ModuleDefinition
extends RefCounted

enum Rarity { COMMON, UNCOMMON, RARE }

var id: StringName
var display_name := ""
var short_name := ""
var description := ""
var trigger_text := ""
var effect_text := ""
var rarity := Rarity.COMMON
var cost := 0
var priority := 0
var icon_text := "◇"
var effect: ModuleEffect


func _init(
	module_id: StringName,
	name: String,
	compact_name: String,
	module_description: String,
	trigger: String,
	effect_description: String,
	module_rarity: Rarity,
	price: int,
	resolution_priority: int,
	icon: String,
	implementation: ModuleEffect
) -> void:
	id = module_id
	display_name = name
	short_name = compact_name
	description = module_description
	trigger_text = trigger
	effect_text = effect_description
	rarity = module_rarity
	cost = price
	priority = resolution_priority
	icon_text = icon
	effect = implementation


func sell_value() -> int:
	return floori(float(cost) / 2.0)


func rarity_name() -> String:
	return Rarity.keys()[rarity]


func rarity_weight() -> int:
	return [60, 30, 10][rarity]


func rarity_color() -> Color:
	return [Color("89a8c7"), Color("67e8a5"), Color("d88cff")][rarity]
