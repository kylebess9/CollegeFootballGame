class_name PlaySim
extends RefCounted
## Simulates one play from snap to whistle.
##
## Field frame used here: the offense always drives toward +x.
## x = 0..10 is the offense's own end zone, 10 = own goal line, 110 = opponent goal line.
## y = 0..53.33 across the field. The screen flips this when the away team has the ball.
##
## Movement is automatic. Dice decide the contested moments:
##   blocks (block dice), throws (accuracy), catches, interceptions, tackles, play-action bites, fumbles.

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
const HANDOFF_TIME := 0.55
const OPEN_THRESHOLD := 1.8
const MAX_TIME := 20.0

var dice: Dice
var off_team: Team
var def_team: Team
var off_name := ""
var def_name := ""
var off_play: Dictionary
var def_play: Dictionary
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
var rerolls := {SimActor.Side.OFFENSE: 0, SimActor.Side.DEFENSE: 0}

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
var turnover := false

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
var windup := 0.0
var pending_rec: SimActor = null
var pending_hurried := false
var pending_away := false


func setup(offense: Team, defense: Team, off_call: String, def_call: String, ball_on: float, spot_y: float,
		situation: Dictionary, off_rerolls: int, def_rerolls: int, dice_in: Dice) -> void:
	dice = dice_in
	off_team = offense
	def_team = defense
	off_name = off_call
	def_name = def_call
	off_play = Playbook.OFFENSE[off_call]
	def_play = Playbook.DEFENSE[def_call]
	is_run = off_play["type"] == "run"
	play_action = bool(off_play.get("play_action", false))
	los = OWN_GOAL + ball_on
	ball_y = clampf(spot_y, HASH_LEFT, HASH_RIGHT)
	down = int(situation.get("down", 1))
	to_go = int(situation.get("to_go", 10))
	rerolls[SimActor.Side.OFFENSE] = off_rerolls
	rerolls[SimActor.Side.DEFENSE] = def_rerolls
	run_side = 1 if dice.rng.randf() < 0.5 else -1
	_build_offense()
	_build_defense()
	qb = slots["O:QB"]
	holder = qb
	ball_pos = qb.pos
	if not is_run:
		qb_set = Vector2(los - float(off_play["drop"]), ball_y)


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


func _build_offense() -> void:
	var dc := off_team.depth_chart()
	var c := ball_y
	var O := SimActor.Side.OFFENSE
	_add(off_team, O, "C", dc["C"], Vector2(los - 0.6, c))
	_add(off_team, O, "LG", dc["LG"], Vector2(los - 0.7, c - 1.4))
	_add(off_team, O, "RG", dc["RG"], Vector2(los - 0.7, c + 1.4))
	_add(off_team, O, "LT", dc["LT"], Vector2(los - 0.9, c - 2.8))
	_add(off_team, O, "RT", dc["RT"], Vector2(los - 0.9, c + 2.8))
	_add(off_team, O, "TE", dc["TE"], Vector2(los - 0.9, c + 4.3))
	_add(off_team, O, "QB", dc["QB"], Vector2(los - 4.0, c))
	_add(off_team, O, "RB", dc["RB"], Vector2(los - 6.5, c))
	var wr1y := _clamp_y(c - 13.0)
	_add(off_team, O, "WR1", dc["WR1"], Vector2(los - 0.8, wr1y))
	_add(off_team, O, "WR3", dc["WR3"], Vector2(los - 1.5, (wr1y + c) * 0.5 + 0.5))
	_add(off_team, O, "WR2", dc["WR2"], Vector2(los - 1.5, _clamp_y(c + 15.0)))

	var line_blocks := {"LT": "DE1", "LG": "DT1", "RG": "DT2", "RT": "DE2"}
	for s in line_blocks:
		var a: SimActor = slots["O:" + s]
		a.job = "block"
		a.block_target = null # resolved after defense exists
	slots["O:C"].job = "block"
	slots["O:QB"].job = "qb"

	if is_run:
		var rb: SimActor = slots["O:RB"]
		rb.job = "rb_run"
		var s := float(run_side)
		if off_play["run_path"] == "inside":
			rb.path = [Vector2(los - 1.5, c + s * 2.0), Vector2(los + 2.0, c + s * 2.5)]
		else:
			rb.path = [Vector2(los - 3.5, c + s * 7.0), Vector2(los + 0.5, c + s * 11.0)]
		rb.path_end = "free"
		for s2 in ["TE", "WR1", "WR2", "WR3"]:
			slots["O:" + s2].job = "block"
	else:
		var routes: Dictionary = off_play["routes"]
		for s2 in ["TE", "WR1", "WR2", "WR3", "RB"]:
			var a: SimActor = slots["O:" + s2]
			if routes.has(s2):
				_assign_route(a, routes[s2])
			else:
				a.job = "block"
		if play_action:
			# RB carries out the fake, then picks up blitzers.
			slots["O:RB"].job = "fake"


func _assign_route(a: SimActor, route_name: String) -> void:
	var r: Dictionary = Playbook.ROUTES[route_name]
	var outside := 1.0 if a.start_pos.y >= ball_y else -1.0
	if a.slot == "RB":
		outside = float(run_side)
	a.job = "route"
	a.path.clear()
	for p in r["points"]:
		var pt: Vector2 = a.start_pos + Vector2(p.x, p.y * outside)
		pt.y = clampf(pt.y, 1.5, FIELD_W - 1.5)
		a.path.append(pt)
	a.path_end = r["end"]


func _build_defense() -> void:
	var dc := def_team.depth_chart()
	var c := ball_y
	var D := SimActor.Side.DEFENSE
	var run_first := bool(def_play.get("run_first", false))
	_add(def_team, D, "DE1", dc["DE1"], Vector2(los + 1.0, c - 4.0))
	_add(def_team, D, "DT1", dc["DT1"], Vector2(los + 1.0, c - 1.0))
	_add(def_team, D, "DT2", dc["DT2"], Vector2(los + 1.0, c + 1.2))
	_add(def_team, D, "DE2", dc["DE2"], Vector2(los + 1.0, c + 3.7))
	_add(def_team, D, "WILL", dc["WILL"], Vector2(los + 5.0, c - 4.0))
	_add(def_team, D, "MIKE", dc["MIKE"], Vector2(los + 5.0, c))
	_add(def_team, D, "SAM", dc["SAM"], Vector2(los + 4.5, c + 4.5))
	var wr1: SimActor = slots["O:WR1"]
	var wr2: SimActor = slots["O:WR2"]
	var wr3: SimActor = slots["O:WR3"]
	_add(def_team, D, "CB1", dc["CB1"], Vector2(los + 6.0, wr1.pos.y))
	_add(def_team, D, "CB2", dc["CB2"], Vector2(los + 6.0, wr2.pos.y))
	if run_first:
		_add(def_team, D, "SS", dc["SS"], Vector2(los + 5.5, c - 6.5))
	else:
		_add(def_team, D, "SS", dc["SS"], Vector2(los + 8.0, wr3.pos.y + 1.0))
	_add(def_team, D, "FS", dc["FS"], Vector2(los + 13.0, c))

	for s in ["DE1", "DT1", "DT2", "DE2"]:
		slots["D:" + s].job = "rush"
	var assign: Dictionary = def_play["assign"]
	for s in assign:
		var a: SimActor = slots["D:" + s]
		var info: Dictionary = assign[s]
		match info["type"]:
			"man":
				a.job = "man"
				a.man_target = slots["O:" + info["target"]]
				if a.has_skill("Shutdown"):
					a.react_time = maxf(0.05, a.react_time - 0.12)
			"zone":
				a.job = "zone"
				var zy: float
				if info.has("fy"):
					zy = FIELD_W * float(info["fy"])
				else:
					zy = c + float(info["dy"])
				a.zone_center = Vector2(los + float(info["dx"]), _clamp_y(zy))
				a.zone_radius = float(info["r"])
			"blitz":
				a.job = "rush"
		if run_first and s in ["WILL", "MIKE", "SAM", "SS"]:
			a.run_first = true

	# Offensive blocking assignments
	var O := "O:"
	slots[O + "LT"].block_target = slots["D:DE1"]
	slots[O + "LG"].block_target = slots["D:DT1"]
	slots[O + "RG"].block_target = slots["D:DT2"]
	slots[O + "RT"].block_target = slots["D:DE2"]
	if is_run:
		slots[O + "C"].block_target = slots["D:MIKE"]
		slots[O + "TE"].block_target = slots["D:SAM"]
		slots[O + "WR1"].block_target = slots["D:CB1"]
		slots[O + "WR2"].block_target = slots["D:CB2"]
		slots[O + "WR3"].block_target = slots["D:SS"]
		# Defenders figure out it's a run after the handoff, depending on Awareness.
		for d in defenders():
			d.pursue_at = HANDOFF_TIME + d.react_time * 1.5
			if d.run_first:
				d.pursue_at = HANDOFF_TIME + 0.1
	else:
		for d in defenders():
			if d.run_first:
				d.bite_until = 0.9 + d.react_time


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


## A Blood Bowl style test: roll a d6, need target or higher. Skills and team re-rolls can save a failure.
func _test(a: SimActor, target: int, label: String, skill: String = "", team_reroll := false) -> Dictionary:
	target = Dice.clamp_target(target)
	var first := dice.d6()
	var roll := first
	var ok := roll >= target
	var detail := "%s: needs %d+, rolled %d" % [label, target, roll]
	if not ok and skill != "" and a.has_skill(skill):
		roll = dice.d6()
		ok = roll >= target
		detail += ", %s re-roll %d" % [skill, roll]
	elif not ok and team_reroll and rerolls[a.side] > 0:
		rerolls[a.side] -= 1
		roll = dice.d6()
		ok = roll >= target
		detail += ", TEAM RE-ROLL %d (%d left)" % [roll, rerolls[a.side]]
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
	if is_run and not handed_off and t >= HANDOFF_TIME:
		handed_off = true
		var rb: SimActor = slots["O:RB"]
		holder = rb
		rb.job = "carry"
		qb_state = "handed_off"
		qb.job = "idle"
		_log("%s takes the handoff" % rb.tag(), rb.pos, -1, "", "")
	if play_action and not handed_off and t >= HANDOFF_TIME:
		handed_off = true
		_log("Play-action fake!", qb.pos)
		for d in defenders():
			if d.slot in ["WILL", "MIKE", "SAM", "SS"] and d.job != "man" or d.run_first:
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


# ---------------------------------------------------------------- QB decisions

func _qb_decide() -> void:
	var threat := _nearest_free_opponent(qb)
	var threat_dist: float = INF if threat == null else threat.pos.distance_to(qb.pos)
	under_pressure = threat_dist < 1.3 + 0.3 * qb.r("awr")

	if qb_state == "drop":
		if qb.pos.distance_to(qb_set) < 0.4 and t >= float(off_play["read_start"]):
			qb_state = "read"
			_start_read(0)
		elif not under_pressure:
			return

	var reads: Array = off_play["reads"]
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
	for s in off_play["reads"]:
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
	if a.engaged != null:
		a.vel = Vector2.ZERO
		return
	var target := _desired(a)
	var speed := a.top_speed
	if a.slow_time > 0.0:
		speed *= 0.5
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


func _rush_target(d: SimActor) -> Vector2:
	if _chasing(d):
		return _pursue_point(d)
	if holder != null:
		return holder.pos
	if ball_in_air:
		return d.pos
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
				if b.pos.distance_to(d.pos) < BLOCK_RANGE:
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
	# A defender can only try to intercept if he gets to the ball before the receiver does.
	var rec := ball_target
	var rec_dist := rec.pos.distance_to(ball_to) if rec.is_up() else 99.0
	var best_d: SimActor = null
	var best_dist := INF
	for d in defenders():
		if not d.is_free():
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
		var res := _test(best_d, 10 - best_d.r("hnd") + mod, "Interception (Hands)", "Ball Hawk")
		if res["ok"]:
			_log("INTERCEPTED by %s!" % best_d.tag(), best_d.pos, 0, res["detail"], "INT!")
			_start_turnover(best_d)
			return
		defended = true
		_log("%s gets a hand on it" % best_d.tag(), best_d.pos, 0, res["detail"], "Breakup")

	if not rec.is_up() or rec_dist > CATCH_REACH:
		_end_incomplete("Pass incomplete, %s can't reach it" % rec.tag())
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
	var air_yards := ball_to.x - los
	var use_team := down >= 3 or air_yards >= 15.0
	var label := "Catch (Hands%s%s)" % [
		", %d defender%s close" % [marks, "" if marks == 1 else "s"] if marks > 0 else "",
		", off target" if ball_quality != "good" else ""]
	if defended:
		label = label.trim_suffix(")") + ", tipped)"
	var res2 := _test(rec, 7 - rec.r("hnd") + mod2, label, "Soft Hands", use_team)
	if not res2["ok"]:
		_end_incomplete("Pass incomplete, dropped by %s" % rec.tag(), res2["detail"])
		return
	_log("Caught by %s" % rec.tag(), rec.pos, 1, res2["detail"], "Caught")
	rec.pos = ball_to
	rec.slow_time = 0.45
	holder = rec
	rec.job = "carry"
	rec.path.clear()
	rec.path_index = 0
	for d in defenders():
		d.pursue_at = minf(d.pursue_at, t + d.react_time)


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
		var breaking_free := true
		for o in opps:
			if o != d and o.is_up() and o.pos.distance_to(c.pos) < 4.0:
				breaking_free = false
		var near_goal := (c.pos.x > OPP_GOAL - 12.0) if c.side == SimActor.Side.OFFENSE else (c.pos.x < OWN_GOAL + 12.0)
		var label := "%s (%s Tackling %d vs Agility %d%s%s%s)" % [
			"Diving tackle" if dive > 0 else "Tackle", d.slot, d.r("tkl"), c.r("agi"),
			", %d helping" % assists if assists > 0 else "",
			", engaged" if engaged_pen > 0 else "",
			", Elusive" if elusive > 0 else ""]
		var res := _test(d, target, label, "Sure Tackler", breaking_free or near_goal)
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
		_finish({"kind": "td", "end_x": OPP_GOAL, "turnover": false, "clock_stops": true,
			"text": "TOUCHDOWN %s!" % c.tag()})
		_log("TOUCHDOWN!", c.pos, 1, "", "TOUCHDOWN")
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

func _end_tackled(c: SimActor, note: String, oob := false) -> void:
	if c == null:
		_end_incomplete("Whistle")
		return
	var x := c.pos.x
	if turnover:
		_finish({"kind": "int", "end_x": x, "turnover": true, "clock_stops": true,
			"text": "Turnover, return ends at the spot"})
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
	r["rerolls_off"] = rerolls[SimActor.Side.OFFENSE]
	r["rerolls_def"] = rerolls[SimActor.Side.DEFENSE]
	r["thrown"] = thrown_at >= 0.0
	result = r
