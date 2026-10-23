extends ConfirmationDialog
## Asks for a new play's name. On offense it also asks pass or run, and for a pass, whether
## it's play action. Stays open with a message until the name is usable.

signal submitted(play_name: String, is_run: bool, play_action: bool)

## Returns "" if a name is fine, otherwise why it isn't (empty, already used...).
var check_name: Callable = func(_n: String) -> String: return ""

var _name_edit: LineEdit
var _type_row: Control
var _pass_radio: CheckBox
var _run_radio: CheckBox
var _pa_check: CheckBox
var _error: Label


func _init() -> void:
	ok_button_text = "Submit"
	dialog_hide_on_ok = false
	min_size = Vector2i(380, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)

	v.add_child(UiStyle.label("Play name", 14, UiStyle.MUTED))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. Smash"
	_name_edit.text_submitted.connect(func(_t: String) -> void: _submit())
	v.add_child(_name_edit)

	var type_col := VBoxContainer.new()
	_type_row = type_col
	v.add_child(type_col)
	var radios := HBoxContainer.new()
	radios.add_theme_constant_override("separation", 18)
	type_col.add_child(radios)
	var group := ButtonGroup.new()
	_pass_radio = _radio("Pass", group)
	_run_radio = _radio("Run", group)
	radios.add_child(_pass_radio)
	radios.add_child(_run_radio)
	_pa_check = CheckBox.new()
	_pa_check.text = "Play action"
	_pa_check.tooltip_text = "Fake a handoff to the RB before the throw."
	type_col.add_child(_pa_check)
	_pass_radio.toggled.connect(func(on: bool) -> void:
		_pa_check.disabled = not on
		if not on:
			_pa_check.button_pressed = false)

	_error = UiStyle.label("", 13, UiStyle.BAD)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_error)
	confirmed.connect(_submit)


func _radio(text: String, group: ButtonGroup) -> CheckBox:
	var r := CheckBox.new()
	r.text = text
	r.button_group = group
	return r


## Opens the dialog for a formation. offense: show the pass/run choice.
func open(formation_name: String, offense: bool) -> void:
	title = "Add a play to %s" % formation_name
	_name_edit.text = ""
	_error.text = ""
	_type_row.visible = offense
	_pass_radio.button_pressed = true
	_pa_check.disabled = false
	_pa_check.button_pressed = false
	popup_centered()
	_name_edit.grab_focus()


func _submit() -> void:
	var n := _name_edit.text.strip_edges()
	var problem: String = check_name.call(n)
	if problem != "":
		_error.text = problem
		return
	hide()
	submitted.emit(n, _type_row.visible and _run_radio.button_pressed, _pa_check.button_pressed)
