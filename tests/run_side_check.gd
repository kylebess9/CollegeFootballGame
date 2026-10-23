extends SceneTree
## RB run side: a back lined up off to one side of the ball always runs (and swings, and fakes)
## to that side; one directly behind the ball still goes either way.
##   godot --headless --script res://tests/run_side_check.gd

const RUNS := 200

var fails := 0
var _keep: Array[OffensiveFormation] = [] # plays hold their formation weakly


func _init() -> void:
	var gen := TeamGenerator.new(3)
	var dice := Dice.new(4)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var pb := Playbook.make_default()
	var de := pb.defense_play("Cover 3")
	for rb_y in [0.0, -3.0, 3.0]:
		var f := _pistol_with_rb_at(rb_y)
		for play_name in ["Inside Run", "Outside Run", "Curl Flat"]:
			var sides := {}
			for i in RUNS:
				var sim := PlaySim.new()
				sim.setup(a, b, _find(f, play_name), de, 40.0, 26.67, {"down": 1, "to_go": 10}, dice)
				var rb: SimActor = sim.slots["O:RB"]
				var end_y: float = rb.path[rb.path.size() - 1].y
				var went := 1 if end_y > sim.ball_y else -1
				if went != sim.run_side:
					print("  %s: path went %d but run_side is %d" % [play_name, went, sim.run_side])
					fails += 1
				sides[went] = true
				sim.dispose()
			var label := "RB at %+.0f, %s: sides %s" % [rb_y, play_name, sides.keys()]
			print(label)
			if rb_y == 0.0 and sides.size() != 2:
				print("  centered back should go both ways")
				fails += 1
			elif rb_y != 0.0 and sides.keys() != [int(signf(rb_y))]:
				print("  offset back should only go to his own side")
				fails += 1
	_keep.clear()
	print("FAIL" if fails > 0 else "OK")
	quit(1 if fails > 0 else 0)


func _find(f: OffensiveFormation, play_name: String) -> OffensivePlay:
	for p in f.plays:
		if p.name == play_name:
			return p
	return null


func _pistol_with_rb_at(y: float) -> OffensiveFormation:
	var f: OffensiveFormation = Playbook.offense_packages()[0]
	for s in f.spots:
		if s.slot == "RB":
			s.offset.y = y
	_keep.append(f)
	return f
