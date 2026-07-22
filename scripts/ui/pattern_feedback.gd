class_name PatternFeedback
extends CanvasLayer

@onready var overlay: Control = %PatternFeedbackOverlay

var _active_panel: Control


func show_patterns(panel_anchor: Vector2, action_anchor: Vector2, results: Array[PatternResult]) -> void:
	clear_feedback()
	if results.is_empty():
		return
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("cbd6e6"))
	var total := 0
	var lines: Array[String] = ["PATTERNS"]
	for result in results:
		lines.append("%s    +%d" % [result.feedback_text(), result.total_points])
		total += result.total_points
	lines.append("──────────────")
	lines.append("PATTERN SCORE          +%d" % total)
	label.text = "\n".join(lines)
	panel.add_child(label)
	overlay.add_child(panel)
	_active_panel = panel
	panel.position = Vector2(
		clampf(panel_anchor.x, 12.0, overlay.size.x - 300.0),
		clampf(panel_anchor.y, 150.0, overlay.size.y - 230.0)
	)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.98, 0.98)
	panel.pivot_offset = panel.custom_minimum_size * 0.5
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(panel, "scale", Vector2.ONE, 0.12)
	tween.tween_interval(1.75)
	tween.tween_property(panel, "modulate:a", 0.0, 0.35)
	tween.tween_callback(panel.queue_free)

	var highlight := Label.new()
	highlight.text = results[0].feedback_text()
	highlight.add_theme_font_size_override("font_size", 16)
	highlight.add_theme_color_override("font_color", Color("67e8a5"))
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(highlight)
	highlight.position = action_anchor - Vector2(45.0, 32.0)
	var highlight_tween := highlight.create_tween().set_parallel(true)
	highlight_tween.tween_property(highlight, "position", highlight.position - Vector2(0.0, 28.0), 0.9)
	highlight_tween.tween_property(highlight, "modulate:a", 0.0, 0.9).set_delay(0.35)
	highlight_tween.chain().tween_callback(highlight.queue_free)


func clear_feedback() -> void:
	for child in overlay.get_children():
		child.queue_free()
	_active_panel = null
