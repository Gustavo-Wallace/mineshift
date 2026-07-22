class_name ScoreController
extends RefCounted

signal score_event_created(event: ScoreEvent)
signal metrics_changed

const MANUAL_REVEAL_SCORES: Array[int] = [5, 10, 20, 35, 55, 80, 110, 145, 185]
const CASCADE_BASE_SCORE := 3
const CASCADE_RISK_SCORE := 2
const CORRECT_FLAG_BONUS := 15
const FIELD_CLEAR_BONUS := 500

var actions_taken := 0
var safe_reveal_streak := 0
var highest_safe_reveal_streak := 0
var total_cells_revealed := 0
var total_cascade_cells := 0
var flag_placements := 0
var current_score := 0

var manual_base_points := 0
var streak_bonus_points := 0
var manual_reveal_points := 0
var cascade_cell_points := 0
var cascade_bonus_points := 0
var flag_bonus_points := 0
var clear_bonus_points := 0
var accuracy_bonus_points := 0
var efficiency_bonus_points := 0
var event_history: Array[ScoreEvent] = []
var completion_bonuses_applied := false


func reset() -> void:
	actions_taken = 0
	safe_reveal_streak = 0
	highest_safe_reveal_streak = 0
	total_cells_revealed = 0
	total_cascade_cells = 0
	flag_placements = 0
	current_score = 0
	manual_base_points = 0
	streak_bonus_points = 0
	manual_reveal_points = 0
	cascade_cell_points = 0
	cascade_bonus_points = 0
	flag_bonus_points = 0
	clear_bonus_points = 0
	accuracy_bonus_points = 0
	efficiency_bonus_points = 0
	event_history.clear()
	completion_bonuses_applied = false
	metrics_changed.emit()


func record_flag_action(placed: bool = true) -> void:
	actions_taken += 1
	if placed:
		flag_placements += 1
	metrics_changed.emit()


func record_manual_reveal(
	position: Vector2i,
	clicked_adjacent_mines: int,
	automatic_adjacent_counts: Array[int],
	hit_mine: bool
) -> ScoreEvent:
	actions_taken += 1
	if hit_mine:
		safe_reveal_streak = 0
		var mine_event := ScoreEvent.new()
		mine_event.position = position
		mine_event.adjacent_mines = clicked_adjacent_mines
		mine_event.hit_mine = true
		_commit_event(mine_event)
		return mine_event

	safe_reveal_streak += 1
	highest_safe_reveal_streak = maxi(highest_safe_reveal_streak, safe_reveal_streak)
	var event := _make_event(position, clicked_adjacent_mines, automatic_adjacent_counts, false)
	var multiplier := get_streak_multiplier()
	event.manual_base_score = get_manual_reveal_score(clicked_adjacent_mines)
	event.streak_multiplier = multiplier
	event.manual_final_score = int(round(event.manual_base_score * multiplier))
	event.total_score += event.manual_final_score
	manual_base_points += event.manual_base_score
	streak_bonus_points += event.manual_final_score - event.manual_base_score
	manual_reveal_points += event.manual_final_score
	total_cells_revealed += 1 + automatic_adjacent_counts.size()
	_commit_event(event)
	return event


func record_chord(
	position: Vector2i,
	clicked_adjacent_mines: int,
	automatic_adjacent_counts: Array[int],
	hit_mine: bool
) -> ScoreEvent:
	actions_taken += 1
	if hit_mine:
		safe_reveal_streak = 0
	var event := _make_event(position, clicked_adjacent_mines, automatic_adjacent_counts, true)
	event.hit_mine = hit_mine
	total_cells_revealed += automatic_adjacent_counts.size()
	_commit_event(event)
	return event


func apply_victory_bonuses(correct_flags: int, incorrect_flags: int) -> void:
	if completion_bonuses_applied:
		return
	completion_bonuses_applied = true
	flag_bonus_points = correct_flags * CORRECT_FLAG_BONUS
	clear_bonus_points = FIELD_CLEAR_BONUS
	accuracy_bonus_points = get_accuracy_bonus(incorrect_flags)
	efficiency_bonus_points = get_efficiency_bonus(actions_taken)
	current_score += flag_bonus_points + clear_bonus_points + accuracy_bonus_points + efficiency_bonus_points
	metrics_changed.emit()


func apply_shift_bonuses(correct_flags: int, incorrect_flags: int) -> void:
	if completion_bonuses_applied:
		return
	completion_bonuses_applied = true
	flag_bonus_points = correct_flags * CORRECT_FLAG_BONUS
	clear_bonus_points = 0
	accuracy_bonus_points = get_accuracy_bonus(incorrect_flags)
	efficiency_bonus_points = get_efficiency_bonus(actions_taken)
	current_score += flag_bonus_points + accuracy_bonus_points + efficiency_bonus_points
	metrics_changed.emit()


func get_manual_reveal_score(adjacent_mines: int) -> int:
	assert(adjacent_mines >= 0 and adjacent_mines < MANUAL_REVEAL_SCORES.size())
	return MANUAL_REVEAL_SCORES[adjacent_mines]


func get_streak_multiplier() -> float:
	if safe_reveal_streak >= 10:
		return 1.75
	if safe_reveal_streak >= 7:
		return 1.50
	if safe_reveal_streak >= 5:
		return 1.30
	if safe_reveal_streak >= 3:
		return 1.15
	return 1.0


func get_cascade_size_bonus(cell_count: int) -> int:
	if cell_count >= 25:
		return 175
	if cell_count >= 15:
		return 90
	if cell_count >= 8:
		return 40
	if cell_count >= 4:
		return 15
	return 0


func get_accuracy_bonus(incorrect_flags: int) -> int:
	if incorrect_flags == 0:
		return 250
	if incorrect_flags == 1:
		return 100
	return 0


func get_efficiency_bonus(action_count: int) -> int:
	if action_count <= 25:
		return 300
	if action_count <= 35:
		return 200
	if action_count <= 50:
		return 100
	return 0


func _make_event(
	position: Vector2i,
	clicked_adjacent_mines: int,
	automatic_adjacent_counts: Array[int],
	is_chord: bool
) -> ScoreEvent:
	var event := ScoreEvent.new()
	event.position = position
	event.adjacent_mines = clicked_adjacent_mines
	event.automatic_cells = automatic_adjacent_counts.size()
	event.streak_multiplier = get_streak_multiplier()
	event.is_chord = is_chord
	for adjacent_count in automatic_adjacent_counts:
		event.cascade_cell_score += CASCADE_BASE_SCORE + adjacent_count * CASCADE_RISK_SCORE
	event.cascade_size_bonus = get_cascade_size_bonus(event.automatic_cells)
	event.cascade_message = _get_cascade_message(event.automatic_cells)
	event.total_score = event.cascade_cell_score + event.cascade_size_bonus
	cascade_cell_points += event.cascade_cell_score
	cascade_bonus_points += event.cascade_size_bonus
	total_cascade_cells += event.automatic_cells
	return event


func _commit_event(event: ScoreEvent) -> void:
	current_score += event.total_score
	event_history.append(event)
	score_event_created.emit(event)
	metrics_changed.emit()


func _get_cascade_message(cell_count: int) -> String:
	if cell_count >= 25:
		return "MASSIVE CASCADE"
	if cell_count >= 15:
		return "LARGE CASCADE"
	if cell_count >= 8:
		return "CASCADE"
	return ""
