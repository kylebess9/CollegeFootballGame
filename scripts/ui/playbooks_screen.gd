extends Control
## Manage Playbooks: the user's offensive playbooks on the left, defensive on the right.
## Pick one to open it in the playbook editor, or add a new one at the bottom of either list.

var main # main.gd


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	var m := UiStyle.margin(root, 24)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	var title := UiStyle.label("MANAGE PLAYBOOKS", 34, UiStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)
	cols.add_child(_column(Playbook.OFFENSE))
	cols.add_child(_column(Playbook.DEFENSE))

	var back := UiStyle.button("Back to Menu")
	back.custom_minimum_size = Vector2(220, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(main.show_menu)
	root.add_child(back)


func _column(kind: String) -> Control:
	var label := "Offensive" if kind == Playbook.OFFENSE else "Defensive"
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UiStyle.label("%s PLAYBOOKS" % label.to_upper(), 16, UiStyle.MUTED))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for pb in PlaybookStore.list(kind):
		list.add_child(_playbook_row(pb))
	var add := UiStyle.button("+  Add %s Playbook" % label)
	add.add_theme_color_override("font_color", UiStyle.GOOD)
	add.pressed.connect(func() -> void: main.show_playbook_editor(PlaybookStore.create(kind)))
	list.add_child(add)
	return panel


func _playbook_row(pb: Playbook) -> Control:
	var h := HBoxContainer.new()
	var open := UiStyle.button(pb.name)
	open.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.pressed.connect(func() -> void: main.show_playbook_editor(pb))
	h.add_child(open)
	var formations: Array = pb.offensive_formations if pb.kind == Playbook.OFFENSE else pb.defensive_formations
	var plays := 0
	for f in formations:
		plays += f.plays.size()
	h.add_child(UiStyle.label("%s · %s" % [_count(formations.size(), "formation"), _count(plays, "play")], 13, UiStyle.MUTED))
	var del := IconButton.make(IconButton.Icon.CROSS, UiStyle.BAD, "Delete %s" % pb.name)
	del.custom_minimum_size = Vector2(38, 38)
	del.pressed.connect(func() -> void:
		var ask := ConfirmationDialog.new()
		ask.dialog_text = "Delete %s? This can't be undone." % pb.name
		ask.confirmed.connect(func() -> void:
			PlaybookStore.delete(pb)
			main.show_playbooks())
		add_child(ask)
		ask.popup_centered())
	h.add_child(del)
	return h


func _count(n: int, noun: String) -> String:
	return "%d %s%s" % [n, noun, "" if n == 1 else "s"]
