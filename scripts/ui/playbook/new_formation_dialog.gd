extends ConfirmationDialog
## Starts a new formation: its name and how many players at each position. Needs exactly
## 11 players, at least 5 offensive linemen on offense, and no more players at a position
## than a roster carries. Stays open with a message until the numbers work.

signal submitted(formation_name: String, counts: Dictionary)

## Returns "" if a name is fine, otherwise why it isn't (empty, already used...).
var check_name: Callable = func(_n: String) -> String: return ""

var _offense := true
var _name_edit: LineEdit
var _grid: GridContainer
var _spins := {} # position -> SpinBox
var _total: Label
var _error: Label


func _init() -> void:
	ok_button_text = "Add"
	dialog_hide_on_ok = false
	min_size = Vector2i(380, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	v.add_child(UiStyle.label("Formation name", 14, UiStyle.MUTED))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. Trips Right"
	v.add_child(_name_edit)
	v.add_child(UiStyle.label("Players at each position", 14, UiStyle.MUTED))
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 16)
	v.add_child(_grid)
	_total = UiStyle.label("", 14)
	v.add_child(_total)
	_error = UiStyle.label("", 13, UiStyle.BAD)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_error)
	confirmed.connect(_submit)


func open(offense: bool) -> void:
	_offense = offense
	title = "New %s formation" % ("offensive" if offense else "defensive")
	_name_edit.text = ""
	_error.text = ""
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_spins.clear()
	var defaults: Dictionary = FormationDraft.OFFENSE_POSITIONS if offense else FormationDraft.DEFENSE_POSITIONS
	for pos in defaults:
		var l := UiStyle.label(pos, 15)
		l.custom_minimum_size = Vector2(60, 0)
		_grid.add_child(l)
		var spin := SpinBox.new()
		spin.min_value = FormationDraft.MIN_OL if offense and pos == "OL" else 0
		# Can't field more players at a position than the roster has.
		spin.max_value = TeamGenerator.ROSTER_COUNTS.get(pos, FormationDraft.PLAYERS)
		spin.value = defaults[pos]
		spin.value_changed.connect(func(_v: float) -> void: _refresh_total())
		_grid.add_child(spin)
		_spins[pos] = spin
	_refresh_total()
	popup_centered()
	_name_edit.grab_focus()


func counts() -> Dictionary:
	var out := {}
	for pos in _spins:
		out[pos] = int(_spins[pos].value)
	return out


func _total_players() -> int:
	var n := 0
	for pos in _spins:
		n += int(_spins[pos].value)
	return n


func _refresh_total() -> void:
	var n := _total_players()
	_total.text = "Total: %d of %d" % [n, FormationDraft.PLAYERS]
	_total.add_theme_color_override("font_color", UiStyle.GOOD if n == FormationDraft.PLAYERS else UiStyle.BAD)


func _submit() -> void:
	var n := _name_edit.text.strip_edges()
	var problem: String = check_name.call(n)
	if problem == "" and _total_players() != FormationDraft.PLAYERS:
		problem = "A formation needs exactly %d players (this one has %d)." % [FormationDraft.PLAYERS, _total_players()]
	if problem != "":
		_error.text = problem
		return
	hide()
	submitted.emit(n, counts())
