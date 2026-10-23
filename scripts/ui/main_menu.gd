extends Control
## Title screen: shows both teams and starts a game.

var main # main.gd

const QUARTER_OPTIONS := [5, 8, 12, 15]


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.custom_minimum_size = Vector2(720, 0)
	center.add_child(col)

	var title := UiStyle.label("AI COLLEGE FOOTBALL", 48, UiStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UiStyle.label("Build the roster. Call the plays. Roll the dice.", 18, UiStyle.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(Control.new())

	col.add_child(_team_card("YOUR TEAM (home)", main.my_team))
	var vs := UiStyle.label("vs", 20, UiStyle.MUTED)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(vs)
	col.add_child(_team_card("OPPONENT (CPU)", main.cpu_team))

	var opts := HBoxContainer.new()
	opts.alignment = BoxContainer.ALIGNMENT_CENTER
	opts.add_theme_constant_override("separation", 10)
	opts.add_child(UiStyle.label("Quarter length:", 16, UiStyle.MUTED))
	var q := OptionButton.new()
	for m in QUARTER_OPTIONS:
		q.add_item("%d minutes" % m)
	q.select(QUARTER_OPTIONS.find(int(main.quarter_minutes)))
	q.item_selected.connect(func(i: int) -> void: main.quarter_minutes = float(QUARTER_OPTIONS[i]))
	opts.add_child(q)
	col.add_child(opts)

	var debug_check := CheckBox.new()
	debug_check.text = "Debug Mode"
	debug_check.tooltip_text = "Click a player in the roster or on the field to edit their ratings and skills. Can also be toggled anytime with F1."
	debug_check.button_pressed = Settings.debug_mode
	debug_check.toggled.connect(Settings.set_debug_mode)
	# Keep the checkbox in sync if debug mode is toggled some other way (e.g. F1) while
	# this menu is up, and stop listening once the menu is gone.
	var sync_check := func(key: String, value: Variant) -> void:
		if key == "debug_mode":
			debug_check.set_pressed_no_signal(value)
	Settings.changed.connect(sync_check)
	tree_exiting.connect(func() -> void: Settings.changed.disconnect(sync_check))
	var debug_row := HBoxContainer.new()
	debug_row.alignment = BoxContainer.ALIGNMENT_CENTER
	debug_row.add_child(debug_check)
	col.add_child(debug_row)

	var play := UiStyle.button("KICK OFF")
	play.custom_minimum_size = Vector2(0, 56)
	play.add_theme_font_size_override("font_size", 22)
	play.pressed.connect(main.show_match)
	col.add_child(play)

	var practice := UiStyle.button("PRACTICE MODE")
	practice.tooltip_text = "No clock, no score. Call a play and a coverage, watch it develop, and run it again from the same spot."
	practice.custom_minimum_size = Vector2(0, 44)
	practice.pressed.connect(main.show_practice)
	col.add_child(practice)

	var playbooks := UiStyle.button("MANAGE PLAYBOOKS")
	playbooks.tooltip_text = "Build your own offensive and defensive playbooks: add plays, pick routes and coverages."
	playbooks.custom_minimum_size = Vector2(0, 44)
	playbooks.pressed.connect(main.show_playbooks)
	col.add_child(playbooks)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var b1 := UiStyle.button("My Roster")
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b1.pressed.connect(func() -> void: main.show_roster(main.my_team))
	var b2 := UiStyle.button("Opponent Roster")
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b2.pressed.connect(func() -> void: main.show_roster(main.cpu_team))
	var b3 := UiStyle.button("New Random Teams")
	b3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b3.pressed.connect(func() -> void:
		main.new_teams()
		main.show_menu())
	row.add_child(b1)
	row.add_child(b2)
	row.add_child(b3)
	col.add_child(row)

	var note := UiStyle.label("Recruiting, the draft, trades and player development come next. For now teams are randomly generated.", 14, UiStyle.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)


func _team_card(caption: String, t: Team) -> Control:
	var panel := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.add_child(UiStyle.color_chip(t.color, 40))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiStyle.label(caption, 13, UiStyle.MUTED))
	v.add_child(UiStyle.label(t.display_name(), 24))
	h.add_child(v)
	var stats := VBoxContainer.new()
	stats.add_child(UiStyle.label("Overall %d" % t.team_overall(), 18, UiStyle.ACCENT))
	h.add_child(stats)
	panel.add_child(h)
	return panel
