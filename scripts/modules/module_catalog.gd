class_name ModuleCatalog
extends RefCounted


static func create_definitions() -> Array[ModuleDefinition]:
	var chain_effect := PatternSpecificModuleEffect.new(&"chain")
	chain_effect.per_metric_above = 25
	chain_effect.metric_floor = 4
	chain_effect.additive_cap = 225
	var match_effect := PatternSpecificModuleEffect.new(&"match", 40, 0.0, 1.5)
	match_effect.additional_only = true
	return [
		ModuleDefinition.new(&"risk_processor", "RISK PROCESSOR", "RISK PROC", "Manual high-number reveals score +35%.", "Manual reveal of 4, 5, 6, 7 or 8.", "+35% cell score; HIGH RISK pattern unchanged.", ModuleDefinition.Rarity.COMMON, 5, 20, "△", ManualNumberModuleEffect.new([4, 5, 6, 7, 8], 0.35)),
		ModuleDefinition.new(&"odd_circuit", "ODD CIRCUIT", "ODD", "Manual odd-number reveals score +25%.", "Manual reveal of 1, 3, 5 or 7.", "+25% cell score; automatic cells unchanged.", ModuleDefinition.Rarity.COMMON, 4, 21, "◇", ManualNumberModuleEffect.new([1, 3, 5, 7], 0.25)),
		ModuleDefinition.new(&"even_circuit", "EVEN CIRCUIT", "EVEN", "Manual even-number reveals score +25%.", "Manual reveal of 2, 4, 6 or 8.", "+25% cell score; automatic cells unchanged.", ModuleDefinition.Rarity.COMMON, 4, 22, "□", ManualNumberModuleEffect.new([2, 4, 6, 8], 0.25)),
		ModuleDefinition.new(&"cascade_cache", "CASCADE CACHE", "CASCADE", "Cascade patterns score +50%.", "Any CASCADE pattern, including the opening cascade.", "+50% CASCADE score after its opening modifier.", ModuleDefinition.Rarity.COMMON, 5, 40, "▱", PatternSpecificModuleEffect.new(&"cascade", 0, 0.50)),
		ModuleDefinition.new(&"sequence_driver", "SEQUENCE DRIVER", "SEQUENCE", "Sequences gain +60 base score and ×1.25.", "Every SEQUENCE pattern.", "+60 additive, then an independent ×1.25.", ModuleDefinition.Rarity.UNCOMMON, 7, 31, "≋", PatternSpecificModuleEffect.new(&"sequence", 60, 0.0, 1.25)),
		ModuleDefinition.new(&"match_matrix", "MATCH MATRIX", "MATCH", "Matches gain +40. Additional matches score ×1.5.", "Every MATCH; multiplier starts with the second match in an action.", "+40 additive; additional matches ×1.5.", ModuleDefinition.Rarity.UNCOMMON, 7, 32, "▦", match_effect),
		ModuleDefinition.new(&"chain_reactor", "CHAIN REACTOR", "CHAIN", "Chains gain +25 per connected number beyond 4, up to +225.", "Any CHAIN larger than four cells.", "+25 per extra chain cell; maximum +225.", ModuleDefinition.Rarity.UNCOMMON, 8, 30, "⌁", chain_effect),
		ModuleDefinition.new(&"surround_protocol", "SURROUND PROTOCOL", "SURROUND", "Surround patterns score +75%.", "Any valid SURROUND pattern.", "+75% score without changing detection or revealing mine truth.", ModuleDefinition.Rarity.UNCOMMON, 8, 41, "◎", PatternSpecificModuleEffect.new(&"surround", 0, 0.75)),
		ModuleDefinition.new(&"streak_relay", "STREAK RELAY", "RELAY", "Safe Streak multipliers activate one reveal earlier.", "Every safe manual reveal near a multiplier threshold.", "Moves each threshold one reveal earlier; maximum remains ×1.75.", ModuleDefinition.Rarity.UNCOMMON, 8, 10, "↯", StreakRelayModuleEffect.new()),
		ModuleDefinition.new(&"opening_signal", "OPENING SIGNAL", "OPENING", "Opening Cascades no longer suffer the ×0.5 penalty.", "CASCADE on the first action of a field.", "Removes only the opening CASCADE penalty.", ModuleDefinition.Rarity.RARE, 10, 35, "◈", OpeningSignalModuleEffect.new()),
		ModuleDefinition.new(&"overclock", "OVERCLOCK", "OVERCLOCK", "After reaching the target, all new action score gains +40%.", "Actions started after TARGET REACHED.", "+40% to the final action score; completion rewards unchanged.", ModuleDefinition.Rarity.RARE, 12, 80, "⟫", OverclockModuleEffect.new()),
		ModuleDefinition.new(&"pattern_mirror", "PATTERN MIRROR", "MIRROR", "The highest-scoring pattern in each action repeats at 50%.", "Any action that creates at least one pattern.", "Adds 50% of the final highest pattern without another activation.", ModuleDefinition.Rarity.RARE, 13, 90, "◫", PatternMirrorModuleEffect.new()),
	]
