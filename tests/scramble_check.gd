extends SceneTree
## QB scrambling (the rollout):
##   godot --headless --script res://tests/scramble_check.gd
## - a QB under PlaySim.MIN_SCRAMBLE_SPEED never rolls out, a faster one does (only once pressured),
## - a rolling QB keeps reading, and ends it with a throw, a tuck-and-run or a throw-away,
## - a throw back across the run is penalized and says so, and one with the run is not,
## - the pocket rules still hold: a QB who rolls out and is hit behind the line is sacked.

var fails := 0


func _expect(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _set_qb_speed(team: Team, spd: int) -> void:
	for p in team.roster:
		if p.position == "QB":
			p.ratings["spd"] = spd


func _initialize() -> void:
	var gen := TeamGenerator.new(5)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var pb := Playbook.make_default()

	var slow_rolls := 0
	var fast_rolls := 0
	var rolled_unpressured := 0
	var ends := {}
	var with_run := 0
	var rolled_sacks := 0
	for spd in [PlaySim.MIN_SCRAMBLE_SPEED - 1, PlaySim.MIN_SCRAMBLE_SPEED + 1]:
		_set_qb_speed(a, spd)
		for rep in 150:
			for play in pb.offense_plays():
				if not play is PassPlay:
					continue
				var sim := PlaySim.new()
				sim.setup(a, b, play, pb.defense_plays()[rep % pb.defense_plays().size()], 30.0, 26.6,
					{"down": 1, "to_go": 10}, Dice.new(rep * 13 + 5))
				var rolled := false
				var guard := 0
				while not sim.done and guard < 900:
					sim.step()
					guard += 1
					if sim.qb_state == "rollout":
						if not rolled and not sim.under_pressure:
							rolled_unpressured += 1
						rolled = true
				if rolled:
					if spd < PlaySim.MIN_SCRAMBLE_SPEED:
						slow_rolls += 1
					else:
						fast_rolls += 1
						var kind: String = sim.result.get("kind", "?")
						ends[kind] = int(ends.get(kind, 0)) + 1
						if kind == "sack":
							rolled_sacks += 1
						for e in sim.events:
							if str(e["detail"]).begins_with("Accuracy") and str(e["detail"]).contains("pressured"):
								with_run += 1
				sim.dispose()
	print("  rollouts at speed >= min: ", fast_rolls, " ends: ", ends)
	_expect(slow_rolls == 0, "a QB under the minimum scramble speed never rolls out")
	_expect(fast_rolls > 0, "a QB at or over it does")
	_expect(rolled_unpressured == 0, "and only once pressured")
	_expect(ends.size() > 1, "a rollout ends more than one way (throw, run, sack...)")
	_expect(with_run > 0, "rollout throws are made on the run")

	# Throwing back across the run: forced, so it doesn't depend on how the rollouts fall.
	var flagged := {}
	for dir in [1.0, -1.0]:
		var sim := PlaySim.new()
		var play: PassPlay = pb.offense_plays().filter(func(p: OffensivePlay) -> bool: return p is PassPlay)[0]
		sim.setup(a, b, play, pb.defense_plays()[0], 30.0, 26.6, {"down": 1, "to_go": 10}, Dice.new(3))
		for i in 20:
			sim.step()
		var rec: SimActor = sim.slots["O:" + play.reads[0]]
		var toward := (sim._catch_point(rec) - sim.qb.pos).normalized()
		sim.pending_move = toward * dir * 5.0 # running toward / directly away from the receiver
		sim._release(rec, true)
		var text := ""
		for e in sim.events:
			text += str(e["detail"])
		flagged[dir] = text.contains("throwing back across the run")
		sim.dispose()
	_expect(flagged[1.0] == false, "a throw in the direction of the run is not penalized")
	_expect(flagged[-1.0] == true, "a throw back across it is, and says so")

	print("scramble_check: ", "OK" if fails == 0 else "FAILED", " (%d failures)" % fails)
	quit(fails)
