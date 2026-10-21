extends SceneTree
## Regression test: catches and runs into the end zone must always be touchdowns,
## and no catch or interception may happen out of bounds.
##   godot --headless --script res://tests/redzone_check.gd
func _init() -> void:
	var gen := TeamGenerator.new(3)
	var dice := Dice.new(4)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var tds := 0
	var bad := 0
	var catch_td := 0
	var oob_catch := 0
	var catches := 0
	for off in Playbook.offense_names():
		for de in Playbook.defense_names():
			for i in 90:
				var sim := PlaySim.new()
				var spot := 70.0 + (i % 4) * 7.0 # 70, 77, 84, 91
				sim.setup(a, b, off, de, spot, 26.67, {"down": 1, "to_go": 10}, 0, 0, dice)
				var r := sim.run_to_end()
				# Every catch and interception must happen inside the field of play.
				for e in sim.events:
					var txt: String = e["text"]
					if txt.begins_with("Caught by") or txt.begins_with("INTERCEPTED"):
						catches += 1
						var p: Vector2 = e["pos"]
						if p.x > 120.0 or p.x < 0.0 or p.y < 0.0 or p.y > 53.333:
							oob_catch += 1
				if r["kind"] == "td":
					tds += 1
					if r["thrown"]: catch_td += 1
				elif not r["turnover"] and float(r["end_x"]) >= 110.0:
					bad += 1
				var gs := GameState.new(a, b, 8.0, dice)
				gs.ball_on = spot
				var before := gs.score[1]
				gs.apply_play(r, Playbook.is_run(off))
				if r["kind"] == "td" and gs.score[gs.AWAY] == before:
					bad += 1
				sim.dispose()
	print("plays=3150 TDs=%d (passing %d)  plays ending in end zone without TD=%d" % [tds, catch_td, bad])
	print("catches+INTs=%d  made out of bounds=%d" % [catches, oob_catch])
	quit()
