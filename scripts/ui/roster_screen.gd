extends Control
## Roster table with every rating and skill, plus a legend explaining what each one does.
## The bar above the table picks the offensive and defensive playbooks the team uses in games
## and practice.
## In debug mode, clicking a player opens an editor for their ratings and skills instead.

const PlayerEditor := preload("res://scripts/ui/player_editor.gd")

var main
var team: Team
var tree: Tree
var legend: RichTextLabel
var edit_panel: PlayerEditor
var _item_players := {} # TreeItem -> FootballPlayer

const POS_ORDER := ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S", "K"]
const COLS := ["Pos", "#", "Name", "Yr", "OVR", "SPD", "STR", "AGI", "HND", "PAS", "TKL", "AWR", "KCK", "Skills"]


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	var m := UiStyle.margin(root, 20)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	var back := UiStyle.button("< Back")
	back.pressed.connect(main.show_menu)
	header.add_child(back)
	header.add_child(UiStyle.color_chip(team.color, 32))
	header.add_child(UiStyle.label(team.display_name(), 28))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(UiStyle.label("Overall %d   |   ★ = starter" % team.team_overall(), 16, UiStyle.MUTED))
	root.add_child(header)
	root.add_child(_playbook_bar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	tree = Tree.new()
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_stretch_ratio = 2.6
	tree.columns = COLS.size()
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	for i in COLS.size():
		tree.set_column_title(i, COLS[i])
		tree.set_column_expand(i, i == 2 or i == 13)
		if not (i == 2 or i == 13):
			tree.set_column_custom_minimum_width(i, 52)
	tree.set_column_custom_minimum_width(2, 170)
	tree.item_selected.connect(_on_row_selected)
	body.add_child(tree)
	_fill()

	legend = RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.text = _legend_text()
	body.add_child(legend)

	edit_panel = PlayerEditor.new()
	edit_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_panel.visible = false
	edit_panel.saved.connect(_on_edit_saved)
	edit_panel.cancelled.connect(_on_edit_closed)
	body.add_child(edit_panel)


# ---------------------------------------------------------------- playbooks

func _playbook_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.add_child(UiStyle.label("PLAYBOOKS", 16, UiStyle.MUTED))
	bar.add_child(_playbook_picker(Playbook.OFFENSE))
	bar.add_child(_playbook_picker(Playbook.DEFENSE))
	return bar


## A labelled dropdown of the stock playbook plus every saved playbook of this kind.
## Playbooks that can't be used yet (illegal formations, no plays) are listed but disabled.
func _playbook_picker(kind: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UiStyle.label("Offense:" if kind == Playbook.OFFENSE else "Defense:", 16))
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(240, 0)
	opt.add_item("Standard (stock)")
	var choices: Array = [null]
	var assigned: Playbook = team.offense_playbook if kind == Playbook.OFFENSE else team.defense_playbook
	var selected := 0
	for pb in PlaybookStore.list(kind):
		opt.add_item(pb.name)
		var i := opt.item_count - 1
		choices.append(pb)
		if not Playbook.usable_as(pb, kind):
			opt.set_item_disabled(i, true)
			opt.set_item_tooltip(i, "Can't be used yet: it needs at least one legal play. Fix it in Manage Playbooks.")
		if assigned != null and pb.resource_path == assigned.resource_path:
			selected = i
	opt.select(selected)
	opt.tooltip_text = "The %s playbook this team calls plays from in games and practice." % kind
	opt.item_selected.connect(func(i: int) -> void:
		if kind == Playbook.OFFENSE:
			team.offense_playbook = choices[i]
		else:
			team.defense_playbook = choices[i])
	h.add_child(opt)
	# An assigned playbook that has since broken or been deleted falls back to the stock one.
	if assigned != null and team.playbook_for(kind) == null:
		h.add_child(UiStyle.label("%s can't be used, so Standard is in use." % assigned.name, 13, UiStyle.BAD))
	return h


func _on_row_selected() -> void:
	if not Settings.debug_mode:
		return
	var p: FootballPlayer = _item_players.get(tree.get_selected())
	if p == null:
		return
	edit_panel.setup(p)
	edit_panel.visible = true
	legend.visible = false


func _on_edit_saved() -> void:
	_on_edit_closed()
	_fill() # ratings/skills may have changed


func _on_edit_closed() -> void:
	edit_panel.visible = false
	legend.visible = true


func _fill() -> void:
	tree.clear()
	_item_players.clear()
	var root_item := tree.create_item()
	var starters := {}
	var dc := team.depth_chart()
	for slot in dc:
		starters[dc[slot]] = true
	for pos in POS_ORDER:
		for p in team.players_at(pos):
			var it := tree.create_item(root_item)
			_item_players[it] = p
			var star := "★ " if starters.has(p) else ""
			var vals := [pos, str(p.number), star + p.full_name(), p.year_label(), str(p.overall())]
			for a in FootballPlayer.ATTRS:
				vals.append(str(p.r(a)))
			vals.append(", ".join(p.skills))
			for i in vals.size():
				it.set_text(i, vals[i])
				if i >= 5 and i <= 12:
					it.set_text_alignment(i, HORIZONTAL_ALIGNMENT_CENTER)
					var v := int(vals[i])
					if v >= 5:
						it.set_custom_color(i, UiStyle.GOOD)
					elif v <= 2:
						it.set_custom_color(i, UiStyle.MUTED)
			it.set_custom_color(4, UiStyle.ACCENT)
			var tip := ""
			for s in p.skills:
				tip += "%s: %s\n" % [s, FootballPlayer.SKILLS[s]]
			if tip != "":
				it.set_tooltip_text(13, tip.strip_edges())


func _legend_text() -> String:
	var s := "[color=#f2b134][b]HOW RATINGS WORK[/b][/color]\n"
	s += "Ratings go from 1 to 6. Most dice rolls need [b](7 - rating)+[/b] on a d6, so 4 means a 3+ (67%) and 6 means a 2+ (83%). A 1 always fails and a 6 always succeeds.\n\n"
	for a in FootballPlayer.ATTRS:
		s += "[b]%s[/b] [color=#8a96a8]%s[/color]\n%s\n\n" % [a.to_upper(), FootballPlayer.ATTR_NAMES[a], FootballPlayer.ATTR_HELP[a]]
	s += "[color=#f2b134][b]SKILLS[/b][/color]\n"
	for k in FootballPlayer.SKILLS:
		s += "[b]%s[/b]: %s\n" % [k, FootballPlayer.SKILLS[k]]
	return s
