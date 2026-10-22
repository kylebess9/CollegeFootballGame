extends Control
## Edit one playbook: its name in the top left, the field in the middle showing the selected
## play's art, the formations and their plays on the right, and the selected play's options
## along the bottom. Laid out like match_screen / practice_screen. Every change is saved
## straight away.
##
## This is the "edit playbook" view; formation building, custom routes and run paths will
## be further views of this screen.

const FieldView := preload("res://scripts/ui/field_view.gd")
const FormationList := preload("res://scripts/ui/playbook/formation_list.gd")
const PlayOptions := preload("res://scripts/ui/playbook/play_options.gd")
const AddPlayDialog := preload("res://scripts/ui/playbook/add_play_dialog.gd")
const FormationDialog := preload("res://scripts/ui/playbook/formation_dialog.gd")
## Where the ball sits for the play art, in yards from the offense's own goal.
const PREVIEW_SPOT := 40.0

var main
var playbook: Playbook
var selected_play: Resource = null # OffensivePlay or DefensivePlay
var _adding_to: Resource = null # the formation the add-play dialog is open for

var gs: GameState # only feeds FieldView/PlaySim the two teams and the ball spot
var field: FieldView
var formation_list: FormationList
var options: PlayOptions
var add_dialog: AddPlayDialog
var formation_dialog: FormationDialog
var confirm: ConfirmationDialog
var sim: PlaySim
## The opposite side's play the preview lines up against, from the stock playbook.
var stock := Playbook.make_default()


func _exit_tree() -> void:
	_clear_sim()


func _ready() -> void:
	gs = GameState.new(main.my_team, main.cpu_team, 1.0, Dice.new(1))
	gs.ball_on = PREVIEW_SPOT
	gs.spot_y = GameState.FIELD_W * 0.5
	_build_ui()
	field.gs = gs
	formation_list.show_formations(_formations())


func is_offense() -> bool:
	return playbook.kind != Playbook.DEFENSE


func _formations() -> Array:
	return playbook.offensive_formations if is_offense() else playbook.defensive_formations


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var m := UiStyle.margin(root, 10)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	root.add_child(_build_header())

	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	root.add_child(mid)

	field = FieldView.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(field)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(390, 0)
	mid.add_child(side)
	side.add_child(UiStyle.label("FORMATIONS", 13, UiStyle.MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	formation_list = FormationList.new()
	formation_list.play_selected.connect(select_play)
	formation_list.add_play_requested.connect(_on_add_play)
	formation_list.edit_formation_requested.connect(_on_edit_formation)
	formation_list.delete_play_requested.connect(_on_delete_play)
	scroll.add_child(formation_list)

	var bottom := PanelContainer.new()
	bottom.custom_minimum_size = Vector2(0, 150)
	options = PlayOptions.new()
	options.changed.connect(_on_play_edited)
	bottom.add_child(options)
	root.add_child(bottom)

	add_dialog = AddPlayDialog.new()
	add_dialog.check_name = _name_problem
	add_dialog.submitted.connect(_add_play)
	add_child(add_dialog)
	formation_dialog = FormationDialog.new()
	formation_dialog.name_changed.connect(_rename_formation)
	formation_dialog.delete_requested.connect(_on_delete_formation)
	add_child(formation_dialog)
	confirm = ConfirmationDialog.new()
	add_child(confirm)


## No team names here: the playbook's name (editable) on the left, the view in the middle,
## and the way back on the right.
func _build_header() -> Control:
	var panel := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)

	var name_edit := LineEdit.new()
	name_edit.text = playbook.name
	name_edit.placeholder_text = "Playbook name"
	name_edit.custom_minimum_size = Vector2(360, 0)
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.tooltip_text = "Click to rename this playbook."
	name_edit.text_changed.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			playbook.name = t.strip_edges()
			_save())
	h.add_child(name_edit)

	var center := UiStyle.label("EDIT PLAYBOOK  ·  %s" % ("OFFENSE" if is_offense() else "DEFENSE"), 18, UiStyle.ACCENT)
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(center)

	var back := UiStyle.button("Back to Playbooks")
	back.pressed.connect(main.show_playbooks)
	h.add_child(back)
	return panel


# ---------------------------------------------------------------- selecting and drawing plays

func select_play(p: Resource) -> void:
	selected_play = p
	formation_list.select(p)
	options.show_play(p)
	_draw_play()


## Lines the selected play up on the field against a stock play from the other side and
## draws its art: routes and run paths on offense, zones, man lines and blitzes on defense.
func _draw_play() -> void:
	_clear_sim()
	if selected_play == null:
		return
	var off_call: OffensivePlay
	var def_call: DefensivePlay
	if is_offense():
		off_call = selected_play as OffensivePlay
		def_call = stock.defense_play("Cover 3")
	else:
		off_call = stock.offense_play("Four Verticals")
		def_call = selected_play as DefensivePlay
	sim = PlaySim.new()
	sim.setup(gs.teams[0], gs.teams[1], off_call, def_call, gs.ball_on, gs.spot_y, gs.situation(), Dice.new(1))
	field.sim = sim
	field.preview = true
	field.ghost_routes = is_offense()
	field.ghost_defense = not is_offense()
	field.flip = false


func _clear_sim() -> void:
	if field != null:
		field.sim = null
	if sim != null:
		sim.dispose()
		sim = null


func _on_play_edited() -> void:
	_draw_play()
	formation_list.rebuild() # the Pass / PA Pass tag can change
	_save()


func _save() -> void:
	PlaybookStore.save(playbook)


# ---------------------------------------------------------------- adding and deleting

func _on_add_play(f: Resource) -> void:
	_adding_to = f
	add_dialog.open(f.name, is_offense())


func _name_problem(n: String) -> String:
	if n == "":
		return "Give the play a name."
	if playbook.has_play(n):
		return "This playbook already has a play called %s." % n
	return ""


func _add_play(play_name: String, is_run: bool, play_action: bool) -> void:
	var f := _adding_to
	var p: Resource
	if not is_offense():
		p = DefensivePlay.blank(play_name, f as DefensiveFormation)
	elif is_run:
		p = RunPlay.make(play_name, "", RunPlay.INSIDE)
	else:
		p = PassPlay.blank(play_name, play_action, f as OffensiveFormation)
	f.add_play(p)
	_save()
	select_play(p)


func _on_delete_play(p: Resource) -> void:
	_ask("Delete %s?" % p.name, func() -> void:
		p.formation.remove_play(p)
		if selected_play == p:
			select_play(null)
		else:
			formation_list.rebuild()
		_save())


func _on_edit_formation(f: Resource) -> void:
	formation_dialog.open(f)


func _rename_formation(f: Resource, new_name: String) -> void:
	f.name = new_name
	formation_list.rebuild()
	_save()


func _on_delete_formation(f: Resource) -> void:
	_ask("Delete %s and its %d plays?" % [f.name, f.plays.size()], func() -> void:
		if selected_play != null and selected_play.formation == f:
			select_play(null)
		_formations().erase(f)
		formation_list.rebuild()
		_save())


## Yes/no confirmation before something that can't be undone.
func _ask(question: String, on_yes: Callable) -> void:
	for c in confirm.confirmed.get_connections():
		confirm.confirmed.disconnect(c["callable"])
	confirm.dialog_text = question
	confirm.confirmed.connect(on_yes, CONNECT_ONE_SHOT)
	confirm.popup_centered()
