class_name OffensiveFormation
extends Resource
## Where the 11 offensive players line up, and the plays run from this look.

const PLAYERS := 11
const MIN_ON_LINE := 7
const MAX_IN_BACKFIELD := 4
## A player lined up within this many yards of the line counts as on the line.
const LINE_DEPTH := 1.0
## How far (across) a player can be from the center and still take the snap.
const SNAP_LANE := 0.5

@export var name := ""
@export var spots: Array[FormationSpot] = []
@export var plays: Array[OffensivePlay] = []


static func make(formation_name: String, formation_spots: Array[FormationSpot]) -> OffensiveFormation:
	var f := OffensiveFormation.new()
	f.name = formation_name
	f.spots = formation_spots
	return f


func add_play(play: OffensivePlay) -> OffensivePlay:
	play.formation = self
	plays.append(play)
	return play


func spot(slot: String) -> FormationSpot:
	for s in spots:
		if s.slot == slot:
			return s
	return null


func has_slot(slot: String) -> bool:
	return spot(slot) != null


func on_line(s: FormationSpot) -> bool:
	return s.offset.x >= -LINE_DEPTH


## The interior lineman the ball is snapped from: the offensive lineman closest to the ball.
func center_spot() -> FormationSpot:
	var best: FormationSpot = null
	for s in spots:
		if s.position == "OL" and on_line(s) and (best == null or absf(s.offset.y) < absf(best.offset.y)):
			best = s
	return best


## Rule problems with this formation; empty when it's legal.
func validate() -> Array[String]:
	var errs: Array[String] = []
	if spots.size() != PLAYERS:
		errs.append("%s has %d players, needs %d" % [name, spots.size(), PLAYERS])
	var seen := {}
	var line := 0
	for s in spots:
		if seen.has(s.slot):
			errs.append("%s lists %s twice" % [name, s.slot])
		seen[s.slot] = true
		if on_line(s):
			line += 1
	if line < MIN_ON_LINE:
		errs.append("%s has %d players on the line, needs at least %d" % [name, line, MIN_ON_LINE])
	if spots.size() - line > MAX_IN_BACKFIELD:
		errs.append("%s has %d players in the backfield, at most %d allowed" % [name, spots.size() - line, MAX_IN_BACKFIELD])
	var c := center_spot()
	var qb := spot("QB")
	if c == null:
		errs.append("%s has no center on the line" % name)
	elif qb == null:
		errs.append("%s has no QB" % name)
	elif absf(qb.offset.y - c.offset.y) > SNAP_LANE or qb.offset.x >= c.offset.x:
		errs.append("%s needs the QB lined up directly behind the center to take the snap" % name)
	for p in plays:
		errs.append_array(p.validate())
	return errs


func is_legal() -> bool:
	return validate().is_empty()
