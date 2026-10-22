extends AcceptDialog
## Opened by a formation's pencil: rename the formation, or delete it with all its plays.
## Moving players around will be added here once formations can be built.

signal name_changed(formation: Resource, new_name: String)
signal delete_requested(formation: Resource)

var _formation: Resource
var _name_edit: LineEdit
var _summary: Label


func _init() -> void:
	ok_button_text = "Done"
	min_size = Vector2i(380, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	v.add_child(UiStyle.label("Formation name", 14, UiStyle.MUTED))
	_name_edit = LineEdit.new()
	_name_edit.text_submitted.connect(func(_t: String) -> void: hide())
	v.add_child(_name_edit)
	_summary = UiStyle.label("", 13, UiStyle.MUTED)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_summary)
	add_button("Delete formation", true, "delete")
	custom_action.connect(func(action: StringName) -> void:
		if action == &"delete":
			hide()
			delete_requested.emit(_formation))
	visibility_changed.connect(func() -> void:
		if not visible and _formation != null:
			var n := _name_edit.text.strip_edges()
			if n != "" and n != _formation.name:
				name_changed.emit(_formation, n))


func open(f: Resource) -> void:
	_formation = null # so the visibility hook doesn't fire for the previous formation
	title = "Edit %s" % f.name
	_name_edit.text = f.name
	var who := []
	for s in f.spots:
		who.append(s.slot)
	_summary.text = "Lines up: %s." % ", ".join(who)
	popup_centered()
	_formation = f
	_name_edit.grab_focus()
