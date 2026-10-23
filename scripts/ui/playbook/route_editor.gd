extends AcceptDialog
## "Playbook Routes": the field on the left showing the selected route, every route on the
## right. Stock routes are shown as they are and can be copied; the playbook's own routes
## can be reshaped on the field, renamed, switched between stop and go, and deleted.
## Every change is applied to the playbook (and the plays running that route) straight
## away, and `routes_changed` tells the editor to save and redraw.

signal routes_changed

var playbook: Playbook
var canvas: RouteCanvas
var selected := ""

var _list: VBoxContainer
var _title: Label
var _name_edit: LineEdit
var _end: OptionButton
var _copy: Button
var _delete: Button
var _hint: Label
var _error: Label


func _init() -> void:
	title = "Playbook Routes"
	ok_button_text = "Done"
	min_size = Vector2i(1200, 720)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	add_child(h)
	canvas = RouteCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.changed.connect(_on_route_edited)
	h.add_child(canvas)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(320, 0)
	side.add_theme_constant_override("separation", 8)
	h.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	side.add_child(details)
	_title = UiStyle.label("", 18, UiStyle.ACCENT)
	details.add_child(_title)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Route name"
	_name_edit.text_changed.connect(_on_rename)
	details.add_child(_name_edit)
	_end = OptionButton.new()
	_end.add_item("Stop at the last point")
	_end.add_item("Keep going after the last point")
	_end.item_selected.connect(func(i: int) -> void:
		playbook.custom_route(selected).end = Route.STOP if i == 0 else Route.GO
		_on_route_edited())
	details.add_child(_end)
	_error = UiStyle.label("", 13, UiStyle.BAD)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size = Vector2(320, 0)
	details.add_child(_error)
	_hint = UiStyle.label("", 13, UiStyle.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(320, 0) # so it wraps at the panel's width, not one word a line
	details.add_child(_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_copy = UiStyle.button("Copy as New Route")
	_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_copy.pressed.connect(func() -> void: new_route(playbook.make_route(selected)))
	row.add_child(_copy)
	_delete = UiStyle.button("Delete")
	_delete.add_theme_color_override("font_color", UiStyle.BAD)
	_delete.pressed.connect(_delete_selected)
	row.add_child(_delete)
	details.add_child(row)


func open(pb: Playbook) -> void:
	playbook = pb
	select(pb.custom_routes[0].name if not pb.custom_routes.is_empty() else Playbook.route_names()[0])
	popup_centered()


func select(route_name: String) -> void:
	selected = route_name
	var custom := playbook.is_custom_route(route_name)
	# Stock routes are shown from a copy, so nothing can change the shared tree.
	canvas.show_route(playbook.custom_route(route_name) if custom else Playbook.route(route_name), custom)
	_title.text = route_name
	_name_edit.visible = custom
	_name_edit.text = route_name
	_end.visible = custom
	_end.select(0 if canvas.route.end == Route.STOP else 1)
	_delete.visible = custom
	_error.text = ""
	_hint.text = ("Drag a point to move it. Hover the line between two points and click to add one there. Right-click a point to remove it."
		if custom else "A stock route: every playbook has it and it can't be changed. Copy it to make your own version.")
	_rebuild_list()


## Adds a route of the playbook's own (a copy of `base`, or a straight stem) and selects it.
func new_route(base: Route = null) -> void:
	var n := 1
	while playbook.all_route_names().has("route %d" % n):
		n += 1
	var r := playbook.add_custom_route("route %d" % n, base)
	select(r.name)
	routes_changed.emit()


func _rebuild_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_list.add_child(UiStyle.label("THIS PLAYBOOK'S ROUTES", 12, UiStyle.MUTED))
	for r in playbook.custom_routes:
		_list.add_child(_route_button(r.name))
	var add := UiStyle.button("+  New Route")
	add.add_theme_color_override("font_color", UiStyle.GOOD)
	add.pressed.connect(func() -> void: new_route())
	_list.add_child(add)
	_list.add_child(UiStyle.label("STOCK ROUTES", 12, UiStyle.MUTED))
	for n in Playbook.route_names():
		_list.add_child(_route_button(n))


func _route_button(route_name: String) -> Button:
	var b := UiStyle.button(route_name)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.button_pressed = route_name == selected
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(select.bind(route_name))
	return b


func _on_route_edited() -> void:
	playbook.refresh_route(selected)
	routes_changed.emit()


func _on_rename(t: String) -> void:
	var n := t.strip_edges()
	if n == selected:
		_error.text = ""
		return
	if n == "":
		_error.text = "Give the route a name."
	elif playbook.all_route_names().has(n):
		_error.text = "There's already a route called %s." % n
	else:
		_error.text = ""
		playbook.rename_route(selected, n)
		selected = n
		_title.text = n
		_rebuild_list()
		routes_changed.emit()


func _delete_selected() -> void:
	playbook.remove_custom_route(selected)
	select(playbook.custom_routes[0].name if not playbook.custom_routes.is_empty() else Playbook.route_names()[0])
	routes_changed.emit()
