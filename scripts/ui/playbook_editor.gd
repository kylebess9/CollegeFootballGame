extends Control
## Edit one playbook. Laid out like match_screen / practice_screen, with two views:
##   Edit playbook  - the playbook's name in the top left, the field in the middle showing
##                    the selected play's art, the formations and their plays on the right,
##                    and the selected play's options along the bottom. Clicking a route
##                    runner on the field lets his route be reshaped for that play alone.
##                    Run Play plays the selected play out on the field, against the other
##                    side's stock play picked next to it: a defense (or None, for no
##                    defenders at all, the default) for an offensive play, an offensive play
##                    for a defensive one. Hovering that picker draws the other side's play too.
##   Edit formation - the formation builder: a close-up field to drag players around on,
##                    the players still to place along the bottom, and whether the
##                    formation is legal on the right.
## Every change to a play is saved straight away; a formation is saved when the builder's
## Save is pressed. Custom routes and run paths can be further views of this screen.

const FieldView := preload("res://scripts/ui/field_view.gd")
const FormationList := preload("res://scripts/ui/playbook/formation_list.gd")
const PlayOptions := preload("res://scripts/ui/playbook/play_options.gd")
const AddPlayDialog := preload("res://scripts/ui/playbook/add_play_dialog.gd")
const NewFormationDialog := preload("res://scripts/ui/playbook/new_formation_dialog.gd")
const FormationPanel := preload("res://scripts/ui/playbook/formation_panel.gd")
const PlayerTray := preload("res://scripts/ui/playbook/player_tray.gd")
const RouteEditor := preload("res://scripts/ui/playbook/route_editor.gd")
## Where the ball sits for the play art, in yards from the offense's own goal.
const PREVIEW_SPOT := 40.0
## How long a run play's end stays on the field before the play art comes back (seconds).
const AFTER_RUN := 1.6

var main
var playbook: Playbook
var selected_play: Resource = null # OffensivePlay or DefensivePlay
var _adding_to: Resource = null
var _highlight_slot := "" # the player whose drop-down the mouse is over # the formation the add-play dialog is open for

var gs: GameState # only feeds FieldView/PlaySim the two teams and the ball spot
var field: FieldView
var route_overlay: PlayRouteOverlay
var formation_list: FormationList
var options: PlayOptions
var add_dialog: AddPlayDialog
var new_formation_dialog: NewFormationDialog
var view_title: Label
## Edit playbook view.
var playbook_view: Array[Control] = []
## Edit formation view.
var formation_view: Array[Control] = []
var board: FormationBoard
var formation_panel: FormationPanel
var tray: PlayerTray
var draft: FormationDraft = null # the formation being built, while the builder is open
var editing_formation: Resource = null # the formation the draft came from; null for a new one
var confirm: ConfirmationDialog
var route_editor: RouteEditor
var sim: PlaySim
## The opposite side's play the preview lines up against, from the stock playbook.
var stock := Playbook.make_default()
## The other side's stock play to line up against, picked in the header.
var opponent_pick: OptionButton
var _opponents: Array[Resource] = [] # one per item of opponent_pick
## While the mouse is over the picker: its item to line up against instead of the picked one
## (-1 for the picked one), with the other side's art drawn too.
var _preview_index := -1
var _show_opponent := false
## The "None" defense: a formation with nobody in it, kept here since plays hold it weakly.
var _no_defense_formation := DefensiveFormation.make("None", [] as Array[FormationSpot])
var _no_defense := _no_defense_formation.add_play(DefensivePlay.make("None", "", [] as Array[CoverageAssignment]))
var run_button: Button
## While Run Play is playing: the sim steps in _process, then the play art comes back.
var running := false
var _accum := 0.0
var _after := 0.0
var _events_shown := 0


func _exit_tree() -> void:
	_clear_sim()


func _ready() -> void:
	gs = GameState.new(main.my_team, main.cpu_team, 1.0, Dice.new(1))
	gs.possession = GameState.HOME # the offense attacks to the right, where the sim lines it up
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
	route_overlay = PlayRouteOverlay.new()
	route_overlay.field = field
	route_overlay.changed.connect(_on_route_drawn)
	route_overlay.customized.connect(func() -> void: options.show_play(selected_play)) # "Custom"
	field.add_child(route_overlay)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(390, 0)
	mid.add_child(side)
	board = FormationBoard.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.changed.connect(_on_draft_changed)
	mid.add_child(board)
	formation_panel = FormationPanel.new()
	formation_panel.custom_minimum_size = Vector2(390, 0)
	formation_panel.extra_problems = _formation_name_problems
	formation_panel.changed.connect(_on_draft_changed)
	formation_panel.save_requested.connect(_save_formation)
	formation_panel.cancel_requested.connect(_close_builder)
	formation_panel.delete_requested.connect(func() -> void: _on_delete_formation(editing_formation))
	mid.add_child(formation_panel)
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
	var add_formation := UiStyle.button("+  Add Formation")
	add_formation.add_theme_color_override("font_color", UiStyle.GOOD)
	add_formation.pressed.connect(func() -> void: new_formation_dialog.open(is_offense()))
	side.add_child(add_formation)

	var bottom := PanelContainer.new()
	bottom.custom_minimum_size = Vector2(0, 150)
	options = PlayOptions.new()
	options.playbook = playbook
	options.changed.connect(_on_play_edited)
	options.player_hovered.connect(_highlight_player)
	bottom.add_child(options)
	root.add_child(bottom)
	var tray_panel := PanelContainer.new()
	tray = PlayerTray.new()
	tray.board = board
	tray.changed.connect(_on_draft_changed)
	tray_panel.add_child(tray)
	root.add_child(tray_panel)

	playbook_view.assign([field, side, bottom])
	formation_view.assign([board, formation_panel, tray_panel])
	_show_view(false)

	add_dialog = AddPlayDialog.new()
	add_dialog.check_name = _name_problem
	add_dialog.submitted.connect(_add_play)
	add_child(add_dialog)
	new_formation_dialog = NewFormationDialog.new()
	new_formation_dialog.check_name = _new_formation_name_problem
	new_formation_dialog.submitted.connect(_on_new_formation)
	add_child(new_formation_dialog)
	confirm = ConfirmationDialog.new()
	add_child(confirm)
	route_editor = RouteEditor.new()
	route_editor.routes_changed.connect(_save)
	# Plays running an edited route have been updated; show them as they are now.
	route_editor.visibility_changed.connect(func() -> void:
		if not route_editor.visible:
			options.show_play(selected_play)
			_draw_play())
	add_child(route_editor)


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

	view_title = UiStyle.label("", 18, UiStyle.ACCENT)
	view_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(view_title)

	run_button = UiStyle.button("Run Play")
	run_button.tooltip_text = "Play the selected play out on the field."
	run_button.disabled = true # until a play is picked
	run_button.pressed.connect(run_play)
	h.add_child(run_button)
	h.add_child(_build_opponent_pick())
	if is_offense():
		var routes := UiStyle.button("Playbook Routes")
		routes.tooltip_text = "See the stock routes and draw this playbook's own."
		routes.pressed.connect(func() -> void: route_editor.open(playbook))
		h.add_child(routes)
	var back := UiStyle.button("Back to Playbooks")
	back.pressed.connect(main.show_playbooks)
	h.add_child(back)
	return panel


## The other side's stock plays. Offense lines up against None (no defenders) by default or a
## stock defensive call; defense against a stock offensive play, Four Verticals by default.
## The pick stays as the user moves between plays.
func _build_opponent_pick() -> OptionButton:
	opponent_pick = OptionButton.new()
	if is_offense():
		opponent_pick.tooltip_text = "The defense the play lines up and runs against. None takes every defender off the field."
		opponent_pick.add_item("Defense: None")
		_opponents.append(_no_defense)
		for f in stock.defensive_formations:
			for p in f.plays:
				opponent_pick.add_item("%s: %s" % [f.name, p.name])
				_opponents.append(p)
	else:
		opponent_pick.tooltip_text = "The offensive play the defense lines up and runs against."
		for f in stock.offensive_formations:
			for p in f.plays:
				opponent_pick.add_item("%s: %s" % [f.name, p.name])
				_opponents.append(p)
	opponent_pick.select(maxi(0, _opponents.find(stock.offense_play("Four Verticals"))) if not is_offense() else 0)
	opponent_pick.item_selected.connect(func(_i: int) -> void: _draw_play())
	# Hovering the picker (or an item in its open list) draws that play's art as well.
	var popup := opponent_pick.get_popup()
	opponent_pick.mouse_entered.connect(func() -> void: preview_opponent(-1, true))
	opponent_pick.mouse_exited.connect(func() -> void:
		if not popup.visible:
			preview_opponent(-1, false))
	popup.id_focused.connect(func(id: int) -> void: preview_opponent(popup.get_item_index(id), true))
	popup.popup_hide.connect(func() -> void: preview_opponent(-1, false))
	return opponent_pick


## Lines the selected play up against the picker's item `index` (-1: the picked one) and
## draws the other side's art too while `show` is on. Leaves a running play alone.
func preview_opponent(index: int, show: bool) -> void:
	if running or (index == _preview_index and show == _show_opponent):
		return
	_preview_index = index
	_show_opponent = show
	_draw_play()


# ---------------------------------------------------------------- selecting and drawing plays

func select_play(p: Resource) -> void:
	selected_play = p
	route_overlay.select("")
	formation_list.select(p)
	options.show_play(p)
	_draw_play()


## Lines the selected play up on the field against a stock play from the other side and
## draws its art: routes and run paths on offense, zones, man lines and blitzes on defense.
func _draw_play() -> void:
	running = false
	_clear_sim()
	run_button.disabled = selected_play == null or not selected_play.validate().is_empty()
	if selected_play == null:
		route_overlay.attach(null, null)
		return
	_line_up(Dice.new(1))
	field.preview = true
	field.ghost_routes = is_offense() or _show_opponent
	field.ghost_defense = not is_offense() or _show_opponent
	field.flip = false
	route_overlay.attach(selected_play, sim)
	_highlight_player(_highlight_slot) # keep pointing him out after an edit redraws the play


## A new sim of the selected play against the other side's call, shown on the field.
func _line_up(dice: Dice) -> void:
	var opp := opponent_play(_preview_index)
	var off_call: OffensivePlay = selected_play if is_offense() else opp
	var def_call: DefensivePlay = opp if is_offense() else selected_play
	sim = PlaySim.new()
	sim.setup(gs.teams[0], gs.teams[1], off_call, def_call, gs.ball_on, gs.spot_y, gs.situation(), dice)
	field.sim = sim


## The other side's play at the picker's item `index`, or the picked one for -1.
func opponent_play(index := -1) -> Resource:
	return _opponents[index if index >= 0 else opponent_pick.selected]


## Plays the selected play out from the snap. The dice are fresh each time, so it can go
## differently run to run, as in a game.
func run_play() -> void:
	if selected_play == null or run_button.disabled:
		return
	_preview_index = -1
	_show_opponent = false
	_clear_sim()
	route_overlay.attach(null, null) # nothing to edit while players move
	_line_up(Dice.new(randi()))
	field.preview = false
	running = true
	_accum = 0.0
	_after = AFTER_RUN
	_events_shown = 0


func _process(delta: float) -> void:
	if not running or sim == null:
		return
	if not sim.done:
		_accum += delta
		while _accum >= PlaySim.DT and not sim.done:
			_accum -= PlaySim.DT
			sim.step()
		_show_events()
		return
	_after -= delta
	if _after <= 0.0:
		_draw_play() # back to the play art


## The play's moments (catches, tackles...) as pop-ups on the field, as in practice.
func _show_events() -> void:
	while _events_shown < sim.events.size():
		var e: Dictionary = sim.events[_events_shown]
		_events_shown += 1
		if str(e["short"]) != "":
			var ok: int = e["ok"]
			field.add_popup(e["short"], e["pos"], UiStyle.GOOD if ok == 1 else (UiStyle.BAD if ok == 0 else UiStyle.TEXT))


## Points out the player whose drop-down the mouse is over.
func _highlight_player(slot: String) -> void:
	_highlight_slot = slot
	var key := ("O:" if is_offense() else "D:") + slot
	field.highlighted = sim.slots.get(key) if sim != null and slot != "" else null


func _clear_sim() -> void:
	if field != null:
		field.sim = null
		field.highlighted = null
	if sim != null:
		sim.dispose()
		sim = null


func _on_play_edited() -> void:
	_draw_play()
	formation_list.rebuild() # the Pass / PA Pass tag can change
	_save()


## A route reshaped on the field: the play holds it, so just redraw and save.
func _on_route_drawn() -> void:
	_draw_play()
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


func _on_delete_formation(f: Resource) -> void:
	_ask("Delete %s and its %d plays?" % [f.name, f.plays.size()], func() -> void:
		if selected_play != null and selected_play.formation == f:
			select_play(null)
		_formations().erase(f)
		_close_builder()
		_save())


## Yes/no confirmation before something that can't be undone.
func _ask(question: String, on_yes: Callable) -> void:
	for c in confirm.confirmed.get_connections():
		confirm.confirmed.disconnect(c["callable"])
	confirm.dialog_text = question
	confirm.confirmed.connect(on_yes, CONNECT_ONE_SHOT)
	confirm.popup_centered()


# ---------------------------------------------------------------- formation builder

func in_builder() -> bool:
	return draft != null


## Switches between the edit playbook view and the formation builder.
func _show_view(building: bool) -> void:
	for c in playbook_view:
		c.visible = not building
	for c in formation_view:
		c.visible = building
	var side_name := "OFFENSE" if is_offense() else "DEFENSE"
	view_title.text = "%s  ·  %s" % ["EDIT FORMATION" if building else "EDIT PLAYBOOK", side_name]


func _open_builder(d: FormationDraft, from: Resource) -> void:
	draft = d
	editing_formation = from
	board.draft = d
	tray.draft = d
	formation_panel.edit(d, from != null)
	_show_view(true)
	_on_draft_changed()


func _close_builder() -> void:
	draft = null
	editing_formation = null
	board.draft = null
	tray.draft = null
	_show_view(false)
	formation_list.rebuild()
	_draw_play()


func _on_draft_changed() -> void:
	formation_panel.refresh()
	board.queue_redraw()
	tray.queue_redraw()


func _new_formation_name_problem(n: String) -> String:
	if n == "":
		return "Give the formation a name."
	if _formation_named(n, null) != null:
		return "This playbook already has a formation called %s." % n
	return ""


func _formation_name_problems() -> Array[String]:
	var errs: Array[String] = []
	if draft != null and _formation_named(draft.name, editing_formation) != null:
		errs.append("This playbook already has a formation called %s." % draft.name)
	return errs


func _formation_named(n: String, except: Resource) -> Resource:
	for f in _formations():
		if f != except and f.name == n:
			return f
	return null


func _on_new_formation(formation_name: String, counts: Dictionary) -> void:
	_open_builder(FormationDraft.create(formation_name, is_offense(), counts), null)


func _on_edit_formation(f: Resource) -> void:
	_open_builder(FormationDraft.from_formation(f), f)


func _save_formation() -> void:
	if not formation_panel.problems().is_empty():
		return
	if editing_formation != null:
		draft.apply_to(editing_formation)
	else:
		_formations().append(draft.to_formation())
	_save()
	_close_builder()
	options.show_play(selected_play) # the play's checks may change with the formation
