extends SceneTree
## Every stock formation is legal and every offensive play runs against every defensive call
## (a few snaps each, from midfield and the red zone) without breaking the sim.
##   godot --headless --script res://tests/stock_formations_check.gd
var failures := 0


func _init() -> void:
	var pb := Playbook.make_default()
	var errs := pb.validate()
	_expect(errs.is_empty(), "stock playbook is legal: %s" % [errs])
	_expect(pb.offensive_formations.size() >= 5 and pb.defensive_formations.size() >= 7, "stock formations are all there")
	for f in pb.defensive_formations:
		var dl := 0
		var backs := 0
		for s in f.spots:
			if s.position == "DL": dl += 1
			elif s.position in ["CB", "S"]: backs += 1
		print("  %-16s %d linemen, %d defensive backs, %d calls" % [f.name, dl, backs, f.plays.size()])

	var gen := TeamGenerator.new(7)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var dice := Dice.new(11)
	var plays := 0
	for off in pb.offense_names():
		for de in pb.defense_names():
			for i in 4:
				var sim := PlaySim.new()
				var spot := 50.0 if i % 2 == 0 else 92.0
				sim.setup(a, b, pb.offense_play(off), pb.defense_play(de), spot, 26.67, {"down": 1, "to_go": 10}, dice)
				_expect(sim.actors.size() == 22, "%s vs %s has 22 players" % [off, de])
				var r := sim.run_to_end()
				_expect(r.has("kind") and is_finite(float(r["end_x"])), "%s vs %s ends with a result" % [off, de])
				plays += 1
				sim.dispose()
	print("stock_formations_check: %s (%d plays, %d failures)" % ["OK" if failures == 0 else "FAILED", plays, failures])
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
