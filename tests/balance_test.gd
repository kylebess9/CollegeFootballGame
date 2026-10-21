extends SceneTree
## Headless balance check. Run with:
##   godot --headless --script res://tests/balance_test.gd
## Prints average results for every offense vs defense call, then simulates full games.


func _init() -> void:
	var gen := TeamGenerator.new(7)
	var dice := Dice.new(11)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var reps := 150
	var totals := {}
	print("%-16s %-12s %6s %6s %6s %6s %6s %6s %5s" % ["offense", "defense", "avg", "succ%", "cmp%", "sack%", "to%", "20+%", "secs"])
	for off in Playbook.offense_names():
		var row_sum := 0.0
		for de in Playbook.defense_names():
			var s := {"yds": 0.0, "succ": 0, "cmp": 0, "att": 0, "sack": 0, "to": 0, "big": 0, "secs": 0.0}
			for i in reps:
				var sim := PlaySim.new()
				sim.setup(a, b, off, de, 35.0, 26.67, {"down": 1, "to_go": 10}, 0, 0, dice)
				var r := sim.run_to_end()
				var y: int = r["yards"]
				if r["turnover"]:
					s["to"] += 1
				else:
					s["yds"] += y
				if y >= 4 and not r["turnover"]:
					s["succ"] += 1
				if y >= 20 and not r["turnover"]:
					s["big"] += 1
				if r["kind"] == "sack":
					s["sack"] += 1
				if r["thrown"]:
					s["att"] += 1
					if r["kind"] in ["tackle", "oob", "td"]:
						s["cmp"] += 1
				s["secs"] += float(r["duration"])
				sim.dispose()
			var avg: float = s["yds"] / reps
			row_sum += avg
			print("%-16s %-12s %6.1f %6.0f %6.0f %6.1f %6.1f %6.1f %5.1f" % [off, de, avg,
				100.0 * s["succ"] / reps,
				(100.0 * s["cmp"] / s["att"]) if s["att"] > 0 else 0.0,
				100.0 * s["sack"] / reps, 100.0 * s["to"] / reps, 100.0 * s["big"] / reps,
				s["secs"] / reps])
		totals[off] = row_sum / Playbook.defense_names().size()
	print("\nAverage by offensive call: ", totals)

	print("\nFull games (CPU vs CPU, 15 min quarters):")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var pts := 0
	var plays := 0
	var games := 20
	for g in games:
		var home := gen.make_team(g % 10, Color.BLUE)
		var away := gen.make_team((g + 3) % 10, Color.RED)
		var gs := GameState.new(home, away, 15.0, dice)
		var guard := 0
		while not gs.over and guard < 400:
			guard += 1
			var oc := CoachAI.pick_offense(gs, rng)
			if oc == "Punt":
				gs.run_punt()
				continue
			if oc == "Field Goal":
				gs.run_field_goal()
				continue
			var dc := CoachAI.pick_defense(gs, rng)
			var sim := PlaySim.new()
			sim.setup(gs.offense(), gs.defense(), oc, dc, gs.ball_on, gs.spot_y, gs.situation(),
				gs.rerolls[gs.possession], gs.rerolls[1 - gs.possession], dice)
			gs.apply_play(sim.run_to_end(), Playbook.is_run(oc))
			sim.dispose()
		pts += gs.score[0] + gs.score[1]
		plays += gs.stats[0]["plays"] + gs.stats[1]["plays"]
		print("  %s %d - %d %s   (plays %d, yds %d-%d, TO %d-%d)" % [home.abbrev, gs.score[0], gs.score[1], away.abbrev,
			gs.stats[0]["plays"] + gs.stats[1]["plays"], gs.stats[0]["yards"], gs.stats[1]["yards"],
			gs.stats[0]["turnovers"], gs.stats[1]["turnovers"]])
	print("Avg points per team: %.1f, plays per game: %.0f" % [pts / (2.0 * games), plays / float(games)])
	quit()
