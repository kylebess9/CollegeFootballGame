class_name CoachAI
extends RefCounted
## Very simple play-calling for the CPU (and for "auto" mode).
## Mostly random, with a little situational sense. This is the place to make the CPU smarter later.
## The pools below name stock plays; when the team's playbook doesn't have the one picked
## (a custom playbook), it calls a random play of the same type from its own playbook.


static func pick_offense(gs: GameState, rng: RandomNumberGenerator) -> String:
	if gs.down == 4:
		var fg := gs.fg_target()
		if fg <= 4:
			return "Field Goal"
		if gs.to_go <= 2 and gs.ball_on >= 45.0:
			return _offense_call(gs, "Inside Run", true, rng)
		if fg <= 5 and gs.ball_on >= 60.0:
			return "Field Goal"
		return "Punt"
	var run_chance := 0.45
	if gs.to_go >= 8:
		run_chance = 0.25
	elif gs.to_go <= 2:
		run_chance = 0.65
	if rng.randf() < run_chance:
		return _offense_call(gs, "Inside Run" if rng.randf() < 0.6 else "Outside Run", true, rng)
	var passes := ["Quick Slants", "Curl Flat", "Dig Cross", "Four Verticals", "PA Deep Shot"]
	if gs.to_go <= 4:
		passes = ["Quick Slants", "Quick Slants", "Curl Flat", "Dig Cross", "PA Deep Shot"]
	return _offense_call(gs, passes[rng.randi() % passes.size()], false, rng)


static func pick_defense(gs: GameState, rng: RandomNumberGenerator) -> String:
	var pool := ["Cover 3", "Cover 3", "Cover 2", "Cover 1 Man", "Blitz", "Run Stuff"]
	if gs.to_go <= 2:
		pool = ["Run Stuff", "Run Stuff", "Cover 1 Man", "Blitz", "Cover 3"]
	elif gs.to_go >= 9:
		pool = ["Cover 3", "Cover 2", "Cover 2", "Cover 1 Man", "Blitz"]
	var pick: String = pool[rng.randi() % pool.size()]
	var pb := gs.defense_playbook()
	if pb.defense_play(pick) != null:
		return pick
	var names := pb.defense_names()
	return names[rng.randi() % names.size()]


## This play if the offense's playbook has it. Otherwise a random run (or pass) from the
## playbook, or any play if it has none of that type.
static func _offense_call(gs: GameState, pick: String, run: bool, rng: RandomNumberGenerator) -> String:
	var pb := gs.offense_playbook()
	if pb.offense_play(pick) != null:
		return pick
	var same: Array[String] = []
	for p in pb.offense_plays():
		if p.is_run() == run:
			same.append(p.name)
	if same.is_empty():
		same = pb.offense_names()
	return same[rng.randi() % same.size()]
