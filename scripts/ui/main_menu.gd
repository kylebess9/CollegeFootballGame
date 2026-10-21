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

	var play := UiStyle.button("KICK OFF")
	play.custom_minimum_size = Vector2(0, 56)
	play.add_theme_font_size_override("font_size", 22)
	play.pressed.connect(main.show_match)
	col.add_child(play)

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
