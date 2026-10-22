class_name IconButton
extends Button
## A small square button with a drawn icon (the bundled font has no icon glyphs, so they're
## drawn with lines instead of text).

enum Icon { PLUS, PENCIL, CROSS, EXPANDED, COLLAPSED }

var icon_kind := Icon.PLUS
var icon_color := UiStyle.TEXT


static func make(kind: Icon, color: Color, tip: String) -> IconButton:
	var b := IconButton.new()
	b.icon_kind = kind
	b.icon_color = color
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(30, 30)
	b.focus_mode = Control.FOCUS_NONE
	return b


func set_icon(kind: Icon) -> void:
	icon_kind = kind
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var k := minf(size.x, size.y) * 0.28
	var col := icon_color if not disabled else UiStyle.MUTED
	match icon_kind:
		Icon.PLUS:
			draw_line(c - Vector2(k, 0), c + Vector2(k, 0), col, 3.0)
			draw_line(c - Vector2(0, k), c + Vector2(0, k), col, 3.0)
		Icon.CROSS:
			var d := k * 0.75
			draw_line(c - Vector2(d, d), c + Vector2(d, d), col, 2.5)
			draw_line(c + Vector2(-d, d), c + Vector2(d, -d), col, 2.5)
		Icon.PENCIL:
			# A pencil on a 45 degree slant: body, then the sharpened tip at the bottom left.
			var dir := Vector2(1, -1).normalized()
			var side := Vector2(-dir.y, dir.x) * k * 0.32
			var tip := c - dir * k * 1.1
			var neck := tip + dir * k * 0.6
			var back := c + dir * k * 1.1
			draw_colored_polygon(PackedVector2Array([neck + side, back + side, back - side, neck - side]), col)
			draw_colored_polygon(PackedVector2Array([tip, neck + side, neck - side]), col.darkened(0.35))
		Icon.EXPANDED:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-k, -k * 0.5), c + Vector2(k, -k * 0.5),
				c + Vector2(0, k * 0.6)]), col)
		Icon.COLLAPSED:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.5, -k), c + Vector2(-k * 0.5, k),
				c + Vector2(k * 0.6, 0)]), col)
