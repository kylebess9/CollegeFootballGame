class_name PlaySim
extends RefCounted
## Simulates one play from snap to whistle.
##
## Field frame used here: the offense always drives toward +x.
## x = 0..10 is the offense's own end zone, 10 = own goal line, 110 = opponent goal line.
## y = 0..53.33 across the field. The screen flips this when the away team has the ball.
##
## Movement is automatic. Dice decide the contested moments:
##   blocks (block dice), throws (accuracy), catches, interceptions, tackles, play-action bites, fumbles,
##   scooping up a loose ball.

const DT := 1.0 / 30.0
const FIELD_LEN := 120.0
const FIELD_W := 53.333
const OWN_GOAL := 10.0
const OPP_GOAL := 110.0
const HASH_LEFT := 23.58
const HASH_RIGHT := 29.75

const TACKLE_RANGE := 1.1
const ZONE_RANGE := 1.6        # a defender this close to a receiver or runner "marks" him (Blood Bowl tackle zone)
const BLOCK_RANGE := 1.3
const BLOCK_INTERVAL := 1.0
const ASSIST_RANGE := 2.0
const BALL_SPEED := 21.0
const CATCH_REACH := 1.6
const HANDOFF_TIME := 0.55    # when a play-action fake happens, and when the defense reads a run
const HANDOFF_RADIUS := 10.0   # on a run the RB must get this close to the QB for a handoff...
const HANDOFF_MIN_TIME := 0.3 # ...no sooner than this after the snap, else (RunPlay.time_delay) it's a pitch
const PITCH_CATCH := 2        # a pitch is caught on this or better, with a free re-roll
const OPEN_INT_BONUS := 3     # an interception is this much easier when no receiver is near the ball
const CATCH_BURST := 1.2      # speed multiplier for a receiver who catches it cleanly...
const CATCH_BURST_TIME := 1.0 # ...for this long
const BOBBLE_STALL := 0.6     # a receiver who bobbles it and stays up stands still this long
const LOOSE_REACH := 0.8      # how close a player has to be to try to scoop up a loose ball
const FAKE_READ_DEPTH := 10.0 # safeties lined up shallower than this read play-action fakes
const OPEN_THRESHOLD := 1.8
const MAX_TIME := 20.0
const END_LINE_STOP := FIELD_LEN - 1.5 # receivers settle this deep in the end zone

var dice: Dice
var off_team: Team
var def_team: Team
var off_name := ""
var def_name := ""
var off_play: OffensivePlay
var def_play: DefensivePlay
var pass_play: PassPlay # off_play as a pass, null on runs
var is_run := false
var play_action := false
var los := 35.0
var ball_y := 26.667
var down := 1
var to_go := 10

var actors: Array[SimActor] = []
var slots := {} # "O:QB" / "D:MIKE" -> SimActor
var t := 0.0
var done := false
var result := {}
var events: Array[Dictionary] = []

# Ball
var holder: SimActor = null
var ball_pos := Vector2.ZERO
var ball_in_air := false
var ball_from := Vector2.ZERO
var ball_to := Vector2.ZERO
var ball_flight := 0.0
var ball_flight_time := 0.0
var ball_target: SimActor = null
var ball_quality := "good" # good / bad / duck / away
var thrown_at := -1.0
var pitched := false # the ball in the air is a pitch on a run, not a pass
var ball_loose := false # fumbled backward pass on the ground, up for grabs
var turnover := false
var turnover_kind := "int" # result kind when a turnover's return is tackled

# QB brain
var qb: SimActor
var qb_state := "drop" # drop, read, handed_off, thrown, scramble
var qb_set := Vector2.ZERO
var read_index := 0
var read_timer := 0.0
var read_noise := 0.0
var under_pressure := false
var pressure_decided := false
var handed_off := false
var run_side := 1
var run_side_fixed := false # true when the RB lines up off to one side, so he always goes that way
## On a run, who gets the ball (RunPlay.ball_carrier()); null on a pass.
var runner: SimActor = null
var windup := 0.0
var pending_rec: SimActor = null
var pending_hurried := false
var pending_away := false


func setup(offense: Team, defense: Team, off_call: OffensivePlay, def_call: DefensivePlay, ball_on: float,
		spot_y: float, situation: Dictionary, dice_in: Dice) -> void:
	dice = dice_in
	off_team = offense
	def_team = defense
	off_play = off_call
	def_play = def_call
	off_name = off_call.name
	def_name = def_call.name
	is_run = off_play.is_run()
	pass_play = null if is_run else off_play as PassPlay
	play_action = pass_play != null and pass_play.play_action
	los = OWN_GOAL + ball_on
	ball_y = clampf(spot_y, HASH_LEFT, HASH_RIGHT)
	down = int(situation.get("down", 1))
	to_go = int(situation.get("to_go", 10))
	run_side = 1 if dice.rng.randf() < 0.5 else -1
	_build_offense(off_play)
	_build_defense(def_play)
	_assign_blocks()
	qb = slots["O:" + off_play.formation.snap_slot]
	holder = qb
	ball_pos = qb.pos
	if not is_run:
		qb_set = Vector2(los - pass_play.drop, ball_y)


# ---------------------------------------------------------------- setup

func _add(team: Team, side: int, slot: String, p: FootballPlayer, at: Vector2) -> SimActor:
	var a := SimActor.new()
	a.id = actors.size()
	a.player = p
	a.side = side
	a.slot = slot
	a.pos = at
	a.start_pos = at
	a.top_speed = 5.2 + 0.65 * p.r("spd")
	a.react_time = maxf(0.08, 0.55 - 0.07 * p.r("awr"))
	actors.append(a)
	slots[("O:" if side == SimActor.Side.OFFENSE else "D:") + slot] = a
	return a


func _clamp_y(y: float) -> float:
	return clampf(y, 3.0, FIELD_W - 3.0)


## The starter the depth chart lists for this spot's slot, or else the best player at the
## spot's position who isn't already on the field.
func _player_for(team: Team, dc: Dictionary, spot: FormationSpot, used: Dictionary) -> FootballPlayer:
	if dc.has(spot.slot) and not used.has(dc[spot.slot]):
		return dc[spot.slot]
	for p in team.players_at(spot.position):
		if not used.has(p):
			return p
	push_error("%s has nobody left to play %s (%s)" % [team.school, spot.slot, spot.position])
	return null


## Lines the offense up in the play's formation and gives everyone their job. Blocking
## targets are handed out later, by _assign_blocks, once the defense is on the field.
func _build_offense(play: OffensivePlay) -> void:
	var dc := off_team.depth_chart()
	var c := ball_y
	var O := SimActor.Side.OFFENSE
	var used := {}
	for spot in play.formation.spots:
		var p := _player_for(off_team, dc, spot, used)
		used[p] = true
		var a := _add(off_team, O, spot.slot, p, Vector2(los + spot.offset.x, _clamp_y(c + spot.offset.y)))
		a.position = spot.position
		a.job = "qb" if spot.slot == play.formation.snap_slot else "block"

	# A back lined up in the snap lane behind the ball can go either way (the coin flip in setup);
	# one offset to a side always goes to the side he's on: runs, swing routes and PA fakes.
	if is_run:
		# Nobody valid to give it to (the editor can line up a broken play): the QB keeps it.
		runner = slots.get("O:" + (play as RunPlay).ball_carrier(), slots["O:" + play.formation.snap_slot])
	var back: SimActor = runner if is_run else slots.get("O:RB")
	if back != null:
		var off_y: float = back.start_pos.y - c
		if absf(off_y) > OffensiveFormation.SNAP_LANE:
			run_side = 1 if off_y > 0.0 else -1
			run_side_fixed = true

	if is_run:
		var rp := play as RunPlay
		var s := float(run_side)
		if rp.has_custom_path():
			runner.path.clear()
			for p in rp.path:
				var pt := runner.start_pos + p
				runner.path.append(Vector2(minf(pt.x, END_LINE_STOP), clampf(pt.y, 1.5, FIELD_W - 1.5)))
			run_side_fixed = true # drawn as it goes, never mirrored
		elif rp.run_path == RunPlay.INSIDE:
			runner.path = [Vector2(los - 1.5, c + s * 2.0), Vector2(los + 2.0, c + s * 2.5)]
		else:
			runner.path = [Vector2(los - 3.5, c + s * 7.0), Vector2(los + 0.5, c + s * 11.0)]
		runner.path_end = "free"
		if runner.slot == play.formation.snap_slot:
			# A QB keeper: he runs it himself from the snap.
			runner.job = "carry"
			qb_state = "handed_off"
		else:
			runner.job = "rb_run"
	else:
		var routes := (play as PassPlay).routes
		for slot in routes:
			_assign_route(slots["O:" + slot], routes[slot])
		if play_action:
			# RB carries out the fake, then picks up blitzers.
			slots["O:RB"].job = "fake"


func _assign_route(a: SimActor, r: Route) -> void:
	var outside := route_side(a)
	a.job = "route"
	a.path.clear()
	for p in r.points:
		var pt: Vector2 = a.start_pos + Vector2(p.x, p.y * outside)
		pt.y = clampf(pt.y, 1.5, FIELD_W - 1.5)
		pt.x = minf(pt.x, END_LINE_STOP)
		a.path.append(pt)
	a.path_end = r.end


## Which way "toward the sideline" is for this player's route: 1 toward y = FIELD_W, -1
## toward y = 0. Routes are mirrored for receivers left of the ball; the RB goes to his run side.
func route_side(a: SimActor) -> float:
	if a.slot == "RB":
		return float(run_side)
	return 1.0 if a.start_pos.y >= ball_y else -1.0


## Pass catchers (WR/TE) split out to one side, widest first. side is -1 for the offense's
## left, 1 for its right.
func _receivers_on(side: int) -> Array[SimActor]:
	var out: Array[SimActor] = []
	for o in offense():
		if o.player.position in ["WR", "TE"] and signf(o.pos.y - ball_y) == side:
			out.append(o)
	out.sort_custom(func(a: SimActor, b: SimActor) -> bool:
		return absf(a.pos.y - ball_y) > absf(b.pos.y - ball_y))
	return out


## Where a defensive spot lines up across the field: over a receiver when it has an align
## ("left_1" = widest receiver on the left), otherwise relative to the ball. If there's no
## such receiver, the defender lines up 12 yards outside the ball on that side instead.
func _align_y(spot: FormationSpot) -> float:
	if spot.align == "":
		return ball_y + spot.offset.y
	var parts := spot.align.split("_")
	var side := -1 if parts[0] == "left" else 1
	var rank := int(parts[1]) if parts.size() > 1 else 1
	var recs := _receivers_on(side)
	if rank >= 1 and rank <= recs.size():
		return recs[rank - 1].pos.y + spot.offset.y
	return ball_y + side * 12.0 + spot.offset.y


## Lines the defense up in the call's formation and hands out assignments. Man defenders, in
## the call's order, each pick up the closest receiver nobody is covering yet (unless the
## call names a target).
func _build_defense(play: DefensivePlay) -> void:
	var dc := def_team.depth_chart()
	var D := SimActor.Side.DEFENSE
	var used := {}
	for spot in play.formation.spots:
		var p := _player_for(def_team, dc, spot, used)
		used[p] = true
		var a := _add(def_team, D, spot.slot, p, Vector2(los + spot.offset.x, _clamp_y(_align_y(spot))))
		a.position = spot.position
		if spot.position == "DL":
			a.job = "rush"

	var covered := {}
	for info in play.assignments:
		var a: SimActor = slots["D:" + info.slot]
		match info.type:
			CoverageAssignment.MAN:
				a.job = "man"
				a.man_target = _pick_man(a, info.target, covered)
				if a.man_target != null:
					covered[a.man_target] = true
				if a.has_skill("Shutdown"):
					a.react_time = maxf(0.05, a.react_time - 0.12)
			CoverageAssignment.ZONE:
				a.job = "zone"
				var zc := info.zone.center(los, ball_y)
				a.zone_center = Vector2(zc.x, _clamp_y(zc.y))
				a.zone_radius = info.zone.radius
			CoverageAssignment.BLITZ:
				a.job = "rush"
		# Run-first calls send everyone but the deep defenders at the line.
		if play.run_first and not (info.type == CoverageAssignment.ZONE and info.zone.is_deep()):
			a.run_first = true

	if is_run:
		# Defenders figure out it's a run after the handoff, depending on Awareness (later, if
		# the QB holds it longer: _defense_sees_run).
		for d in defenders():
			d.pursue_at = HANDOFF_TIME + d.react_time * 1.5
			if d.run_first:
				d.pursue_at = HANDOFF_TIME + 0.1
	else:
		for d in defenders():
			if d.run_first:
				d.bite_until = 0.9 + d.react_time


## A man defender's receiver: the named target if the call gives one and he's free, else the
## closest uncovered receiver (anyone but the QB and the offensive line).
func _pick_man(d: SimActor, target: String, covered: Dictionary) -> SimActor:
	if target != "" and slots.has("O:" + target) and not covered.has(slots["O:" + target]):
		return slots["O:" + target]
	var best: SimActor = null
	var bd := INF
	for o in offense():
		if o.player.position in ["QB", "OL"] or covered.has(o):
			continue
		var dist := o.pos.distance_to(d.pos)
		if dist < bd:
			bd = dist
			best = o
	return best


## Initial blocking assignments, made once both teams are lined up: the offensive line first,
## each lineman taking the closest defender nobody else has (closest pairs first). On a pass
## the line only looks at the rushers. On a run the other blockers (TE, receivers) then take
## the defender lined up most directly across from them, so a receiver stalks the man over
## him rather than turning inside to the nearest linebacker. Anyone left without a target
## finds one during the play.
func _assign_blocks() -> void:
	var line: Array[SimActor] = []
	var others: Array[SimActor] = []
	for o in offense():
		if o.job != "block":
			continue
		if o.player.position == "OL":
			line.append(o)
		elif is_run:
			others.append(o)
	var open: Array[SimActor] = []
	for d in defenders():
		if is_run or d.job == "rush":
			open.append(d)
	_pair_closest(line, open, false)
	_pair_closest(others, open, true)


## Greedily pairs blockers with defenders, closest pair first: by straight-line distance, or
## with across = true by how far apart they are across the field. Paired defenders are
## removed from `open`.
func _pair_closest(blockers: Array[SimActor], open: Array[SimActor], across: bool) -> void:
	var pairs := []
	for b in blockers:
		for d in open:
			var gap := absf(b.pos.y - d.pos.y) if across else b.pos.distance_to(d.pos)
			pairs.append([gap, b, d])
	pairs.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var done_b := {}
	for pr in pairs:
		var b: SimActor = pr[1]
		var d: SimActor = pr[2]
		if done_b.has(b) or not open.has(d):
			continue
		b.block_target = d
		done_b[b] = true
		open.erase(d)


# ---------------------------------------------------------------- helpers

func offense() -> Array[SimActor]:
	var out: Array[SimActor] = []
	for a in actors:
		if a.side == SimActor.Side.OFFENSE:
			out.append(a)
	return out


func defenders() -> Array[SimActor]:
	var out: Array[SimActor] = []
	for a in actors:
		if a.side == SimActor.Side.DEFENSE:
			out.append(a)
	return out


func opponents_of(a: SimActor) -> Array[SimActor]:
	var out: Array[SimActor] = []
	for o in actors:
		if o.side != a.side:
			out.append(o)
	return out


## Event value meaning "good for this side".
func _fav(side: int) -> int:
	return 1 if side == SimActor.Side.OFFENSE else 0


## Inside the field of play, end zones included.
func _in_bounds(p: Vector2) -> bool:
	return p.x >= 0.0 and p.x <= FIELD_LEN and p.y >= 0.0 and p.y <= FIELD_W


func goal_dir(a: SimActor) -> float:
	return 1.0 if a.side == SimActor.Side.OFFENSE else -1.0


## True while the QB still has the ball in the pocket (not yet a runner).
func qb_in_pocket() -> bool:
	return holder == qb and qb_state in ["drop", "read", "windup"]


func carrier_live() -> bool:
	return holder != null and not qb_in_pocket()


## ok: 1 = good for the offense, 0 = good for the defense, -1 = neutral.
func _log(text: String, at: Vector2, ok: int = -1, detail: String = "", short := "") -> void:
	events.append({"t": t, "text": text, "pos": at, "ok": ok, "detail": detail, "short": short})


## A Blood Bowl style test: roll a d6, need target or higher. A matching skill can save a failure.
## free_reroll gives the re-roll whether or not the player has the skill (it's still one re-roll).
func _test(a: SimActor, target: int, label: String, skill: String = "", free_reroll := false) -> Dictionary:
	target = Dice.clamp_target(target)
	var first := dice.d6()
	var roll := first
	var ok := roll >= target
	var detail := "%s: needs %d+, rolled %d" % [label, target, roll]
	if not ok and (free_reroll or (skill != "" and a.has_skill(skill))):
		roll = dice.d6()
		ok = roll >= target
		detail += ", %s re-roll %d" % [skill if skill != "" and a.has_skill(skill) else "free", roll]
	return {"ok": ok, "roll": roll, "first": first, "target": target, "detail": detail}


# ---------------------------------------------------------------- main loop

func run_to_end() -> Dictionary:
	while not done:
		step()
	return result


func step() -> void:
	if done:
		return
	t += DT
	for a in actors:
		a.down_time = maxf(0.0, a.down_time - DT)
		a.block_cooldown = maxf(0.0, a.block_cooldown - DT)
		a.tackle_cooldown = maxf(0.0, a.tackle_cooldown - DT)
		a.slow_time = maxf(0.0, a.slow_time - DT)
		a.cut_time = maxf(0.0, a.cut_time - DT)
		a.stall_time = maxf(0.0, a.stall_time - DT)
		a.burst_time = maxf(0.0, a.burst_time - DT)

	_handle_snap_events()
	if not is_run and holder == qb and qb_state in ["drop", "read"]:
		_qb_decide()
	elif qb_state == "windup" and holder == qb:
		windup -= DT
		if windup <= 0.0:
			if pending_away:
				_release_away()
			else:
				_release(pending_rec, pending_hurried)
	for a in actors:
		_move(a)
	for a in actors:
		a.record_history()
	_update_blocks()
	_update_ball()
	if done:
		return
	_check_tackles()
	if done:
		return
	_check_boundaries()
	if not done and t >= MAX_TIME:
		_end_tackled(holder, "Whistle")


func _handle_snap_events() -> void:
	if is_run and not handed_off and holder == qb and runner == qb:
		if t >= HANDOFF_MIN_TIME:
			handed_off = true
			_log("%s keeps it" % qb.tag(), qb.pos, -1, "", "")
			_defense_sees_run()
	elif is_run and not handed_off and holder == qb:
		var rb := runner
		if t >= HANDOFF_MIN_TIME and rb.is_up() and rb.pos.distance_to(qb.pos) <= HANDOFF_RADIUS:
			handed_off = true
			holder = rb
			rb.job = "carry"
			qb_state = "handed_off"
			qb.job = "idle"
			_log("%s takes the handoff" % rb.tag(), rb.pos, -1, "", "")
			_defense_sees_run()
		elif t >= (off_play as RunPlay).time_delay:
			# The RB never got to him in time: pitch it.
			handed_off = true
			pitched = true
			ball_quality = "pitch"
			_log("%s pitches it to %s" % [qb.tag(), rb.tag()], qb.pos, -1, "", "Pitch")
			_launch(_catch_point(rb), rb)
			_defense_sees_run()
	if play_action and not handed_off and t >= HANDOFF_TIME:
		handed_off = true
		_log("Play-action fake!", qb.pos)
		for d in defenders():
			if _reads_fake(d) or d.run_first:
				if d.run_first:
					d.bite_until = maxf(d.bite_until, t + 1.2)
					_log("%s bites on the fake (crashing the run)" % d.tag(), d.pos, 1, "", "Bit!")
					continue
				var deep := d.job == "zone" and d.zone_center.x - los >= 12.0
				var res := _test(d, 7 - d.r("awr") - (1 if deep else 0), "Read the fake (Awareness)")
				if not res["ok"]:
					d.bite_until = t + 0.9
					_log("%s bites on the fake" % d.tag(), d.pos, 1, res["detail"], "Bit!")
		slots["O:RB"].job = "block"


## Defenders can't be sure it's a run until the ball goes to the RB: a QB who holds it past
## the usual handoff time (a late pitch) holds them off as long.
func _defense_sees_run() -> void:
	for d in defenders():
		d.pursue_at = maxf(d.pursue_at, t + (0.1 if d.run_first else d.react_time * 1.5))


## Whether a defender has to read a play-action fake: linebackers, and safeties lined up
## within run-support depth (closer than FAKE_READ_DEPTH yards off the ball), unless he's in
## man coverage. Goes by the formation spot, so custom fronts with any number of LBs and
## safeties work the same way the stock ones do.
func _reads_fake(d: SimActor) -> bool:
	if d.job == "man":
		return false
	if d.position == "LB":
		return true
	return d.position == "S" and d.start_pos.x - los < FAKE_READ_DEPTH


# ---------------------------------------------------------------- QB decisions

func _qb_decide() -> void:
	var threat := _nearest_free_opponent(qb)
	var threat_dist: float = INF if threat == null else threat.pos.distance_to(qb.pos)
	under_pressure = threat_dist < 1.3 + 0.3 * qb.r("awr")

	if qb_state == "drop":
		if qb.pos.distance_to(qb_set) < 0.4 and t >= pass_play.read_start:
			qb_state = "read"
			_start_read(0)
		elif not under_pressure:
			return

	var reads := pass_play.reads
	if under_pressure:
		var best := _best_option(20.0)
		if best["actor"] != null and float(best["open"]) >= OPEN_THRESHOLD - 0.8:
			_log("QB under pressure, gets it out", qb.pos, -1)
			_throw(best["actor"], true)
			return
		if not pressure_decided:
			pressure_decided = true
			var res := _test(qb, 7 - qb.r("awr"), "Pocket poise (Awareness)")
			if res["ok"]:
				if _scramble_lane():
					_start_scramble(res["detail"])
				else:
					_throw_away(res["detail"])
				return
			_log("QB holds the ball too long", qb.pos, 0, res["detail"], "Holds it")
		return

	if qb_state != "read":
		return
	read_timer -= DT
	var rec: SimActor = slots["O:" + reads[read_index]]
	if rec.job == "route" and rec.is_up():
		var o := _openness(rec) + read_noise
		if o >= OPEN_THRESHOLD:
			_throw(rec, false)
			return
	if read_timer <= 0.0:
		if read_index + 1 < reads.size():
			_start_read(read_index + 1)
		else:
			# Progression done: check down to anyone open, or scramble.
			var best := _best_option()
			if best["actor"] != null and float(best["open"]) >= OPEN_THRESHOLD - 0.6:
				_throw(best["actor"], false)
			elif _scramble_lane():
				_start_scramble("")
			elif t > 4.5:
				var res := _test(qb, 7 - qb.r("awr"), "Throw it away (Awareness)")
				if res["ok"]:
					_throw_away(res["detail"])
				else:
					_start_read(0)
			else:
				_start_read(0)


func _start_read(i: int) -> void:
	read_index = i
	var awr := qb.r("awr")
	read_timer = maxf(0.25, 0.62 - 0.06 * awr - (0.08 if qb.has_skill("Field General") else 0.0))
	read_noise = 0.0
	# Misreads: low Awareness QBs sometimes think a covered man is open (or miss an open one).
	var target := 7 - awr - (2 if qb.has_skill("Field General") else 0)
	if dice.d6() < Dice.clamp_target(target - 1):
		read_noise = dice.rng.randf_range(-1.2, 1.6)


func _flight_time(from: Vector2, to: Vector2) -> float:
	return from.distance_to(to) / BALL_SPEED + 0.1


## Where a receiver will be after `time` seconds if he keeps running his route.
func _predict(a: SimActor, time: float) -> Vector2:
	var p := a.pos
	var remaining := a.top_speed * time
	var i := a.path_index
	var dir := a.path_dir
	while remaining > 0.0 and i < a.path.size():
		var seg := a.path[i] - p
		var L := seg.length()
		if L > remaining:
			return p + seg.normalized() * remaining
		p = a.path[i]
		remaining -= L
		if L > 0.01:
			dir = seg.normalized()
		i += 1
	if a.path_end == "go" and remaining > 0.0:
		p += dir * remaining
	p.y = clampf(p.y, 0.5, FIELD_W - 0.5)
	p.x = minf(p.x, END_LINE_STOP)
	return p


func _catch_point(rec: SimActor) -> Vector2:
	var land := _predict(rec, _flight_time(qb.pos, rec.pos))
	land = _predict(rec, _flight_time(qb.pos, land))
	return land


## Yards of cushion the receiver will have when the ball arrives. Negative means covered.
func _openness(rec: SimActor) -> float:
	var land := _catch_point(rec)
	var tf := _flight_time(qb.pos, land)
	var best := 99.0
	for d in defenders():
		if not d.is_up():
			continue
		var reach := d.top_speed * maxf(0.0, tf - d.react_time) * 0.8
		if d.engaged != null:
			reach = 0.0
		best = minf(best, d.pos.distance_to(land) - reach)
	return best


func _best_option(max_dist: float = 999.0) -> Dictionary:
	var best_actor: SimActor = null
	var best_open := -99.0
	for s in pass_play.reads:
		var a: SimActor = slots["O:" + s]
		if a.job != "route" or not a.is_up():
			continue
		if a.pos.distance_to(qb.pos) > max_dist:
			continue
		var o := _openness(a)
		if o > best_open:
			best_open = o
			best_actor = a
	return {"actor": best_actor, "open": best_open}


func _scramble_lane() -> bool:
	for d in defenders():
		if not d.is_free():
			continue
		var rel := d.pos - qb.pos
		if rel.x > -1.0 and rel.x < 6.0 and absf(rel.y) < 4.0:
			return false
	return true


func _start_scramble(detail: String) -> void:
	qb_state = "scramble"
	qb.job = "carry"
	qb.path.clear()
	_log("%s scrambles!" % qb.tag(), qb.pos, 1, detail, "Scramble")
	for d in defenders():
		d.pursue_at = minf(d.pursue_at, t + d.react_time + 0.2)


func _throw(rec: SimActor, hurried: bool) -> void:
	qb_state = "windup"
	pending_rec = rec
	pending_hurried = hurried
	pending_away = false
	windup = 0.12 if hurried else 0.25


func _release(rec: SimActor, hurried: bool) -> void:
	var land := _catch_point(rec)
	var dist := qb.pos.distance_to(land)
	var mod := 0
	var range_name := "short"
	if dist <= 8.0:
		mod = -2
		range_name = "quick"
	elif dist <= 18.0:
		mod = -1
	elif dist <= 32.0:
		mod = 0
		range_name = "long"
	else:
		mod = 2
		range_name = "deep"
	if qb.has_skill("Cannon Arm") and mod > 0:
		mod -= 1
	if hurried:
		mod += 1
	if qb.has_skill("Accurate"):
		mod -= 1
	var res := _test(qb, 7 - qb.r("pas") + mod, "Accuracy (%s, %d yds%s)" % [range_name, int(dist), ", pressured" if hurried else ""])
	var target := land
	if int(res["first"]) == 1 and not res["ok"]:
		ball_quality = "duck"
		target += dice.scatter(dice.rng.randf_range(2.5, 4.0) + dist * 0.06)
		_log("%s throws a wobbly duck toward %s" % [qb.tag(), rec.tag()], qb.pos, 0, res["detail"], "Duck!")
	elif not res["ok"]:
		ball_quality = "bad"
		target += dice.scatter(dice.rng.randf_range(1.5, 2.6) + dist * 0.05)
		_log("%s throws off target to %s" % [qb.tag(), rec.tag()], qb.pos, 0, res["detail"], "Off target")
	else:
		ball_quality = "good"
		_log("%s throws to %s" % [qb.tag(), rec.tag()], qb.pos, 1, res["detail"], "On target")
	target.y = clampf(target.y, -1.0, FIELD_W + 1.0)
	_launch(target, rec)


func _throw_away(detail: String) -> void:
	qb_state = "windup"
	pending_away = true
	windup = 0.15
	_log("%s looks to throw it away" % qb.tag(), qb.pos, -1, detail, "")


func _release_away() -> void:
	var y := -2.0 if qb.pos.y < FIELD_W * 0.5 else FIELD_W + 2.0
	ball_quality = "away"
	_log("%s throws it away" % qb.tag(), qb.pos, -1, "", "Thrown away")
	_launch(Vector2(qb.pos.x + 6.0, y), null)


func _launch(to: Vector2, rec: SimActor) -> void:
	qb_state = "thrown"
	qb.job = "idle"
	holder = null
	ball_in_air = true
	ball_from = qb.pos
	ball_to = to
	ball_target = rec
	ball_flight = 0.0
	ball_flight_time = _flight_time(ball_from, ball_to)
	thrown_at = t


# ---------------------------------------------------------------- movement

func _move(a: SimActor) -> void:
	if not a.is_up():
		a.vel = Vector2.ZERO
		return
	if a.shove != Vector2.ZERO:
		var step_len := minf(a.shove.length(), 4.0 * DT)
		var s := a.shove.normalized() * step_len
		a.pos += s
		a.shove -= s
		if a.shove.length() < 0.01:
			a.shove = Vector2.ZERO
	if a.engaged != null or a.stall_time > 0.0:
		a.vel = Vector2.ZERO
		return
	var target := _desired(a)
	var speed := a.top_speed
	if a.slow_time > 0.0:
		speed *= 0.5
	elif a.burst_time > 0.0:
		speed *= CATCH_BURST
	if a.cut_time > 0.0:
		speed *= 0.55
	if a.job == "block" and holder == qb and not is_run:
		speed *= 0.7
	var to := target - a.pos
	var L := to.length()
	if L < 0.05:
		a.vel = Vector2.ZERO
		return
	a.vel = to / L * minf(speed, L / DT)
	a.pos += a.vel * DT


func _desired(a: SimActor) -> Vector2:
	match a.job:
		"qb":
			if is_run:
				return a.pos
			return qb_set
		"idle":
			return a.pos
		"loose":
			return ball_pos
		"fake":
			return qb.pos + Vector2(0.5, float(run_side) * 1.0)
		"rb_run":
			return _follow_path(a, false)
		"carry":
			return _carrier_target(a)
		"route":
			return _route_target(a)
		"block":
			return _block_target_point(a)
		"rush":
			return _rush_target(a)
		"man":
			return _man_target(a)
		"zone":
			return _zone_target(a)
		"pursue":
			return _pursue_point(a)
		"escort":
			if holder != null:
				return holder.pos + Vector2(goal_dir(holder) * 3.0, (a.start_pos.y - ball_y) * 0.3)
			return a.pos
	return a.pos


func _follow_path(a: SimActor, allow_free: bool) -> Vector2:
	if a.path_index < a.path.size():
		var p := a.path[a.path_index]
		if a.pos.distance_to(p) < 0.6:
			var prev := a.path_dir
			a.path_index += 1
			if a.path_index < a.path.size():
				var nd := (a.path[a.path_index] - a.pos).normalized()
				if prev.dot(nd) < 0.7 and a.job == "route":
					a.cut_time = maxf(0.05, 0.35 - 0.04 * a.r("agi"))
					if a.has_skill("Route Technician"):
						a.cut_time *= 0.3
				a.path_dir = nd
				return a.path[a.path_index]
		else:
			var d := (p - a.pos)
			if d.length() > 0.01:
				a.path_dir = d.normalized()
			return p
	if allow_free:
		return _carrier_target(a)
	if a.path_end == "go":
		var p2 := a.pos + a.path_dir * 5.0
		p2.y = clampf(p2.y, 1.0, FIELD_W - 1.0)
		p2.x = minf(p2.x, END_LINE_STOP)
		return p2
	return a.pos


func _route_target(a: SimActor) -> Vector2:
	if ball_in_air:
		if ball_target == a:
			return ball_to
		return _follow_path(a, false)
	if holder != null and holder != qb and holder.side == a.side:
		a.job = "block"
		a.block_target = null
		return a.pos
	return _follow_path(a, false)


func _carrier_target(c: SimActor) -> Vector2:
	if c.job == "carry" and c.path_index < c.path.size():
		# Leave the designed path early if a free defender is right in the way.
		var blocked := false
		for d in opponents_of(c):
			if d.is_free() and d.pos.distance_to(c.pos) < 2.5 and (d.pos.x - c.pos.x) * goal_dir(c) > 0.0:
				blocked = true
		if not blocked:
			return _follow_path(c, false)
		c.path_index = c.path.size()
	var dir := goal_dir(c)
	var desired := Vector2(dir, 0.0)
	for d in opponents_of(c):
		if not d.is_free():
			continue
		var rel := d.pos - c.pos
		var dist := rel.length()
		if dist > 8.0 or dist < 0.01:
			continue
		if rel.x * dir < -1.0:
			continue
		var w := (8.0 - dist) / 8.0
		var lateral := -signf(rel.y)
		if absf(rel.y) < 0.2:
			lateral = 1.0 if c.pos.y < FIELD_W * 0.5 else -1.0
		desired.y += lateral * w * 1.4
	if c.pos.y < 4.0:
		desired.y += (4.0 - c.pos.y) * 0.4
	elif c.pos.y > FIELD_W - 4.0:
		desired.y -= (c.pos.y - (FIELD_W - 4.0)) * 0.4
	desired.x = dir * maxf(absf(desired.x), 0.5)
	return c.pos + desired.normalized() * 4.0


func _ball_spot() -> Vector2:
	if holder != null:
		return holder.pos
	if ball_in_air:
		return ball_to
	return ball_pos


func _block_target_point(a: SimActor) -> Vector2:
	var tgt := a.block_target
	if tgt == null or not tgt.is_up() or (tgt.engaged != null and tgt.engaged != a) or a.block_cooldown > 0.0:
		if a.block_cooldown <= 0.0:
			a.block_target = _find_block_target(a)
			tgt = a.block_target
		else:
			tgt = null
	if tgt == null:
		# Nobody to block: help a teammate (assist) or set up in front of the ball.
		var help := _nearest_engaged_defender(a)
		if help != null and help.pos.distance_to(a.pos) < 6.0:
			return help.pos + (a.pos - help.pos).normalized() * 1.2
		if holder == qb and not is_run:
			return a.start_pos + Vector2(-1.5, 0.0)
		if holder != null:
			return holder.pos + Vector2(goal_dir(holder) * 3.0, (a.start_pos.y - ball_y) * 0.2)
		return a.pos
	var anchor := _ball_spot()
	var between := (anchor - tgt.pos)
	if between.length() > 0.01:
		between = between.normalized()
	return tgt.pos + between * 0.9


func _find_block_target(a: SimActor) -> SimActor:
	var anchor := _ball_spot()
	var taken := {}
	for o in offense():
		if o != a and o.block_target != null:
			taken[o.block_target.id] = true
	var best: SimActor = null
	var best_score := INF
	for d in defenders():
		if not d.is_up() or d.engaged != null or taken.has(d.id):
			continue
		var da := d.pos.distance_to(a.pos)
		var dh := d.pos.distance_to(anchor)
		if da > 8.0:
			continue
		if holder == qb and not is_run:
			# Pass protection: only care about players coming after the QB.
			if d.job != "rush" and dh > 6.0:
				continue
		var score := da + dh * 0.7
		if score < best_score:
			best_score = score
			best = d
	return best


func _nearest_engaged_defender(a: SimActor) -> SimActor:
	var best: SimActor = null
	var bd := INF
	for d in defenders():
		if d.engaged != null and d.is_up():
			var dist := d.pos.distance_to(a.pos)
			if dist < bd:
				bd = dist
				best = d
	return best


func _nearest_free_opponent(a: SimActor) -> SimActor:
	var best: SimActor = null
	var bd := INF
	for o in opponents_of(a):
		if o.is_free():
			var dist := o.pos.distance_to(a.pos)
			if dist < bd:
				bd = dist
				best = o
	return best


func _chasing(d: SimActor) -> bool:
	return carrier_live() and t >= d.pursue_at


func _blocker_cuts_off(b: SimActor, d: SimActor) -> bool:
	# Is the blocker actually standing in the defender's way -- between him and the point
	# he's heading to intercept the ball carrier -- rather than off to the side or behind him
	# while the defender runs away or around him? For now this is a flat yes/no: in his way
	# means a block is allowed, not in his way means no block chance at all; later this is a
	# natural spot for a holding roll instead (let the block succeed anyway at the risk of a
	# penalty, rather than a flat no).
	if not carrier_live():
		return true
	var target := _pursue_point(d)
	var path := target - d.pos
	var path_len := path.length()
	if path_len < 0.5:
		return true
	var dir := path / path_len
	var to_blocker := b.pos - d.pos
	var ahead := to_blocker.dot(dir)
	if ahead <= 0.0 or ahead >= path_len:
		return false
	var lateral := (to_blocker - dir * ahead).length()
	return lateral <= BLOCK_RANGE


func _rush_target(d: SimActor) -> Vector2:
	if _chasing(d):
		return _pursue_point(d)
	if holder != null:
		return holder.pos
	if ball_in_air:
		return ball_to if pitched else d.pos
	return qb.pos


func _bite_point(d: SimActor) -> Vector2:
	var rb: SimActor = slots["O:RB"]
	return Vector2(minf(rb.pos.x + 1.0, los + 1.0), rb.pos.y)


func _man_target(d: SimActor) -> Vector2:
	if _chasing(d):
		return _pursue_point(d)
	if ball_in_air and t >= thrown_at + d.react_time:
		return ball_to
	if t < d.bite_until:
		return _bite_point(d)
	var m := d.man_target
	if m == null or m.job != "route":
		# His man stayed in to block: sit in a short zone and watch.
		if m != null and m.job in ["block", "fake"] and t > 0.8:
			d.job = "zone"
			d.zone_center = Vector2(los + 5.0, d.pos.y)
			d.zone_radius = 5.0
		return d.pos
	var seen := m.pos_ago(d.react_time, DT)
	var cushion := Vector2(1.2, 0.0)
	if m.pos.x < los:
		cushion = Vector2(0.6, 0.0)
	return seen + cushion


func _zone_target(d: SimActor) -> Vector2:
	if _chasing(d):
		return _pursue_point(d)
	if ball_in_air and t >= thrown_at + d.react_time:
		return ball_to
	if carrier_live() and not is_run:
		# The pass was just caught (or the QB scrambled) and this defender hasn't
		# reacted yet. Hold position instead of hunting for a receiver who's no
		# longer running a route (job flips to "carry" the instant the ball is
		# caught) or snapping back to the zone's anchor point -- either of which
		# can send him the wrong way for a beat, which reads as a glitch rather
		# than a believable reaction delay.
		return d.pos
	if t < d.bite_until:
		return _bite_point(d)
	var best: SimActor = null
	var best_depth := -INF
	for o in offense():
		if o.job != "route":
			continue
		var seen := o.pos_ago(d.react_time, DT)
		if seen.distance_to(d.zone_center) <= d.zone_radius + 1.5:
			if seen.x > best_depth:
				best_depth = seen.x
				best = o
	if best == null:
		return d.zone_center
	var seen2 := best.pos_ago(d.react_time, DT) + Vector2(1.0, 0.0)
	if d.zone_center.x - los >= 12.0:
		# Deep defender: never let anyone get behind you.
		var vel_x := maxf(0.0, best.vel.x)
		return Vector2(maxf(d.zone_center.x, seen2.x + 2.0 + vel_x * 0.25),
			lerpf(d.zone_center.y, seen2.y, 0.75))
	var p := d.zone_center.lerp(seen2, 0.8)
	var off := p - d.zone_center
	if off.length() > d.zone_radius + 3.0:
		p = d.zone_center + off.normalized() * (d.zone_radius + 3.0)
	return p


func _pursue_point(d: SimActor) -> Vector2:
	if holder == null:
		if ball_in_air:
			return ball_to
		return d.pos
	return _intercept_point(d, holder)


## Aim where the runner will be when we can get there (a pursuit angle), not where he is now.
func _intercept_point(d: SimActor, c: SimActor) -> Vector2:
	var rel := c.pos - d.pos
	var v := c.vel
	var s := d.top_speed
	# Solve |rel + v*t| = s*t for the smallest positive t.
	var qa := v.dot(v) - s * s
	var qb := 2.0 * rel.dot(v)
	var qc := rel.dot(rel)
	var tt := -1.0
	if absf(qa) < 0.001:
		if absf(qb) > 0.001:
			tt = -qc / qb
	else:
		var disc := qb * qb - 4.0 * qa * qc
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-qb - sq) / (2.0 * qa)
			var t2 := (-qb + sq) / (2.0 * qa)
			if t1 > 0.0 and t2 > 0.0:
				tt = minf(t1, t2)
			else:
				tt = maxf(t1, t2)
	if tt <= 0.0:
		tt = 1.0
	tt = minf(tt, 2.5)
	var p := c.pos + v * tt
	p.y = clampf(p.y, -0.5, FIELD_W + 0.5)
	return p


# ---------------------------------------------------------------- blocking

func _update_blocks() -> void:
	var pass_pro := (not is_run) and qb_in_pocket()
	for b in offense():
		if b.job != "block" or not b.is_up() or b == holder:
			continue
		if b.engaged == null:
			var d := b.block_target
			if d != null and d.is_up() and d.engaged == null and b.block_cooldown <= 0.0 and d.block_cooldown <= 0.0:
				if _blocker_cuts_off(b, d) and b.pos.distance_to(d.pos) < BLOCK_RANGE:
					b.engaged = d
					d.engaged = b
					b.block_timer = 0.6 if pass_pro else 0.25
			continue
		b.block_timer -= DT
		if b.block_timer > 0.0:
			continue
		b.block_timer = BLOCK_INTERVAL
		_resolve_block(b, b.engaged, pass_pro)


func _resolve_block(b: SimActor, d: SimActor, pass_pro: bool) -> void:
	var bs := b.r("str")
	var notes: Array[String] = []
	if is_run and b.has_skill("Road Grader"):
		bs += 1
		notes.append("Road Grader")
	if pass_pro and b.has_skill("Anchor"):
		bs += 1
		notes.append("Anchor")
	var assists := 0
	for o in offense():
		var busy := o.block_target != null and o.block_target != d and o.block_target.is_up()
		if o != b and o.job == "block" and o.is_free() and not busy and o != holder and o.pos.distance_to(d.pos) < ASSIST_RANGE:
			assists += 1
	assists = mini(assists, 2)
	if assists > 0:
		bs += assists
		notes.append("+%d assist" % assists)
	var ds := d.r("str")
	if pass_pro and d.has_skill("Pass Rusher"):
		ds += 1
		notes.append("Pass Rusher")
	var res := dice.roll_block(bs, ds, pass_pro)
	var face: int = res["face"]
	var dice_txt := "Block dice: STR %d vs %d%s, %d %s, %s picks: %s" % [
		bs, ds, (" (" + ", ".join(notes) + ")") if not notes.is_empty() else "",
		res["dice"], "die" if res["dice"] == 1 else "dice", res["chooser"],
		str(res["rolls"])]
	var push_dir := (d.pos - b.pos)
	push_dir = push_dir.normalized() if push_dir.length() > 0.01 else Vector2.RIGHT
	match face:
		Dice.Block.SHED:
			b.disengage()
			b.block_cooldown = 0.9
			d.block_cooldown = 0.7
			_log("%s sheds the block of %s" % [d.tag(), b.tag()], d.pos, 0, dice_txt + " = Shed", "Shed!")
		Dice.Block.STALEMATE:
			pass
		Dice.Block.PUSH:
			d.shove += push_dir * 1.0
			b.shove += push_dir * 1.0
		Dice.Block.DRIVE:
			d.shove += push_dir * 2.0
			b.shove += push_dir * 2.0
		Dice.Block.PANCAKE:
			b.disengage()
			d.down_time = 1.0
			b.block_cooldown = 0.2
			b.block_target = null
			_log("%s pancakes %s" % [b.tag(), d.tag()], d.pos, 1, dice_txt + " = Pancake", "Pancake!")


# ---------------------------------------------------------------- ball

func _update_ball() -> void:
	if holder != null:
		ball_pos = holder.pos
		return
	if ball_loose:
		_try_pickup()
		return
	if not ball_in_air:
		return
	ball_flight += DT
	var f := clampf(ball_flight / ball_flight_time, 0.0, 1.0)
	ball_pos = ball_from.lerp(ball_to, f)
	if f >= 1.0:
		ball_in_air = false
		_resolve_catch()


func _resolve_catch() -> void:
	if ball_target == null:
		_end_incomplete("Pass incomplete (thrown away)")
		return
	# A pass that lands behind where it was thrown from is a backward pass: if nobody catches
	# it, it's a live ball (a fumble), not an incompletion.
	var backward := ball_to.x < ball_from.x
	if not _in_bounds(ball_to):
		if backward:
			_dead_ball(ball_to, "Backward pass goes out of bounds")
		else:
			_end_incomplete("Pass incomplete, out of bounds")
		return
	# A defender can only try to intercept if he gets to the ball before the receiver does.
	var rec := ball_target
	var rec_dist := rec.pos.distance_to(ball_to) if rec.is_up() else 99.0
	var best_d: SimActor = null
	var best_dist := INF
	for d in defenders():
		if not d.is_free() or not _in_bounds(d.pos):
			continue
		var reach := 1.8 if d.has_skill("Ball Hawk") else 1.2
		var dist := d.pos.distance_to(ball_to)
		if dist <= reach and dist < rec_dist and dist < best_dist:
			best_dist = dist
			best_d = d
	var defended := false
	if best_d != null:
		var mod := 0
		if ball_quality == "good":
			mod = 1
		elif ball_quality == "duck":
			mod = -1
		# A ball thrown where no offensive player can get to it is a gift: much easier to pick
		# off, and the defender gets a free re-roll.
		var alone := true
		for o in offense():
			if o.is_up() and o.pos.distance_to(ball_to) <= CATCH_REACH:
				alone = false
				break
		var label := "Interception (Hands)"
		if alone:
			mod -= OPEN_INT_BONUS
			label = "Interception (Hands, no receiver near, re-roll)"
		var res := _test(best_d, 10 - best_d.r("hnd") + mod, label, "Ball Hawk", alone)
		if res["ok"]:
			_log("INTERCEPTED by %s!" % best_d.tag(), best_d.pos, 0, res["detail"], "INT!")
			_start_turnover(best_d)
			return
		defended = true
		_log("%s gets a hand on it" % best_d.tag(), best_d.pos, 0, res["detail"], "Breakup")

	if not rec.is_up() or rec_dist > CATCH_REACH:
		if backward:
			_fumble_loose(ball_to, "%s can't reach the backward pass" % rec.tag(), "")
		else:
			_end_incomplete("Pass incomplete, %s can't reach it" % rec.tag())
		return
	if not _in_bounds(rec.pos):
		if backward:
			_dead_ball(rec.pos, "%s is out of bounds, ball dead" % rec.tag())
		else:
			_end_incomplete("Pass incomplete, %s is out of bounds" % rec.tag())
		return
	if pitched:
		_catch_pitch(rec, backward)
		return
	var marks := 0
	for d in defenders():
		if d.is_free() and d.pos.distance_to(rec.pos) <= ZONE_RANGE:
			marks += 1
	var mod2 := marks + (1 if defended else 0)
	if ball_quality == "bad":
		mod2 += 1
	elif ball_quality == "duck":
		mod2 += 2
	var label := "Catch (Hands%s%s)" % [
		", %d defender%s close" % [marks, "" if marks == 1 else "s"] if marks > 0 else "",
		", off target" if ball_quality != "good" else ""]
	if defended:
		label = label.trim_suffix(")") + ", tipped)"
	var catch_target := 7 - rec.r("hnd") + mod2
	var res2 := _test(rec, catch_target, label, "Soft Hands")
	var clean: bool = res2["ok"]
	# An open receiver (nobody marking him, nobody got a hand on it) who misses the first try
	# bobbles it and gets one more go, one easier. If he hauls it in he has to keep his feet
	# ((7 - Agility)+): stay up and he stands still a moment gathering it, go down and the play
	# is over where he lands (he's down, but it's a catch).
	var bobbled := not clean and marks == 0 and not defended
	if bobbled:
		var res3 := _test(rec, catch_target - 1, "Bobbled, second try (Hands, +1)")
		res2["detail"] += "; " + res3["detail"]
		res2["ok"] = res3["ok"]
	if not res2["ok"]:
		if backward:
			_fumble_loose(ball_to, "%s drops the backward pass" % rec.tag(), res2["detail"])
		else:
			_end_incomplete("Pass incomplete, dropped by %s" % rec.tag(), res2["detail"])
		return
	rec.pos = ball_to
	holder = rec
	rec.job = "carry"
	rec.path.clear()
	rec.path_index = 0
	if bobbled:
		var feet := _test(rec, 7 - rec.r("agi"), "Stay on his feet (Agility)")
		if not feet["ok"]:
			_log("Caught by %s after a bobble, but he goes down" % rec.tag(), rec.pos, 1,
				res2["detail"] + "; " + feet["detail"], "Caught")
			_end_tackled(rec, "Caught by %s, down after the bobble" % rec.tag())
			return
		_log("Caught by %s after a bobble" % rec.tag(), rec.pos, 1,
			res2["detail"] + "; " + feet["detail"], "Bobbled catch")
		rec.stall_time = BOBBLE_STALL
	else:
		# A clean catch on the first try (Soft Hands' re-roll counts) lets him turn upfield in stride.
		_log("Caught by %s" % rec.tag(), rec.pos, 1, res2["detail"], "Caught")
		rec.burst_time = CATCH_BURST_TIME
	for d in defenders():
		# A defender who was already covering this receiver (his man, or close enough in
		# zone to have a hand on the play) is watching the catch happen and reacts right
		# away. Everyone else still needs a short beat to find the ball.
		var covering_him := d.man_target == rec or d.pos.distance_to(rec.pos) <= 4.0
		d.pursue_at = minf(d.pursue_at, t if covering_him else t + d.react_time)
	if rec.pos.x >= OPP_GOAL:
		_touchdown(rec)


## A pitch is an easy catch: PITCH_CATCH+, and a miss always gets a second try. The RB
## keeps running his designed path once he has it.
func _catch_pitch(rec: SimActor, backward: bool) -> void:
	var roll := dice.d6()
	var detail := "Pitch catch: needs %d+, rolled %d" % [PITCH_CATCH, roll]
	if roll < PITCH_CATCH:
		roll = dice.d6()
		detail += ", re-roll %d" % roll
	if roll < PITCH_CATCH:
		if backward:
			_fumble_loose(ball_to, "%s drops the pitch" % rec.tag(), detail)
		else:
			_end_incomplete("Pitch dropped by %s" % rec.tag(), detail)
		return
	_log("%s gathers in the pitch" % rec.tag(), rec.pos, 1, detail, "")
	rec.pos = ball_to
	holder = rec
	rec.job = "carry"
	if rec.pos.x >= OPP_GOAL:
		_touchdown(rec)


## A dropped backward pass: the ball hits the ground and scatters, and both sides go after it.
func _fumble_loose(at: Vector2, text: String, detail: String) -> void:
	ball_loose = true
	holder = null
	ball_in_air = false
	ball_pos = at
	_log("FUMBLE! %s" % text, at, 0, detail, "Fumble!")
	for a in actors:
		a.disengage()
		a.job = "loose"
	_scatter_ball(dice.rng.randf_range(1.0, 3.0))


## The loose ball bounces `dist` yards in a random direction, like the Blood Bowl scatter template.
func _scatter_ball(dist: float) -> void:
	ball_pos += dice.scatter(dist)
	if not _in_bounds(ball_pos):
		_dead_ball(ball_pos, "The ball rolls out of bounds")


## The closest player to a loose ball tries to scoop it up: (7 - Agility)+, one harder for each
## opponent marking him. A miss knocks it another yard away.
func _try_pickup() -> void:
	var best: SimActor = null
	var best_dist := LOOSE_REACH
	for a in actors:
		if not a.is_up() or a.tackle_cooldown > 0.0:
			continue
		var dist := a.pos.distance_to(ball_pos)
		if dist <= best_dist:
			best_dist = dist
			best = a
	if best == null:
		return
	var marks := 0
	for o in opponents_of(best):
		if o.is_free() and o.pos.distance_to(best.pos) <= ZONE_RANGE:
			marks += 1
	var label := "Scoop up the ball (Agility%s)" % (", %d marking him" % marks if marks > 0 else "")
	var res := _test(best, 7 - best.r("agi") + marks, label, "Ball Security")
	if not res["ok"]:
		best.tackle_cooldown = 0.6
		_log("%s can't pick it up" % best.tag(), ball_pos, -1, res["detail"], "Bobbled")
		_scatter_ball(1.0)
		return
	ball_loose = false
	holder = best
	if best.side == SimActor.Side.DEFENSE:
		_log("Recovered by %s!" % best.tag(), ball_pos, 0, res["detail"], "Recovered!")
		turnover_kind = "fumble"
		_start_turnover(best)
		return
	_log("%s falls on it, offense keeps the ball" % best.tag(), ball_pos, 1, res["detail"], "Recovered")
	best.job = "carry"
	best.path.clear()
	for a in actors:
		if a == best:
			continue
		if a.side == best.side:
			a.job = "block"
			a.block_target = null
		else:
			a.job = "pursue"
			a.pursue_at = t + a.react_time


## The ball is dead where it went out (a backward pass or a loose ball out of bounds); the
## offense keeps it there, unless that's in its own end zone.
func _dead_ball(at: Vector2, text: String) -> void:
	_log(text, at, -1)
	var x := minf(at.x, OPP_GOAL - 0.5)
	if x <= OWN_GOAL:
		_finish({"kind": "safety", "end_x": x, "turnover": false, "clock_stops": true, "text": "SAFETY!"})
		return
	_finish({"kind": "oob", "end_x": x, "end_y": clampf(at.y, 0.0, FIELD_W), "turnover": false,
		"clock_stops": true, "text": text})


func _start_turnover(new_holder: SimActor) -> void:
	turnover = true
	holder = new_holder
	new_holder.job = "carry"
	new_holder.disengage()
	new_holder.path.clear()
	for a in actors:
		if a == new_holder:
			continue
		a.disengage()
		if a.side == new_holder.side:
			a.job = "escort"
		else:
			a.job = "pursue"
			a.pursue_at = t + a.react_time


# ---------------------------------------------------------------- tackles

func _check_tackles() -> void:
	if holder == null:
		return
	var c := holder
	var opps := opponents_of(c)
	opps.sort_custom(func(x: SimActor, y: SimActor) -> bool: return x.pos.distance_to(c.pos) < y.pos.distance_to(c.pos))
	for d in opps:
		if not d.is_up() or d.tackle_cooldown > 0.0:
			continue
		var dist := d.pos.distance_to(c.pos)
		if dist > ZONE_RANGE:
			break
		# Engaged defenders can only arm-tackle a runner going right past them, and it's harder.
		var engaged_pen := 2 if d.engaged != null else 0
		if engaged_pen > 0 and dist > TACKLE_RANGE:
			continue
		# Diving from the edge of his tackle zone is one step harder.
		var dive := 1 if dist > TACKLE_RANGE else 0
		if dive > 0 and c == qb and qb_in_pocket():
			continue
		# Only dive when the runner is getting away; otherwise keep closing for a solid tackle.
		if dive > 0:
			var away := c.vel.dot((c.pos - d.pos).normalized())
			if away < d.top_speed * 0.6:
				continue
		var assists := 0
		for o in opps:
			if o != d and o.is_free() and o.pos.distance_to(c.pos) <= ZONE_RANGE:
				assists += 1
		assists = mini(assists, 2)
		var elusive := 1 if c.has_skill("Elusive") else 0
		var target := 2 + maxi(0, c.r("agi") - d.r("tkl")) / 2 + engaged_pen + dive - assists + elusive
		var label := "%s (%s Tackling %d vs Agility %d%s%s%s)" % [
			"Diving tackle" if dive > 0 else "Tackle", d.slot, d.r("tkl"), c.r("agi"),
			", %d helping" % assists if assists > 0 else "",
			", engaged" if engaged_pen > 0 else "",
			", Elusive" if elusive > 0 else ""]
		var res := _test(d, target, label, "Sure Tackler")
		# Gang tackle: when help is already making it a 2+, a failed roll gets one more chance.
		if not res["ok"] and assists > 0 and target <= 2:
			var r2 := dice.d6()
			res["ok"] = r2 >= 2
			res["roll"] = r2
			res["detail"] = str(res["detail"]) + ", gang tackle re-roll %d" % r2
		if res["ok"]:
			if c == qb and qb_in_pocket():
				_log("SACKED by %s!" % d.tag(), c.pos, _fav(d.side), res["detail"], "Sack!")
			else:
				_log("Tackled by %s" % d.tag(), c.pos, _fav(d.side), res["detail"], "Tackle")
			if int(res["roll"]) == 6 and _check_fumble(c, d):
				return
			_end_tackled(c, "")
			return
		d.down_time = 0.8
		d.tackle_cooldown = 1.0
		c.slow_time = 0.35
		_log("%s breaks a tackle by %s" % [c.tag(), d.tag()], c.pos, _fav(c.side), res["detail"], "Missed!")
		return


## A big hit (natural 6 on the tackle) can jar the ball loose.
func _check_fumble(c: SimActor, hitter: SimActor) -> bool:
	var res := _test(c, 2, "Hold on after big hit", "Ball Security")
	if res["ok"]:
		return false
	var rec := dice.d6()
	var side_rec := hitter.side if rec >= 4 else c.side
	var detail: String = res["detail"] + "; recovery roll %d (4+ = hitting team)" % rec
	if side_rec == c.side:
		_log("FUMBLE! %s's team falls on it" % c.tag(), c.pos, _fav(c.side), detail, "Fumble!")
		_end_tackled(c, "")
	else:
		_log("FUMBLE! Recovered by the other team!", c.pos, _fav(hitter.side), detail, "Fumble!")
		_finish({"kind": "fumble", "end_x": c.pos.x, "turnover": true, "clock_stops": true,
			"text": "Fumble, recovered by the defense"})
	return true


func _check_boundaries() -> void:
	if holder == null:
		return
	var c := holder
	if c.side == SimActor.Side.OFFENSE and c.pos.x >= OPP_GOAL and not (c == qb and qb_in_pocket()):
		_touchdown(c)
		return
	if c.side == SimActor.Side.DEFENSE and c.pos.x <= OWN_GOAL:
		_finish({"kind": "def_td", "end_x": OWN_GOAL, "turnover": true, "clock_stops": true,
			"text": "Returned for a TOUCHDOWN by %s!" % c.tag()})
		_log("Defensive TOUCHDOWN!", c.pos, 0, "", "TOUCHDOWN")
		return
	if c.pos.y < 0.0 or c.pos.y > FIELD_W:
		_log("%s runs out of bounds" % c.tag(), c.pos, -1)
		_end_tackled(c, "Out of bounds", true)


# ---------------------------------------------------------------- finishing

func _touchdown(c: SimActor) -> void:
	_log("TOUCHDOWN!", c.pos, 1, "", "TOUCHDOWN")
	_finish({"kind": "td", "end_x": OPP_GOAL, "turnover": false, "clock_stops": true,
		"text": "TOUCHDOWN %s!" % c.tag()})


func _end_tackled(c: SimActor, note: String, oob := false) -> void:
	if c == null:
		if ball_loose:
			_dead_ball(ball_pos, "Whistle, the ball is dead")
		else:
			_end_incomplete("Whistle")
		return
	var x := c.pos.x
	if turnover:
		_finish({"kind": turnover_kind, "end_x": x, "turnover": true, "clock_stops": true,
			"text": "Turnover, return ends at the spot"})
		return
	# Hit after crossing the goal line still counts: the ball broke the plane.
	if x >= OPP_GOAL and c.side == SimActor.Side.OFFENSE and not (c == qb and qb_in_pocket()):
		_touchdown(c)
		return
	if x <= OWN_GOAL:
		_finish({"kind": "safety", "end_x": x, "turnover": false, "clock_stops": true, "text": "SAFETY!"})
		return
	var kind := "sack" if (c == qb and qb_in_pocket()) else ("oob" if oob else "tackle")
	_finish({"kind": kind, "end_x": x, "turnover": false, "clock_stops": oob, "text": note})


func _end_incomplete(text: String, detail: String = "") -> void:
	_log(text, ball_to, 0, detail, "Incomplete")
	_finish({"kind": "incomplete", "end_x": los, "turnover": false, "clock_stops": true, "text": text})


## Breaks the references between actors so the play can be freed from memory.
func dispose() -> void:
	for a in actors:
		a.engaged = null
		a.block_target = null
		a.man_target = null
	pending_rec = null
	ball_target = null
	holder = null
	qb = null
	slots.clear()
	actors.clear()


func _finish(r: Dictionary) -> void:
	if done:
		return
	done = true
	r["yards"] = int(round(float(r["end_x"]) - los))
	if not r.has("end_y"):
		r["end_y"] = holder.pos.y if holder != null else ball_y
	r["duration"] = t
	r["thrown"] = thrown_at >= 0.0 and not pitched
	result = r
