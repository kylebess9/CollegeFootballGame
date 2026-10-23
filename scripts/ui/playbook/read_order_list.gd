extends VBoxContainer
## The QB's progression for a pass play, as a list to reorder by dragging: one row per route
## runner, first read at the top. Blockers aren't in it; PassPlay adds a player to the bottom
## when he's sent out on a route and drops him when he's kept in to block. While the mouse is
## over a row, or a row is being dragged, `player_hovered` names that player so the editor can
## point him out on the field.

signal moved(slot: String, rank: int) # rank 1 = first read
signal player_hovered(slot: String)

const DRAG_KEY := "read_slot"

var rows: Array[Control] = []
var _slots: Array[String] = []
var _dragging := "" # the slot being dragged
var _drop_index := -1 # where the dragged row would land (0..rows.size()), -1 when none


func _ready() -> void:
	add_theme_constant_override("separation", 4)


func show_reads(p: PassPlay) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	rows.clear()
	_slots.assign(p.reads)
	if _slots.is_empty():
		add_child(UiStyle.label("Nobody is running a route.", 13, UiStyle.MUTED))
		return
	for i in _slots.size():
		var row := _row(i + 1, _slots[i], p.job(_slots[i]))
		rows.append(row)
		add_child(row)


func _row(rank: int, slot: String, route_name: String) -> Control:
	var row := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.06)
	box.set_corner_radius_all(4)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	row.add_theme_stylebox_override("panel", box)
	row.custom_minimum_size = Vector2(220, 0)
	row.mouse_default_cursor_shape = Control.CURSOR_MOVE
	row.tooltip_text = "Drag %s up or down to change when the QB looks at him." % slot
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	for part in [["≡", 16, UiStyle.MUTED, 14], [str(rank), 15, UiStyle.ACCENT, 18], [slot, 14, UiStyle.TEXT, 50],
			[route_name, 14, UiStyle.MUTED, 0]]:
		var l := UiStyle.label(part[0], part[1], part[2])
		l.custom_minimum_size = Vector2(part[3], 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(l)
	row.set_drag_forwarding(_drag_from.bind(slot, row), _can_drop_on_row.bind(row), _drop_on_row.bind(row))
	row.mouse_entered.connect(func() -> void:
		if _dragging == "":
			player_hovered.emit(slot))
	row.mouse_exited.connect(func() -> void:
		if _dragging == "":
			player_hovered.emit(""))
	return row


# ---------------------------------------------------------------- dragging

func _drag_from(_at: Vector2, slot: String, row: Control) -> Variant:
	if get_viewport().gui_is_dragging(): # always, except when a test calls this directly
		var ghost := row.duplicate(0) as Control
		ghost.modulate.a = 0.85
		ghost.size = row.size
		row.set_drag_preview(ghost)
	row.modulate.a = 0.35
	_dragging = slot
	player_hovered.emit(slot) # keep pointing him out the whole drag
	return {DRAG_KEY: slot}


func _can_drop_on_row(at: Vector2, data: Variant, row: Control) -> bool:
	return _can_drop_data(row.position + at, data)


func _drop_on_row(at: Vector2, data: Variant, row: Control) -> void:
	_drop_data(row.position + at, data)


## Drops between rows land too.
func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.get(DRAG_KEY, "") in _slots):
		return false
	_drop_index = index_at(at.y)
	queue_redraw()
	return true


func _drop_data(at: Vector2, data: Variant) -> void:
	var slot: String = data[DRAG_KEY]
	var rank := rank_for(slot, index_at(at.y))
	_end_drag()
	if rank != _slots.find(slot) + 1:
		moved.emit(slot, rank)


## The gap a point in the list falls in: 0 above the first row, rows.size() below the last.
func index_at(y: float) -> int:
	var i := 0
	for r in rows:
		if y > r.position.y + r.size.y * 0.5:
			i += 1
	return i


## The read a player dropped into gap `index` ends up as, counting the others around him.
func rank_for(slot: String, index: int) -> int:
	var from := _slots.find(slot)
	return (index if index <= from else index - 1) + 1


func _end_drag() -> void:
	for r in rows:
		r.modulate.a = 1.0
	if _dragging != "":
		_dragging = ""
		player_hovered.emit("")
	_drop_index = -1
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_end_drag()
	elif what == NOTIFICATION_MOUSE_EXIT and _drop_index >= 0:
		_drop_index = -1
		queue_redraw()


## Where the dragged row would go: a line in the gap.
func _draw() -> void:
	if _drop_index < 0 or rows.is_empty():
		return
	var gap := float(get_theme_constant("separation")) * 0.5
	var y := rows[_drop_index].position.y - gap if _drop_index < rows.size() \
		else rows[-1].position.y + rows[-1].size.y + gap
	draw_line(Vector2(0, y), Vector2(size.x, y), UiStyle.ACCENT, 3.0)
