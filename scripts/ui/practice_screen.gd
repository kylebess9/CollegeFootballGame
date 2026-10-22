extends Control
## Practice mode: no clock, no score, no downs. Pick an offensive play, then a defensive
## coverage, watch it develop, and the ball resets to the same spot for another rep.
## This is a separate screen from match_screen.gd (not a mode flag on it) since the two
## have very little in common once the clock/score/down machinery is gone.

const FieldView := preload("res://scripts/ui/field_view.gd")
const PlayerEditor := preload("res://scripts/ui/player_editor.gd")
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
var spot_spin: SpinBox
var speed_option: OptionButton

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
		_show_lineup(pending_off) # live-update the preview lineup as the spot changes


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

## Step 1: show offensive plays.
func _begin_rep() -> void:
	_reset_spot()
	state = "calling_off"
	pending_off = ""
	pending_def = ""
	_show_lineup()
	for c in call_buttons.get_children():
		c.queue_free()
	call_title.text = "Pick an offensive play."
	call_hint.text = "Hover a play to see what it does."
	for name in Playbook.offense_names():
		var b := UiStyle.button(name, Playbook.OFFENSE[name]["desc"])
		b.pressed.connect(_offense_called.bind(name))
		_hook_preview(b, name, "")
		call_buttons.add_child(b)


## Step 2: show defensive coverages, now that the offensive play is set.
func _offense_called(call: String) -> void:
	if state != "calling_off":
		return
	pending_off = call
	state = "calling_def"
	_show_lineup(call) # keep the chosen play's routes up while the coverage is picked
	for c in call_buttons.get_children():
		c.queue_free()
	call_title.text = "%s. Pick a defensive coverage." % call
	call_hint.text = "Hover a call to see its strengths."
	for name in Playbook.defense_names():
		var b := UiStyle.button(name, Playbook.DEFENSE[name]["desc"])
		b.pressed.connect(_defense_called.bind(name))
		_hook_preview(b, "", name)
		call_buttons.add_child(b)


func _defense_called(call: String) -> void:
	if state != "calling_def":
		return
	pending_def = call
	for c in call_buttons.get_children():
		c.queue_free()
	_start_play()


## Shows both teams lined up at the ball while a play is being called. With off_play / def_play
## set, the lineup uses that call's design and draws it as a ghost overlay (routes for the
## offense; man lines, zones and blitz arrows for the defense).
func _show_lineup(off_play: String = "", def_play: String = "") -> void:
	var p := PlaySim.new()
	p.setup(gs.offense(), gs.defense(), off_play if off_play != "" else "Inside Run",
		def_play if def_play != "" else "Cover 3", gs.ball_on, gs.spot_y,
		gs.situation(), Dice.new(1))
	if sim != null:
		sim.dispose()
	sim = p
	field.sim = p
	field.preview = true
	field.ghost_routes = off_play != ""
	field.ghost_defense = def_play != ""
	field.flip = false


## Hovering a play button previews it on the field. While the coverage is being picked, the
## chosen offensive play stays drawn so the two can be compared.
func _hook_preview(b: Button, off_play: String, def_play: String) -> void:
	b.mouse_entered.connect(func() -> void:
		if state == "calling_off" or state == "calling_def":
			_show_lineup(off_play if off_play != "" else pending_off, def_play))
	b.mouse_exited.connect(func() -> void:
		if state == "calling_off" or state == "calling_def":
			_show_lineup(pending_off))


func _start_play() -> void:
	if editing:
		_on_edit_closed() # don't let a play start with the debug editor still up
	if sim != null:
		sim.dispose()
	_log_line("\n[color=#f2b134]%s[/color]\n[b]%s[/b] vs [b]%s[/b]" % [gs.field_position_text(), pending_off, pending_def])
	call_title.text = "%s vs %s" % [pending_off, pending_def]
	call_hint.text = "Watching the play..."
	sim = PlaySim.new()
	sim.setup(gs.offense(), gs.defense(), pending_off, pending_def, gs.ball_on, gs.spot_y,
		gs.situation(), dice)
	sim_was_run = Playbook.is_run(pending_off)
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
