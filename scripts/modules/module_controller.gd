class_name ModuleController
extends RefCounted

signal economy_changed
signal build_changed
signal stock_changed

enum PurchaseResult { SUCCESS, INVALID_OFFER, INSUFFICIENT_CREDITS, SLOTS_FULL, ALREADY_OWNED, BUSY }

const SLOT_LIMIT := 5
const STOCK_SIZE := 3
const BASE_REROLL_COST := 2

var credits := 0
var catalog: Array[ModuleDefinition] = ModuleCatalog.create_definitions()
var installed: Array[ModuleRuntime] = []
var stock: Array[ModuleDefinition] = []
var shop_field_number := 0
var reroll_count := 0
var pending_sale_id: StringName = &""
var lost_provisional_points := 0
var last_transaction_message := ""
var archived_stats: Dictionary = {}

var _definitions_by_id: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _transaction_locked := false
var _action_contributions: Array[ModuleContribution] = []
var _action_activation_keys: Dictionary = {}


func _init() -> void:
	for definition in catalog:
		_definitions_by_id[definition.id] = definition
	_rng.randomize()


func set_random_seed(seed: int) -> void:
	_rng.seed = seed


func start_run() -> void:
	credits = 0
	installed.clear()
	stock.clear()
	shop_field_number = 0
	reroll_count = 0
	pending_sale_id = &""
	lost_provisional_points = 0
	last_transaction_message = ""
	archived_stats.clear()
	_transaction_locked = false
	begin_action()
	economy_changed.emit()
	build_changed.emit()
	stock_changed.emit()


func abandon_run() -> void:
	start_run()


func reset_field() -> void:
	for runtime in installed:
		runtime.reset_field()
	lost_provisional_points = 0
	begin_action()


func confirm_field(result: FieldResult) -> void:
	result.module_points = provisional_points()
	result.module_stats = provisional_stats()
	for runtime in installed:
		runtime.confirm_field()
	award_field_credits(result)


func lose_field() -> void:
	lost_provisional_points = provisional_points()
	for runtime in installed:
		runtime.reset_field()
	begin_action()


func award_field_credits(result: FieldResult) -> void:
	if result.credits_awarded:
		return
	var reward := calculate_credit_reward(result.provisional_total_score, result.target_score, result.full_clear, result.incorrect_flags)
	result.credit_base = reward["base"]
	result.credit_overscore = reward["overscore"]
	result.credit_full_clear = reward["full_clear"]
	result.credit_precision = reward["precision"]
	result.credits_earned = reward["total"]
	credits += result.credits_earned
	result.credits_after = credits
	result.credits_awarded = true
	economy_changed.emit()


func calculate_credit_reward(field_score: int, target_score: int, full_clear: bool, incorrect_flags: int) -> Dictionary:
	var overscore := 0
	if target_score > 0 and field_score > target_score:
		var ratio := float(field_score - target_score) / float(target_score)
		if ratio >= 1.0:
			overscore = 5
		elif ratio >= 0.5:
			overscore = 3
		elif ratio >= 0.25:
			overscore = 2
		elif ratio >= 0.10:
			overscore = 1
	var clear_reward := 2 if full_clear else 0
	var precision := 1 if incorrect_flags == 0 else 0
	return {"base": 5, "overscore": overscore, "full_clear": clear_reward, "precision": precision, "total": 5 + overscore + clear_reward + precision}


func prepare_shop(completed_field: int) -> void:
	if shop_field_number == completed_field and not stock.is_empty():
		return
	shop_field_number = completed_field
	reroll_count = 0
	pending_sale_id = &""
	stock = _generate_stock([])
	stock_changed.emit()


func reroll_cost() -> int:
	return BASE_REROLL_COST + reroll_count


func can_reroll() -> bool:
	return credits >= reroll_cost() and not _available_definitions().is_empty()


func reroll() -> bool:
	if not can_reroll() or _transaction_locked:
		last_transaction_message = "INSUFFICIENT CREDITS" if credits < reroll_cost() else "NO MODULES AVAILABLE"
		return false
	_transaction_locked = true
	var previous := stock_ids()
	credits -= reroll_cost()
	reroll_count += 1
	stock = _generate_stock(previous)
	last_transaction_message = "STOCK REFRESHED"
	_transaction_locked = false
	economy_changed.emit()
	stock_changed.emit()
	return true


func buy_offer(index: int) -> PurchaseResult:
	if _transaction_locked:
		return PurchaseResult.BUSY
	if index < 0 or index >= stock.size() or stock[index] == null:
		return PurchaseResult.INVALID_OFFER
	var definition := stock[index]
	if owns(definition.id):
		return PurchaseResult.ALREADY_OWNED
	if installed.size() >= SLOT_LIMIT:
		last_transaction_message = "MODULE SLOTS FULL"
		return PurchaseResult.SLOTS_FULL
	if credits < definition.cost:
		last_transaction_message = "INSUFFICIENT CREDITS"
		return PurchaseResult.INSUFFICIENT_CREDITS
	_transaction_locked = true
	credits -= definition.cost
	installed.append(ModuleRuntime.new(definition))
	installed.sort_custom(_sort_runtime)
	stock[index] = null
	last_transaction_message = "MODULE INSTALLED"
	_transaction_locked = false
	economy_changed.emit()
	build_changed.emit()
	stock_changed.emit()
	return PurchaseResult.SUCCESS


func install_for_test(id: StringName) -> bool:
	if owns(id) or not _definitions_by_id.has(id) or installed.size() >= SLOT_LIMIT:
		return false
	installed.append(ModuleRuntime.new(_definitions_by_id[id]))
	installed.sort_custom(_sort_runtime)
	build_changed.emit()
	return true


func request_sale(id: StringName) -> bool:
	if not owns(id):
		return false
	pending_sale_id = id
	return true


func cancel_sale() -> void:
	pending_sale_id = &""


func confirm_sale() -> bool:
	if pending_sale_id == &"" or _transaction_locked:
		return false
	var runtime := get_runtime(pending_sale_id)
	if runtime == null:
		pending_sale_id = &""
		return false
	_transaction_locked = true
	credits += runtime.definition.sell_value()
	var archived: Dictionary = archived_stats.get(runtime.definition.id, {"activations": 0, "points": 0, "best": 0})
	archived["activations"] = int(archived["activations"]) + runtime.confirmed_activations
	archived["points"] = int(archived["points"]) + runtime.confirmed_points
	archived["best"] = maxi(int(archived["best"]), runtime.confirmed_best_contribution)
	archived_stats[runtime.definition.id] = archived
	installed.erase(runtime)
	last_transaction_message = "MODULE SOLD"
	pending_sale_id = &""
	_transaction_locked = false
	economy_changed.emit()
	build_changed.emit()
	return true


func owns(id: StringName) -> bool:
	return get_runtime(id) != null


func get_runtime(id: StringName) -> ModuleRuntime:
	for runtime in installed:
		if runtime.definition.id == id:
			return runtime
	return null


func get_definition(id: StringName) -> ModuleDefinition:
	return _definitions_by_id.get(id) as ModuleDefinition


func stock_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for definition in stock:
		if definition != null:
			ids.append(definition.id)
	return ids


func available_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for definition in _available_definitions():
		ids.append(definition.id)
	return ids


func begin_action() -> void:
	_action_contributions.clear()
	_action_activation_keys.clear()


func action_contributions() -> Array[ModuleContribution]:
	return _action_contributions.duplicate()


func get_streak_multiplier(streak: int, default_multiplier: float) -> float:
	var offset := 0
	for runtime in installed:
		offset = maxi(offset, runtime.definition.effect.streak_threshold_offset())
	if offset == 0:
		return default_multiplier
	var shifted := streak + offset
	if shifted >= 10: return 1.75
	if shifted >= 7: return 1.50
	if shifted >= 5: return 1.30
	if shifted >= 3: return 1.15
	return 1.0


func record_streak_change(before: int, after: int) -> void:
	if after <= before:
		return
	for runtime in installed:
		if runtime.definition.effect.streak_threshold_offset() > 0:
			_record(runtime, 15, before, "STREAK_THRESHOLD", "EARLY TIER", after)


func modify_manual_score(score_after_streak: int, number: int) -> int:
	var modifiers: Array[Dictionary] = []
	for runtime in installed:
		var percent := runtime.definition.effect.manual_percent(number)
		if percent > 0.0:
			modifiers.append({"runtime": runtime, "percent": percent})
	var running := score_after_streak
	var accumulated := 0.0
	for modifier in modifiers:
		var previous_accumulated := accumulated
		accumulated += float(modifier["percent"])
		var before_combined := int(round(score_after_streak * (1.0 + previous_accumulated)))
		var after_combined := int(round(score_after_streak * (1.0 + accumulated)))
		var delta := after_combined - before_combined
		var runtime: ModuleRuntime = modifier["runtime"]
		_record(runtime, 20, running, "CELL_PERCENT", "+%d%%" % int(round(float(modifier["percent"]) * 100.0)), running + delta)
		running += delta
	return running


func modify_patterns(results: Array[PatternResult], context: PatternActionContext) -> void:
	if results.is_empty():
		return
	var ranks := _same_pattern_ranks(results)
	for result in results:
		var rank := int(ranks.get(result, 0))
		for runtime in installed:
			var additive := runtime.definition.effect.pattern_additive(result, context, rank)
			if additive > 0:
				var before := result.total_points
				result.base_points += additive
				result.recalculate()
				_record(runtime, 30, before, "PATTERN_ADDITIVE", "+%d" % additive, result.total_points)
		for runtime in installed:
			if runtime.definition.effect.removes_opening_cascade_penalty(result, context) and result.multiplier < 1.0:
				var before := result.total_points
				result.multiplier = 1.0
				result.detail = "OPENING CASCADE %d" % result.metric
				result.recalculate()
				_record(runtime, 35, before, "BASE_MULTIPLIER_OVERRIDE", "REMOVE ×0.5", result.total_points)
		var percent_modifiers: Array[Dictionary] = []
		for runtime in installed:
			var percent := runtime.definition.effect.pattern_percent(result, context, rank)
			if percent > 0.0:
				percent_modifiers.append({"runtime": runtime, "percent": percent})
		var percent_base := result.total_points
		var accumulated := 0.0
		for modifier in percent_modifiers:
			var previous := accumulated
			accumulated += float(modifier["percent"])
			var delta := int(round(percent_base * (1.0 + accumulated))) - int(round(percent_base * (1.0 + previous)))
			var runtime: ModuleRuntime = modifier["runtime"]
			var before := result.total_points
			result.total_points += delta
			_record(runtime, 40, before, "PATTERN_PERCENT", "+%d%%" % int(round(float(modifier["percent"]) * 100.0)), result.total_points)
		for runtime in installed:
			var multiplier := runtime.definition.effect.pattern_multiplier(result, context, rank)
			if not is_equal_approx(multiplier, 1.0):
				var before := result.total_points
				result.total_points = int(round(result.total_points * multiplier))
				_record(runtime, 45, before, "INDEPENDENT_MULTIPLIER", "×%.2f" % multiplier, result.total_points)
	_apply_pattern_mirror(results)


func apply_global_action(action_score: int, target_was_reached: bool) -> int:
	var modifiers: Array[Dictionary] = []
	for runtime in installed:
		var percent := runtime.definition.effect.action_percent(target_was_reached)
		if percent > 0.0:
			modifiers.append({"runtime": runtime, "percent": percent})
	var accumulated := 0.0
	var running := action_score
	for modifier in modifiers:
		var previous := accumulated
		accumulated += float(modifier["percent"])
		var delta := int(round(action_score * (1.0 + accumulated))) - int(round(action_score * (1.0 + previous)))
		var runtime: ModuleRuntime = modifier["runtime"]
		_record(runtime, 80, running, "GLOBAL_MULTIPLIER", "×%.2f" % (1.0 + float(modifier["percent"])), running + delta)
		running += delta
	return running - action_score


func provisional_points() -> int:
	var total := 0
	for runtime in installed:
		total += runtime.provisional_points
	return total


func confirmed_points() -> int:
	var total := 0
	for data in archived_stats.values():
		total += int((data as Dictionary).get("points", 0))
	for runtime in installed:
		total += runtime.confirmed_points
	return total


func provisional_stats() -> Dictionary:
	var stats := {}
	for runtime in installed:
		stats[runtime.definition.id] = {"activations": runtime.provisional_activations, "points": runtime.provisional_points, "best": runtime.provisional_best_contribution}
	return stats


func most_activated_module() -> String:
	var best_name := "NONE"
	var best := 0
	for id in archived_stats:
		var activations := int((archived_stats[id] as Dictionary).get("activations", 0))
		if activations > best:
			best = activations
			var definition := get_definition(id)
			best_name = definition.display_name if definition != null else str(id)
	for runtime in installed:
		var archived_activations := int((archived_stats.get(runtime.definition.id, {}) as Dictionary).get("activations", 0))
		var total := archived_activations + runtime.confirmed_activations
		if total > best:
			best = total
			best_name = runtime.definition.display_name
	return best_name


func highest_scoring_module() -> String:
	var best_name := "NONE"
	var best := 0
	for id in archived_stats:
		var points := int((archived_stats[id] as Dictionary).get("points", 0))
		if points > best:
			best = points
			var definition := get_definition(id)
			best_name = definition.display_name if definition != null else str(id)
	for runtime in installed:
		var archived_points := int((archived_stats.get(runtime.definition.id, {}) as Dictionary).get("points", 0))
		var total := archived_points + runtime.confirmed_points
		if total > best:
			best = total
			best_name = runtime.definition.display_name
	return best_name


func installed_names() -> String:
	if installed.is_empty():
		return "NONE"
	var names: Array[String] = []
	for runtime in installed:
		names.append(runtime.definition.short_name)
	return ", ".join(names)


func active_global_status(target_reached: bool) -> String:
	var active: Array[String] = []
	for runtime in installed:
		if runtime.definition.effect.action_percent(target_reached) > 0.0:
			active.append("%s ACTIVE" % runtime.definition.short_name)
	return " // ".join(active)


func _record(runtime: ModuleRuntime, phase: int, before: int, type: String, text: String, after: int) -> void:
	var contribution := ModuleContribution.new().configure(runtime.definition.id, runtime.definition.display_name, phase, before, type, text, after)
	_action_contributions.append(contribution)
	var activation_key := runtime.definition.id
	var first_activation := not _action_activation_keys.has(activation_key)
	_action_activation_keys[activation_key] = true
	runtime.record(contribution.points_added, first_activation)


func _apply_pattern_mirror(results: Array[PatternResult]) -> void:
	var mirror_runtime: ModuleRuntime
	for runtime in installed:
		if runtime.definition.effect.mirrors_highest_pattern():
			mirror_runtime = runtime
			break
	if mirror_runtime == null or results.is_empty():
		return
	var source := results[0]
	for candidate in results:
		if candidate.total_points > source.total_points or (candidate.total_points == source.total_points and candidate.definition.visual_priority > source.definition.visual_priority):
			source = candidate
	var mirror_points := int(round(source.total_points * 0.5))
	if mirror_points <= 0:
		return
	var mirror := PatternResult.new()
	mirror.definition = source.definition
	mirror.base_points = mirror_points
	mirror.total_points = mirror_points
	mirror.metric = source.metric
	mirror.detail = "PATTERN MIRROR +%d" % mirror_points
	mirror.counts_as_activation = false
	mirror.module_source_id = mirror_runtime.definition.id
	results.append(mirror)
	_record(mirror_runtime, 60, 0, "PATTERN_MIRROR", "50%", mirror_points)


func _same_pattern_ranks(results: Array[PatternResult]) -> Dictionary:
	var ranks := {}
	var groups := {}
	for result in results:
		var id := result.definition.id
		if not groups.has(id):
			groups[id] = []
		(groups[id] as Array).append(result)
	for id in groups:
		var group: Array = groups[id]
		group.sort_custom(func(a: PatternResult, b: PatternResult) -> bool: return a.base_points > b.base_points)
		for index in group.size():
			ranks[group[index]] = index
	return ranks


func _available_definitions() -> Array[ModuleDefinition]:
	var available: Array[ModuleDefinition] = []
	for definition in catalog:
		if not owns(definition.id):
			available.append(definition)
	return available


func _generate_stock(previous_ids: Array[StringName]) -> Array[ModuleDefinition]:
	var available := _available_definitions()
	var generated: Array[ModuleDefinition] = []
	if available.is_empty():
		return generated
	var commons: Array[ModuleDefinition] = []
	for definition in available:
		if definition.rarity == ModuleDefinition.Rarity.COMMON:
			commons.append(definition)
	if not commons.is_empty():
		var common := commons[_rng.randi_range(0, commons.size() - 1)]
		generated.append(common)
		available.erase(common)
	while generated.size() < STOCK_SIZE and not available.is_empty():
		var selected := _weighted_pick(available)
		generated.append(selected)
		available.erase(selected)
	if stock_ids_from(generated) == previous_ids and not available.is_empty():
		generated[generated.size() - 1] = _weighted_pick(available)
	return generated


func _weighted_pick(options: Array[ModuleDefinition]) -> ModuleDefinition:
	var total_weight := 0
	for definition in options:
		total_weight += definition.rarity_weight()
	var roll := _rng.randi_range(1, total_weight)
	for definition in options:
		roll -= definition.rarity_weight()
		if roll <= 0:
			return definition
	return options.back()


func stock_ids_from(definitions: Array[ModuleDefinition]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for definition in definitions:
		if definition != null:
			ids.append(definition.id)
	return ids


func _sort_runtime(a: ModuleRuntime, b: ModuleRuntime) -> bool:
	if a.definition.priority != b.definition.priority:
		return a.definition.priority < b.definition.priority
	return str(a.definition.id) < str(b.definition.id)
