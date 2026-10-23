extends Control
## Practice mode: no clock, no score, no downs. Pick an offensive formation and play, then a
## defensive formation and coverage, watch it develop, and the ball resets to the same spot
## for another rep.
## This is a separate screen from match_screen.gd (not a mode flag on it) since the two
## have very little in common once the clock/score/down machinery is gone.

const FieldView := preload("res://scripts/ui/field_view.gd")
const PlayerEditor := preload("res://scripts/ui/player_editor.gd")
const PlayCaller := preload("res://scripts/ui/play_caller.gd")
const SPEEDS := [0.5, 1.0, 2.0, 4.0]
const POST_PLAY_PAUSE := 1.6

var main
var gs: GameState # still used to feed FieldView/PlaySim.setup(), but never scored or advanced
var dice: Dice
var practice_spot := 50.0 # yards from the offense's own goal; the rep resets here every time

var field: FieldView
var side_header: Label
var log_label: RichTextLabel
var hover_label: RichTextLabel
var edit_panel: PlayerEditor
var editing := false # true while the debug player editor is open; suspends hover swapping
var call_title: Label
var call_hint: Label
var call_buttons: HFlowContainer
var caller: PlayCaller
var spot_spin: SpinBox
var speed_option: OptionButton
var redo_button: Button

var sim: PlaySim
var sim_was_run := false
var state := "calling_off" # calling_off, calling_def, playing, post
var speed := 1.0
var accum := 0.0
var post_timer := 0.0
var events_shown := 0
var paused := false
var pending_off := ""
var pending_def := ""
var last_off := "" # the calls of the last rep that ran, for the redo button
var last_def := ""


func _exit_tree() -> void:
	if sim != null:
		sim.dispose()
		sim = null


func _ready() -> void:
	dice = Dice.new()
	gs = GameState.new(main.my_team, main.cpu_team, 1.0, dice)
	_reset_spot()
	_build_ui()
	field.gs = gs
	_log_line("[color=#f2b134][b]PRACTICE MODE[/b][/color]  %s offense vs %s defense." % [
		gs.teams[0].display_name(), gs.teams[1].display_name()])
	_begin_rep()


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
	field.hover_changed.connect(_on_hover_changed)
	field.actor_clicked.connect(_on_actor_clicked)
	mid.add_child(field)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(390, 0)
	mid.add_child(side)
	side_header = UiStyle.label("PLAY-BY-PLAY & DICE", 13, UiStyle.MUTED)
	side.add_child(side_header)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_font_size_override("normal_font_size", 14)
	log_label.add_theme_font_size_override("bold_font_size", 14)
	side.add_child(log_label)
	hover_label = RichTextLabel.new()
	hover_label.bbcode_enabled = true
	hover_label.visible = false
	hover_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hover_label.add_theme_font_size_override("normal_font_size", 14)
	hover_label.add_theme_font_size_override("bold_font_size", 14)
	side.add_child(hover_label)
	edit_panel = PlayerEditor.new()
	edit_panel.visible = false
	edit_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit_panel.saved.connect(_on_edit_saved)
	edit_panel.cancelled.connect(_on_edit_closed)
	side.add_child(edit_panel)
	redo_button = UiStyle.button("Redo Play", "Run the same offensive and defensive calls again")
	redo_button.disabled = true
	redo_button.pressed.connect(_redo_play)
	side.add_child(redo_button)

	root.add_child(_build_call_panel())


## Replaces match_screen's scoreboard: team chips either side, and in the middle -- instead
## of a clock -- the ball-spot picker the player uses to practice from wherever they like.
func _build_header() -> Control:
	var panel := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)
	var home: Team = gs.teams[0]
	var away: Team = gs.teams[1]

	h.add_child(UiStyle.color_chip(home.color, 26))
	h.add_child(UiStyle.label(home.display_name() + "  (OFFENSE)", 18))

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	var spot_row := HBoxContainer.new()
	spot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	spot_row.add_theme_constant_override("separation", 8)
	spot_row.add_child(UiStyle.label("Ball on (yards from own goal):", 14, UiStyle.MUTED))
	spot_spin = SpinBox.new()
	spot_spin.min_value = 1
	spot_spin.max_value = 99
	spot_spin.step = 1
	spot_spin.value = practice_spot
	spot_spin.custom_minimum_size = Vector2(80, 0)
	spot_spin.value_changed.connect(_on_spot_changed)
	spot_row.add_child(spot_spin)
	center.add_child(spot_row)
	h.add_child(center)

	h.add_child(UiStyle.label(away.display_name() + "  (DEFENSE)", 18))
	h.add_child(UiStyle.color_chip(away.color, 26))
	return panel


func _build_call_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 150)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	panel.add_child(h)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	call_title = UiStyle.label("", 18, UiStyle.ACCENT)
	left.add_child(call_title)
	call_hint = UiStyle.label("", 13, UiStyle.MUTED)
	call_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(call_hint)
	call_buttons = HFlowContainer.new()
	call_buttons.add_theme_constant_override("h_separation", 8)
	call_buttons.add_theme_constant_override("v_separation", 8)
	left.add_child(call_buttons)
	caller = PlayCaller.new(call_title, call_hint, call_buttons)
	caller.called.connect(_on_called)
	caller.preview.connect(_on_caller_preview)
	caller.backed_out.connect(_on_backed_out)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(230, 0)
	right.add_theme_constant_override("separation", 8)
	h.add_child(right)
	var sp := HBoxContainer.new()
	sp.add_child(UiStyle.label("Speed ", 14, UiStyle.MUTED))
	speed_option = OptionButton.new()
	for s in SPEEDS:
		speed_option.add_item("%sx" % str(s))
	speed_option.select(1)
	speed_option.item_selected.connect(func(i: int) -> void: speed = SPEEDS[i])
	sp.add_child(speed_option)
	right.add_child(sp)
	var pause := UiStyle.button("Pause")
	pause.toggle_mode = true
	pause.toggled.connect(func(on: bool) -> void:
		paused = on
		pause.text = "Resume" if on else "Pause")
	right.add_child(pause)
	var quit := UiStyle.button("Quit to Menu")
	quit.pressed.connect(main.show_menu)
	right.add_child(quit)
	return panel


func _reset_spot() -> void:
	gs.ball_on = clampf(practice_spot, 1.0, 99.0)
	gs.spot_y = GameState.FIELD_W * 0.5
	gs.down = 1
	gs.to_go = 10
	gs.possession = GameState.HOME


func _on_spot_changed(v: float) -> void:
	practice_spot = v
	_reset_spot()
	if state == "calling_off" or state == "calling_def":
		_on_caller_preview(caller.rest_play(), false) # live-update the preview lineup as the spot changes


func _log_line(bb: String) -> void:
	log_label.append_text(bb + "\n")


## Swaps the play-by-play panel for a player's stats and skills while the mouse is over them
## on the field, and swaps it back as soon as it isn't. Suspended while the debug editor
## (opened by clicking a player) is up, so a stray hover elsewhere doesn't hide it.
func _on_hover_changed(actor: SimActor) -> void:
	if editing:
		return
	if actor == null:
		hover_label.visible = false
		log_label.visible = true
		side_header.text = "PLAY-BY-PLAY & DICE"
		return
	hover_label.text = _player_card_bbcode(actor)
	hover_label.visible = true
	log_label.visible = false
	side_header.text = "PLAYER INFO"


## Debug mode only: clicking a player on the field opens the ratings/skills editor.
func _on_actor_clicked(actor: SimActor) -> void:
	if not Settings.debug_mode or actor == null:
		return
	editing = true
	edit_panel.setup(actor.player)
	edit_panel.visible = true
	hover_label.visible = false
	log_label.visible = false
	side_header.text = "EDIT PLAYER (DEBUG)"


func _on_edit_saved() -> void:
	_on_edit_closed()


func _on_edit_closed() -> void:
	editing = false
	edit_panel.visible = false
	log_label.visible = true
	side_header.text = "PLAY-BY-PLAY & DICE"


func _player_card_bbcode(a: SimActor) -> String:
	var p: FootballPlayer = a.player
	var team: Team = sim.off_team if a.side == SimActor.Side.OFFENSE else sim.def_team
	var s := "[color=#f2b134][b]%s[/b][/color]  [color=#8a96a8]%s[/color]\n" % [p.full_name(), team.abbrev]
	s += "%s · #%d · %s · Overall [color=#f2b134][b]%d[/b][/color]\n\n" % [a.slot, p.number, p.year_label(), p.overall()]
	for attr in FootballPlayer.ATTRS:
		s += "[b]%s[/b] (%s): %d\n" % [FootballPlayer.ATTR_NAMES[attr], attr.to_upper(), p.r(attr)]
	if not p.skills.is_empty():
		s += "\n[color=#f2b134][b]Skills[/b][/color]\n"
		for sk in p.skills:
			s += "[b]%s[/b]: %s\n" % [sk, FootballPlayer.SKILLS[sk]]
	return s


# ---------------------------------------------------------------- rep flow

## Step 1: the offense picks a formation, then a play in it.
func _begin_rep() -> void:
	_reset_spot()
	state = "calling_off"
	pending_off = ""
	pending_def = ""
	caller.back_text = ""
	caller.start(gs.offense_playbook(), Playbook.OFFENSE, "OFFENSE.")


## Step 2: the defense picks a formation, then a call in it, now that the offensive play is
## set. Its formation list has a back button to change the offensive play.
func _offense_called(call: String) -> void:
	if state != "calling_off":
		return
	pending_off = call
	state = "calling_def"
	caller.back_text = "< Change offense play"
	caller.start(gs.defense_playbook(), Playbook.DEFENSE, "DEFENSE vs %s." % call)


func _defense_called(call: String) -> void:
	if state != "calling_def":
		return
	pending_def = call
	_start_play()


func _on_called(call: String) -> void:
	if state == "calling_off":
		_offense_called(call)
	elif state == "calling_def":
		_defense_called(call)


func _on_backed_out() -> void:
	if state == "calling_def":
		_begin_rep()


## Shows both teams lined up at the ball while a play is being called, in these plays'
## formations (each playbook's first play when empty). ghost_off / ghost_def also draw the
## play itself as an overlay (routes for the offense; man lines, zones and blitz arrows for
## the defense).
func _show_lineup(off_play: String = "", def_play: String = "", ghost_off := false, ghost_def := false) -> void:
	var p := PlaySim.new()
	p.setup(gs.offense(), gs.defense(),
		gs.offense_playbook().offense_play_or_first(off_play),
		gs.defense_playbook().defense_play_or_first(def_play), gs.ball_on, gs.spot_y,
		gs.situation(), Dice.new(1))
	if sim != null:
		sim.dispose()
	sim = p
	field.sim = p
	field.preview = true
	field.ghost_routes = ghost_off
	field.ghost_defense = ghost_def
	field.flip = false


## Hovering a formation or play previews it on the field. While the defense is calling, the
## chosen offensive play stays drawn so the two can be compared.
func _on_caller_preview(play_name: String, ghost: bool) -> void:
	if state == "calling_off":
		_show_lineup(play_name, "", ghost, false)
	elif state == "calling_def":
		_show_lineup(pending_off, play_name, true, ghost)


func _start_play() -> void:
	if editing:
		_on_edit_closed() # don't let a play start with the debug editor still up
	if sim != null:
		sim.dispose()
	last_off = pending_off
	last_def = pending_def
	redo_button.disabled = true
	_log_line("\n[color=#f2b134]%s[/color]\n[b]%s[/b] vs [b]%s[/b]" % [gs.field_position_text(), pending_off, pending_def])
	call_title.text = "%s vs %s" % [pending_off, pending_def]
	call_hint.text = "Watching the play..."
	sim = PlaySim.new()
	sim.setup(gs.offense(), gs.defense(), gs.offense_play(pending_off), gs.defense_play(pending_def),
		gs.ball_on, gs.spot_y, gs.situation(), dice)
	sim_was_run = gs.offense_playbook().is_run(pending_off)
	field.preview = false
	events_shown = 0
	accum = 0.0
	field.sim = sim
	field.flip = false
	state = "playing"


func _process(delta: float) -> void:
	if paused:
		return
	match state:
		"playing":
			accum += delta * speed
			while accum >= PlaySim.DT and not sim.done:
				accum -= PlaySim.DT
				sim.step()
			_flush_events()
			if sim.done:
				_finish_play()
		"post":
			post_timer -= delta * maxf(1.0, speed * 0.5)
			if post_timer <= 0.0:
				if sim != null:
					field.sim = null
					sim.dispose()
					sim = null
				_begin_rep() # back to step 1, ball reset to the chosen spot


func _flush_events() -> void:
	while events_shown < sim.events.size():
		var e: Dictionary = sim.events[events_shown]
		events_shown += 1
		var ok: int = e["ok"]
		# Green = good for the offense, red = good for the defense.
		var col := "#e6eaf0"
		if ok == 1:
			col = "#5fd38a"
		elif ok == 0:
			col = "#ff6b6b"
		var line := "  [color=%s]• %s[/color]" % [col, e["text"]]
		if str(e["detail"]) != "":
			line += "\n[indent][color=#8a96a8]%s[/color][/indent]" % e["detail"]
		_log_line(line)
		if str(e["short"]) != "":
			var pc := UiStyle.TEXT
			if ok == 1:
				pc = UiStyle.GOOD
			elif ok == 0:
				pc = UiStyle.BAD
			field.add_popup(e["short"], e["pos"], pc)


## Unlike a real game, nothing here is scored or advanced -- just logged, then reset.
func _finish_play() -> void:
	var res := sim.result
	var kind: String = res["kind"]
	var yards: int = res["yards"]
	var verb := {"td": "TOUCHDOWN", "def_td": "Defensive touchdown", "safety": "Safety",
		"int": "INTERCEPTED", "fumble": "Fumble lost", "tackle": "Tackled after %d" % yards,
		"oob": "Out of bounds after %d" % yards, "sack": "Sacked for %d" % yards,
		"incomplete": "Incomplete"}
	_log_line("   [b]%s[/b]" % verb.get(kind, "Gain of %d" % yards))
	state = "post"
	post_timer = POST_PLAY_PAUSE
	redo_button.disabled = false


## Runs the last rep's calls again from the chosen spot, skipping both play calls. Works
## during the post-play pause too, or once the call panel is back up.
func _redo_play() -> void:
	if state == "playing" or last_off == "":
		return
	_reset_spot()
	caller.clear()
	pending_off = last_off
	pending_def = last_def
	_start_play()
