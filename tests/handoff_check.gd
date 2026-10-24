extends SceneTree
## Handoffs, pitches and backward-pass fumbles on run plays:
##   godot --headless --script res://tests/handoff_check.gd
## - the stock Inside Run is a handoff (the RB reaches the QB in time),
## - a run whose time_delay runs out before the RB gets there becomes a pitch, caught on 2+ with
##   a re-roll, and a pitch never counts as a pass attempt,
## - a dropped pitch (a pass behind the QB) is a fumble: the ball scatters and somebody scoops it
##   up, or it's dead out of bounds; the play always ends in a legal result,
## - time_delay saves and validates.

var fails := 0
var _keep: OffensiveFormation # plays hold their formation weakly


func _expect(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _count(sim: PlaySim, prefix: String) -> int:
	var n := 0
	for e in sim.events:
		if str(e["text"]).begins_with(prefix) or str(e["text"]).contains(prefix):
			n += 1
	return n


func _init() -> void:
	var gen := TeamGenerator.new(5)
	var dice := Dice.new(9)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var pb := Playbook.make_default()
	var defense := pb.defense_names()

	# The stock inside run: always a handoff.
	var handoffs := 0
	var pitches := 0
	for de in defense:
		for i in 60:
			var sim := PlaySim.new()
			sim.setup(a, b, pb.offense_play("Inside Run"), pb.defense_play(de), 35.0, 26.67, {}, dice)
			sim.run_to_end()
			handoffs += _count(sim, "takes the handoff")
			pitches += _count(sim, "pitches it")
			sim.dispose()
	_expect(handoffs == defense.size() * 60 and pitches == 0, "Inside Run is always a handoff (%d handoffs, %d pitches)" % [handoffs, pitches])

	# The same run with no time to get there: always a pitch. The RB is still coming forward
	# past the QB, so the pitch goes slightly forward and a drop is just incomplete.
	var quick := pb.offense_play("Inside Run").duplicate() as RunPlay
	quick.formation = pb.offense_play("Inside Run").formation
	quick.time_delay = 0.2
	_expect(quick.validate().is_empty(), "a 0.2 s time_delay is legal")
	var odd := 0
	var thrown := 0
	var fwd_drops := 0
	var fwd_fumbles := 0
	for de in defense:
		for i in 100:
			var sim := PlaySim.new()
			sim.setup(a, b, quick, pb.defense_play(de), 35.0, 26.67, {}, dice)
			var r := sim.run_to_end()
			if _count(sim, "pitches it") != 1 or _count(sim, "takes the handoff") != 0:
				odd += 1
			if r["thrown"]:
				thrown += 1
			fwd_drops += _count(sim, "Pitch dropped")
			fwd_fumbles += _count(sim, "drops the pitch")
			sim.dispose()
	_expect(odd == 0, "a run whose time_delay runs out is always a pitch (%d odd)" % odd)
	_expect(thrown == 0, "a pitch is never counted as a pass attempt")
	_expect(fwd_fumbles == 0, "a dropped forward pitch is incomplete, not a fumble (%d drops)" % fwd_drops)

	# Under center, the outside run's RB swings wide of the QB and never gets to him: a pitch
	# back to him, so a drop is a fumble.
	var toss := _under_center_toss()
	_expect(toss.validate().is_empty() and toss.formation.validate().is_empty(), "the under-center test formation is legal")
	var n := 0
	var sacks := 0
	var caught := 0
	var drops := 0
	var fumbles := 0
	var bad := 0
	var kinds := {}
	for de in defense:
		for i in 400:
			var sim := PlaySim.new()
			sim.setup(a, b, toss, pb.defense_play(de), 35.0 + (i % 3) * 30.0, 26.67, {}, dice)
			var r := sim.run_to_end()
			n += _count(sim, "pitches it")
			if _count(sim, "SACKED") > 0:
				sacks += 1 # dropped before the QB could get rid of it
			caught += _count(sim, "gathers in the pitch")
			drops += _count(sim, "drops the pitch") + _count(sim, "can't reach the backward pass")
			if _count(sim, "drops the pitch") + _count(sim, "can't reach the backward pass") > 0:
				# Not a later fumble on the tackle after the RB falls on it.
				for e in sim.events:
					var txt := str(e["text"])
					if txt.begins_with("FUMBLE! RB") and not txt.ends_with("'s team falls on it"):
						fumbles += 1
				kinds[r["kind"]] = int(kinds.get(r["kind"], 0)) + 1
			if r["thrown"] or not r["kind"] in ["tackle", "oob", "td", "safety", "fumble", "def_td", "int", "sack"]:
				bad += 1
			sim.dispose()
	print("    Toss: %d plays, %d sacks first, %d pitches, %d caught, %d dropped (2+ with a re-roll misses 2.8%%)" % [defense.size() * 400, sacks, n, caught, drops])
	_expect(n + sacks == defense.size() * 400, "a run where the RB can't reach the QB is a pitch")
	_expect(drops > 0 and float(drops) / n < 0.08, "a pitch is almost always caught, but not always")
	print("    dropped pitches end as %s" % kinds)
	_expect(fumbles == drops, "every dropped backward pitch is a fumble")
	_expect(bad == 0, "every pitch play ends in a run result")

	# Scooping up a loose ball: force a dropped pitch and play it out many times.
	var outcomes := {}
	var bad_kind := 0
	for i in 300:
		var sim := PlaySim.new()
		sim.setup(a, b, toss, pb.defense_play(defense[i % defense.size()]), 35.0, 26.67, {}, dice)
		while not sim.done and not sim.pitched:
			sim.step()
		while not sim.done and sim.ball_in_air:
			sim.step()
		if sim.done or sim.holder == null:
			sim.dispose()
			continue
		# Pretend he dropped it.
		sim.holder.job = "rb_run"
		sim.holder = null
		sim._fumble_loose(sim.ball_pos, "test drop", "")
		var r := sim.run_to_end()
		var key := "lost" if r["turnover"] else str(r["kind"])
		outcomes[key] = int(outcomes.get(key, 0)) + 1
		if r["turnover"] and not r["kind"] in ["fumble", "def_td"]:
			bad_kind += 1
		if not r["turnover"] and float(r["end_x"]) >= PlaySim.OPP_GOAL and r["kind"] != "td":
			bad_kind += 1
		sim.dispose()
	print("    forced fumbles: %s" % outcomes)
	_expect(bad_kind == 0, "loose-ball plays end in a legal result")
	_expect(outcomes.has("lost") and (outcomes.has("tackle") or outcomes.has("td")), "both sides recover loose balls")

	# time_delay saves and validates.
	quick.time_delay = 0.05
	_expect(not quick.validate().is_empty(), "a time_delay below the minimum is rejected")
	var path := "user://handoff_check_run.tres"
	var r2 := RunPlay.make("Toss", "", RunPlay.OUTSIDE)
	r2.time_delay = 0.4
	ResourceSaver.save(r2, path)
	var back := load(path) as RunPlay
	_expect(back != null and is_equal_approx(back.time_delay, 0.4), "time_delay survives a save and reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("handoff_check: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)


## The QB under center and the RB seven yards deep, running the outside path.
func _under_center_toss() -> RunPlay:
	var spots: Array[FormationSpot] = [
		FormationSpot.make("C", "OL", Vector2(-0.6, 0.0)),
		FormationSpot.make("LG", "OL", Vector2(-0.7, -1.4)),
		FormationSpot.make("RG", "OL", Vector2(-0.7, 1.4)),
		FormationSpot.make("LT", "OL", Vector2(-0.9, -2.8)),
		FormationSpot.make("RT", "OL", Vector2(-0.9, 2.8)),
		FormationSpot.make("TE", "TE", Vector2(-0.9, 4.3)),
		FormationSpot.make("QB", "QB", Vector2(-1.3, 0.0)),
		FormationSpot.make("RB", "RB", Vector2(-7.0, 0.0)),
		FormationSpot.make("WR1", "WR", Vector2(-0.8, -13.0)),
		FormationSpot.make("WR3", "WR", Vector2(-1.5, -6.0)),
		FormationSpot.make("WR2", "WR", Vector2(-1.5, 15.0)),
	]
	_keep = OffensiveFormation.make("Under Center", spots)
	return _keep.add_play(RunPlay.make("Toss", "", RunPlay.OUTSIDE)) as RunPlay
