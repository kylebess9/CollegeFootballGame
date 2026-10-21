extends SceneTree
## Prints a full CPU vs CPU game, play by play. Run with:
##   godot --headless --script res://tests/game_log.gd
func _init() -> void:
	var gen := TeamGenerator.new(21)
	var dice := Dice.new(8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var home := gen.make_team(0, Color.BLUE)
	var away := gen.make_team(1, Color.RED)
	var gs := GameState.new(home, away, 15.0, dice)
	while not gs.over:
		var pre := "%s %s | %s %d-%d" % [gs.offense().abbrev, gs.down_text(), gs.clock_text(), gs.score[0], gs.score[1]]
		var oc := CoachAI.pick_offense(gs, rng)
		var lines: Array[String]
		if oc == "Punt":
			lines = gs.run_punt()
		elif oc == "Field Goal":
			lines = gs.run_field_goal()
		else:
			var dc := CoachAI.pick_defense(gs, rng)
			var sim := PlaySim.new()
			sim.setup(gs.offense(), gs.defense(), oc, dc, gs.ball_on, gs.spot_y, gs.situation(), dice)
			var r := sim.run_to_end()
			oc += " v " + dc + " [" + r["kind"] + "]"
			lines = gs.apply_play(r, Playbook.is_run(oc))
		print(pre, " :: ", oc, " -> ", " / ".join(lines))
	quit()
