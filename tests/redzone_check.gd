extends SceneTree
## Regression test: catches and runs into the end zone must always be touchdowns.
##   godot --headless --script res://tests/redzone_check.gd
func _init() -> void:
	var gen := TeamGenerator.new(3)
	var dice := Dice.new(4)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var tds := 0
	var bad := 0
	var catch_td := 0
	for off in Playbook.offense_names():
		for de in Playbook.defense_names():
			for i in 90:
				var sim := PlaySim.new()
				sim.setup(a, b, off, de, 88.0, 26.67, {"down": 1, "to_go": 10}, 0, 0, dice)
				var r := sim.run_to_end()
				if r["kind"] == "td":
					tds += 1
					if r["thrown"]: catch_td += 1
				elif not r["turnover"] and float(r["end_x"]) >= 110.0:
					bad += 1
				var gs := GameState.new(a, b, 8.0, dice)
				gs.ball_on = 88.0
				var before := gs.score[1]
				gs.apply_play(r, Playbook.is_run(off))
				if r["kind"] == "td" and gs.score[gs.AWAY] == before:
					bad += 1
				sim.dispose()
	print("plays=3150 TDs=%d (passing %d)  plays ending in end zone without TD=%d" % [tds, catch_td, bad])
	quit()
