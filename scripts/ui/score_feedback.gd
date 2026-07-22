class_name ScoreFeedback
extends CanvasLayer

const SCORE_COLOR := Color("dff8ff")
const MULTIPLIER_COLOR := Color("67e8a5")
const CASCADE_COLOR := Color("65ddff")

@onready var overlay: Control = %FeedbackOverlay


func show_score_feedback(screen_position: Vector2, event: ScoreEvent) -> void:
	if event == null or event.total_score <= 0:
		return
	var score_label := _make_label(event.score_text(), 18, SCORE_COLOR)
	if event.streak_multiplier > 1.0 and not event.is_chord:
		score_label.modulate = MULTIPLIER_COLOR
	_place_and_animate(score_label, screen_position - Vector2(32.0, 24.0), Vector2(0.0, -34.0), 0.85)

	if not event.cascade_message.is_empty():
		var cascade_text := "%s  +%d" % [event.cascade_message, event.cascade_size_bonus]
		var cascade_label := _make_label(cascade_text, 13, CASCADE_COLOR)
		_place_and_animate(cascade_label, screen_position + Vector2(-72.0, 4.0), Vector2(0.0, -22.0), 1.15)


func clear_feedback() -> void:
	for child in overlay.get_children():
		child.queue_free()


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.z_index = 50
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _place_and_animate(label: Label, start_position: Vector2, movement: Vector2, duration: float) -> void:
	overlay.add_child(label)
	label.position = start_position
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position", start_position + movement, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, duration).set_delay(duration * 0.45)
	tween.chain().tween_callback(label.queue_free)
