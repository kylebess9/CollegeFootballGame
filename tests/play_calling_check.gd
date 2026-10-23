extends SceneTree
## Two-step play calling on the practice and match screens: pick a formation, then a play in
## it, with a back button to the formation list. Practice calls the offense, then the defense
## (which can back out to the offense). In a game the user's offense calls without seeing the
## defense, while the user's defense sees the CPU offense's formation but not its play.
## Practice also has a redo button that reruns the last rep's calls.
##   godot --headless --script res://tests/play_calling_check.gd
# Loaded once the game is up, since the screens use the Settings autoload.
var MatchScreen: GDScript
var PracticeScreen: GDScript

var failures := 0


func _initialize() -> void:
	MatchScreen = load("res://scripts/ui/match_screen.gd")
	PracticeScreen = load("res://scripts/ui/practice_screen.gd")
	if MatchScreen == null or not MatchScreen.can_instantiate() or PracticeScreen == null or not PracticeScreen.can_instantiate():
		print("play_calling_check: FAILED (screens don't compile)")
		quit(1)
		return
	var gen := TeamGenerator.new(11)
	var stub := MainStub.new()
	stub.my_team = gen.make_team(0, Color.BLUE)
	stub.cpu_team = gen.make_team(1, Color.RED)
	root.add_child(stub)
	await _check_practice(stub)
	await _check_match(stub)
	stub.queue_free()
	await process_frame
	print("play_calling_check: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _check_practice(stub: MainStub) -> void:
	var p: Control = PracticeScreen.new()
	p.main = stub
	stub.add_child(p)
	await process_frame
	_expect(p.state == "calling_off" and _texts(p) == ["Pistol"], "practice opens on the offense's formations: %s" % [_texts(p)])
	_press(p, "Pistol")
	var plays := _texts(p)
	_expect(plays.size() == 8 and plays[0] == "< Formations" and "Quick Slants" in plays, "picking Pistol lists its plays: %s" % [plays])
	_hover(p, "Quick Slants")
	_expect(p.field.preview and p.field.ghost_routes, "hovering a play draws its routes")
	_press(p, "< Formations")
	_expect(p.state == "calling_off" and _texts(p) == ["Pistol"], "back goes to the formation list")
	_press(p, "Pistol")
	_press(p, "Quick Slants")
	_expect(p.state == "calling_def" and p.pending_off == "Quick Slants", "picking a play moves on to the defense")
	_expect(_texts(p) == ["4-3", "4-3 Box", "< Change offense play"], "defense formations, with a way back: %s" % [_texts(p)])
	_press(p, "4-3 Box")
	_expect(_texts(p)[0] == "< Formations" and "Run Stuff" in _texts(p), "picking 4-3 Box lists its calls: %s" % [_texts(p)])
	_hover(p, "Run Stuff")
	_expect(p.field.ghost_routes and p.field.ghost_defense and p.field.sim.def_play.name == "Run Stuff",
		"hovering a call keeps the offense's routes up and draws the coverage")
	_press(p, "< Formations")
	_press(p, "< Change offense play")
	_expect(p.state == "calling_off" and p.pending_off == "" and _texts(p) == ["Pistol"], "the defense can send it back to the offense")
	_press(p, "Pistol")
	_press(p, "Inside Run")
	_press(p, "4-3")
	_press(p, "Cover 2")
	_expect(p.state == "playing" and p.pending_off == "Inside Run" and p.pending_def == "Cover 2" and _texts(p).is_empty(),
		"picking a call runs the play")
	_expect(p.redo_button.disabled, "redo is off while the play runs")

	# Redo: once the play is over, runs the same two calls again without calling them.
	while not p.sim.done:
		p.sim.step()
	p._finish_play()
	_expect(p.state == "post" and not p.redo_button.disabled, "redo is on once the play is over")
	p.redo_button.pressed.emit()
	_expect(p.state == "playing" and p.pending_off == "Inside Run" and p.pending_def == "Cover 2" and not p.sim.done,
		"redo during the post-play pause reruns the same calls")
	while not p.sim.done:
		p.sim.step()
	p._finish_play()
	p.post_timer = 0.0
	p._process(0.0)
	_expect(p.state == "calling_off" and not p.redo_button.disabled, "redo stays on once the call panel is back")
	p.redo_button.pressed.emit()
	_expect(p.state == "playing" and p.pending_off == "Inside Run" and p.pending_def == "Cover 2" and _texts(p).is_empty(),
		"redo from the call panel skips both calls")
	p.queue_free()
	await process_frame


func _check_match(stub: MainStub) -> void:
	var m: Control = MatchScreen.new()
	m.main = stub
	stub.add_child(m)
	await process_frame

	# A custom offense with a second, empty formation: it isn't offered.
	var pb := Playbook.make_default()
	pb.offensive_formations.append(OffensiveFormation.make("Empty", []))
	m.gs.offense_playbooks[GameState.HOME] = pb

	# On offense: the CPU's defense is already called, and kept off the field until the snap.
	m.gs.possession = GameState.HOME
	m.gs.down = 1
	m._begin_snap()
	_expect(m.pending_def != "", "CPU defense calls first")
	_expect(_texts(m).size() == 3 and _texts(m)[0] == "Pistol" and _texts(m)[1] == "Punt" and _texts(m)[2].begins_with("Field Goal"),
		"offense formations (skipping the empty one) and the kicks: %s" % [_texts(m)])
	_expect(m.field.preview and m.field.hide_defense and not m.field.ghost_defense, "the defense is hidden while the offense calls")
	_press(m, "Pistol")
	_hover(m, "Four Verticals")
	_expect(m.field.ghost_routes and m.field.hide_defense and not m.field.ghost_defense, "hovering a play shows routes, still no defense")
	_press(m, "< Formations")
	_expect(_texts(m)[0] == "Pistol", "back goes to the formation list")
	_press(m, "Pistol")
	_press(m, "Dig Cross")
	_expect(m.state == "playing" and m.pending_off == "Dig Cross" and not m.field.hide_defense and not m.field.preview,
		"the defense appears at the snap")
	m.state = "calling"
	m.sim.dispose()
	m.sim = null

	# On defense: the CPU offense lines up in its formation, without showing its play.
	m.gs.possession = GameState.AWAY
	m.gs.down = 1
	m._begin_snap()
	var off_play: OffensivePlay = m.gs.offense_playbook().offense_play(m.pending_off)
	_expect(off_play != null, "CPU offense calls first: %s" % m.pending_off)
	_expect(m.field.preview and not m.field.hide_defense and not m.field.ghost_routes, "the CPU offense lines up, its routes hidden")
	_expect(m.field.sim.off_play.formation == off_play.formation, "the field shows the CPU offense's formation")
	_expect(off_play.formation.name in m.call_title.text, "the title names the CPU's formation: %s" % m.call_title.text)
	_expect(_texts(m) == ["4-3", "4-3 Box"], "defense formations: %s" % [_texts(m)])
	_press(m, "4-3")
	_hover(m, "Blitz")
	_expect(m.field.ghost_defense and not m.field.ghost_routes and m.field.sim.off_play == off_play,
		"hovering a call draws the coverage against the CPU's real lineup")
	_press(m, "Blitz")
	_expect(m.state == "playing" and m.pending_def == "Blitz", "picking a call runs the play")
	m.queue_free()
	await process_frame


func _buttons(screen: Node) -> Array:
	return screen.call_buttons.get_children()


func _texts(screen: Node) -> Array:
	return _buttons(screen).map(func(b: Button) -> String: return b.text)


func _find(screen: Node, text: String) -> Button:
	for b in _buttons(screen):
		if b.text == text:
			return b
	_expect(false, "no %s button among %s" % [text, _texts(screen)])
	return null


func _press(screen: Node, text: String) -> void:
	var b := _find(screen, text)
	if b != null:
		b.pressed.emit()


func _hover(screen: Node, text: String) -> void:
	var b := _find(screen, text)
	if b != null:
		b.mouse_entered.emit()


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + what)


class MainStub extends Control:
	var my_team: Team
	var cpu_team: Team
	var quarter_minutes := 8.0

	func show_menu() -> void:
		pass
