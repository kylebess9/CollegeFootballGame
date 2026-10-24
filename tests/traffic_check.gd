extends SceneTree
## Defenders squeezing through a block are slowed (issue #59):
##   godot --headless --script res://tests/traffic_check.gd
## - a free defender heading into a teammate's block (the engaged defender or his blocker, within
##   PlaySim.TRAFFIC_RANGE and ahead of him) is in traffic; one moving away from it, one far from
##   it and the engaged defender himself are not, and neither is an offensive player,
## - in traffic a defender covers TRAFFIC_SLOW of his usual ground in a step,
## - a free rusher squeezing through a block reaches the QB later than one coming around it from
##   the same distance, and the stock blitzes do get slowed this way in real plays.

var fails := 0


func _expect(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	var gen := TeamGenerator.new(5)
	var dice := Dice.new(9)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var pb := Playbook.make_default()

	# Geometry, on a hand-placed field.
	var sim := PlaySim.new()
	sim.setup(a, b, pb.offense_play("Four Verticals"), pb.defense_play("Blitz"), 35.0, 26.67, {}, dice)
	var dl: SimActor = null
	var blocker: SimActor = null
	for d in sim.defenders():
		if d.position == "DL":
			dl = d
			break
	for o in sim.offense():
		if o.position == "OL":
			blocker = o
			break
	var lb: SimActor = sim.slots["D:MIKE"]
	for x in sim.actors:
		x.engaged = null
	dl.pos = Vector2(60.0, 26.0)
	blocker.pos = Vector2(59.2, 26.0)
	dl.engaged = blocker
	blocker.engaged = dl
	var toward := Vector2.LEFT # the defense goes toward the offense's goal, -x
	lb.pos = Vector2(61.0, 26.3)
	_expect(sim.in_traffic(lb, toward), "a defender heading into a teammate's block is in traffic")
	_expect(not sim.in_traffic(lb, Vector2.RIGHT), "moving away from the block, he isn't")
	lb.pos = Vector2(58.4, 26.3)
	_expect(sim.in_traffic(lb, toward) == false, "once past the blocker, he isn't")
	lb.pos = Vector2(61.0, 30.0)
	_expect(not sim.in_traffic(lb, toward), "a defender wide of the block (an edge rush) isn't")
	_expect(not sim.in_traffic(dl, toward), "the engaged defender himself isn't")
	var wr: SimActor = null
	for o in sim.offense():
		if o.job == "route":
			wr = o
			break
	wr.pos = Vector2(61.0, 26.3)
	_expect(not sim.in_traffic(wr, toward), "an offensive player never is")
	wr.pos = Vector2(80.0, 5.0)

	# Speed: one step in traffic against one in the open, same target, same player.
	lb.pos = Vector2(61.0, 26.3)
	var start := lb.pos
	lb.job = "pursue"
	sim.qb.pos = Vector2(50.0, 26.3)
	var to_qb := (sim.qb.pos - lb.pos).normalized()
	sim._move(lb)
	var traffic_step := lb.pos.distance_to(start)
	lb.pos = Vector2(61.0, 40.0)
	sim.qb.pos = Vector2(50.0, 40.0)
	var open_start := lb.pos
	sim._move(lb)
	var open_step := lb.pos.distance_to(open_start)
	_expect(to_qb.x < 0.0 and open_step > 0.0, "the open step moves him toward the QB (%.3f yd)" % open_step)
	_expect(absf(traffic_step - open_step * PlaySim.TRAFFIC_SLOW) < 0.01,
		"in traffic he covers %.0f%% of the ground (%.3f vs %.3f yd)" % [PlaySim.TRAFFIC_SLOW * 100.0, traffic_step, open_step])
	sim.dispose()

	# A free rusher straight behind the block gets to the QB later than one the same distance
	# away who comes around it.
	var through := _time_to_qb(a, b, pb, dice, Vector2(50.0, 26.0))
	var around := _time_to_qb(a, b, pb, dice, Vector2(41.0 + 9.0 * cos(0.6), 26.0 + 9.0 * sin(0.6)))
	_expect(through > around + 0.05, "squeezing through the block is slower than coming around it (%.2f s vs %.2f s)" % [through, around])

	# Real plays: the stock blitzes do run into traffic.
	var hits := 0
	var tries := 0
	for call in ["Blitz", "Nickel Blitz", "46 Blitz", "3-4 Zone Blitz"]:
		for i in 40:
			hits += _blitzers_in_traffic(a, b, pb, call, dice)
			tries += 1
	print("  plays with a blitzer slowed in traffic: %d/%d" % [hits, tries])
	_expect(hits > 0, "stock blitzes do get slowed squeezing through blocks")

	print("traffic_check: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


## Seconds a free rusher starting at from takes to get within a yard of a QB standing behind
## an engaged DT and guard at (45-46, 26).
func _time_to_qb(a: Team, b: Team, pb: Playbook, dice: Dice, from: Vector2) -> float:
	var sim := PlaySim.new()
	sim.setup(a, b, pb.offense_play("Four Verticals"), pb.defense_play("Blitz"), 35.0, 26.67, {}, dice)
	var dt: SimActor = sim.slots["D:DT1"]
	var og: SimActor = sim.slots["O:LG"]
	for x in sim.actors:
		x.engaged = null
		x.pos = Vector2(100.0, 50.0)
	dt.pos = Vector2(46.0, 26.0)
	og.pos = Vector2(45.2, 26.0)
	dt.engaged = og
	og.engaged = dt
	sim.qb.pos = Vector2(41.0, 26.0)
	var r: SimActor = sim.slots["D:MIKE"]
	r.job = "rush"
	r.pos = from
	var time := 0.0
	while r.pos.distance_to(sim.qb.pos) > 1.0 and time < 5.0:
		sim._move(r)
		time += PlaySim.DT
	sim.dispose()
	return time


## 1 if any blitzer in this call was slowed in traffic before the throw, in one dropback.
func _blitzers_in_traffic(a: Team, b: Team, pb: Playbook, call: String, dice: Dice) -> int:
	var sim := PlaySim.new()
	sim.setup(a, b, pb.offense_play("Four Verticals"), pb.defense_play(call), 35.0, 26.67, {}, dice)
	var rushers: Array[SimActor] = []
	for d in sim.defenders():
		if d.job == "rush" and d.position != "DL":
			rushers.append(d)
	var hit := 0
	while not sim.done and sim.holder == sim.qb and hit == 0:
		var before := {}
		for d in rushers:
			before[d] = d.pos
		sim.step()
		for d in rushers:
			var dir: Vector2 = d.pos - before[d]
			if dir.length() > 0.001 and sim.in_traffic(d, dir.normalized()):
				hit = 1
	sim.dispose()
	return hit
