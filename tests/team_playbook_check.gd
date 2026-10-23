extends SceneTree
## Checks a team's assigned playbooks: games and practice run the team's own offense and
## defense, the CPU only calls plays its playbook has (even with every stock play renamed),
## and a deleted or broken playbook falls back to the stock one.
##   godot --headless --script res://tests/team_playbook_check.gd

var failures := 0


func _initialize() -> void:
	PlaybookStore.root = "user://test_team_playbooks"
	_clear_store()
	var gen := TeamGenerator.new(7)
	var home := gen.make_team(0, Color.BLUE)
	var away := gen.make_team(1, Color.RED)

	# Nothing assigned: both teams run the stock playbook.
	var gs := GameState.new(home, away, 8.0, Dice.new(1))
	_expect(gs.offense_playbook().name == "Standard" and gs.defense_playbook().name == "Standard",
		"unassigned teams use the stock playbook")

	# Custom playbooks with every play renamed, so none of CoachAI's stock names exist.
	var off := PlaybookStore.create(Playbook.OFFENSE)
	for p in off.offense_plays():
		p.name = "Custom " + p.name
	var def := PlaybookStore.create(Playbook.DEFENSE)
	for p in def.defense_plays():
		p.name = "Custom " + p.name
	PlaybookStore.save(off)
	PlaybookStore.save(def)
	_expect(Playbook.usable_as(off, Playbook.OFFENSE) and Playbook.usable_as(def, Playbook.DEFENSE),
		"renamed playbooks are usable")
	_expect(not Playbook.usable_as(off, Playbook.DEFENSE), "an offensive playbook can't be the defense")
	home.offense_playbook = off
	away.defense_playbook = def
	gs = GameState.new(home, away, 8.0, Dice.new(1))
	gs.possession = GameState.HOME
	_expect(gs.offense_playbook() == off and gs.defense_playbook() == def,
		"home offense and away defense use their assigned playbooks")
	gs.possession = GameState.AWAY
	_expect(gs.offense_playbook().name == "Standard" and gs.defense_playbook().name == "Standard",
		"sides without an assignment still use the stock playbook")

	# The CPU only calls plays from the playbooks in use, in every situation.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	gs.possession = GameState.HOME
	var bad_calls := 0
	for i in 2000:
		gs.down = 1 + i % 4
		gs.to_go = 1 + i % 12
		gs.ball_on = 20.0 + (i * 7) % 75
		var oc := CoachAI.pick_offense(gs, rng)
		if gs.offense_play(oc) == null and not off.is_kick(oc):
			bad_calls += 1
		if gs.defense_play(CoachAI.pick_defense(gs, rng)) == null:
			bad_calls += 1
	_expect(bad_calls == 0, "CPU never calls a play missing from the playbook (%d bad calls)" % bad_calls)

	# A playbook with only passes still gets a call on 4th and short.
	var passes_only := PlaybookStore.create(Playbook.OFFENSE)
	for f in passes_only.offensive_formations:
		for p in f.plays.duplicate():
			if p.is_run():
				f.remove_play(p)
	PlaybookStore.save(passes_only)
	home.offense_playbook = passes_only
	gs = GameState.new(home, away, 8.0, Dice.new(1))
	gs.possession = GameState.HOME
	gs.down = 4
	gs.to_go = 1
	gs.ball_on = 50.0
	var call := CoachAI.pick_offense(gs, rng)
	_expect(gs.offense_play(call) != null or passes_only.is_kick(call), "4th and 1 with no runs calls a pass (%s)" % call)

	# Full CPU games with custom playbooks on both sides run to the end.
	home.offense_playbook = off
	home.defense_playbook = def
	away.offense_playbook = off
	away.defense_playbook = def
	var dice := Dice.new(9)
	for g in 3:
		gs = GameState.new(home, away, 8.0, dice)
		var guard := 0
		while not gs.over and guard < 400:
			guard += 1
			var oc := CoachAI.pick_offense(gs, rng)
			if oc == Playbook.SPECIAL_PUNT:
				gs.run_punt()
				continue
			if oc == Playbook.SPECIAL_FG:
				gs.run_field_goal()
				continue
			var dc := CoachAI.pick_defense(gs, rng)
			var sim := PlaySim.new()
			sim.setup(gs.offense(), gs.defense(), gs.offense_play(oc), gs.defense_play(dc), gs.ball_on, gs.spot_y,
				gs.situation(), dice)
			gs.apply_play(sim.run_to_end(), gs.offense_playbook().is_run(oc))
			sim.dispose()
		_expect(gs.over, "game %d with custom playbooks finishes (%d-%d)" % [g + 1, gs.score[0], gs.score[1]])

	# A broken playbook (no plays left) and a deleted one both fall back to stock.
	var empty := PlaybookStore.create(Playbook.DEFENSE)
	for f in empty.defensive_formations:
		for p in f.plays.duplicate():
			f.remove_play(p)
	PlaybookStore.save(empty)
	away.defense_playbook = empty
	_expect(away.playbook_for(Playbook.DEFENSE) == null, "a defense with no calls isn't used")
	away.defense_playbook = def
	PlaybookStore.delete(def)
	_expect(away.playbook_for(Playbook.DEFENSE) == null, "a deleted playbook isn't used")
	var reuse := PlaybookStore.create(Playbook.DEFENSE)
	_expect(away.playbook_for(Playbook.DEFENSE) == null and reuse.resource_path != "",
		"a new playbook saved after the delete doesn't bring the deleted one back")
	gs = GameState.new(home, away, 8.0, Dice.new(1))
	gs.possession = GameState.HOME
	_expect(gs.defense_playbook().name == "Standard", "the game falls back to the stock defense")

	_clear_store()
	print("team_playbook_check: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _clear_store() -> void:
	for kind in [Playbook.OFFENSE, Playbook.DEFENSE]:
		var dir := PlaybookStore.dir_for(kind)
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute("%s/%s" % [dir, f])


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

