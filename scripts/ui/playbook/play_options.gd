extends HBoxContainer
## The playbook editor's bottom panel: the main options of the selected play.
##   Pass play      - drop, read start and play action on the left; on the right every
##                    player but the snap taker, each with a route or Pass Block.
##   Run play       - the run path (inside / outside).
##   Defensive call - "run first" on the left; on the right every defender off the line,
##                    each with Man, Blitz or a zone.
## Each kind of play has its own _build_* function, so new play types or options slot in
## beside them. Emits `changed` after every edit so the editor can redraw and save.

signal changed
## The player whose cell the mouse is over (or whose drop-down is open), "" when none, so
## the editor can point him out on the field.
signal player_hovered(slot: String)

const BLOCK_LABEL := "Pass Block"
const MAN_LABEL := "Man"
const BLITZ_LABEL := "Blitz"

var play: Resource = null
var _left: VBoxContainer
var _right: HFlowContainer
var _errors: Label


func _ready() -> void:
	add_theme_constant_override("separation", 20)
	_left = VBoxContainer.new()
	_left.custom_minimum_size = Vector2(300, 0)
	_left.add_theme_constant_override("separation", 6)
	add_child(_left)
	add_child(VSeparator.new())
	_right = HFlowContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_theme_constant_override("h_separation", 12)
	_right.add_theme_constant_override("v_separation", 8)
	add_child(_right)
	show_play(null)


func show_play(p: Resource) -> void:
	play = p
	player_hovered.emit("")
	for c in _left.get_children() + _right.get_children():
		c.queue_free()
	if p == null:
		_left.add_child(UiStyle.label("No play selected", 18, UiStyle.ACCENT))
		var hint := UiStyle.label("Pick a play from the list on the right, or add one with a formation's green +.", 13, UiStyle.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_left.add_child(hint)
		return
	_left.add_child(UiStyle.label(p.name, 18, UiStyle.ACCENT))
	if p is PassPlay:
		_build_pass(p)
	elif p is RunPlay:
		_build_run(p)
	elif p is DefensivePlay:
		_build_defense(p)
	_errors = UiStyle.label("", 13, UiStyle.BAD)
	_errors.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left.add_child(_errors)
	_refresh_errors()


func _edited() -> void:
	_refresh_errors()
	changed.emit()


## Rule problems with the play (no reads, say), so the user sees why it won't work.
func _refresh_errors() -> void:
	_errors.text = "\n".join(play.validate())


# ---------------------------------------------------------------- pass

func _build_pass(p: PassPlay) -> void:
	_left.add_child(_spin_row("Drop (yards)", p.drop, 1.0, 12.0, 0.5,
		"How far the QB drops back before setting up.", func(v: float) -> void: p.drop = v))
	_left.add_child(_spin_row("Read start (sec)", p.read_start, 0.0, 5.0, 0.1,
		"Seconds after the snap before the QB starts his progression.", func(v: float) -> void: p.read_start = v))
	var pa := CheckBox.new()
	pa.text = "Play action"
	pa.tooltip_text = "Fake a handoff to the RB before the throw."
	pa.button_pressed = p.play_action
	pa.toggled.connect(func(on: bool) -> void:
		p.play_action = on
		_edited())
	_left.add_child(pa)

	var routes := Playbook.route_names()
	# Receivers and backs first, then the linemen, who can only block.
	var slots := p.formation.non_snap_slots()
	var order := slots.filter(func(sl: String) -> bool: return p.formation.is_eligible(sl))
	order.append_array(slots.filter(func(sl: String) -> bool: return not p.formation.is_eligible(sl)))
	for slot in order:
		var opt := OptionButton.new()
		opt.add_item(BLOCK_LABEL)
		if not p.formation.is_eligible(slot):
			opt.disabled = true
			opt.tooltip_text = "Linemen always block."
		else:
			var names := routes.duplicate()
			var custom_route: Route = p.routes.get(slot)
			if custom_route != null and not custom_route.name in names:
				names.append(custom_route.name) # a route that isn't in the stock tree
			for r in names:
				opt.add_item(r)
			opt.select(names.find(p.job(slot)) + 1)
			opt.item_selected.connect(func(i: int) -> void:
				if i == 0:
					p.set_block(slot)
				else:
					var r: String = names[i - 1]
					p.set_route(slot, Playbook.route(r) if Playbook.ROUTES.has(r) else custom_route)
				_edited())
		_right.add_child(_player_cell(slot, p.formation.spot(slot).position, opt))


# ---------------------------------------------------------------- run

func _build_run(p: RunPlay) -> void:
	var opt := OptionButton.new()
	for path in RunPlay.PATHS:
		opt.add_item(path.capitalize())
	opt.select(RunPlay.PATHS.find(p.run_path))
	opt.item_selected.connect(func(i: int) -> void:
		p.run_path = RunPlay.PATHS[i]
		_edited())
	_left.add_child(_row("Run path", opt, "Inside: between the tackles. Outside: to the edge."))
	var note := UiStyle.label("The RB takes the handoff; everyone else blocks.", 13, UiStyle.MUTED)
	_right.add_child(note)


# ---------------------------------------------------------------- defense

func _build_defense(p: DefensivePlay) -> void:
	var rf := CheckBox.new()
	rf.text = "Run first"
	rf.tooltip_text = "Everyone not in a deep zone attacks the line at the snap. Strong against the run, easy to fool with play action."
	rf.button_pressed = p.run_first
	rf.toggled.connect(func(on: bool) -> void:
		p.run_first = on
		_edited())
	_left.add_child(rf)

	var zones := Playbook.zone_names()
	for s in p.formation.spots:
		var opt := OptionButton.new()
		if s.position == "DL":
			opt.add_item("Rush")
			opt.disabled = true
			opt.tooltip_text = "Down linemen always rush."
			_right.add_child(_player_cell(s.slot, s.position, opt))
			continue
		var a: CoverageAssignment = p.assignment(s.slot)
		var choices: Array[String] = [MAN_LABEL, BLITZ_LABEL]
		choices.append_array(zones)
		var current := MAN_LABEL
		if a != null and a.type == CoverageAssignment.BLITZ:
			current = BLITZ_LABEL
		elif a != null and a.type == CoverageAssignment.ZONE:
			current = a.zone.name
			if not current in choices:
				choices.append(current) # a zone that isn't in the stock list
		for c in choices:
			opt.add_item(c)
		opt.select(choices.find(current))
		var slot := s.slot
		var custom_zone: Zone = a.zone if a != null else null
		opt.item_selected.connect(func(i: int) -> void:
			var c := choices[i]
			if c == MAN_LABEL:
				p.set_assignment(CoverageAssignment.man(slot))
			elif c == BLITZ_LABEL:
				p.set_assignment(CoverageAssignment.blitz(slot))
			else:
				p.set_assignment(CoverageAssignment.in_zone(slot,
					Playbook.zone(c) if Playbook.ZONES.has(c) else custom_zone))
			_edited())
		_right.add_child(_player_cell(s.slot, s.position, opt))


# ---------------------------------------------------------------- widgets

func _player_cell(slot: String, position: String, control: Control) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(140, 0)
	var caption := UiStyle.label("%s  (%s)" % [slot, position], 13, UiStyle.MUTED)
	caption.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(caption)
	control.custom_minimum_size = Vector2(140, 0)
	v.add_child(control)
	var popup: PopupMenu = control.get_popup() if control is OptionButton else null
	for c in [caption, control]:
		c.mouse_entered.connect(func() -> void: player_hovered.emit(slot))
		# Keep him highlighted while his drop-down list is open.
		c.mouse_exited.connect(func() -> void:
			if popup == null or not popup.visible:
				player_hovered.emit(""))
	if popup != null:
		popup.popup_hide.connect(func() -> void: player_hovered.emit(""))
	return v


func _row(caption: String, control: Control, tip: String) -> Control:
	var h := HBoxContainer.new()
	var l := UiStyle.label(caption, 14, UiStyle.MUTED)
	l.custom_minimum_size = Vector2(140, 0)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(l)
	control.tooltip_text = tip
	h.add_child(control)
	return h


func _spin_row(caption: String, value: float, lo: float, hi: float, step: float, tip: String,
		apply: Callable) -> Control:
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.value = value
	spin.custom_minimum_size = Vector2(110, 0)
	spin.value_changed.connect(func(v: float) -> void:
		apply.call(v)
		_edited())
	return _row(caption, spin, tip)
