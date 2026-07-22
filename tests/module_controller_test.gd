extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_credit_rewards()
	_test_shop_economy()
	_test_manual_modules()
	_test_streak_relay()
	_test_pattern_modules()
	_test_overclock_and_mirror()
	_test_module_lifecycle()
	if _failures == 0:
		print("PASS: Mineshift module economy and effects tests completed successfully.")
	quit(_failures)


func _test_credit_rewards() -> void:
	var modules := ModuleController.new()
	modules.start_run()
	_expect(modules.credits == 0, "Shift Credits must start at zero.")
	var base := modules.calculate_credit_reward(100, 100, false, 1)
	_expect(base["total"] == 5 and base["base"] == 5, "A completed field must grant five base credits.")
	_expect(modules.calculate_credit_reward(109, 100, false, 1)["overscore"] == 0, "Below 10% overscore must grant no credit.")
	_expect(modules.calculate_credit_reward(110, 100, false, 1)["overscore"] == 1, "10% overscore credit tier is incorrect.")
	_expect(modules.calculate_credit_reward(125, 100, false, 1)["overscore"] == 2, "25% overscore credit tier is incorrect.")
	_expect(modules.calculate_credit_reward(150, 100, false, 1)["overscore"] == 3, "50% overscore credit tier is incorrect.")
	_expect(modules.calculate_credit_reward(200, 100, true, 0)["total"] == 13, "Maximum normal field reward must be 13 credits.")
	var result := _field_result(150, 100, true, 0)
	modules.award_field_credits(result)
	modules.award_field_credits(result)
	_expect(modules.credits == 11, "Field credits must be granted exactly once.")
	modules.lose_field()
	_expect(modules.credits == 11, "A loss must preserve previously confirmed credits for the summary.")
	modules.start_run()
	_expect(modules.credits == 0, "A new run must clear Shift Credits.")
	modules.lose_field()
	_expect(modules.credits == 0, "A lost unconfirmed field must never grant credits.")


func _test_shop_economy() -> void:
	var modules := ModuleController.new()
	modules.set_random_seed(12345)
	modules.start_run()
	modules.credits = 40
	modules.prepare_shop(1)
	var first_stock := modules.stock_ids()
	_expect(first_stock.size() == 3, "A shop should offer three modules while enough remain.")
	_expect(modules.stock[0].rarity == ModuleDefinition.Rarity.COMMON, "A common module should be guaranteed when one is available.")
	_expect(_unique_count(first_stock) == first_stock.size(), "Shop stock must not contain duplicates.")
	modules.prepare_shop(1)
	_expect(modules.stock_ids() == first_stock, "Reopening a shop must preserve its stock.")
	var bought_id := modules.stock[0].id
	var bought_cost := modules.stock[0].cost
	_expect(modules.buy_offer(0) == ModuleController.PurchaseResult.SUCCESS, "A funded purchase with space must succeed.")
	_expect(modules.credits == 40 - bought_cost and modules.owns(bought_id), "Buying must spend credits and install the module.")
	_expect(modules.buy_offer(0) == ModuleController.PurchaseResult.INVALID_OFFER, "A sold offer must reject rapid duplicate purchases.")
	modules.prepare_shop(2)
	_expect(not modules.stock_ids().has(bought_id), "Owned modules must not appear in a new shop.")
	_expect(modules.reroll_cost() == 2, "The first reroll in each shop must cost two credits.")
	var stock_before_reroll := modules.stock_ids()
	var credits_before := modules.credits
	_expect(modules.reroll(), "A funded reroll must succeed.")
	_expect(modules.credits == credits_before - 2 and modules.reroll_cost() == 3, "Reroll cost must increase after use.")
	_expect(modules.stock_ids() != stock_before_reroll, "A reroll must avoid repeating the entire prior stock when alternatives remain.")
	credits_before = modules.credits
	_expect(modules.reroll(), "A second funded reroll must succeed.")
	_expect(modules.credits == credits_before - 3 and modules.reroll_cost() == 4, "The second reroll must cost three credits.")
	credits_before = modules.credits
	_expect(modules.reroll(), "A third funded reroll must succeed.")
	_expect(modules.credits == credits_before - 4 and modules.reroll_cost() == 5, "The third reroll must cost four credits and expose a five-credit next reroll.")
	modules.prepare_shop(3)
	_expect(modules.reroll_cost() == 2, "A new shop must reset reroll cost.")
	modules.credits = 0
	_expect(not modules.reroll(), "Reroll without enough credits must not change stock.")
	var poor_stock := modules.stock_ids()
	_expect(modules.buy_offer(0) == ModuleController.PurchaseResult.INSUFFICIENT_CREDITS, "Purchase without credits must be rejected.")
	_expect(modules.stock_ids() == poor_stock, "Rejected transactions must not alter stock.")
	modules.credits = 100
	for id in [&"odd_circuit", &"even_circuit", &"cascade_cache", &"sequence_driver"]:
		modules.install_for_test(id)
	_expect(modules.installed.size() == ModuleController.SLOT_LIMIT, "The build must expose exactly five module slots.")
	modules.prepare_shop(4)
	_expect(modules.buy_offer(0) == ModuleController.PurchaseResult.SLOTS_FULL, "Purchasing with five occupied slots must be rejected.")
	var sale_id := modules.installed[0].definition.id
	var sale_value := modules.installed[0].definition.sell_value()
	var credits_at_sale := modules.credits
	_expect(modules.request_sale(sale_id), "An installed module must be selectable for sale.")
	modules.cancel_sale()
	_expect(modules.owns(sale_id), "Cancelling a sale must keep the module.")
	modules.request_sale(sale_id)
	_expect(modules.confirm_sale(), "A confirmed sale must succeed.")
	_expect(not modules.owns(sale_id) and modules.credits == credits_at_sale + sale_value, "Selling must free a slot and grant floor(cost / 2).")
	_expect(modules.available_ids().has(sale_id), "A sold module must return to the offer pool.")
	_expect(modules.get_definition(&"risk_processor").sell_value() == 2 and modules.get_definition(&"chain_reactor").sell_value() == 4 and modules.get_definition(&"pattern_mirror").sell_value() == 6, "Sale values must use floor(base price / 2).")


func _test_manual_modules() -> void:
	var risk := _scoring_with([&"risk_processor"])
	var event := risk.record_manual_reveal(Vector2i.ZERO, 4, [], false)
	_expect(event.manual_final_score == 74, "RISK PROCESSOR must add 35% to a manual 4.")
	var odd := _scoring_with([&"odd_circuit"])
	_expect(odd.record_manual_reveal(Vector2i.ZERO, 3, [], false).manual_final_score == 44, "ODD CIRCUIT must add 25% to odd manual numbers.")
	_expect(odd.record_chord(Vector2i.ZERO, 3, [3], false).manual_final_score == 0, "ODD CIRCUIT must not affect chord cells.")
	var even := _scoring_with([&"even_circuit"])
	_expect(even.record_manual_reveal(Vector2i.ZERO, 4, [], false).manual_final_score == 69, "EVEN CIRCUIT must add 25% to even manual numbers.")
	var combined := _scoring_with([&"even_circuit", &"risk_processor"])
	event = combined.record_manual_reveal(Vector2i.ZERO, 4, [], false)
	_expect(event.manual_final_score == 88, "Manual percentages must combine additively and independently of install order.")
	_expect(event.module_bonus_points == 33, "Manual module contribution must be retained in the action summary.")
	var reversed := _scoring_with([&"risk_processor", &"even_circuit"])
	_expect(reversed.record_manual_reveal(Vector2i.ZERO, 4, [], false).manual_final_score == event.manual_final_score, "Visual or purchase order must not alter module resolution.")
	var cascade_cells := _scoring_with([&"cascade_cache"])
	_expect(cascade_cells.record_manual_reveal(Vector2i.ZERO, 0, [1, 2, 3, 4], false).cascade_cell_score == 32, "CASCADE CACHE must not modify automatic cell points.")
	var risk_patterns := _patterns_with([&"risk_processor"])
	var risk_context := _number_context([4], 99)
	risk_context.action_type = PatternActionContext.ActionType.MANUAL_REVEAL
	risk_context.clicked_value = 4
	_expect(_find_pattern(risk_patterns.detect(risk_context), &"high_risk").total_points == 75, "RISK PROCESSOR must not modify the HIGH RISK pattern itself.")


func _test_streak_relay() -> void:
	var scoring := _scoring_with([&"streak_relay"])
	var expected: Array[float] = [1.0, 1.15, 1.15, 1.30, 1.30, 1.50, 1.50, 1.50, 1.75]
	for index in expected.size():
		var event := scoring.record_manual_reveal(Vector2i(index, 0), 2, [], false)
		_expect(is_equal_approx(event.streak_multiplier, expected[index]), "STREAK RELAY tier is incorrect at streak %d." % (index + 1))


func _test_pattern_modules() -> void:
	var cascade := _patterns_with([&"cascade_cache"])
	var opening := _automatic_context(8, true, 1)
	var results := cascade.detect(opening)
	_expect(_find_pattern(results, &"cascade").total_points == 30, "CASCADE CACHE must modify an opening cascade after its ×0.5 penalty.")
	var opening_combo := _patterns_with([&"cascade_cache", &"opening_signal"])
	results = opening_combo.detect(_automatic_context(8, true, 2))
	_expect(_find_pattern(results, &"cascade").total_points == 60, "OPENING SIGNAL must remove the penalty before CASCADE CACHE applies.")

	var sequence := _patterns_with([&"sequence_driver"])
	results = sequence.detect(_number_context([1, 2, 3, 4], 3))
	_expect(_find_pattern(results, &"sequence").total_points == 275, "SEQUENCE DRIVER must apply +60 before ×1.25.")

	var matches := _patterns_with([&"match_matrix"])
	results = matches.detect(_number_context([1, 1, 1], 4))
	_expect(_find_pattern(results, &"match").total_points == 100, "MATCH MATRIX must add 40 to a single match.")
	results = matches.detect(_number_context([1, 1, 1, 2, 2, 2, 2], 5))
	var match_results := _find_patterns(results, &"match")
	match_results.sort_custom(func(a: PatternResult, b: PatternResult) -> bool: return a.metric > b.metric)
	_expect(match_results.size() == 2 and match_results[0].total_points == 150 and match_results[1].total_points == 150, "Additional MATCH results must receive ×1.5 after sorting by base score.")

	var chain := _patterns_with([&"chain_reactor"])
	results = chain.detect(_chain_context(7, 6))
	_expect(_find_pattern(results, &"chain").total_points == 175, "CHAIN REACTOR must add 25 per cell beyond four.")
	results = chain.detect(_chain_context(13, 7))
	_expect(_find_pattern(results, &"chain").total_points == 525, "CHAIN REACTOR must cap its bonus at +225.")

	var surround_definition := PatternDefinition.new(&"surround", "SURROUND", "", "", "", 50, 60, 2, true)
	var surround_result := PatternResult.new().configure(surround_definition, 100, 4, "SURROUND 4")
	var surround_modules := ModuleController.new()
	surround_modules.install_for_test(&"surround_protocol")
	surround_modules.begin_action()
	var direct_results: Array[PatternResult] = [surround_result]
	surround_modules.modify_patterns(direct_results, PatternActionContext.new())
	_expect(surround_result.total_points == 175, "SURROUND PROTOCOL must add 75% without changing pattern detection.")


func _test_overclock_and_mirror() -> void:
	var modules := ModuleController.new()
	modules.install_for_test(&"overclock")
	modules.begin_action()
	_expect(modules.apply_global_action(100, false) == 0, "OVERCLOCK must remain inactive before the target.")
	modules.begin_action()
	_expect(modules.apply_global_action(100, true) == 40, "OVERCLOCK must add 40% after the target.")

	var mirror := _patterns_with([&"pattern_mirror"])
	var results := mirror.detect(_number_context([1, 2, 3, 4], 20))
	var mirrored := results.filter(func(result: PatternResult) -> bool: return not result.counts_as_activation)
	_expect(mirrored.size() == 1 and mirrored[0].total_points == 80, "PATTERN MIRROR must repeat the highest final pattern at 50%.")
	_expect(mirror.total_patterns == 1, "PATTERN MIRROR must not create a statistical pattern activation.")
	_expect(results.filter(func(result: PatternResult) -> bool: return not result.counts_as_activation).size() == 1, "PATTERN MIRROR must not recurse into itself.")

	var tie_modules := ModuleController.new()
	tie_modules.install_for_test(&"pattern_mirror")
	tie_modules.begin_action()
	var low_priority := PatternDefinition.new(&"low", "LOW", "", "", "", 100, 10, 1, false)
	var high_priority := PatternDefinition.new(&"high", "HIGH", "", "", "", 100, 90, 1, false)
	var tied: Array[PatternResult] = [PatternResult.new().configure(low_priority, 100, 1, "LOW"), PatternResult.new().configure(high_priority, 100, 1, "HIGH")]
	tie_modules.modify_patterns(tied, PatternActionContext.new())
	_expect(tied.back().detail == "PATTERN MIRROR +50" and tied.back().definition.id == &"high", "PATTERN MIRROR ties must use pattern priority.")


func _test_module_lifecycle() -> void:
	var modules := ModuleController.new()
	modules.install_for_test(&"risk_processor")
	var scoring := ScoreController.new()
	scoring.set_module_controller(modules)
	scoring.record_manual_reveal(Vector2i.ZERO, 4, [], false)
	var runtime := modules.get_runtime(&"risk_processor")
	_expect(runtime.provisional_activations == 1 and runtime.provisional_points > 0, "Module effects must begin as provisional statistics.")
	var result := _field_result(100, 100, false, 0)
	modules.confirm_field(result)
	_expect(runtime.confirmed_activations == 1 and runtime.provisional_activations == 0, "Completing a field must confirm module statistics.")
	scoring.record_manual_reveal(Vector2i.ZERO, 4, [], false)
	modules.reset_field()
	_expect(runtime.provisional_points == 0 and modules.owns(&"risk_processor"), "Restarting a field must discard provisional stats but keep modules.")
	scoring.record_manual_reveal(Vector2i.ZERO, 4, [], false)
	modules.lose_field()
	_expect(modules.lost_provisional_points > 0 and runtime.provisional_points == 0, "A loss must retain only the lost contribution summary.")
	modules.start_run()
	_expect(modules.installed.is_empty() and modules.credits == 0, "Starting a new run must remove modules and credits.")


func _scoring_with(ids: Array[StringName]) -> ScoreController:
	var modules := ModuleController.new()
	for id in ids:
		modules.install_for_test(id)
	var scoring := ScoreController.new()
	scoring.set_module_controller(modules)
	return scoring


func _patterns_with(ids: Array[StringName]) -> PatternController:
	var modules := ModuleController.new()
	for id in ids:
		modules.install_for_test(id)
	var patterns := PatternController.new()
	patterns.set_module_controller(modules)
	return patterns


func _automatic_context(size: int, opening: bool, action_id: int) -> PatternActionContext:
	var context := PatternActionContext.new()
	context.action_id = action_id
	context.is_opening_action = opening
	for index in size:
		context.automatically_revealed.append(Vector2i(index, 0))
	context.finalize_counts()
	return context


func _number_context(values: Array[int], action_id: int) -> PatternActionContext:
	var context := PatternActionContext.new()
	context.action_id = action_id
	for index in values.size():
		context.revealed_cells.append({"position": Vector2i(index * 2, index * 2), "value": values[index], "manual": false})
	context.finalize_counts()
	return context


func _chain_context(size: int, action_id: int) -> PatternActionContext:
	var context := PatternActionContext.new()
	context.action_id = action_id
	for index in size:
		context.revealed_cells.append({"position": Vector2i(index, 0), "value": 1 + index % 3, "manual": false})
	context.finalize_counts()
	return context


func _field_result(score: int, target: int, full_clear: bool, incorrect_flags: int) -> FieldResult:
	var result := FieldResult.new()
	result.provisional_total_score = score
	result.target_score = target
	result.full_clear = full_clear
	result.incorrect_flags = incorrect_flags
	return result


func _find_pattern(results: Array[PatternResult], id: StringName) -> PatternResult:
	for result in results:
		if result.definition.id == id and result.counts_as_activation:
			return result
	return null


func _find_patterns(results: Array[PatternResult], id: StringName) -> Array[PatternResult]:
	var found: Array[PatternResult] = []
	for result in results:
		if result.definition.id == id and result.counts_as_activation:
			found.append(result)
	return found


func _unique_count(ids: Array[StringName]) -> int:
	var unique := {}
	for id in ids:
		unique[id] = true
	return unique.size()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
