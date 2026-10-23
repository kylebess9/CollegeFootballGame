extends VBoxContainer
## The playbook editor's right panel: every formation in the playbook, each a row with a
## green + (add a play), a pencil (edit the formation) and a drop-down arrow that shows the
## formation's plays underneath. Works for offensive and defensive formations alike, since
## both have a name and a list of plays.

signal play_selected(play: Resource)
signal add_play_requested(formation: Resource)
signal edit_formation_requested(formation: Resource)
signal delete_play_requested(play: Resource)

var formations: Array = [] # OffensiveFormation or DefensiveFormation
var selected: Resource = null
var _collapsed := {} # formation -> true when its plays are hidden


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func show_formations(list: Array) -> void:
	formations = list
	rebuild()


func select(play: Resource) -> void:
	selected = play
	if play != null:
		_collapsed.erase(play.formation) # make sure the selected play is visible
	rebuild()


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if formations.is_empty():
		var empty := UiStyle.label("This playbook has no formations.", 14, UiStyle.MUTED)
		add_child(empty)
	for f in formations:
		add_child(_formation_row(f))
		if not _collapsed.has(f):
			for p in f.plays:
				add_child(_play_row(p))
			if f.plays.is_empty():
				var none := UiStyle.label("No plays yet. Add one with the +.", 13, UiStyle.MUTED)
				add_child(_indent(none))


func _formation_row(f: Resource) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL_LIGHT, UiStyle.BORDER, 6, 4))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	panel.add_child(h)

	var add := IconButton.make(IconButton.Icon.PLUS, UiStyle.GOOD, "Add a play to %s" % f.name)
	add.pressed.connect(func() -> void: add_play_requested.emit(f))
	h.add_child(add)
	var edit := IconButton.make(IconButton.Icon.PENCIL, UiStyle.ACCENT, "Edit %s" % f.name)
	edit.pressed.connect(func() -> void: edit_formation_requested.emit(f))
	h.add_child(edit)

	var open := not _collapsed.has(f)
	var arrow := IconButton.make(IconButton.Icon.EXPANDED if open else IconButton.Icon.COLLAPSED,
		UiStyle.TEXT, "Hide plays" if open else "Show plays")
	arrow.flat = true
	arrow.pressed.connect(_toggle.bind(f))
	h.add_child(arrow)
	var title := Button.new()
	title.flat = true
	title.text = "%s  (%d)" % [f.name, f.plays.size()]
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", UiStyle.ACCENT)
	title.pressed.connect(_toggle.bind(f))
	h.add_child(title)
	return panel


func _play_row(p: Resource) -> Control:
	var h := HBoxContainer.new()
	var b := Button.new()
	b.text = p.name
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = p.description
	b.toggle_mode = true
	b.button_pressed = p == selected
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: play_selected.emit(p))
	h.add_child(b)
	var tag := UiStyle.label(_tag(p), 12, UiStyle.MUTED)
	tag.custom_minimum_size = Vector2(56, 0)
	h.add_child(tag)
	var del := IconButton.make(IconButton.Icon.CROSS, UiStyle.BAD, "Delete %s" % p.name)
	del.flat = true
	del.pressed.connect(func() -> void: delete_play_requested.emit(p))
	h.add_child(del)
	return _indent(h)


func _tag(p: Resource) -> String:
	if p is RunPlay:
		return "Run"
	if p is PassPlay:
		return "PA Pass" if p.play_action else "Pass"
	return ""


func _indent(c: Control) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 28)
	m.add_child(c)
	return m


func _toggle(f: Resource) -> void:
	if _collapsed.has(f):
		_collapsed.erase(f)
	else:
		_collapsed[f] = true
	rebuild()
