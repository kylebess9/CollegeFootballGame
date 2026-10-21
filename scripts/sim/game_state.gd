class_name GameState
extends RefCounted
## Score, clock, downs and possession for one game. Also resolves kicks with dice.

const HOME := 0
const AWAY := 1
const FIELD_W := 53.333

var teams: Array[Team] = []
var score: Array[int] = [0, 0]
var quarter := 1
var quarter_length := 480.0
var clock := 480.0
var possession := AWAY
var ball_on := 25.0 # yards from the offense's own goal line (0-100)
var spot_y := FIELD_W * 0.5
var down := 1
var to_go := 10
var rerolls: Array[int] = [3, 3]
var over := false
var dice: Dice
var stats := [
	{"plays": 0, "yards": 0, "pass_yds": 0, "rush_yds": 0, "turnovers": 0, "first_downs": 0},
	{"plays": 0, "yards": 0, "pass_yds": 0, "rush_yds": 0, "turnovers": 0, "first_downs": 0},
]


func _init(home: Team, away: Team, quarter_minutes: float, dice_in: Dice) -> void:
	teams = [home, away]
	quarter_length = quarter_minutes * 60.0
	clock = quarter_length
	dice = dice_in
	rerolls = [home.rerolls, away.rerolls]


func offense() -> Team:
	return teams[possession]


func defense() -> Team:
	return teams[1 - possession]


func situation() -> Dictionary:
	return {"down": down, "to_go": to_go, "ball_on": ball_on}


static func ordinal(n: int) -> String:
	return ["1st", "2nd", "3rd", "4th"][clampi(n - 1, 0, 3)]


func field_position_text() -> String:
	var b := int(round(ball_on))
	if b == 50:
		return "50"
	if b < 50:
		return "%s %d" % [offense().abbrev, b]
	return "%s %d" % [defense().abbrev, 100 - b]


func down_text() -> String:
	var dist := "Goal" if ball_on + to_go >= 100 else str(to_go)
	return "%s & %s at %s" % [ordinal(down), dist, field_position_text()]


func clock_text() -> String:
	var c := maxi(0, int(ceil(clock)))
	return "Q%d  %d:%02d" % [mini(quarter, 4), c / 60, c % 60]


## Applies a finished play's result. Returns lines for the play-by-play.
func apply_play(res: Dictionary, was_run: bool) -> Array[String]:
	var lines: Array[String] = []
	var off := possession
	rerolls[off] = int(res["rerolls_off"])
	rerolls[1 - off] = int(res["rerolls_def"])
	var kind: String = res["kind"]
	var yards: int = res["yards"]
	stats[off]["plays"] += 1
	var runoff := float(res["duration"]) + (6.0 if bool(res["clock_stops"]) else 32.0)

	match kind:
		"td":
			var gained := int(round(100.0 - ball_on))
			_add_yards(off, gained, was_run)
			lines.append("TOUCHDOWN %s! (%d yards)" % [offense().school, gained])
			_score(off, 6)
			lines.append_array(_extra_point(off))
			lines.append_array(_kickoff(1 - off))
		"def_td":
			stats[off]["turnovers"] += 1
			lines.append("Turnover returned for a TOUCHDOWN by %s!" % defense().school)
			_score(1 - off, 6)
			lines.append_array(_extra_point(1 - off))
			lines.append_array(_kickoff(off))
		"safety":
			lines.append("SAFETY! 2 points to %s" % defense().school)
			_score(1 - off, 2)
			lines.append_array(_kickoff(1 - off))
		"int", "fumble":
			stats[off]["turnovers"] += 1
			var new_on := 110.0 - float(res["end_x"])
			lines.append("%s! %s takes over." % ["Interception" if kind == "int" else "Fumble lost", defense().school])
			possession = 1 - off
			if new_on <= 0.0:
				new_on = 20.0
				lines.append("Touchback.")
			_new_series(new_on, FIELD_W - float(res["end_y"]))
		_:
			_add_yards(off, yards, was_run)
			var verb := {"tackle": "Gain of %d", "oob": "Out of bounds after %d", "sack": "Sacked, %d",
				"incomplete": "Incomplete"}
			var fmt: String = verb.get(kind, "Gain of %d")
			lines.append(fmt % yards if fmt.contains("%d") else fmt)
			ball_on = clampf(ball_on + yards, 1.0, 99.0)
			if kind != "incomplete":
				spot_y = clampf(float(res["end_y"]), 23.58, 29.75)
			to_go -= yards
			if to_go <= 0:
				stats[off]["first_downs"] += 1
				lines.append("FIRST DOWN!")
				down = 1
				to_go = mini(10, int(ceil(100.0 - ball_on)))
			else:
				down += 1
				if down > 4:
					lines.append("Turnover on downs.")
					possession = 1 - off
					_new_series(100.0 - ball_on, FIELD_W - spot_y)
	lines.append_array(_run_clock(runoff))
	return lines


func _add_yards(team: int, yards: int, was_run: bool) -> void:
	stats[team]["yards"] += yards
	if was_run:
		stats[team]["rush_yds"] += yards
	else:
		stats[team]["pass_yds"] += yards


func _new_series(on: float, y: float) -> void:
	ball_on = clampf(on, 1.0, 99.0)
	spot_y = clampf(y, 23.58, 29.75)
	down = 1
	to_go = mini(10, int(ceil(100.0 - ball_on)))


func _score(team: int, pts: int) -> void:
	score[team] += pts


func _kicker(team: int) -> FootballPlayer:
	return teams[team].depth_chart()["K"]


func _extra_point(team: int) -> Array[String]:
	var k := _kicker(team)
	var r := dice.d6()
	if r > 1:
		_score(team, 1)
		return ["Extra point is good."]
	var r2 := dice.d6()
	if r2 >= 7 - k.r("kck"):
		_score(team, 1)
		return ["Extra point wobbles... and sneaks in! (rolled 1, then %d)" % r2]
	return ["Extra point MISSED! (rolled 1, then %d, needed %d+)" % [r2, 7 - k.r("kck")]]


func _kickoff(receiving: int) -> Array[String]:
	possession = receiving
	_new_series(25.0, FIELD_W * 0.5)
	return ["Kickoff to %s, touchback at the 25." % teams[receiving].school]


func fg_distance() -> int:
	return int(round(100.0 - ball_on + 17.0))


func fg_target(team: int = -1) -> int:
	if team < 0:
		team = possession
	var k := _kicker(team)
	var d := fg_distance()
	var base := 2
	if d >= 55:
		base = 6
	elif d >= 50:
		base = 5
	elif d >= 40:
		base = 4
	elif d >= 30:
		base = 3
	var max_range := 45 + k.r("kck") * 3
	if d > max_range:
		return 7
	return base - (k.r("kck") - 3)


func run_field_goal() -> Array[String]:
	var off := possession
	var d := fg_distance()
	var target := fg_target()
	var lines: Array[String] = []
	var roll := dice.d6()
	var need := Dice.clamp_target(target)
	if target >= 7:
		roll = 0
	if roll >= need:
		_score(off, 3)
		lines.append("%d-yard FIELD GOAL is GOOD! (needed %d+, rolled %d)" % [d, need, roll])
		lines.append_array(_kickoff(1 - off))
	else:
		if target >= 7:
			lines.append("%d-yard field goal attempt is way short, out of the kicker's range." % d)
		else:
			lines.append("%d-yard field goal is NO GOOD (needed %d+, rolled %d)" % [d, need, roll])
		possession = 1 - off
		_new_series(maxf(20.0, 100.0 - (ball_on - 7.0)), FIELD_W * 0.5)
	stats[off]["plays"] += 1
	lines.append_array(_run_clock(8.0))
	return lines


func run_punt() -> Array[String]:
	var off := possession
	var k := _kicker(off)
	var a := dice.d6()
	var b := dice.d6()
	var dist := 34 + a + b + (k.r("kck") - 3) * 3
	var land := ball_on + dist
	var lines: Array[String] = []
	possession = 1 - off
	if land >= 100.0:
		lines.append("Punt of %d yards (34 + %d + %d, kicker adjusted) into the end zone. Touchback." % [dist, a, b])
		_new_series(20.0, FIELD_W * 0.5)
	else:
		var ret := maxi(0, dice.d6() + dice.d6() - 3)
		lines.append("Punt of %d yards, returned %d." % [dist, ret])
		_new_series(100.0 - land + ret, FIELD_W * 0.5)
	stats[off]["plays"] += 1
	lines.append_array(_run_clock(15.0))
	return lines


func _run_clock(seconds: float) -> Array[String]:
	var lines: Array[String] = []
	clock -= seconds
	if clock > 0.0:
		return lines
	if quarter == 2:
		lines.append("--- HALFTIME ---")
		quarter = 3
		clock = quarter_length
		rerolls = [teams[0].rerolls, teams[1].rerolls]
		lines.append_array(_kickoff(HOME))
	elif quarter >= 4:
		over = true
		clock = 0.0
		lines.append("--- FINAL ---")
	else:
		lines.append("--- End of Q%d ---" % quarter)
		quarter += 1
		clock = quarter_length
	return lines
