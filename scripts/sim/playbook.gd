class_name Playbook
extends Resource
## A team's playbook: offensive formations (each holding its plays), defensive formations
## (each holding its coverages), and the special teams kicks.
##
## Plays are data, not code. make_default() builds the stock playbook every team uses for
## now. make_offense() / make_defense() start the one-sided playbooks the user builds in the
## playbook editor (saved by PlaybookStore). Play names must be unique within a playbook,
## since calls are made by name.
##
## Formations come in "packages": a formation plus its stock plays. offense_packages() and
## defense_packages() list them; add a new formation there and it becomes available to
## every new playbook.

const SPECIAL_PUNT := "Punt"
const SPECIAL_FG := "Field Goal"

## What a playbook holds. COMBINED (the stock playbook) has both sides; the editor builds
## one-sided ones.
const COMBINED := ""
const OFFENSE := "offense"
const DEFENSE := "defense"

## Stock route tree, shared by every playbook. See Route for the point format.
const ROUTES := {
	"go": {"points": [Vector2(45, 0)], "end": "go"},
	"slant": {"points": [Vector2(2, 0), Vector2(7, -5)], "end": "go"},
	"post": {"points": [Vector2(11, 0), Vector2(26, -8)], "end": "go"},
	"corner": {"points": [Vector2(10, 0), Vector2(22, 7)], "end": "go"},
	"curl": {"points": [Vector2(12, 0), Vector2(10.5, -1)], "end": "stop"},
	"out": {"points": [Vector2(8, 0), Vector2(8, 6)], "end": "go"},
	"dig": {"points": [Vector2(11, 0), Vector2(11, -12)], "end": "go"},
	"hitch": {"points": [Vector2(6, 0), Vector2(5, 0)], "end": "stop"},
	"seam": {"points": [Vector2(30, 0)], "end": "go"},
	"flat": {"points": [Vector2(1, 4), Vector2(3, 9)], "end": "stop"},
	"swing": {"points": [Vector2(-1, 4), Vector2(1, 9)], "end": "stop"},
}

## Stock zones the editor offers a defender: name -> [depth, spot, radius, width, yards].
## See Zone for what each field means.
const ZONES := {
	"Deep Third Left": [Zone.Depth.DEEP, Zone.Spot.LEFT, 9.0, 0.66, 17.0],
	"Deep Third Right": [Zone.Depth.DEEP, Zone.Spot.RIGHT, 9.0, 0.66, 17.0],
	"Deep Middle": [Zone.Depth.DEEP, Zone.Spot.CENTER, 10.0, 0.0, 19.0],
	"Deep Half Left": [Zone.Depth.DEEP, Zone.Spot.LEFT, 11.0, 0.46, 17.0],
	"Deep Half Right": [Zone.Depth.DEEP, Zone.Spot.RIGHT, 11.0, 0.46, 17.0],
	"Hook Left": [Zone.Depth.INTERMEDIATE, Zone.Spot.LEFT, 5.0, 0.15, 7.0],
	"Hook Right": [Zone.Depth.INTERMEDIATE, Zone.Spot.RIGHT, 5.0, 0.15, 7.0],
	"Middle Hole": [Zone.Depth.INTERMEDIATE, Zone.Spot.CENTER, 5.0, 0.0, 10.0],
	"Curl Flat Left": [Zone.Depth.SHALLOW, Zone.Spot.LEFT, 6.0, 0.375, 6.0],
	"Curl Flat Right": [Zone.Depth.SHALLOW, Zone.Spot.RIGHT, 6.0, 0.375, 6.0],
	"Flat Left": [Zone.Depth.SHALLOW, Zone.Spot.LEFT, 6.0, 0.74, 5.0],
	"Flat Right": [Zone.Depth.SHALLOW, Zone.Spot.RIGHT, 6.0, 0.74, 5.0],
	"Short Middle": [Zone.Depth.SHALLOW, Zone.Spot.CENTER, 6.0, 0.0, 6.0],
}

@export var name := ""
@export var kind := COMBINED
@export var offensive_formations: Array[OffensiveFormation] = []
@export var defensive_formations: Array[DefensiveFormation] = []
@export var kicks: Array[KickPlay] = []


## A fresh copy of a stock route.
static func route(route_name: String) -> Route:
	var r: Dictionary = ROUTES[route_name]
	var pts: Array[Vector2] = []
	pts.assign(r["points"])
	return Route.make(route_name, pts, r["end"])


static func route_names() -> Array[String]:
	var out: Array[String] = []
	out.assign(ROUTES.keys())
	return out


## A fresh copy of a stock zone.
static func zone(zone_name: String) -> Zone:
	var z: Array = ZONES[zone_name]
	return Zone.make(zone_name, z[0], z[1], z[2], z[3], z[4])


static func zone_names() -> Array[String]:
	var out: Array[String] = []
	out.assign(ZONES.keys())
	return out


## Plays only hold a weak link back to their formation, and that link isn't saved. Call
## this after loading a playbook from disk.
func link_plays() -> void:
	for f in offensive_formations:
		for p in f.plays:
			p.formation = f
	for f in defensive_formations:
		for p in f.plays:
			p.formation = f


func has_play(play_name: String) -> bool:
	return offense_play(play_name) != null or defense_play(play_name) != null or is_kick(play_name)


# ---------------------------------------------------------------- lookups

func offense_plays() -> Array[OffensivePlay]:
	var out: Array[OffensivePlay] = []
	for f in offensive_formations:
		out.append_array(f.plays)
	return out


func defense_plays() -> Array[DefensivePlay]:
	var out: Array[DefensivePlay] = []
	for f in defensive_formations:
		out.append_array(f.plays)
	return out


func offense_names() -> Array[String]:
	var out: Array[String] = []
	for p in offense_plays():
		out.append(p.name)
	return out


func defense_names() -> Array[String]:
	var out: Array[String] = []
	for p in defense_plays():
		out.append(p.name)
	return out


func offense_play(play_name: String) -> OffensivePlay:
	for p in offense_plays():
		if p.name == play_name:
			return p
	return null


func defense_play(play_name: String) -> DefensivePlay:
	for p in defense_plays():
		if p.name == play_name:
			return p
	return null


func kick(play_name: String) -> KickPlay:
	for k in kicks:
		if k.name == play_name:
			return k
	return null


func is_kick(play_name: String) -> bool:
	return kick(play_name) != null


func is_run(play_name: String) -> bool:
	var p := offense_play(play_name)
	return p != null and p.is_run()


## Every rule problem in the playbook; empty when everything is legal.
func validate() -> Array[String]:
	var errs: Array[String] = []
	for f in offensive_formations:
		errs.append_array(f.validate())
	for f in defensive_formations:
		errs.append_array(f.validate())
	var seen := {}
	for n in offense_names() + defense_names():
		if seen.has(n):
			errs.append("Two plays are named %s" % n)
		seen[n] = true
	if kind != DEFENSE and (not is_kick(SPECIAL_PUNT) or not is_kick(SPECIAL_FG)):
		errs.append("%s needs a Punt and a Field Goal" % name)
	return errs


# ---------------------------------------------------------------- stock playbook

static func make_default() -> Playbook:
	var pb := Playbook.new()
	pb.name = "Standard"
	pb.offensive_formations.assign(offense_packages())
	pb.defensive_formations.assign(defense_packages())
	pb.kicks.assign(_stock_kicks())
	return pb


## A new offensive playbook: every stock offensive package, plus the kicks.
static func make_offense(playbook_name: String) -> Playbook:
	var pb := Playbook.new()
	pb.name = playbook_name
	pb.kind = OFFENSE
	pb.offensive_formations.assign(offense_packages())
	pb.kicks.assign(_stock_kicks())
	return pb


## A new defensive playbook: every stock defensive package.
static func make_defense(playbook_name: String) -> Playbook:
	var pb := Playbook.new()
	pb.name = playbook_name
	pb.kind = DEFENSE
	pb.defensive_formations.assign(defense_packages())
	return pb


## Fresh copies of every stock offensive formation, each with its plays.
static func offense_packages() -> Array[OffensiveFormation]:
	return [_pistol()]


## Fresh copies of every stock defensive formation, each with its calls.
static func defense_packages() -> Array[DefensiveFormation]:
	return [_base_43(), _box_43()]


static func _stock_kicks() -> Array[KickPlay]:
	return [
		KickPlay.make(SPECIAL_PUNT, KickPlay.PUNT,
			"Kick it away. Distance = 34 + 2d6 yards, adjusted by your kicker's Kicking rating."),
		KickPlay.make(SPECIAL_FG, KickPlay.FIELD_GOAL,
			"Needs the shown number or better on a d6. Longer kicks are harder; a better kicker lowers the target."),
	]


## QB four yards behind the center with the RB behind him; WR1 and the slot (WR3) to the
## left, the TE and WR2 to the right.
static func _pistol() -> OffensiveFormation:
	var spots: Array[FormationSpot] = [
		FormationSpot.make("C", "OL", Vector2(-0.6, 0.0)),
		FormationSpot.make("LG", "OL", Vector2(-0.7, -1.4)),
		FormationSpot.make("RG", "OL", Vector2(-0.7, 1.4)),
		FormationSpot.make("LT", "OL", Vector2(-0.9, -2.8)),
		FormationSpot.make("RT", "OL", Vector2(-0.9, 2.8)),
		FormationSpot.make("TE", "TE", Vector2(-0.9, 4.3)),
		FormationSpot.make("QB", "QB", Vector2(-4.0, 0.0)),
		FormationSpot.make("RB", "RB", Vector2(-6.5, 0.0)),
		FormationSpot.make("WR1", "WR", Vector2(-0.8, -13.0)),
		FormationSpot.make("WR3", "WR", Vector2(-1.5, -6.0)),
		FormationSpot.make("WR2", "WR", Vector2(-1.5, 15.0)),
	]
	var f := OffensiveFormation.make("Pistol", spots)
	f.add_play(RunPlay.make("Inside Run",
		"Handoff between the tackles. Linemen block the man in front of them; the center climbs to the middle linebacker.",
		RunPlay.INSIDE))
	f.add_play(RunPlay.make("Outside Run",
		"Toss to the edge. Needs a fast back and receivers who can block corners.",
		RunPlay.OUTSIDE))
	f.add_play(PassPlay.make("Quick Slants",
		"3-step drop, quick throw. Beats the blitz; weak against tight man coverage.",
		5.5, 0.75, false,
		{"WR1": route("slant"), "WR2": route("slant"), "WR3": route("slant"), "TE": route("flat")},
		["RB"], ["WR3", "WR1", "WR2", "TE"]))
	f.add_play(PassPlay.make("Curl Flat",
		"Intermediate timing throws that sit down in holes in zone coverage.",
		7.0, 1.3, false,
		{"WR1": route("curl"), "WR2": route("curl"), "WR3": route("out"), "TE": route("seam"), "RB": route("swing")},
		[], ["WR1", "WR3", "WR2", "RB"]))
	f.add_play(PassPlay.make("Four Verticals",
		"Everyone goes deep. Big plays if the line holds and the receivers are fast.",
		8.0, 1.9, false,
		{"WR1": route("go"), "WR2": route("go"), "WR3": route("seam"), "TE": route("seam")},
		["RB"], ["WR3", "TE", "WR2", "WR1"]))
	f.add_play(PassPlay.make("PA Deep Shot",
		"Fake handoff, then throw deep. Linebackers with low Awareness bite on the fake.",
		8.0, 2.2, true,
		{"WR1": route("post"), "WR2": route("corner"), "WR3": route("dig"), "TE": route("flat")},
		["RB"], ["WR1", "WR2", "WR3", "TE"]))
	f.add_play(PassPlay.make("Dig Cross",
		"Crossing routes that punish man coverage with speed and route running.",
		7.0, 1.5, false,
		{"WR1": route("dig"), "WR2": route("post"), "WR3": route("hitch"), "TE": route("out"), "RB": route("swing")},
		[], ["WR1", "WR3", "TE", "RB"]))
	return f


## Four down linemen and three linebackers. The front seven line up off the ball; the corners
## and strong safety line up over receivers.
static func _front_seven() -> Array[FormationSpot]:
	var spots: Array[FormationSpot] = [
		FormationSpot.make("DE1", "DL", Vector2(1.0, -4.0)),
		FormationSpot.make("DT1", "DL", Vector2(1.0, -1.0)),
		FormationSpot.make("DT2", "DL", Vector2(1.0, 1.2)),
		FormationSpot.make("DE2", "DL", Vector2(1.0, 3.7)),
		FormationSpot.make("WILL", "LB", Vector2(5.0, -4.0)),
		FormationSpot.make("MIKE", "LB", Vector2(5.0, 0.0)),
		FormationSpot.make("SAM", "LB", Vector2(4.5, 4.5)),
		FormationSpot.make("CB1", "CB", Vector2(6.0, 0.0), "left_1"),
		FormationSpot.make("CB2", "CB", Vector2(6.0, 0.0), "right_1"),
	]
	return spots


static func _base_43() -> DefensiveFormation:
	var spots := _front_seven()
	spots.append(FormationSpot.make("SS", "S", Vector2(8.0, 1.0), "left_2"))
	spots.append(FormationSpot.make("FS", "S", Vector2(13.0, 0.0)))
	var f := DefensiveFormation.make("4-3", spots)
	var L := Zone.Spot.LEFT
	var R := Zone.Spot.RIGHT
	var C := Zone.Spot.CENTER
	var SH := Zone.Depth.SHALLOW
	var MID := Zone.Depth.INTERMEDIATE
	var DP := Zone.Depth.DEEP
	f.add_play(DefensivePlay.make("Cover 3",
		"Three deep, four underneath. Solid against everything, rarely great.", [
			CoverageAssignment.in_zone("CB1", Zone.make("Deep Third Left", DP, L, 9, 0.66, 17)),
			CoverageAssignment.in_zone("CB2", Zone.make("Deep Third Right", DP, R, 9, 0.66, 17)),
			CoverageAssignment.in_zone("FS", Zone.make("Deep Middle", DP, C, 10, 0.0, 19)),
			CoverageAssignment.in_zone("SS", Zone.make("Curl Flat Left", SH, L, 6, 0.375, 6)),
			CoverageAssignment.in_zone("WILL", Zone.make("Hook Left", MID, L, 5, 0.15, 7)),
			CoverageAssignment.in_zone("MIKE", Zone.make("Hook Right", MID, R, 5, 0.11, 7)),
			CoverageAssignment.in_zone("SAM", Zone.make("Curl Flat Right", SH, R, 6, 0.375, 6)),
		]))
	f.add_play(DefensivePlay.make("Cover 2",
		"Corners squat in the flats, two safeties split the deep field. Weak deep down the middle.", [
			CoverageAssignment.in_zone("CB1", Zone.make("Flat Left", SH, L, 6, 0.74, 5)),
			CoverageAssignment.in_zone("CB2", Zone.make("Flat Right", SH, R, 6, 0.74, 5)),
			CoverageAssignment.in_zone("SS", Zone.make("Deep Half Left", DP, L, 11, 0.46, 17)),
			CoverageAssignment.in_zone("FS", Zone.make("Deep Half Right", DP, R, 11, 0.46, 17)),
			CoverageAssignment.in_zone("WILL", Zone.make("Hook Left", MID, L, 5, 0.225, 8)),
			CoverageAssignment.in_zone("MIKE", Zone.make("Middle Hole", MID, C, 5, 0.0, 10)),
			CoverageAssignment.in_zone("SAM", Zone.make("Hook Right", MID, R, 5, 0.225, 8)),
		]))
	# Man defenders are listed in the order they pick up receivers: each takes the closest
	# receiver nobody has yet.
	f.add_play(DefensivePlay.make("Cover 1 Man",
		"Man coverage on every receiver with one deep safety. Your DBs need speed and Awareness.", [
			CoverageAssignment.man("CB1"),
			CoverageAssignment.man("CB2"),
			CoverageAssignment.man("SS"),
			CoverageAssignment.man("SAM"),
			CoverageAssignment.man("WILL"),
			CoverageAssignment.in_zone("MIKE", Zone.make("Short Middle", SH, C, 6, 0.0, 6)),
			CoverageAssignment.in_zone("FS", Zone.make("Deep Middle", DP, C, 14, 0.0, 17)),
		]))
	f.add_play(DefensivePlay.make("Blitz",
		"Six rushers and man coverage with no safety help. High risk, high reward.", [
			CoverageAssignment.man("CB1"),
			CoverageAssignment.man("CB2"),
			CoverageAssignment.man("SS"),
			CoverageAssignment.man("FS"),
			CoverageAssignment.man("SAM"),
			CoverageAssignment.blitz("WILL"),
			CoverageAssignment.blitz("MIKE"),
		]))
	return f


## Same front with the strong safety walked down into the box as an eighth run defender.
static func _box_43() -> DefensiveFormation:
	var spots := _front_seven()
	spots.append(FormationSpot.make("SS", "S", Vector2(5.5, -6.5)))
	spots.append(FormationSpot.make("FS", "S", Vector2(13.0, 0.0)))
	var f := DefensiveFormation.make("4-3 Box", spots)
	var L := Zone.Spot.LEFT
	var R := Zone.Spot.RIGHT
	var C := Zone.Spot.CENTER
	var SH := Zone.Depth.SHALLOW
	var DP := Zone.Depth.DEEP
	f.add_play(DefensivePlay.make("Run Stuff",
		"Strong safety creeps down and linebackers attack the line on the snap. Vulnerable to play action.", [
			CoverageAssignment.in_zone("CB1", Zone.make("Deep Third Left", DP, L, 9, 0.66, 15)),
			CoverageAssignment.in_zone("CB2", Zone.make("Deep Third Right", DP, R, 9, 0.66, 15)),
			CoverageAssignment.in_zone("FS", Zone.make("Deep Middle", DP, C, 11, 0.0, 16)),
			CoverageAssignment.in_zone("SS", Zone.make("Box Left", SH, L, 5, 0.225, 5)),
			CoverageAssignment.in_zone("WILL", Zone.make("Hook Left", SH, L, 5, 0.15, 5)),
			CoverageAssignment.in_zone("MIKE", Zone.make("Hook Right", SH, R, 5, 0.075, 5)),
			CoverageAssignment.in_zone("SAM", Zone.make("Curl Flat Right", SH, R, 5, 0.2625, 5)),
		], true))
	return f
