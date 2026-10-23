extends Control
## The bottom of the formation builder: the players not on the field yet. Drag one onto the
## field to place him; drag a player from the field back here to take him off.

signal changed

const GAP := 14.0

var draft: FormationDraft
## The board, for the dot size, so players look the same in both places.
var board: FormationBoard
var font: Font


func _ready() -> void:
	font = get_theme_default_font()
	custom_minimum_size = Vector2(0, 70)


func _radius() -> float:
	return board.dot_radius() if board != null else 12.0


## Where each waiting player is drawn, left to right after the hint text.
func _slots() -> Array:
	var out := []
	if draft == null:
		return out
	var r := _radius()
	var x := 20.0 + r
	for s in draft.unplaced_spots():
		out.append([s, Vector2(x, size.y * 0.62)])
		x += r * 2.0 + GAP
	return out


func _draw() -> void:
	var hint := "Drag players onto the field. Drag one back here to take him off."
	if draft != null and draft.unplaced_spots().is_empty():
		hint = "Everyone is on the field. Drag a player back here to take him off."
	draw_string(font, Vector2(8, 18), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiStyle.MUTED)
	for e in _slots():
		FormationBoard.draw_player(self, font, e[1], _radius(), e[0])


func _get_drag_data(at: Vector2) -> Variant:
	for e in _slots():
		if (e[1] as Vector2).distance_to(at) <= _radius() + 3.0:
			set_drag_preview(FormationBoard.DotPreview.make(e[0], _radius(), font))
			return {"formation_slot": (e[0] as FormationSpot).slot}
	return null


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("formation_slot") and draft.is_placed(data["formation_slot"]) \
		and draft.can_move(data["formation_slot"])


func _drop_data(_at: Vector2, data: Variant) -> void:
	draft.remove(data["formation_slot"])
	changed.emit()
