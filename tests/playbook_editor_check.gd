extends SceneTree
## Checks the data side of the playbook editor: new playbooks start legal with the right
## packages, editing a play keeps it consistent, and playbooks survive a save and reload.
## Then opens the editor screen on each kind of playbook to make sure it builds.
##   godot --headless --script res://tests/playbook_editor_check.gd
const PlaybookEditor := preload("res://scripts/ui/playbook_editor.gd")
const PlaybooksScreen := preload("res://scripts/ui/playbooks_screen.gd")

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
	for slot in ["WR1", "WR2", "TE", "RB"]:
		pa.set_block(slot)
	_expect(not pa.validate().is_empty(), "a pass play with nobody running a route is caught")
	pa.set_route("TE", Playbook.route("seam"))
	pa.drop = 5.5
	pa.read_start = 0.9
	call.set_assignment(CoverageAssignment.in_zone("FS", Playbook.zone("Deep Middle")))
	call.set_assignment(CoverageAssignment.blitz("MIKE"))
	_expect(call.validate().is_empty() and call.assignments.size() == 7, "editing a call keeps one job per defender")

	# Save and reload, from scratch.
	PlaybookStore.save(off)
	PlaybookStore.save(def)
	var path := off.resource_path
	off = null
	def = null
	pistol = null
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

	await _check_screens(loaded, defs[0], a, b)

	_clear_store()
	print("playbook_editor_check: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


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
		await _edit_through_ui(ed)
		ed.queue_free()
		await process_frame
	stub.queue_free()


## Adds a play with the dialog's callback, flips every option on the bottom panel, then
## deletes the play, the way a user would.
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
