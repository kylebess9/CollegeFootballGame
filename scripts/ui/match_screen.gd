extends Control
## One game. You coach the home team: call plays on offense and defense,
## watch them play out, and read every dice roll in the log.

const FieldView := preload("res://scripts/ui/field_view.gd")
const PlayerEditor := preload("res://scripts/ui/player_editor.gd")
const SPEEDS := [0.5, 1.0, 2.0, 4.0]
const POST_PLAY_PAUSE := 1.6

var main
var gs: GameState
var dice: Dice
var rng := RandomNumberGenerator.new()
var me := GameState.HOME

var field: FieldView
var side_header: Label
var log_label: RichTextLabel
var hover_label: RichTextLabel
var edit_panel: PlayerEditor
var editing := false # true while the debug player editor is open; suspends hover swapping
var call_title: Label
var call_hint: Label
var call_buttons: HFlowContainer
var auto_check: CheckBox
var speed_option: OptionButton
var score_home: Label
var score_away: Label
var clock_label: Label
var down_label: Label
var poss_home: Label
var poss_away: Label
var final_panel: PanelContainer

var sim: PlaySim
var sim_was_run := false
var sim_off_is_me := false
var state := "calling" # calling, playing, post, over
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
	rng.randomize()
	dice = Dice.new()
	gs = GameState.new(main.my_team, main.cpu_team, main.quarter_minutes, dice)
	_build_ui()
	field.gs = gs
	_log_line("[color=#f2b134][b]KICKOFF[/b][/color]  %s vs %s. %s receives. Touchback at the 25." % [
		gs.teams[0].display_name(), gs.teams[1].display_name(), gs.offense().school])
	_begin_snap()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var m := UiStyle.margin(root, 10)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	root.add_child(_build_scoreboard())

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

	final_panel = PanelContainer.new()
	final_panel.visible = false
	final_panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(final_panel)


func _build_scoreboard() -> Control:
	var panel := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)
	var home: Team = gs.teams[0]
	var away: Team = gs.teams[1]

	poss_home = UiStyle.label("●", 18, UiStyle.ACCENT)
	h.add_child(poss_home)
	h.add_child(UiStyle.color_chip(home.color, 26))
	var hv := VBoxContainer.new()
	hv.add_child(UiStyle.label(home.display_name() + "  (YOU)", 18))
	h.add_child(hv)
	score_home = UiStyle.label("0", 36, UiStyle.TEXT)
	h.add_child(score_home)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_label = UiStyle.label("", 22, UiStyle.ACCENT)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	down_label = UiStyle.label("", 16)
	down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(clock_label)
	center.add_child(down_label)
	h.add_child(center)

	score_away = UiStyle.label("0", 36, UiStyle.TEXT)
	h.add_child(score_away)
	var av := VBoxContainer.new()
	var an := UiStyle.label(away.display_name() + "  (CPU)", 18)
	an.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	av.add_child(an)
	h.add_child(av)
	h.add_child(UiStyle.color_chip(away.color, 26))
	poss_away = UiStyle.label("●", 18, UiStyle.ACCENT)
	h.add_child(poss_away)
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
	auto_check = CheckBox.new()
	auto_check.text = "Auto-call my plays"
	auto_check.tooltip_text = "Let the AI call your plays too, so you can just watch."
	auto_check.toggled.connect(func(_on: bool) -> void:
		if state == "calling":
			_begin_snap())
	right.add_child(auto_check)
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


func _refresh_scoreboard() -> void:
	score_home.text = str(gs.score[0])
	score_away.text = str(gs.score[1])
	clock_label.text = gs.clock_text() if not gs.over else "FINAL"
	down_label.text = "" if gs.over else "%s ball: %s" % [gs.offense().abbrev, gs.down_text()]
	poss_home.modulate.a = 1.0 if gs.possession == 0 and not gs.over else 0.0
	poss_away.modulate.a = 1.0 if gs.possession == 1 and not gs.over else 0.0


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


# ---------------------------------------------------------------- game flow

func _begin_snap() -> void:
	_refresh_scoreboard()
	if gs.over:
		_show_final()
		return
	state = "calling"
	pending_off = ""
	pending_def = ""
	_show_lineup()
	for c in call_buttons.get_children():
		c.queue_free()
	var on_offense := gs.possession == me
	# The CPU decides first. If it punts or kicks, the user has nothing to call.
	if not on_offense:
		pending_off = CoachAI.pick_offense(gs, rng)
		if gs.offense_playbook().is_kick(pending_off):
			call_title.text = "%s: %s" % [gs.offense().school, pending_off]
			call_hint.text = ""
			_run_special(pending_off)
			return
	else:
		pending_def = CoachAI.pick_defense(gs, rng)

	if auto_check.button_pressed:
		call_title.text = "Auto-calling..."
		call_hint.text = ""
		var pick := CoachAI.pick_offense(gs, rng) if on_offense else CoachAI.pick_defense(gs, rng)
		get_tree().create_timer(0.25).timeout.connect(func() -> void:
			if is_inside_tree() and state == "calling":
				_user_called(pick))
		return

	if on_offense:
		call_title.text = "YOUR OFFENSE: %s. Call a play." % gs.down_text()
		call_hint.text = "Hover a play to see what it does. The CPU has already picked its defense."
		var pb := gs.offense_playbook()
		for name in pb.offense_names():
			var b := UiStyle.button(name, pb.offense_play(name).description)
			b.pressed.connect(_user_called.bind(name))
			_hook_preview(b, name, "")
			call_buttons.add_child(b)
		var punt := pb.kick(Playbook.SPECIAL_PUNT)
		var kb := UiStyle.button(punt.name, punt.description)
		kb.pressed.connect(_user_called.bind(punt.name))
		call_buttons.add_child(kb)
		var t := gs.fg_target()
		var fg_text := "Field Goal (%d yds, %s)" % [gs.fg_distance(), "out of range" if t >= 7 else "%d+" % Dice.clamp_target(t)]
		var fg := pb.kick(Playbook.SPECIAL_FG)
		var fb := UiStyle.button(fg_text, fg.description)
		fb.pressed.connect(_user_called.bind(fg.name))
		call_buttons.add_child(fb)
	else:
		call_title.text = "YOUR DEFENSE: %s has %s. Call a coverage." % [gs.offense().school, gs.down_text()]
		call_hint.text = "Hover a call to see its strengths. The CPU has already picked its play."
		var dpb := gs.defense_playbook()
		for name in dpb.defense_names():
			var b := UiStyle.button(name, dpb.defense_play(name).description)
			b.pressed.connect(_user_called.bind(name))
			_hook_preview(b, "", name)
			call_buttons.add_child(b)


## Shows both teams lined up at the ball while a play is being called. With off_play / def_play
## set, the lineup uses that call's design and draws it as a ghost overlay (routes for the
## offense; man lines, zones and blitz arrows for the defense).
func _show_lineup(off_play: String = "", def_play: String = "") -> void:
	var p := PlaySim.new()
	p.setup(gs.offense(), gs.defense(), gs.offense_play(off_play if off_play != "" else "Inside Run"),
		gs.defense_play(def_play if def_play != "" else "Cover 3"), gs.ball_on, gs.spot_y,
		gs.situation(), Dice.new(1))
	if sim != null:
		sim.dispose()
	sim = p
	field.sim = p
	field.preview = true
	field.ghost_routes = off_play != ""
	field.ghost_defense = def_play != ""
	field.flip = gs.possession == GameState.AWAY


## Hovering a play button previews it on the field. Only the user's own call is ever drawn;
## the CPU's call stays hidden behind the neutral placeholder lineup.
func _hook_preview(b: Button, off_play: String, def_play: String) -> void:
	b.mouse_entered.connect(func() -> void:
		if state == "calling":
			_show_lineup(off_play, def_play))
	b.mouse_exited.connect(func() -> void:
		if state == "calling" and (field.ghost_routes or field.ghost_defense):
			_show_lineup())


func _user_called(call: String) -> void:
	if state != "calling":
		return
	for c in call_buttons.get_children():
		c.queue_free()
	if gs.possession == me:
		pending_off = call
	else:
		pending_def = call
	if gs.offense_playbook().is_kick(pending_off):
		_run_special(pending_off)
		return
	_start_play()


func _run_special(call: String) -> void:
	state = "post"
	_log_play_header(call, "")
	var lines := gs.run_punt() if gs.offense_playbook().kick(call).kind == KickPlay.PUNT else gs.run_field_goal()
	for l in lines:
		_log_line("   [b]%s[/b]" % l)
	field.sim = null
	if sim != null:
		sim.dispose()
		sim = null
	post_timer = POST_PLAY_PAUSE
	_refresh_scoreboard()


func _log_play_header(off_call: String, def_call: String) -> void:
	var who := gs.offense().abbrev
	var calls := "[b]%s[/b]" % off_call
	if def_call != "":
		calls += " vs [b]%s[/b]" % def_call
	_log_line("\n[color=#f2b134]%s | %s %s[/color]\n%s" % [gs.clock_text(), who, gs.down_text(), calls])


func _start_play() -> void:
	if editing:
		_on_edit_closed() # don't let a play start with the debug editor still up
	if sim != null:
		sim.dispose()
	_log_play_header(pending_off, pending_def)
	call_title.text = "%s vs %s" % [pending_off, pending_def]
	call_hint.text = "Watching the play..."
	sim = PlaySim.new()
	sim.setup(gs.offense(), gs.defense(), gs.offense_play(pending_off), gs.defense_play(pending_def),
		gs.ball_on, gs.spot_y, gs.situation(), dice)
	sim_was_run = gs.offense_playbook().is_run(pending_off)
	sim_off_is_me = gs.possession == me
	field.preview = false
	events_shown = 0
	accum = 0.0
	field.sim = sim
	field.flip = gs.possession == GameState.AWAY
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
				_begin_snap()


func _flush_events() -> void:
	while events_shown < sim.events.size():
		var e: Dictionary = sim.events[events_shown]
		events_shown += 1
		var ok: int = e["ok"]
		# Green = good for you, red = bad for you, whichever side of the ball you're on.
		var mine := -1
		if ok >= 0:
			mine = 1 if (ok == 1) == sim_off_is_me else 0
		var col := "#e6eaf0"
		if mine == 1:
			col = "#5fd38a"
		elif mine == 0:
			col = "#ff6b6b"
		var line := "  [color=%s]• %s[/color]" % [col, e["text"]]
		if str(e["detail"]) != "":
			line += "\n[indent][color=#8a96a8]%s[/color][/indent]" % e["detail"]
		_log_line(line)
		if str(e["short"]) != "":
			var pc := UiStyle.TEXT
			if mine == 1:
				pc = UiStyle.GOOD
			elif mine == 0:
				pc = UiStyle.BAD
			field.add_popup(e["short"], e["pos"], pc)


func _finish_play() -> void:
	var lines := gs.apply_play(sim.result, sim_was_run)
	for l in lines:
		_log_line("   [b]%s[/b]" % l)
	state = "post"
	post_timer = POST_PLAY_PAUSE
	_refresh_scoreboard()


func _show_final() -> void:
	state = "over"
	call_title.text = "FINAL"
	call_hint.text = ""
	_log_line("\n[color=#f2b134][b]FINAL: %s %d, %s %d[/b][/color]" % [gs.teams[0].school, gs.score[0], gs.teams[1].school, gs.score[1]])
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var won := gs.score[0] > gs.score[1]
	var tie := gs.score[0] == gs.score[1]
	var head := UiStyle.label("TIE GAME" if tie else ("YOU WIN!" if won else "YOU LOSE"), 34,
		UiStyle.ACCENT if won or tie else UiStyle.BAD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var sc := UiStyle.label("%s %d  -  %d %s" % [gs.teams[0].abbrev, gs.score[0], gs.score[1], gs.teams[1].abbrev], 26)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 30)
	for row in [["", gs.teams[0].abbrev, gs.teams[1].abbrev],
			["Total yards", str(gs.stats[0]["yards"]), str(gs.stats[1]["yards"])],
			["Passing", str(gs.stats[0]["pass_yds"]), str(gs.stats[1]["pass_yds"])],
			["Rushing", str(gs.stats[0]["rush_yds"]), str(gs.stats[1]["rush_yds"])],
			["First downs", str(gs.stats[0]["first_downs"]), str(gs.stats[1]["first_downs"])],
			["Turnovers", str(gs.stats[0]["turnovers"]), str(gs.stats[1]["turnovers"])],
			["Plays", str(gs.stats[0]["plays"]), str(gs.stats[1]["plays"])]]:
		for i in 3:
			grid.add_child(UiStyle.label(row[i], 16, UiStyle.MUTED if i == 0 else UiStyle.TEXT))
	v.add_child(grid)
	var b := UiStyle.button("Back to Menu")
	b.pressed.connect(main.show_menu)
	v.add_child(b)
	final_panel.add_child(UiStyle.margin(v, 20))
	final_panel.visible = true
	final_panel.custom_minimum_size = Vector2(420, 0)
	final_panel.position = (size - Vector2(420, 400)) * 0.5
	_refresh_scoreboard()
