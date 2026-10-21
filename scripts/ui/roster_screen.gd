extends Control
## Roster table with every rating and skill, plus a legend explaining what each one does.

var main
var team: Team

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

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	var tree := Tree.new()
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
	body.add_child(tree)
	_fill(tree)

	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.text = _legend_text()
	body.add_child(legend)


func _fill(tree: Tree) -> void:
	var root_item := tree.create_item()
	var starters := {}
	var dc := team.depth_chart()
	for slot in dc:
		starters[dc[slot]] = true
	for pos in POS_ORDER:
		for p in team.players_at(pos):
			var it := tree.create_item(root_item)
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
