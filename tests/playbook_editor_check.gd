extends SceneTree
## Checks the data side of the playbook editor: new playbooks start legal with the right
## packages, editing a play keeps it consistent, and playbooks survive a save and reload.
## Then opens the editor screen on each kind of playbook to make sure it builds.
##   godot --headless --script res://tests/playbook_editor_check.gd
const PlaybookEditor := preload("res://scripts/ui/playbook_editor.gd")
const PlaybooksScreen := preload("res://scripts/ui/playbooks_screen.gd")
const PlayOptions := preload("res://scripts/ui/playbook/play_options.gd")

var failures := 0


func _initialize() -> void:
	PlaybookStore.root = "user://test_playbooks"
	_clear_store()

	var off := PlaybookStore.create(Playbook.OFFENSE)
	var def := PlaybookStore.create(Playbook.DEFENSE)
	_expect(off.name == "Offensive Playbook #1", "first offensive playbook is #1 (got %s)" % off.name)
	_expect(def.name == "Defensive Playbook #1", "first defensive playbook is #1 (got %s)" % def.name)
	_expect(PlaybookStore.create(Playbook.OFFENSE).name == "Offensive Playbook #2", "second offensive playbook is #2")
	_expect(off.validate().is_empty(), "new offensive playbook is legal: %s" % [off.validate()])
	_expect(def.validate().is_empty(), "new defensive playbook is legal: %s" % [def.validate()])
	_expect(off.offensive_formations.size() == 1 and off.offensive_formations[0].name == "Pistol"
		and off.offensive_formations[0].plays.size() == 7, "offense starts with the Pistol package")
	_expect(off.defensive_formations.is_empty(), "offensive playbook has no defense")
	var def_names := def.defensive_formations.map(func(f: DefensiveFormation) -> String: return f.name)
	_expect(def_names == ["4-3", "4-3 Box"], "defense starts with both 4-3 packages")

	# New plays start legal.
	var pistol: OffensiveFormation = off.offensive_formations[0]
	_expect(pistol.non_snap_slots().size() == 10 and not "QB" in pistol.non_snap_slots(), "QB takes the snap")
	_expect(not pistol.is_eligible("LT") and pistol.is_eligible("RB"), "linemen can't run routes, the RB can")
	var pa := pistol.add_play(PassPlay.blank("My PA", true, pistol)) as PassPlay
	_expect(pa.validate().is_empty(), "blank pass play is legal: %s" % [pa.validate()])
	_expect(pa.job("WR1") == "go" and pa.job("RB") == PassPlay.BLOCK, "blank pass play: receivers go, RB blocks")
	var run := pistol.add_play(RunPlay.make("My Run", "", RunPlay.OUTSIDE)) as RunPlay
	_expect(run.validate().is_empty(), "new run play is legal")
	var base: DefensiveFormation = def.defensive_formations[0]
	var call := base.add_play(DefensivePlay.blank("My Call", base))
	_expect(call.validate().is_empty(), "blank defensive call is legal: %s" % [call.validate()])

	# Editing a pass play keeps routes, protect and reads in step.
	pa.set_route("RB", Playbook.route("swing"))
	pa.set_block("WR3")
	_expect(pa.job("RB") == "swing" and "RB" in pa.reads and not "RB" in pa.protect, "RB sent on a swing")
	_expect(pa.job("WR3") == PassPlay.BLOCK and not "WR3" in pa.reads and "WR3" in pa.protect, "WR3 kept in")
	pa.set_route("WR3", Playbook.route("dig"))
	var before_reads := pa.reads.duplicate()
	pa.set_read_priority("WR3", 1)
	_expect(pa.reads[0] == "WR3" and pa.reads.slice(1) == before_reads.filter(func(r: String) -> bool: return r != "WR3"),
		"moving WR3 to first read keeps everyone else's order")
	pa.set_read_priority("WR3", 99)
	_expect(pa.reads[-1] == "WR3", "a priority past the end puts him last")
	pa.set_block("WR3")
	for slot in ["WR1", "WR2", "TE", "RB"]:
		pa.set_block(slot)
	_expect(not pa.validate().is_empty(), "a pass play with nobody running a route is caught")
	pa.set_route("TE", Playbook.route("seam"))
	pa.drop = 5.5
	pa.read_start = 0.9
	call.set_assignment(CoverageAssignment.in_zone("FS", Playbook.zone("Deep Middle")))
	call.set_assignment(CoverageAssignment.blitz("MIKE"))
	_expect(call.validate().is_empty() and call.assignments.size() == 7, "editing a call keeps one job per defender")

	# A route of the playbook's own, run by a play, then reshaped.
	var whip := off.add_custom_route("whip", Playbook.route("out"))
	_expect(off.all_route_names().has("whip") and off.is_custom_route("whip") and not Playbook.ROUTES.has("whip"),
		"custom routes belong to the playbook, not the stock tree")
	var wp := pistol.add_play(PassPlay.blank("My Whip", false, pistol)) as PassPlay
	wp.set_route("WR1", off.make_route("whip"))
	whip.points.insert(1, Vector2(9, 3))
	_expect(wp.routes["WR1"].points.size() == 2, "plays keep their own copy until the route is refreshed")
	off.refresh_route("whip")
	_expect(wp.routes["WR1"].points == whip.points and wp.routes["WR1"] != whip, "refreshing pushes the new points to plays")
	off.rename_route("whip", "whip out")
	_expect(wp.job("WR1") == "whip out" and off.custom_route("whip out") != null, "renaming a route renames it in plays")

	# Save and reload, from scratch.
	PlaybookStore.save(off)
	PlaybookStore.save(def)
	var path := off.resource_path
	off = null
	def = null
	pistol = null
	whip = null
	wp = null
	pa = null
	run = null
	base = null
	call = null
	var offs := PlaybookStore.list(Playbook.OFFENSE)
	var defs := PlaybookStore.list(Playbook.DEFENSE)
	_expect(offs.size() == 2 and defs.size() == 1, "store lists 2 offensive and 1 defensive playbooks")
	var loaded: Playbook = offs[0]
	_expect(loaded.resource_path == path, "playbooks list oldest first")
	_expect(loaded.offense_play("My PA") != null and loaded.offense_play("My PA").formation != null,
		"reloaded plays know their formation")
	var lpa := loaded.offense_play("My PA") as PassPlay
	_expect(lpa != null and lpa.play_action and lpa.drop == 5.5 and lpa.read_start == 0.9
		and lpa.job("TE") == "seam" and lpa.reads == ["TE"], "pass play edits survive a reload")
	var lwp := loaded.offense_play("My Whip") as PassPlay
	_expect(loaded.custom_route("whip out") != null and loaded.custom_route("whip out").points.size() == 3
		and lwp.job("WR1") == "whip out" and lwp.routes["WR1"].points.size() == 3, "custom routes survive a reload")
	_expect((loaded.offense_play("My Run") as RunPlay).run_path == RunPlay.OUTSIDE, "run path survives a reload")
	var lcall := defs[0].defense_play("My Call")
	_expect(lcall != null and lcall.assignment("MIKE").type == CoverageAssignment.BLITZ
		and lcall.assignment("FS").zone.name == "Deep Middle", "defensive edits survive a reload")
	_expect(loaded.validate().is_empty() and defs[0].validate().is_empty(), "reloaded playbooks are legal")

	# The sim runs a play from an edited playbook.
	var gen := TeamGenerator.new(5)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var sim := PlaySim.new()
	sim.setup(a, b, lpa, lcall, 35.0, 26.67, {}, Dice.new(3))
	var res := sim.run_to_end()
	_expect(res.has("kind"), "an edited play runs in the sim")
	sim.dispose()

	PlaybookStore.delete(offs[1])
	_expect(PlaybookStore.list(Playbook.OFFENSE).size() == 1, "deleting a playbook removes it")

	_check_drafts(a, b)
	await _check_screens(loaded, defs[0], a, b)

	_clear_store()
	print("playbook_editor_check: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


## The formation builder's rules: the line is laid out for you, players snap to the line
## and behind the center, can't overlap, and the snap goes to whoever is closest behind
## the center. Then a built formation runs in the sim.
func _check_drafts(a: Team, b: Team) -> void:
	var d := FormationDraft.create("Trips", true, {"QB": 1, "RB": 1, "WR": 3, "TE": 1, "OL": 5})
	_expect(d.placed_spots().size() == 5 and d.spot("C").offset == Vector2(FormationDraft.OL_X, 0.0),
		"new offense: the five linemen start on the line with the center over the ball")
	_expect(not d.is_legal(), "new offense isn't legal until everyone is placed")
	_expect(not d.place("C", Vector2(-3, 0)), "the center can't be moved")
	_expect(d.place("QB", Vector2(-4.0, 0.7)) and d.spot("QB").offset == Vector2(-4.0, 0.0),
		"dropping near the spot behind the center snaps onto it")
	_expect(d.snap_slot == "QB", "the QB, behind the center, gets the snap")
	_expect(not d.place("RB", Vector2(-4.3, 0.2)), "players can't overlap")
	_expect(d.place("RB", Vector2(-6.5, 0.0)) and d.snap_slot == "QB", "the RB behind the QB doesn't take the snap")
	_expect(d.place("WR1", Vector2(-1.4, -13.0)) and is_equal_approx(d.spot("WR1").offset.x, FormationDraft.OL_X),
		"dropping near the line snaps onto it")
	d.place("WR2", Vector2(-0.8, 15.0))
	d.place("WR3", Vector2(-1.5, -6.0))
	d.place("TE", Vector2(-0.8, 4.2))
	_expect(d.is_legal(), "trips formation is legal: %s" % [d.problems()])
	for slot in ["WR1", "WR2", "TE"]:
		d.place(slot, d.spot(slot).offset + Vector2(-4.0, 0.0))
	_expect(not d.is_legal(), "6 on the line and 5 in the backfield is caught: %s" % [d.problems()])
	for slot in ["WR1", "WR2", "TE"]:
		d.place(slot, d.spot(slot).offset + Vector2(4.0, 0.0))
	_expect(d.is_legal(), "moving them back makes it legal again")
	d.give_snap("RB")
	_expect(d.snap_slot == "RB" and d.spot("RB").offset.x > d.spot("QB").offset.x and d.is_legal(),
		"picking the RB to take the snap moves him under center")
	d.give_snap("QB")
	_expect(d.snap_slot == "QB" and d.spot("RB").offset == Vector2(-4.0, 0.0),
		"picking the QB back swaps him with the RB")
	d.remove("WR3")
	_expect(not d.is_legal() and not d.is_placed("WR3"), "taking a player off makes it illegal")
	d.place("WR3", Vector2(-1.5, -6.0))
	var f: OffensiveFormation = d.to_formation()
	_expect(f.is_legal() and f.snap_slot == "QB", "the built formation is legal: %s" % [f.validate()])
	var pass_play := f.add_play(PassPlay.blank("Trips Go", false, f)) as PassPlay
	var run := f.add_play(RunPlay.make("Trips Run", "", RunPlay.INSIDE))
	_expect(f.is_legal(), "plays added to the built formation are legal: %s" % [f.validate()])
	pass_play.set_route("QB", Playbook.route("go"))
	_expect(not pass_play.validate().is_empty(), "the snap taker running a route is caught")
	pass_play.set_block("QB")

	var big := FormationDraft.create("Jumbo", true, {"QB": 1, "RB": 1, "TE": 2, "OL": 7})
	_expect(big.spot("C").offset.y == 0.0 and big.spot("OL6").offset.y > big.spot("RT").offset.y
		and big.spot("OL7").offset.y < big.spot("LT").offset.y, "extra linemen go on the ends")

	var dd := FormationDraft.create("Nickel", false, {"DL": 4, "LB": 2, "CB": 3, "S": 2})
	_expect(dd.placed_spots().is_empty(), "new defense starts with everyone to place")
	var y := -15.0
	for s in dd.spots:
		_expect(dd.place(s.slot, Vector2(1.3 if s.position == "DL" else 6.0, y)), "place %s" % s.slot)
		y += 3.0
	_expect(is_equal_approx(dd.spot("DE1").offset.x, FormationDraft.DEF_LINE_X), "defenders snap onto the line too")
	_expect(dd.is_legal(), "nickel defense is legal: %s" % [dd.problems()])
	var df: DefensiveFormation = dd.to_formation()
	var call := df.add_play(DefensivePlay.blank("Nickel Man", df))
	_expect(df.is_legal(), "a call from the built defense is legal: %s" % [df.validate()])

	for off_play in [pass_play, run]:
		var sim := PlaySim.new()
		sim.setup(a, b, off_play, call, 35.0, 26.67, {}, Dice.new(4))
		var res := sim.run_to_end()
		_expect(res.has("kind") and sim.qb.slot == "QB", "%s runs in the sim against built defense" % off_play.name)
		sim.dispose()

	var pistol: OffensiveFormation = Playbook.offense_packages()[0]
	var pd := FormationDraft.from_formation(pistol)
	_expect(pd.is_legal() and pd.snap_slot == "QB" and pd.center_slot == "C", "an existing formation opens legal")

	var base: DefensiveFormation = Playbook.defense_packages()[0]
	var bd := FormationDraft.from_formation(base)
	_expect(bd.is_legal() and bd.spot("CB1").offset.y < -10.0, "corners lined up over receivers are drawn out wide")
	var copy := DefensiveFormation.make("Copy", base.spots.duplicate())
	bd.apply_to(copy)
	_expect(copy.spot("CB1").align == "left_1" and copy.spot("CB1").offset == base.spot("CB1").offset,
		"saving without moving them keeps them lined up over receivers")
	bd.place("CB1", Vector2(7.0, -15.0))
	bd.apply_to(copy)
	_expect(copy.spot("CB1").align == "" and copy.spot("CB1").offset == Vector2(7.0, -15.0),
		"moving one pins him to where he was dropped")


## Opens the Manage Playbooks screen and the editor for each kind of playbook, clicking
## through a play of each type, to make sure the screens build without errors.
func _check_screens(off: Playbook, def: Playbook, a: Team, b: Team) -> void:
	var stub := MainStub.new()
	stub.my_team = a
	stub.cpu_team = b
	root.add_child(stub)

	var list := PlaybooksScreen.new()
	list.main = stub
	stub.add_child(list)
	await process_frame
	_expect(list.get_child_count() > 0, "Manage Playbooks screen builds")
	list.queue_free()

	for pb in [off, def]:
		var ed := PlaybookEditor.new()
		ed.main = stub
		ed.playbook = pb
		stub.add_child(ed)
		await process_frame
		_expect(ed.selected_play == null, "%s: editor opens with nothing selected" % pb.name)
		var plays: Array = pb.offense_plays() if pb.kind == Playbook.OFFENSE else pb.defense_plays()
		for p in plays:
			ed.select_play(p)
			await process_frame
			_expect(ed.selected_play == p and ed.field.sim != null, "%s: selecting %s draws it" % [pb.name, p.name])
		var with_players := plays.filter(func(p: Resource) -> bool: return not p is RunPlay)
		if not with_players.is_empty():
			ed.select_play(with_players[-1])
			await process_frame
			var opt: Control = ed.options.find_children("*", "OptionButton", true, false)[0]
			opt.mouse_entered.emit()
			_expect(ed.field.highlighted != null and ed.field.highlighted.slot == opt.get_parent().get_child(0).text.split(" ")[0],
				"%s: hovering a player's drop-down highlights him on the field" % pb.name)
			opt.mouse_exited.emit()
			_expect(ed.field.highlighted == null, "%s: and leaving it clears the highlight" % pb.name)
		if ed.is_offense():
			var pp: PassPlay = with_players[-1]
			var labels := ed.options.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
			_expect(not labels.any(func(t: String) -> bool: return t.begins_with("LT ") or t.begins_with("C ")),
				"linemen aren't listed for a pass play")
			var ranks := ed.options.find_children("*", "OptionButton", true, false).filter(
				func(o: OptionButton) -> bool: return o.item_count > 0 and o.get_item_text(0) == "1")
			_expect(ranks.size() == pp.reads.size(), "one read-order drop-down per route runner")
		await _run_through_ui(ed)
		await _edit_through_ui(ed)
		await _build_through_ui(ed)
		if ed.is_offense():
			await _routes_through_ui(ed)
			await _play_route_through_ui(ed)
		ed.queue_free()
		await process_frame
	stub.queue_free()


## Adds a play with the dialog's callback, flips every option on the bottom panel, then
## deletes the play, the way a user would.
## Opens Playbook Routes, makes a route, reshapes it on the field the way a user would, and
## checks the play options offer it.
func _routes_through_ui(ed: Node) -> void:
	var pb: Playbook = ed.playbook
	var re = ed.route_editor
	re.open(pb)
	await process_frame
	re.select("slant")
	_expect(not re.canvas.editable, "stock routes can't be edited")
	var before := pb.custom_routes.size()
	re.new_route(pb.make_route("slant"))
	var r: Route = pb.custom_route(re.selected)
	_expect(pb.custom_routes.size() == before + 1 and re.canvas.editable and r.points.size() == 2,
		"copying a stock route makes an editable route of the playbook's own")
	var c: RouteCanvas = re.canvas
	c.size = Vector2(800, 700)
	c._layout()
	# Hover the middle of the line from the receiver to the first point, then click.
	var a := c.to_screen(r.points[0])
	var b := c.to_screen(r.points[1])
	var hover := InputEventMouseMotion.new()
	hover.position = (a + b) * 0.5
	c._gui_input(hover)
	_expect(c._ghost_index == 1, "hovering between points 1 and 2 shows a new point there")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = hover.position
	c._gui_input(click)
	_expect(r.points.size() == 3 and r.points[0] == Vector2(2, 0) and r.points[2] == Vector2(7, -5),
		"clicking adds the point in between, in order: %s" % [r.points])
	var drag := InputEventMouseMotion.new()
	drag.position = c.to_screen(Vector2(6, 4))
	c._gui_input(drag)
	click.pressed = false
	c._gui_input(click)
	_expect(r.points[1] == Vector2(6, 4), "dragging moves the new point: %s" % [r.points])
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = c.to_screen(r.points[1])
	c._gui_input(right)
	_expect(r.points.size() == 2, "right-clicking a point removes it")
	re._name_edit.text = "slant"
	re._on_rename("slant")
	_expect(re._error.text != "" and pb.custom_route("slant") == null, "a route can't take a stock route's name")
	re._on_rename("custom")
	_expect(re._error.text != "" and pb.custom_route("custom") == null, "\"Custom\" is kept for routes drawn in one play")
	re._on_rename("bang")
	_expect(pb.custom_route("bang") == r, "renaming a route")
	re.hide()
	await process_frame
	var pp: PassPlay = null
	for p in pb.offense_plays():
		if p is PassPlay:
			pp = p
	ed.select_play(pp)
	await process_frame
	var offered := false
	for o in ed.options.find_children("*", "OptionButton", true, false):
		for i in o.item_count:
			offered = offered or o.get_item_text(i) == "bang"
	_expect(offered, "the play options offer the playbook's own route")
	re._delete_selected()
	_expect(pb.custom_route("bang") == null, "deleting a route")


## Clicks a receiver on the editor's field and reshapes his route there: it becomes the
## play's own "Custom" route (the playbook's routes untouched), survives a reload, and picking
## a route from his drop-down swaps it back out.
func _play_route_through_ui(ed: Node) -> void:
	var pb: Playbook = ed.playbook
	var pp: PassPlay = null
	for p in pb.offense_plays():
		if p is PassPlay and p.formation.has_slot("WR1"):
			pp = p
	var slot := "WR1"
	pp.set_route(slot, Playbook.route("go")) # one long leg, to hover the middle of
	ed.select_play(pp)
	ed.field.size = Vector2(1200, 540)
	ed.field._layout()
	await process_frame
	var ov: PlayRouteOverlay = ed.route_overlay
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(2, 2)
	ov._gui_input(click)
	_expect(ov.slot == "" and not ov.editable, "clicking off the players picks nobody")
	var actor: SimActor = ed.sim.slots["O:" + slot]
	click.position = ed.field.to_screen(actor.pos)
	ov._gui_input(click)
	click.pressed = false
	ov._gui_input(click)
	_expect(ov.slot == slot and ov.editable, "clicking a receiver on the field picks his route")
	var hover := InputEventMouseMotion.new()
	hover.position = (ov.to_screen(Vector2.ZERO) + ov.to_screen(pp.routes[slot].points[0])) * 0.5
	ov._gui_input(hover)
	_expect(ov._ghost_index == 0, "hovering his route's line shows a new point")
	var at: Vector2 = ov._ghost
	click.pressed = true
	click.position = hover.position
	ov._gui_input(click)
	var drag := InputEventMouseMotion.new()
	for to in [Vector2(10, 2), Vector2(12, 4)]: # each move redraws the play; the drag carries on
		drag.position = ov.to_screen(to)
		ov._gui_input(drag)
	click.pressed = false
	ov._gui_input(click)
	await process_frame
	var r: Route = pp.routes[slot]
	_expect(r.name == Route.CUSTOM and r.points.size() == 2 and r.points[0] == Vector2(12, 4)
		and r.points[1] == Vector2(45, 0), "adding and dragging a point makes it the play's own route: %s %s (ghost %s)" % [r.name, r.points, at])
	_expect(Playbook.route("go").points == [Vector2(45, 0)] and pb.custom_route(Route.CUSTOM) == null,
		"the playbook's routes are left alone")
	var opt: OptionButton = null
	for o in ed.options.find_children("*", "OptionButton", true, false):
		if o.item_count > 1 and o.get_item_text(0) == PlayOptions.BLOCK_LABEL and o.get_parent().get_child(0).text.begins_with(slot + " "):
			opt = o
	_expect(opt != null and opt.get_item_text(opt.selected) == Route.CUSTOM, "his drop-down shows Custom")
	var reloaded: Playbook = null
	for saved in PlaybookStore.list(Playbook.OFFENSE):
		if saved.name == pb.name:
			reloaded = saved
	var saved_route: Route = reloaded.offense_play(pp.name).routes[slot] if reloaded != null else null
	_expect(saved_route != null and saved_route.name == Route.CUSTOM and saved_route.points == r.points,
		"the play's own route is saved with the play")
	for i in opt.item_count:
		if opt.get_item_text(i) == "post":
			opt.select(i)
			opt.item_selected.emit(i)
	await process_frame
	_expect(pp.routes[slot].name == "post" and pp.routes[slot].points == Playbook.route("post").points,
		"picking a route from the drop-down replaces the custom one")
	_expect(ov.route == pp.routes[slot], "and the field shows the new route")
	ed.select_play(null)


## Picks a defense to line up against (offense: None by default, kept from play to play)
## and runs the selected play through to the end, back to the play art.
func _run_through_ui(ed: Node) -> void:
	var pb: Playbook = ed.playbook
	var plays: Array = pb.offense_plays() if ed.is_offense() else pb.defense_plays()
	ed.select_play(null)
	_expect(ed.run_button.disabled, "%s: Run Play is off with no play selected" % pb.name)
	ed.select_play(plays[0])
	await process_frame
	_expect(not ed.run_button.disabled, "%s: and on once one is" % pb.name)
	if ed.is_offense():
		_expect(ed.defense_pick.selected == 0 and ed.sim.defenders().is_empty(),
			"the defense starts as None: no defenders on the field")
		var stock_calls := 0
		for f in Playbook.defense_packages():
			stock_calls += f.plays.size()
		_expect(ed.defense_pick.item_count == stock_calls + 1, "the defense list is None plus every stock call")
		ed.defense_pick.select(1)
		ed.defense_pick.item_selected.emit(1)
		_expect(ed.sim.defenders().size() == 11, "picking a defense lines it up")
		ed.select_play(plays[1])
		_expect(ed.defense_pick.selected == 1 and ed.sim.def_play == ed.opponent_defense()
			and ed.sim.defenders().size() == 11, "the defense stays picked moving to another play")
		ed.defense_pick.select(0)
		ed.defense_pick.item_selected.emit(0)
	for p in plays.slice(0, 3):
		ed.select_play(p)
		ed.run_play()
		_expect(ed.running and not ed.field.preview, "%s: Run Play starts %s" % [pb.name, p.name])
		var ticks := 0
		while ed.running and ticks < 2000:
			ed._process(0.05)
			ticks += 1
		_expect(not ed.running and ed.field.preview and ed.sim != null and ed.sim.t == 0.0,
			"%s: %s plays out, then the play art comes back" % [pb.name, p.name])
	ed.select_play(null)


func _edit_through_ui(ed: Node) -> void:
	var pb: Playbook = ed.playbook
	var formations: Array = pb.offensive_formations if ed.is_offense() else pb.defensive_formations
	var f: Resource = formations[0]
	var before: int = f.plays.size()
	_expect(ed._name_problem("") != "" and ed._name_problem(f.plays[0].name) != "", "%s: blank and taken names are refused" % pb.name)
	for is_run in ([false, true] if ed.is_offense() else [false]):
		var n := "UI Run" if is_run else "UI Play"
		ed._adding_to = f
		ed._add_play(n, is_run, not is_run)
		await process_frame
		var p: Resource = ed.selected_play
		_expect(p != null and p.name == n and f.plays.size() == before + 1, "%s: %s added and selected" % [pb.name, n])
		# Pick the last choice in every enabled drop-down, which is always legal to switch to.
		for opt in ed.options.find_children("*", "OptionButton", true, false):
			if not opt.disabled:
				opt.select(opt.item_count - 1)
				opt.item_selected.emit(opt.item_count - 1)
		await process_frame
		_expect(p.validate().is_empty(), "%s: %s still legal after editing: %s" % [pb.name, n, p.validate()])
		if p is RunPlay:
			_expect(p.run_path == RunPlay.PATHS[-1], "run path drop-down sets the path")
		ed._on_delete_play(p)
		ed.confirm.confirmed.emit()
		await process_frame
		_expect(f.plays.size() == before and ed.selected_play == null, "%s: %s deleted" % [pb.name, n])


## Adds a formation with the builder, dragging everyone onto the field, then reopens it,
## takes a player off and cancels.
func _build_through_ui(ed: Node) -> void:
	var formations: Array = ed._formations()
	var before := formations.size()
	var counts: Dictionary = FormationDraft.OFFENSE_POSITIONS if ed.is_offense() else FormationDraft.DEFENSE_POSITIONS
	ed._on_new_formation("UI Formation", counts)
	await process_frame
	_expect(ed.in_builder() and ed.board.visible and not ed.field.visible, "builder opens for a new formation")
	_expect(ed.formation_panel._save.disabled, "can't save before everyone is placed")
	var d: FormationDraft = ed.draft
	var where := {"QB": Vector2(-4.0, 0.3), "RB": Vector2(-6.5, 0.0), "WR1": Vector2(-0.9, -14.0),
		"WR2": Vector2(-0.9, 14.0), "WR3": Vector2(-1.5, -8.0), "TE": Vector2(-0.9, 4.2)}
	var y := -15.0
	for s in d.unplaced_spots():
		var at: Vector2 = where.get(s.slot, Vector2(5.0, y))
		y += 3.0
		ed.board._drop_data(ed.board.to_screen(at), {"formation_slot": s.slot})
	await process_frame
	_expect(d.unplaced_spots().is_empty() and not ed.formation_panel._save.disabled,
		"everyone placed, save enabled: %s" % [ed.formation_panel.problems()])
	ed._save_formation()
	await process_frame
	_expect(not ed.in_builder() and formations.size() == before + 1, "saving adds the formation")
	var f: Resource = formations[-1]
	_expect(f.is_legal(), "the saved formation is legal: %s" % [f.validate()])

	ed._on_edit_formation(f)
	await process_frame
	var slot: String = ed.draft.placed_spots()[-1].slot
	_expect(ed.tray._can_drop_data(Vector2.ZERO, {"formation_slot": slot}), "a placed player can go back to the tray")
	ed.tray._drop_data(Vector2.ZERO, {"formation_slot": slot})
	await process_frame
	_expect(ed.formation_panel._save.disabled, "taking a player off disables save")
	ed._close_builder()
	_expect(f.spots.size() == 11 and f.is_legal(), "cancelling leaves the formation as it was")
	ed._on_edit_formation(f)
	ed._on_delete_formation(f)
	ed.confirm.confirmed.emit()
	await process_frame
	_expect(formations.size() == before and not ed.in_builder(), "deleting from the builder removes the formation")


func _clear_store() -> void:
	for kind in [Playbook.OFFENSE, Playbook.DEFENSE]:
		var dir := PlaybookStore.dir_for(kind)
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute("%s/%s" % [dir, f])


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## Stands in for main.gd: holds the teams and swallows screen changes.
class MainStub extends Control:
	var my_team: Team
	var cpu_team: Team

	func show_menu() -> void:
		pass

	func show_playbooks() -> void:
		pass

	func show_playbook_editor(_pb: Playbook) -> void:
		pass
