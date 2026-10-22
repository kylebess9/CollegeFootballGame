extends SceneTree
## Checks the stock playbook is legal and that the formation rules catch illegal setups.
##   godot --headless --script res://tests/playbook_check.gd
var failures := 0


func _init() -> void:
	var pb := Playbook.make_default()
	var errs := pb.validate()
	for e in errs:
		print("  stock playbook: ", e)
	_expect(errs.is_empty(), "stock playbook is legal")
	_expect(pb.is_kick("Punt") and pb.is_kick("Field Goal"), "stock playbook has Punt and Field Goal")
	for p in pb.offense_plays():
		_expect(p.formation != null, "%s knows its formation" % p.name)
	for p in pb.defense_plays():
		_expect(p.formation != null and p.formation.spots.size() == 11, "%s puts 11 on the field" % p.name)

	var pistol: OffensiveFormation = pb.offensive_formations[0]
	# 10 players
	var f := OffensiveFormation.make("Ten", pistol.spots.slice(0, 10))
	_expect(not f.is_legal(), "10-man formation is illegal")
	# Pull WR1 off the line: only 6 on the line, 5 in the backfield.
	f = _copy(pistol)
	f.spot("WR1").offset = Vector2(-5.0, -13.0)
	_expect(not f.is_legal(), "6 on the line / 5 in the backfield is illegal")
	# QB not behind the center.
	f = _copy(pistol)
	f.spot("QB").offset = Vector2(-4.0, 3.0)
	_expect(not f.is_legal(), "QB not behind the center is illegal")
	# A pass play that reads someone who isn't running a route.
	f = _copy(pistol)
	var routes: Dictionary[String, Route] = {"WR1": Playbook.route("go")}
	f.add_play(PassPlay.make("Bad Read", "", 7.0, 1.0, false, routes, [], ["WR2"]))
	_expect(not f.is_legal(), "reading a non-route runner is caught")

	var base: DefensiveFormation = pb.defensive_formations[0]
	var d := DefensiveFormation.make("Ten", base.spots.slice(0, 10))
	_expect(not d.is_legal(), "10-man defense is illegal")
	d = DefensiveFormation.make("Copy", base.spots.duplicate())
	var assigns: Array[CoverageAssignment] = [CoverageAssignment.man("CB1")]
	d.add_play(DefensivePlay.make("Half Call", "", assigns))
	_expect(not d.is_legal(), "a call that leaves defenders unassigned is caught")

	# The sim lines everyone up from the formations and resolves man/blocking assignments.
	var gen := TeamGenerator.new(5)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var dice := Dice.new(2)
	var sim := PlaySim.new()
	sim.setup(a, b, pb.offense_play("Quick Slants"), pb.defense_play("Cover 1 Man"), 35.0, 26.67, {}, dice)
	_expect(sim.actors.size() == 22, "22 players on the field")
	var men := {}
	for x in sim.defenders():
		if x.job == "man":
			_expect(x.man_target != null and not men.has(x.man_target), "%s has his own man" % x.slot)
			men[x.man_target] = true
	_expect(sim.slots["D:CB1"].man_target == sim.slots["O:WR1"], "CB1 picks up WR1, the receiver he lines up over")
	_expect(sim.slots["O:LT"].block_target == sim.slots["D:DE1"], "LT blocks the closest rusher (DE1)")
	sim.dispose()
	sim = PlaySim.new()
	sim.setup(a, b, pb.offense_play("Inside Run"), pb.defense_play("Cover 3"), 35.0, 26.67, {}, dice)
	_expect(sim.slots["O:C"].block_target == sim.slots["D:MIKE"], "on a run the center climbs to MIKE")
	_expect(sim.slots["O:WR3"].block_target == sim.slots["D:SS"], "on a run the slot blocks the safety over him")
	sim.dispose()

	print("playbook_check: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _copy(f: OffensiveFormation) -> OffensiveFormation:
	var spots: Array[FormationSpot] = []
	for s in f.spots:
		spots.append(s.duplicate())
	return OffensiveFormation.make(f.name, spots)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
