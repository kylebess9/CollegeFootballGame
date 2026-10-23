extends RefCounted
## Two-step play calling, shared by the match and practice screens: first the list of the
## playbook's formations, then the plays in the one picked, with a back button to the list.
## It fills the screen's call panel (title, hint and button row) and tells the screen what
## to line up on the field; the screen decides what the call does.

## A play was picked.
signal called(play_name: String)
## Line the field up in this play. With ghost, draw the play itself (routes, or coverage);
## without, only its formation's alignment. An empty name means the neutral lineup.
signal preview(play_name: String, ghost: bool)
## The back button on the formation list was pressed (only shown when back_text is set).
signal backed_out()

var title: Label
var hint: Label
var buttons: HFlowContainer
var playbook: Playbook
var side := Playbook.OFFENSE
## Goes in front of both steps' titles, e.g. "YOUR OFFENSE: 1st & 10."
var heading := ""
## Added to the end of both steps' hints.
var note := ""
## Returns extra buttons for the end of the formation list (the kicks, on offense).
var extras := Callable()
## Label of a back button on the formation list; none when empty.
var back_text := ""
## The formation whose plays are showing, or null on the formation list.
var formation: Resource = null


func _init(title_label: Label, hint_label: Label, button_row: HFlowContainer) -> void:
	title = title_label
	hint = hint_label
	buttons = button_row


## Starts over at the formation list for this side of the ball.
func start(pb: Playbook, which_side: String, head: String) -> void:
	playbook = pb
	side = which_side
	heading = head
	show_formations()


## Formations that have at least one play; an empty one has nothing to call.
func formations() -> Array:
	var all: Array = playbook.offensive_formations if side == Playbook.OFFENSE else playbook.defensive_formations
	return all.filter(func(f: Resource) -> bool: return not f.plays.is_empty())


## The play the field rests on while nothing is hovered: the picked formation's first play
## (so the alignment matches the formation), or "" on the formation list.
func rest_play() -> String:
	return formation.plays[0].name if formation != null else ""


func show_formations() -> void:
	formation = null
	_clear()
	title.text = (heading + " Pick a formation.").strip_edges()
	hint.text = ("Hover a formation to see how it lines up. " + note).strip_edges()
	for f in formations():
		var b := UiStyle.button(f.name, "%d %s" % [f.plays.size(), "play" if f.plays.size() == 1 else "plays"])
		b.pressed.connect(show_plays.bind(f))
		_hook_preview(b, f.plays[0].name, false)
		buttons.add_child(b)
	if extras.is_valid():
		for b in extras.call():
			buttons.add_child(b)
	if back_text != "":
		var back := UiStyle.button(back_text)
		back.pressed.connect(func() -> void: backed_out.emit())
		buttons.add_child(back)
	preview.emit("", false)


func show_plays(f: Resource) -> void:
	formation = f
	_clear()
	title.text = ("%s %s: pick a %s." % [heading, f.name, "play" if side == Playbook.OFFENSE else "call"]).strip_edges()
	var how := "Hover a play to see what it does." if side == Playbook.OFFENSE else "Hover a call to see its strengths."
	hint.text = (how + " " + note).strip_edges()
	var back := UiStyle.button("< Formations", "Back to the formation list")
	back.pressed.connect(show_formations)
	buttons.add_child(back)
	for p in f.plays:
		var b := UiStyle.button(p.name, p.description)
		b.pressed.connect(_call.bind(p.name))
		_hook_preview(b, p.name, true)
		buttons.add_child(b)
	preview.emit(rest_play(), false)


func clear() -> void:
	formation = null
	_clear()


func _call(play_name: String) -> void:
	_clear()
	called.emit(play_name)


func _clear() -> void:
	for c in buttons.get_children():
		buttons.remove_child(c)
		c.queue_free()


func _hook_preview(b: Button, play_name: String, ghost: bool) -> void:
	b.mouse_entered.connect(func() -> void: preview.emit(play_name, ghost))
	b.mouse_exited.connect(func() -> void:
		if b.is_inside_tree():
			preview.emit(rest_play(), false))
