class_name PlayerEditor
extends VBoxContainer
## Debug-only editor for one player's ratings and skills (used by the roster screen and
## the match screen's field view, both gated behind Settings.debug_mode). Edits stay local
## to this panel until SAVE is pressed; CANCEL discards them.

signal saved
signal cancelled

var player: FootballPlayer

var _attr_spins := {} # attr name -> SpinBox
var _skill_checks := {} # skill name -> CheckBox


func setup(p: FootballPlayer) -> void:
	player = p
	for c in get_children():
		c.queue_free()
	_attr_spins.clear()
	_skill_checks.clear()

	add_theme_constant_override("separation", 6)
	add_child(UiStyle.label("EDIT PLAYER (DEBUG)", 13, UiStyle.MUTED))
	add_child(UiStyle.label("%s   %s #%d" % [p.full_name(), p.position, p.number], 16, UiStyle.ACCENT))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	scroll.add_child(v)

	for attr in FootballPlayer.ATTRS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := UiStyle.label(FootballPlayer.ATTR_NAMES[attr], 14)
		lbl.custom_minimum_size = Vector2(110, 0)
		row.add_child(lbl)
		var sb := SpinBox.new()
		sb.min_value = 1
		sb.max_value = 6
		sb.step = 1
		sb.value = p.r(attr)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sb)
		_attr_spins[attr] = sb
		v.add_child(row)

	v.add_child(UiStyle.label("Skills", 14, UiStyle.MUTED))
	for sk in FootballPlayer.SKILLS:
		var cb := CheckBox.new()
		cb.text = sk
		cb.tooltip_text = FootballPlayer.SKILLS[sk]
		cb.button_pressed = p.has_skill(sk)
		_skill_checks[sk] = cb
		v.add_child(cb)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	add_child(buttons)
	var save_b := UiStyle.button("SAVE")
	save_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_b.pressed.connect(_on_save)
	buttons.add_child(save_b)
	var cancel_b := UiStyle.button("CANCEL")
	cancel_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_b.pressed.connect(func() -> void: cancelled.emit())
	buttons.add_child(cancel_b)


func _on_save() -> void:
	for attr in _attr_spins:
		var sb: SpinBox = _attr_spins[attr]
		player.ratings[attr] = int(sb.value)
	var new_skills: Array[String] = []
	for sk in _skill_checks:
		var cb: CheckBox = _skill_checks[sk]
		if cb.button_pressed:
			new_skills.append(sk)
	player.skills = new_skills
	saved.emit()
