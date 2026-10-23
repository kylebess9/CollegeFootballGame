extends SceneTree
## Pass speed:
##   godot --headless --script res://tests/pass_speed_check.gd
## - a clean, unhurried pass leaves at the QB's arm speed (PlaySim._arm_speed(), from Strength),
##   and a stronger QB throws faster,
## - a pressured throw comes out slower than that, by a varying amount,
## - a wobbly duck goes at half speed (or less, if it was also pressured),
## - a pitch on a run always goes at BALL_SPEED, whoever the QB is.

var fails := 0


func _expect(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	var gen := TeamGenerator.new(7)
	var dice := Dice.new(13)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var pb := Playbook.make_default()
	var qb: FootballPlayer = a.depth_chart()["QB"]

	var weak := {}
	var strong := {}
	for s in [1, 6]:
		qb.ratings["str"] = s
		var st := _throws(a, b, pb, dice)
		if s == 1:
			weak = st
		else:
			strong = st
	var arm_weak := PlaySim.ARM_SPEED_BASE + PlaySim.ARM_SPEED_PER_STR * 1
	var arm_strong := PlaySim.ARM_SPEED_BASE + PlaySim.ARM_SPEED_PER_STR * 6
	for st in [weak, strong]:
		print("    clean %d, hurried %d (%.1f-%.1f yd/s), ducks %d, pitches %d" % [
			st["clean"].size(), st["hurried"].size(), _min(st["hurried"]), _max(st["hurried"]),
			st["duck"].size(), st["pitch"].size()])
	_expect(weak["clean"].size() > 20 and _min(weak["clean"]) == arm_weak and _max(weak["clean"]) == arm_weak,
		"a clean pass leaves at arm speed (Strength 1: %.0f)" % arm_weak)
	_expect(strong["clean"].size() > 20 and _min(strong["clean"]) == arm_strong and _max(strong["clean"]) == arm_strong,
		"a stronger QB throws faster (Strength 6: %.0f)" % arm_strong)
	_expect(weak["hurried"].size() > 10 and _max(weak["hurried"]) <= arm_weak and _min(weak["hurried"]) < arm_weak * 0.8,
		"a pressured throw loses a varying amount of speed")
	_expect(strong["hurried"].size() > 10 and _min(strong["hurried"]) >= arm_strong * (1.0 - PlaySim.HURRY_SPEED_LOSS / 6.0) - 0.001,
		"a strong arm loses less of it under pressure")
	var ducks: Array = weak["duck"] + strong["duck"]
	var duck_ok := ducks.size() > 5
	for d in ducks:
		if d[0] > d[1] * PlaySim.DUCK_SPEED + 0.001:
			duck_ok = false
	_expect(duck_ok, "a wobbly duck goes at half speed or less (%d ducks)" % ducks.size())
	var pitches: Array = weak["pitch"] + strong["pitch"]
	_expect(pitches.size() > 20 and _min(pitches) == PlaySim.BALL_SPEED and _max(pitches) == PlaySim.BALL_SPEED,
		"a pitch always goes at BALL_SPEED")

	print("pass_speed_check: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit()


## Every play in the stock playbook against every defense (runs with no time for a handoff, so
## they're pitches); the speed of each ball in the air, sorted by kind. Ducks are
## [speed, arm speed] pairs.
func _throws(a: Team, b: Team, pb: Playbook, dice: Dice) -> Dictionary:
	var st := {"clean": [], "hurried": [], "duck": [], "pitch": []}
	for off in pb.offense_names():
		var play := pb.offense_play(off)
		if pb.is_run(off):
			var quick := play.duplicate() as RunPlay
			quick.formation = play.formation
			quick.time_delay = 0.2
			play = quick
		for de in pb.defense_names():
			for i in 25:
				var sim := PlaySim.new()
				sim.setup(a, b, play, pb.defense_play(de), 35.0, 26.67, {}, dice)
				var seen := false
				while not sim.done:
					sim.step()
					if not seen and sim.ball_in_air:
						seen = true
						if sim.pitched:
							st["pitch"].append(sim.ball_speed)
						elif sim.ball_quality == "duck":
							st["duck"].append([sim.ball_speed, sim._arm_speed()])
						elif sim.ball_quality == "away":
							pass
						elif sim.pending_hurried:
							# Throws on the run can lose more (back across it): scramble_check covers those.
							if sim.pending_move.length() <= 0.5:
								st["hurried"].append(sim.ball_speed)
						else:
							st["clean"].append(sim.ball_speed)
				sim.dispose()
	return st


func _min(arr: Array) -> float:
	var m := INF
	for v in arr:
		m = minf(m, v)
	return m


func _max(arr: Array) -> float:
	var m := -INF
	for v in arr:
		m = maxf(m, v)
	return m
