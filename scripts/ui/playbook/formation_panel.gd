extends VBoxContainer
## The formation builder's right panel: the formation's name, who takes the snap (offense),
## the line / backfield counts, and whether the formation is legal yet, with the reasons
## when it isn't. Save is only enabled once it's legal.

signal changed
signal save_requested
signal cancel_requested
signal delete_requested

const NOBODY := "(nobody behind the center)"

var draft: FormationDraft
## Extra problems the editor knows about (e.g. a name another formation already has).
var extra_problems: Callable = func() -> Array[String]: return []

var _name_edit: LineEdit
var _snap_row: Control
var _snap: OptionButton
var _snap_slots: Array[String] = []
var _counts: Label
var _status: Label
var _problems: Label
var _save: Button
var _delete: Button


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UiStyle.label("FORMATION", 13, UiStyle.MUTED))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Formation name"
	_name_edit.add_theme_font_size_override("font_size", 18)
	_name_edit.text_changed.connect(func(t: String) -> void:
		draft.name = t.strip_edges()
		refresh()
		changed.emit())
	add_child(_name_edit)

	var snap_col := VBoxContainer.new()
	_snap_row = snap_col
	snap_col.add_child(UiStyle.label("Takes the snap", 13, UiStyle.MUTED))
	_snap = OptionButton.new()
	_snap.tooltip_text = "Only the player closest behind the center can take the snap. Pick someone here to move him under center."
	_snap.item_selected.connect(_on_snap_picked)
	snap_col.add_child(_snap)
	add_child(snap_col)

	_counts = UiStyle.label("", 14)
	add_child(_counts)
	add_child(HSeparator.new())
	_status = UiStyle.label("", 18)
	add_child(_status)
	_problems = UiStyle.label("", 14, UiStyle.BAD)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_problems)

	_save = UiStyle.button("Save Formation")
	_save.pressed.connect(func() -> void: save_requested.emit())
	add_child(_save)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cancel := UiStyle.button("Cancel")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void: cancel_requested.emit())
	row.add_child(cancel)
	_delete = UiStyle.button("Delete Formation")
	_delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete.add_theme_color_override("font_color", UiStyle.BAD)
	_delete.pressed.connect(func() -> void: delete_requested.emit())
	row.add_child(_delete)
	add_child(row)


## Starts editing a draft. can_delete: it's an existing formation, so offer Delete.
func edit(d: FormationDraft, can_delete: bool) -> void:
	draft = d
	_name_edit.text = d.name
	_snap_row.visible = d.offense
	_delete.visible = can_delete
	refresh()


func problems() -> Array[String]:
	var out := draft.problems()
	out.append_array(extra_problems.call())
	return out


func refresh() -> void:
	if draft == null:
		return
	if draft.offense:
		_fill_snap()
		var c := draft.line_counts()
		_counts.text = "On the line: %d (at least %d)\nIn the backfield: %d (at most %d)" % [
			c["line"], OffensiveFormation.MIN_ON_LINE, c["backfield"], OffensiveFormation.MAX_IN_BACKFIELD]
	else:
		_counts.text = "On the field: %d of %d" % [draft.placed_spots().size(), FormationDraft.PLAYERS]
	var errs := problems()
	var legal := errs.is_empty()
	_status.text = "Legal formation" if legal else "Not legal yet"
	_status.add_theme_color_override("font_color", UiStyle.GOOD if legal else UiStyle.BAD)
	_problems.text = "\n".join(errs.map(func(e: String) -> String: return "• " + e))
	_save.disabled = not legal


## Everyone but the center can be picked; the current snap taker is selected.
func _fill_snap() -> void:
	_snap.clear()
	_snap_slots.clear()
	if draft.snap_slot == "":
		_snap.add_item(NOBODY)
		_snap_slots.append("")
	for s in draft.spots:
		if draft.can_move(s.slot):
			_snap.add_item("%s (%s)" % [s.slot, s.position])
			_snap_slots.append(s.slot)
	_snap.select(_snap_slots.find(draft.snap_slot))


func _on_snap_picked(i: int) -> void:
	if _snap_slots[i] == "":
		return
	draft.give_snap(_snap_slots[i])
	refresh()
	changed.emit()
