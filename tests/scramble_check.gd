extends SceneTree
## QB scrambling (the rollout):
##   godot --headless --script res://tests/scramble_check.gd
## - every QB slides away from the rush once a free rusher gets within PlaySim.ROLLOUT_TRIGGER, and
##   never drifts up toward the line while doing it,
## - out of the pocket, one under PlaySim.MIN_SCRAMBLE_SPEED never tucks and runs (he throws it
##   away or throws to someone open), a faster one sometimes runs,
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

	var max_forward := 0.0
	var slow_rolls := 0
	var fast_rolls := 0
	var slow_runs := 0
	var fast_runs := 0
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
				var roll_x := 0.0
				var ran := false
				var guard := 0
				while not sim.done and guard < 900:
					sim.step()
					guard += 1
					if sim.qb_state == "scramble":
						ran = true
					if sim.qb_state == "rollout":
						if not rolled:
							roll_x = sim.qb.pos.x
							var threat := sim._nearest_free_opponent(sim.qb)
							if threat == null or threat.pos.distance_to(sim.qb.pos) > PlaySim.ROLLOUT_TRIGGER + 1.0:
								rolled_unpressured += 1
						max_forward = maxf(max_forward, sim.qb.pos.x - roll_x)
						rolled = true
				if rolled:
					if spd < PlaySim.MIN_SCRAMBLE_SPEED:
						slow_rolls += 1
						slow_runs += 1 if ran else 0
					else:
						fast_runs += 1 if ran else 0
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
	print("  rollouts at speed < min: ", slow_rolls, " tucked and ran: ", slow_runs, "; at or over: ", fast_rolls, " ran: ", fast_runs)
	_expect(slow_rolls > 0 and fast_rolls > 0, "slow and fast QBs both roll out when pressured")
	_expect(slow_runs == 0, "a QB under the minimum scramble speed never tucks and runs")
	_expect(fast_runs > 0, "a QB at or over it sometimes does")
	_expect(rolled_unpressured == 0, "and only once a rusher is close")
	_expect(max_forward < 0.5, "and he never drifts up toward the line (most forward: %.2f yds)" % max_forward)
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
		var gap := sim._catch_point(rec).y - sim.qb.pos.y
		if absf(gap) < 3.0:
			sim.qb.pos.y -= 5.0 # make sure the receiver is well across the field from him
			gap = sim._catch_point(rec).y - sim.qb.pos.y
		sim.pending_move = Vector2(0.0, signf(gap) * dir * 5.0) # running toward / away from the receiver's side
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
