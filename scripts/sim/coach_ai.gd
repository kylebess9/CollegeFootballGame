class_name CoachAI
extends RefCounted
## Very simple play-calling for the CPU (and for "auto" mode).
## Mostly random, with a little situational sense. This is the place to make the CPU smarter later.


static func pick_offense(gs: GameState, rng: RandomNumberGenerator) -> String:
	if gs.down == 4:
		var fg := gs.fg_target()
		if fg <= 4:
			return "Field Goal"
		if gs.to_go <= 2 and gs.ball_on >= 45.0:
			return "Inside Run"
		if fg <= 5 and gs.ball_on >= 60.0:
			return "Field Goal"
		return "Punt"
	var run_chance := 0.45
	if gs.to_go >= 8:
		run_chance = 0.25
	elif gs.to_go <= 2:
		run_chance = 0.65
	if rng.randf() < run_chance:
		return "Inside Run" if rng.randf() < 0.6 else "Outside Run"
	var passes := ["Quick Slants", "Curl Flat", "Dig Cross", "Four Verticals", "PA Deep Shot"]
	if gs.to_go <= 4:
		passes = ["Quick Slants", "Quick Slants", "Curl Flat", "Dig Cross", "PA Deep Shot"]
	return passes[rng.randi() % passes.size()]


static func pick_defense(gs: GameState, rng: RandomNumberGenerator) -> String:
	var pool := ["Cover 3", "Cover 3", "Cover 2", "Cover 1 Man", "Blitz", "Run Stuff"]
	if gs.to_go <= 2:
		pool = ["Run Stuff", "Run Stuff", "Cover 1 Man", "Blitz", "Cover 3"]
	elif gs.to_go >= 9:
		pool = ["Cover 3", "Cover 2", "Cover 2", "Cover 1 Man", "Blitz"]
	return pool[rng.randi() % pool.size()]
