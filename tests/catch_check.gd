extends SceneTree
## Catches and interceptions on passes:
##   godot --headless --script res://tests/catch_check.gd
## - an open receiver (nobody marking him, no tip) who misses the catch roll bobbles it and gets a
##   second try, one easier; a covered receiver never does,
## - a bobbled catch then needs a stay-on-his-feet roll: up, he stands still a moment (stall_time);
##   down, the play ends where he caught it,
## - a clean catch (first try, Soft Hands' re-roll counts) gives a short speed burst,
## - a defender at a ball no offensive player can reach gets +3 and a free re-roll to pick it off.

var fails := 0


func _expect(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	var gen := TeamGenerator.new(7)
	var dice := Dice.new(11)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var pb := Playbook.make_default()
	var passes: Array[String] = []
	for o in pb.offense_names():
		if not pb.is_run(o):
			passes.append(o)

	var clean := 0
	var clean_burst := 0
	var bobbles := 0
	var covered_bobbles := 0
	var bobble_up := 0
	var bobble_up_stall := 0
	var bobble_down := 0
	var bobble_down_bad := 0
	var bobble_drops := 0
	for off in passes:
		for de in pb.defense_names():
			for i in 60:
				var sim := PlaySim.new()
				sim.setup(a, b, pb.offense_play(off), pb.defense_play(de), 35.0, 26.67, {}, dice)
				var caught_by: SimActor = null
				while not sim.done:
					sim.step()
					if caught_by == null and sim.thrown_at >= 0.0 and sim.holder != null and sim.holder != sim.qb:
						caught_by = sim.holder
						var ev: Dictionary = sim.events.back()
						var txt: String = ev["text"]
						if txt.ends_with("after a bobble"):
							bobble_up += 1
							if caught_by.stall_time > 0.0 and caught_by.burst_time == 0.0:
								bobble_up_stall += 1
						elif txt.begins_with("Caught by") and not txt.contains("bobble"):
							clean += 1
							if caught_by.burst_time > 0.0 and caught_by.stall_time == 0.0:
								clean_burst += 1
				for e in sim.events:
					var detail: String = e["detail"]
					if detail.contains("Bobbled, second try"):
						bobbles += 1
						if detail.contains("close") or detail.contains("tipped"):
							covered_bobbles += 1
						if str(e["text"]).begins_with("Pass incomplete"):
							bobble_drops += 1
					if str(e["text"]).ends_with("but he goes down"):
						bobble_down += 1
						var r := sim.result
						var pos: Vector2 = e["pos"]
						if not (r["kind"] in ["tackle", "td"]) or (r["kind"] == "tackle" and absf(float(r["end_x"]) - pos.x) > 0.01):
							bobble_down_bad += 1
				sim.dispose()
	print("    clean catches %d, bobbles %d (held and up %d, held and down %d, dropped %d)" % [
		clean, bobbles, bobble_up, bobble_down, bobble_drops])
	_expect(bobbles > 0 and bobble_up > 0 and bobble_down > 0 and bobble_drops > 0,
		"open receivers bobble, and all three bobble outcomes happen")
	_expect(covered_bobbles == 0, "a covered or tipped receiver never gets the bobble re-try (%d did)" % covered_bobbles)
	_expect(bobble_up == bobble_up_stall, "a bobbled catch he stays up on stalls him, no burst (%d/%d)" % [bobble_up_stall, bobble_up])
	_expect(bobble_down_bad == 0, "a bobbled catch he goes down on ends the play at the catch (%d bad)" % bobble_down_bad)
	_expect(clean > 0 and clean == clean_burst, "a clean catch gives a speed burst (%d/%d)" % [clean_burst, clean])

	# Interceptions: park a defender on the landing spot. Alone: keep every offensive player
	# away from it. Contested: keep the receiver just inside catch reach, behind the defender.
	var alone := _int_rate(a, b, pb, passes, dice, false)
	var contested := _int_rate(a, b, pb, passes, dice, true)
	print("    interception rate: no receiver near %.0f%% (labelled %d/%d), receiver near %.0f%%" % [
		100.0 * alone[0], alone[2], alone[1], 100.0 * contested[0]])
	_expect(alone[1] > 50 and alone[2] == alone[1], "a ball nobody can reach is always rolled with the bonus")
	_expect(contested[2] == 0, "a ball a receiver can reach never gets the bonus")
	_expect(alone[0] > contested[0] + 0.2, "a ball nobody can reach is picked off far more often")

	print("catch_check: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit()


## Returns [interception rate, interception rolls, rolls with the no-receiver bonus].
func _int_rate(a: Team, b: Team, pb: Playbook, passes: Array[String], dice: Dice, contested: bool) -> Array:
	var rolls := 0
	var bonus := 0
	var picks := 0
	for off in passes:
		for de in pb.defense_names():
			for i in 30:
				var sim := PlaySim.new()
				sim.setup(a, b, pb.offense_play(off), pb.defense_play(de), 35.0, 26.67, {}, dice)
				var hawk: SimActor = null
				while not sim.done:
					if sim.ball_in_air and not sim.pitched and sim.ball_target != null:
						if hawk == null:
							for d in sim.defenders():
								if d.is_free() and (hawk == null or d.pos.distance_to(sim.ball_to) < hawk.pos.distance_to(sim.ball_to)):
									hawk = d
						if hawk != null:
							hawk.pos = sim.ball_to
						for o in sim.offense():
							if o.pos.distance_to(sim.ball_to) < 4.0:
								o.pos = sim.ball_to + Vector2(0.0, 8.0 if sim.ball_to.y < 26.0 else -8.0)
						if contested:
							sim.ball_target.pos = sim.ball_to + Vector2(-1.5, 0.0)
					sim.step()
				for e in sim.events:
					var detail: String = e["detail"]
					if detail.begins_with("Interception"):
						rolls += 1
						if detail.contains("no receiver near"):
							bonus += 1
						if str(e["text"]).begins_with("INTERCEPTED"):
							picks += 1
				sim.dispose()
	return [float(picks) / maxf(1.0, rolls), rolls, bonus]
