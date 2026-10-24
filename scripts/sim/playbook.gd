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
## Routes the user drew for this playbook, on top of the stock ROUTES. Plays keep their
## own copy of a route; refresh_route() pushes an edit out to them.
@export var custom_routes: Array[Route] = []


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


## Every route this playbook can call: the stock tree, then its own.
func all_route_names() -> Array[String]:
	var out := route_names()
	for r in custom_routes:
		out.append(r.name)
	return out


func custom_route(route_name: String) -> Route:
	for r in custom_routes:
		if r.name == route_name:
			return r
	return null


func is_custom_route(route_name: String) -> bool:
	return custom_route(route_name) != null


## A fresh copy of any route this playbook knows, stock or its own; null if none.
func make_route(route_name: String) -> Route:
	if ROUTES.has(route_name):
		return route(route_name)
	var r := custom_route(route_name)
	return r.duplicate(true) as Route if r != null else null


## Adds a route of the playbook's own, starting as a copy of `base` (or a straight
## 10-yard stem) under a new name.
func add_custom_route(route_name: String, base: Route = null) -> Route:
	var r: Route
	if base != null:
		r = base.duplicate(true)
		r.name = route_name
	else:
		var pts: Array[Vector2] = [Vector2(10, 0)]
		r = Route.make(route_name, pts, Route.STOP)
	custom_routes.append(r)
	return r


## Renames one of the playbook's routes, in every play that runs it too.
func rename_route(old_name: String, new_name: String) -> void:
	var r := custom_route(old_name)
	if r == null:
		return
	r.name = new_name
	for p in offense_plays():
		if p is PassPlay:
			for slot in p.routes:
				if p.routes[slot].name == old_name:
					p.routes[slot].name = new_name


## Gives every play running this route a fresh copy of it, after its points changed.
func refresh_route(route_name: String) -> void:
	for p in offense_plays():
		if p is PassPlay:
			for slot in p.routes.keys():
				if p.routes[slot].name == route_name:
					p.routes[slot] = make_route(route_name)


## Removes one of the playbook's routes. Plays already running it keep their copy.
func remove_custom_route(route_name: String) -> void:
	var r := custom_route(route_name)
	if r != null:
		custom_routes.erase(r)


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


## Whether a team can run its offense (or defense) from this playbook in a game: it covers
## that side, has at least one play there, and passes validate().
static func usable_as(pb: Playbook, side: String) -> bool:
	if pb == null:
		return false
	if pb.kind != COMBINED and pb.kind != side:
		return false
	var plays: int = pb.offense_plays().size() if side == OFFENSE else pb.defense_plays().size()
	return plays > 0 and pb.validate().is_empty()


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


## The play the field lines up in while a call is being picked: this one if the playbook
## has it, otherwise the playbook's first.
func offense_play_or_first(play_name: String) -> OffensivePlay:
	var p := offense_play(play_name)
	if p == null and not offense_plays().is_empty():
		p = offense_plays()[0]
	return p


func defense_play_or_first(play_name: String) -> DefensivePlay:
	var p := defense_play(play_name)
	if p == null and not defense_plays().is_empty():
		p = defense_plays()[0]
	return p


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
	return [_pistol(), _shotgun(), _i_formation(), _singleback(), _empty()]


## Fresh copies of every stock defensive formation, each with its calls.
static func defense_packages() -> Array[DefensiveFormation]:
	return [_base_43(), _box_43(), _nickel(), _dime(), _forty_six(), _goal_line(), _base_34()]


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


## The five offensive linemen, lined up the same way in every formation.
static func _offensive_line() -> Array[FormationSpot]:
	var spots: Array[FormationSpot] = [
		FormationSpot.make("C", "OL", Vector2(-0.6, 0.0)),
		FormationSpot.make("LG", "OL", Vector2(-0.7, -1.4)),
		FormationSpot.make("RG", "OL", Vector2(-0.7, 1.4)),
		FormationSpot.make("LT", "OL", Vector2(-0.9, -2.8)),
		FormationSpot.make("RT", "OL", Vector2(-0.9, 2.8)),
	]
	return spots


## QB five yards behind the center, RB beside him, three receivers and a tight end.
static func _shotgun() -> OffensiveFormation:
	var spots := _offensive_line()
	spots.append_array([
		FormationSpot.make("TE", "TE", Vector2(-0.9, 4.3)),
		FormationSpot.make("QB", "QB", Vector2(-5.0, 0.0)),
		FormationSpot.make("RB", "RB", Vector2(-5.0, -2.2)),
		FormationSpot.make("WR1", "WR", Vector2(-0.8, -13.0)),
		FormationSpot.make("WR3", "WR", Vector2(-1.5, -6.0)),
		FormationSpot.make("WR2", "WR", Vector2(-0.8, 15.0)),
	])
	var f := OffensiveFormation.make("Shotgun", spots)
	f.add_play(RunPlay.make("Shotgun Draw",
		"QB waits a beat, then hands off up the middle. The pass-happy look can catch a defense backing off.",
		RunPlay.INSIDE))
	f.add_play(RunPlay.make("Shotgun Sweep",
		"Quick handoff to the edge out of the spread. Needs a fast back and receivers who can block corners.",
		RunPlay.OUTSIDE))
	f.add_play(PassPlay.make("Spread Slants",
		"Quick 3-step throw to three crossing receivers. Gets the ball out before the rush arrives.",
		4.5, 0.7, false,
		{"WR1": route("slant"), "WR2": route("slant"), "WR3": route("slant"), "TE": route("flat")},
		["RB"], ["WR3", "WR1", "WR2", "TE"]))
	f.add_play(PassPlay.make("Spread Curls",
		"Receivers sit down in the holes of a zone while the back swings out as a safety valve.",
		5.0, 1.2, false,
		{"WR1": route("curl"), "WR2": route("curl"), "WR3": route("out"), "TE": route("seam"), "RB": route("swing")},
		[], ["WR1", "WR2", "WR3", "RB"]))
	f.add_play(PassPlay.make("Shotgun Bombs",
		"Everyone goes deep. Extra time in the pocket, but the line has to hold.",
		5.5, 1.8, false,
		{"WR1": route("go"), "WR2": route("go"), "WR3": route("seam"), "TE": route("seam")},
		["RB"], ["WR1", "WR2", "WR3", "TE"]))
	f.add_play(PassPlay.make("Shotgun PA Post",
		"Fake the handoff from the gun, then throw the post. Linebackers with low Awareness bite.",
		5.5, 2.0, true,
		{"WR1": route("post"), "WR2": route("corner"), "WR3": route("dig"), "TE": route("flat")},
		["RB"], ["WR1", "WR2", "WR3", "TE"]))
	return f


## QB under center with a fullback and tailback in a line behind him: power football.
static func _i_formation() -> OffensiveFormation:
	var spots := _offensive_line()
	spots.append_array([
		FormationSpot.make("TE", "TE", Vector2(-0.9, 4.3)),
		FormationSpot.make("QB", "QB", Vector2(-1.6, 0.0)),
		FormationSpot.make("FB", "RB", Vector2(-4.0, 0.0)),
		FormationSpot.make("RB", "RB", Vector2(-6.5, 0.0)),
		FormationSpot.make("WR1", "WR", Vector2(-0.8, -13.0)),
		FormationSpot.make("WR2", "WR", Vector2(-1.5, 15.0)),
	])
	var f := OffensiveFormation.make("I-Formation", spots)
	f.add_play(RunPlay.make("I Power",
		"Fullback leads the tailback through the hole between the tackles.",
		RunPlay.INSIDE))
	f.add_play(RunPlay.make("I Toss",
		"Pitch to the tailback running to the edge, with the fullback out in front.",
		RunPlay.OUTSIDE))
	f.add_play(PassPlay.make("I PA Boot",
		"Fake the handoff to the tailback, then throw. Linebackers with low Awareness bite on the fake.",
		6.0, 1.7, true,
		{"WR1": route("post"), "WR2": route("corner"), "TE": route("flat"), "FB": route("flat")},
		["RB"], ["WR1", "WR2", "TE", "FB"]))
	f.add_play(PassPlay.make("I Hitches",
		"Three-step throw to receivers who stop short of the sticks. Safe and short.",
		4.5, 0.8, false,
		{"WR1": route("hitch"), "WR2": route("hitch"), "TE": route("curl"), "FB": route("flat")},
		["RB"], ["WR1", "WR2", "TE", "FB"]))
	return f


## One back behind the QB under center, two tight ends and two receivers: balanced.
static func _singleback() -> OffensiveFormation:
	var spots := _offensive_line()
	spots.append_array([
		FormationSpot.make("TE", "TE", Vector2(-0.9, 4.3)),
		FormationSpot.make("TE2", "TE", Vector2(-0.9, -4.3)),
		FormationSpot.make("QB", "QB", Vector2(-1.6, 0.0)),
		FormationSpot.make("RB", "RB", Vector2(-5.5, 0.0)),
		FormationSpot.make("WR1", "WR", Vector2(-0.8, -13.0)),
		FormationSpot.make("WR2", "WR", Vector2(-0.8, 15.0)),
	])
	var f := OffensiveFormation.make("Singleback", spots)
	f.add_play(RunPlay.make("Ace Zone",
		"Handoff up the middle behind two tight ends who help the line.",
		RunPlay.INSIDE))
	f.add_play(RunPlay.make("Ace Stretch",
		"Back takes the ball to the edge. Tight ends seal the outside.",
		RunPlay.OUTSIDE))
	f.add_play(PassPlay.make("Ace Curl Flat",
		"Receivers curl in front of the safeties while the tight ends work the flats.",
		6.0, 1.3, false,
		{"WR1": route("curl"), "WR2": route("curl"), "TE": route("flat"), "TE2": route("flat")},
		["RB"], ["WR1", "WR2", "TE", "TE2"]))
	f.add_play(PassPlay.make("Ace Deep Cross",
		"Receivers run deep, tight ends cut across the middle. Needs time in the pocket.",
		7.0, 1.6, false,
		{"WR1": route("post"), "WR2": route("corner"), "TE": route("dig"), "TE2": route("out"), "RB": route("swing")},
		[], ["WR1", "WR2", "TE", "TE2"]))
	f.add_play(PassPlay.make("Ace PA Seam",
		"Fake the run with both tight ends in the game, then throw over the top.",
		7.0, 2.0, true,
		{"WR1": route("go"), "WR2": route("post"), "TE": route("seam"), "TE2": route("flat")},
		["RB"], ["WR1", "WR2", "TE", "TE2"]))
	return f


## Five receivers and no back: maximum spread, nobody to help block.
static func _empty() -> OffensiveFormation:
	var spots := _offensive_line()
	spots.append_array([
		FormationSpot.make("TE", "TE", Vector2(-0.9, 4.3)),
		FormationSpot.make("QB", "QB", Vector2(-5.0, 0.0)),
		FormationSpot.make("WR1", "WR", Vector2(-0.8, -13.0)),
		FormationSpot.make("WR3", "WR", Vector2(-1.5, -6.0)),
		FormationSpot.make("WR2", "WR", Vector2(-0.8, 15.0)),
		FormationSpot.make("WR4", "WR", Vector2(-1.5, 9.0)),
	])
	var f := OffensiveFormation.make("Empty", spots)
	f.add_play(PassPlay.make("Empty Quick Game",
		"Quick throws to five eligible receivers. Gets the ball out fast since nobody is in to block.",
		4.0, 0.6, false,
		{"WR1": route("slant"), "WR2": route("slant"), "WR3": route("hitch"), "WR4": route("hitch"), "TE": route("flat")},
		[], ["WR3", "WR1", "WR4", "WR2", "TE"]))
	f.add_play(PassPlay.make("Empty Curl Flat",
		"Receivers sit down in the zone holes with the tight end working the flat.",
		5.5, 1.2, false,
		{"WR1": route("curl"), "WR2": route("curl"), "WR3": route("out"), "WR4": route("out"), "TE": route("flat")},
		[], ["WR1", "WR2", "WR3", "WR4", "TE"]))
	f.add_play(PassPlay.make("Empty Verticals",
		"Everyone runs deep. Big plays if the QB has time; he is exposed with no back to block.",
		6.0, 1.8, false,
		{"WR1": route("go"), "WR2": route("go"), "WR3": route("seam"), "WR4": route("seam"), "TE": route("post")},
		[], ["WR1", "WR2", "WR3", "WR4", "TE"]))
	f.add_play(PassPlay.make("Empty Dig Cross",
		"Crossing routes across the middle against a defense with nowhere to hide its coverage.",
		5.5, 1.4, false,
		{"WR1": route("dig"), "WR2": route("post"), "WR3": route("dig"), "WR4": route("corner"), "TE": route("out")},
		[], ["WR1", "WR3", "WR2", "WR4", "TE"]))
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


## Shorthands for the zones the extra formations' calls use.
static func _z(zone_name: String, depth: int, spot: int, radius: float, width: float, yards: float) -> Zone:
	return Zone.make(zone_name, depth, spot, radius, width, yards)


## Four linemen, two linebackers and three corners: five defensive backs against three-receiver sets.
static func _nickel() -> DefensiveFormation:
	var spots: Array[FormationSpot] = [
		FormationSpot.make("DE1", "DL", Vector2(1.0, -4.0)),
		FormationSpot.make("DT1", "DL", Vector2(1.0, -1.0)),
		FormationSpot.make("DT2", "DL", Vector2(1.0, 1.2)),
		FormationSpot.make("DE2", "DL", Vector2(1.0, 3.7)),
		FormationSpot.make("WILL", "LB", Vector2(5.0, -2.5)),
		FormationSpot.make("MIKE", "LB", Vector2(5.0, 2.5)),
		FormationSpot.make("CB1", "CB", Vector2(6.0, 0.0), "left_1"),
		FormationSpot.make("CB2", "CB", Vector2(6.0, 0.0), "right_1"),
		FormationSpot.make("CB3", "CB", Vector2(5.0, 0.0), "left_2"),
		FormationSpot.make("SS", "S", Vector2(8.0, 4.0)),
		FormationSpot.make("FS", "S", Vector2(13.0, 0.0)),
	]
	var f := DefensiveFormation.make("Nickel 4-2-5", spots)
	var L := Zone.Spot.LEFT
	var R := Zone.Spot.RIGHT
	var C := Zone.Spot.CENTER
	var SH := Zone.Depth.SHALLOW
	var MID := Zone.Depth.INTERMEDIATE
	var DP := Zone.Depth.DEEP
	f.add_play(DefensivePlay.make("Nickel Cover 3",
		"Three deep with the nickelback in the flat. Extra coverage with one fewer linebacker.", [
			CoverageAssignment.in_zone("CB1", _z("Deep Third Left", DP, L, 9, 0.66, 17)),
			CoverageAssignment.in_zone("CB2", _z("Deep Third Right", DP, R, 9, 0.66, 17)),
			CoverageAssignment.in_zone("FS", _z("Deep Middle", DP, C, 10, 0.0, 19)),
			CoverageAssignment.in_zone("CB3", _z("Curl Flat Left", SH, L, 6, 0.375, 6)),
			CoverageAssignment.in_zone("SS", _z("Curl Flat Right", SH, R, 6, 0.375, 6)),
			CoverageAssignment.in_zone("WILL", _z("Hook Left", MID, L, 5, 0.15, 7)),
			CoverageAssignment.in_zone("MIKE", _z("Hook Right", MID, R, 5, 0.11, 7)),
		]))
	f.add_play(DefensivePlay.make("Nickel Man",
		"Man coverage on every receiver, one deep safety. Three corners match up with three receivers.", [
			CoverageAssignment.man("CB1"),
			CoverageAssignment.man("CB2"),
			CoverageAssignment.man("CB3"),
			CoverageAssignment.man("SS"),
			CoverageAssignment.man("WILL"),
			CoverageAssignment.in_zone("MIKE", _z("Short Middle", SH, C, 6, 0.0, 6)),
			CoverageAssignment.in_zone("FS", _z("Deep Middle", DP, C, 14, 0.0, 17)),
		]))
	f.add_play(DefensivePlay.make("Nickel Blitz",
		"Both linebackers and the nickelback rush against man coverage. No safety help for the corners.", [
			CoverageAssignment.man("CB1"),
			CoverageAssignment.man("CB2"),
			CoverageAssignment.man("SS"),
			CoverageAssignment.man("FS"),
			CoverageAssignment.blitz("CB3"),
			CoverageAssignment.blitz("WILL"),
			CoverageAssignment.blitz("MIKE"),
		]))
	return f


## Four linemen, one linebacker and four corners: six defensive backs for obvious passing downs.
static func _dime() -> DefensiveFormation:
	var spots: Array[FormationSpot] = [
		FormationSpot.make("DE1", "DL", Vector2(1.0, -4.0)),
		FormationSpot.make("DT1", "DL", Vector2(1.0, -1.0)),
		FormationSpot.make("DT2", "DL", Vector2(1.0, 1.2)),
		FormationSpot.make("DE2", "DL", Vector2(1.0, 3.7)),
		FormationSpot.make("MIKE", "LB", Vector2(5.0, 0.0)),
		FormationSpot.make("CB1", "CB", Vector2(6.0, 0.0), "left_1"),
		FormationSpot.make("CB2", "CB", Vector2(6.0, 0.0), "right_1"),
		FormationSpot.make("CB3", "CB", Vector2(5.0, 0.0), "left_2"),
		FormationSpot.make("CB4", "CB", Vector2(5.0, 0.0), "right_2"),
		FormationSpot.make("SS", "S", Vector2(8.0, 3.0)),
		FormationSpot.make("FS", "S", Vector2(13.0, 0.0)),
	]
	var f := DefensiveFormation.make("Dime 4-1-6", spots)
	var L := Zone.Spot.LEFT
	var R := Zone.Spot.RIGHT
	var C := Zone.Spot.CENTER
	var SH := Zone.Depth.SHALLOW
	var MID := Zone.Depth.INTERMEDIATE
	var DP := Zone.Depth.DEEP
	f.add_play(DefensivePlay.make("Dime Quarters",
		"Four deep defenders with the extra backs underneath. Hard to throw deep; the run is wide open.", [
			CoverageAssignment.in_zone("CB1", _z("Deep Third Left", DP, L, 9, 0.66, 17)),
			CoverageAssignment.in_zone("CB2", _z("Deep Third Right", DP, R, 9, 0.66, 17)),
			CoverageAssignment.in_zone("SS", _z("Deep Half Right", DP, R, 11, 0.46, 17)),
			CoverageAssignment.in_zone("FS", _z("Deep Half Left", DP, L, 11, 0.46, 17)),
			CoverageAssignment.in_zone("CB3", _z("Flat Left", SH, L, 6, 0.74, 5)),
			CoverageAssignment.in_zone("CB4", _z("Flat Right", SH, R, 6, 0.74, 5)),
			CoverageAssignment.in_zone("MIKE", _z("Middle Hole", MID, C, 5, 0.0, 10)),
		]))
	f.add_play(DefensivePlay.make("Dime Man",
		"Man coverage everywhere with one deep safety. Needs fast, aware defensive backs.", [
			CoverageAssignment.man("CB1"),
			CoverageAssignment.man("CB2"),
			CoverageAssignment.man("CB3"),
			CoverageAssignment.man("CB4"),
			CoverageAssignment.man("SS"),
			CoverageAssignment.in_zone("MIKE", _z("Short Middle", SH, C, 6, 0.0, 6)),
			CoverageAssignment.in_zone("FS", _z("Deep Middle", DP, C, 14, 0.0, 17)),
		]))
	return f


## Four linemen with the safeties and a linebacker on the line: six or seven players near the ball.
static func _forty_six() -> DefensiveFormation:
	var spots: Array[FormationSpot] = [
		FormationSpot.make("DE1", "DL", Vector2(1.0, -4.0)),
		FormationSpot.make("DT1", "DL", Vector2(1.0, -1.0)),
		FormationSpot.make("DT2", "DL", Vector2(1.0, 1.2)),
		FormationSpot.make("DE2", "DL", Vector2(1.0, 3.7)),
		FormationSpot.make("WILL", "LB", Vector2(1.5, -2.5)),
		FormationSpot.make("SS", "S", Vector2(1.5, 2.5)),
		FormationSpot.make("MIKE", "LB", Vector2(4.5, 0.0)),
		FormationSpot.make("SAM", "LB", Vector2(4.5, 5.0)),
		FormationSpot.make("CB1", "CB", Vector2(6.0, 0.0), "left_1"),
		FormationSpot.make("CB2", "CB", Vector2(6.0, 0.0), "right_1"),
		FormationSpot.make("FS", "S", Vector2(13.0, 0.0)),
	]
	var f := DefensiveFormation.make("46", spots)
	var L := Zone.Spot.LEFT
	var R := Zone.Spot.RIGHT
	var C := Zone.Spot.CENTER
	var SH := Zone.Depth.SHALLOW
	var DP := Zone.Depth.DEEP
	f.add_play(DefensivePlay.make("46 Blitz",
		"Five rushers off the line with man coverage behind. Immediate pressure up the middle; thin in the secondary.", [
			CoverageAssignment.man("CB1"),
			CoverageAssignment.man("CB2"),
			CoverageAssignment.man("SAM"),
			CoverageAssignment.in_zone("FS", _z("Deep Middle", DP, C, 14, 0.0, 17)),
			CoverageAssignment.blitz("WILL"),
			CoverageAssignment.blitz("SS"),
			CoverageAssignment.blitz("MIKE"),
		]))
	f.add_play(DefensivePlay.make("46 Run Stuff",
		"Eight in the box attack the line on the snap. Vulnerable to play action.", [
			CoverageAssignment.in_zone("CB1", _z("Deep Third Left", DP, L, 9, 0.66, 15)),
			CoverageAssignment.in_zone("CB2", _z("Deep Third Right", DP, R, 9, 0.66, 15)),
			CoverageAssignment.in_zone("FS", _z("Deep Middle", DP, C, 11, 0.0, 16)),
			CoverageAssignment.in_zone("SS", _z("Box Right", SH, R, 5, 0.225, 5)),
			CoverageAssignment.in_zone("WILL", _z("Box Left", SH, L, 5, 0.15, 5)),
			CoverageAssignment.in_zone("MIKE", _z("Hook Left", SH, C, 5, 0.075, 5)),
			CoverageAssignment.in_zone("SAM", _z("Curl Flat Right", SH, R, 5, 0.2625, 5)),
		], true))
	return f


## Five linemen and four linebackers with only two corners: stops short-yardage runs at the goal line.
static func _goal_line() -> DefensiveFormation:
	var spots: Array[FormationSpot] = [
		FormationSpot.make("DE1", "DL", Vector2(1.0, -4.5)),
		FormationSpot.make("DT1", "DL", Vector2(1.0, -2.3)),
		FormationSpot.make("NT", "DL", Vector2(1.0, 0.0)),
		FormationSpot.make("DT2", "DL", Vector2(1.0, 2.3)),
		FormationSpot.make("DE2", "DL", Vector2(1.0, 4.5)),
		FormationSpot.make("WILL", "LB", Vector2(3.0, -3.0)),
		FormationSpot.make("MIKE", "LB", Vector2(3.0, -1.0)),
		FormationSpot.make("SAM", "LB", Vector2(3.0, 1.0)),
		FormationSpot.make("JACK", "LB", Vector2(3.0, 3.0)),
		FormationSpot.make("CB1", "CB", Vector2(4.0, 0.0), "left_1"),
		FormationSpot.make("CB2", "CB", Vector2(4.0, 0.0), "right_1"),
	]
	var f := DefensiveFormation.make("Goal Line 5-4-2", spots)
	var L := Zone.Spot.LEFT
	var R := Zone.Spot.RIGHT
	var SH := Zone.Depth.SHALLOW
	f.add_play(DefensivePlay.make("Goal Line Stand",
		"Everyone attacks the line on the snap. Nearly unbeatable on the ground; any pass is wide open.", [
			CoverageAssignment.in_zone("CB1", _z("Flat Left", SH, L, 5, 0.74, 5)),
			CoverageAssignment.in_zone("CB2", _z("Flat Right", SH, R, 5, 0.74, 5)),
			CoverageAssignment.in_zone("WILL", _z("Box Left", SH, L, 4, 0.15, 4)),
			CoverageAssignment.in_zone("MIKE", _z("Box Left Middle", SH, L, 4, 0.075, 4)),
			CoverageAssignment.in_zone("SAM", _z("Box Right Middle", SH, R, 4, 0.075, 4)),
			CoverageAssignment.in_zone("JACK", _z("Box Right", SH, R, 4, 0.15, 4)),
		], true))
	f.add_play(DefensivePlay.make("Goal Line Man",
		"Heavy front with the corners and linebackers locked on receivers. Guards against the quick pass.", [
			CoverageAssignment.man("CB1"),
			CoverageAssignment.man("CB2"),
			CoverageAssignment.man("SAM"),
			CoverageAssignment.man("JACK"),
			CoverageAssignment.blitz("WILL"),
			CoverageAssignment.blitz("MIKE"),
		]))
	return f


## Three linemen and four linebackers: the outside linebackers rush or drop, so the front can disguise a blitz.
static func _base_34() -> DefensiveFormation:
	var spots: Array[FormationSpot] = [
		FormationSpot.make("DE1", "DL", Vector2(1.0, -3.0)),
		FormationSpot.make("NT", "DL", Vector2(1.0, 0.0)),
		FormationSpot.make("DE2", "DL", Vector2(1.0, 3.0)),
		FormationSpot.make("OLB1", "LB", Vector2(3.0, -5.0)),
		FormationSpot.make("ILB1", "LB", Vector2(5.0, -1.8)),
		FormationSpot.make("ILB2", "LB", Vector2(5.0, 1.8)),
		FormationSpot.make("OLB2", "LB", Vector2(3.0, 5.0)),
		FormationSpot.make("CB1", "CB", Vector2(6.0, 0.0), "left_1"),
		FormationSpot.make("CB2", "CB", Vector2(6.0, 0.0), "right_1"),
		FormationSpot.make("SS", "S", Vector2(8.0, 1.0)),
		FormationSpot.make("FS", "S", Vector2(13.0, 0.0)),
	]
	var f := DefensiveFormation.make("3-4", spots)
	var L := Zone.Spot.LEFT
	var R := Zone.Spot.RIGHT
	var C := Zone.Spot.CENTER
	var SH := Zone.Depth.SHALLOW
	var MID := Zone.Depth.INTERMEDIATE
	var DP := Zone.Depth.DEEP
	f.add_play(DefensivePlay.make("3-4 Cover 3",
		"Three deep, four underneath, with the outside linebackers dropping to the flats.", [
			CoverageAssignment.in_zone("CB1", _z("Deep Third Left", DP, L, 9, 0.66, 17)),
			CoverageAssignment.in_zone("CB2", _z("Deep Third Right", DP, R, 9, 0.66, 17)),
			CoverageAssignment.in_zone("FS", _z("Deep Middle", DP, C, 10, 0.0, 19)),
			CoverageAssignment.in_zone("SS", _z("Hook Left", MID, L, 5, 0.15, 7)),
			CoverageAssignment.in_zone("ILB1", _z("Hook Left Inside", MID, L, 5, 0.1, 7)),
			CoverageAssignment.in_zone("ILB2", _z("Hook Right", MID, R, 5, 0.11, 7)),
			CoverageAssignment.in_zone("OLB1", _z("Curl Flat Left", SH, L, 6, 0.375, 6)),
			CoverageAssignment.in_zone("OLB2", _z("Curl Flat Right", SH, R, 6, 0.375, 6)),
		]))
	f.add_play(DefensivePlay.make("3-4 Zone Blitz",
		"Both outside linebackers rush while the corners and safeties play zone. Disguises where the pressure comes from.", [
			CoverageAssignment.in_zone("CB1", _z("Deep Third Left", DP, L, 9, 0.66, 17)),
			CoverageAssignment.in_zone("CB2", _z("Deep Third Right", DP, R, 9, 0.66, 17)),
			CoverageAssignment.in_zone("FS", _z("Deep Middle", DP, C, 10, 0.0, 19)),
			CoverageAssignment.in_zone("SS", _z("Curl Flat Right", SH, R, 6, 0.375, 6)),
			CoverageAssignment.in_zone("ILB1", _z("Hook Left", MID, L, 5, 0.15, 7)),
			CoverageAssignment.in_zone("ILB2", _z("Middle Hole", MID, C, 5, 0.0, 10)),
			CoverageAssignment.blitz("OLB1"),
			CoverageAssignment.blitz("OLB2"),
		]))
	f.add_play(DefensivePlay.make("3-4 Man",
		"Man coverage on every receiver with one deep safety. The inside linebackers cover backs and tight ends.", [
			CoverageAssignment.man("CB1"),
			CoverageAssignment.man("CB2"),
			CoverageAssignment.man("SS"),
			CoverageAssignment.man("OLB1"),
			CoverageAssignment.man("OLB2"),
			CoverageAssignment.in_zone("ILB1", _z("Short Middle", SH, C, 6, 0.0, 6)),
			CoverageAssignment.blitz("ILB2"),
			CoverageAssignment.in_zone("FS", _z("Deep Middle", DP, C, 14, 0.0, 17)),
		]))
	return f
