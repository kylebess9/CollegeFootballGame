class_name DefensiveFormation
extends Resource
## Where the 11 defenders line up, and the coverages called from this look.
## Down linemen (position DL) always rush; everyone else gets a job from the play.

const PLAYERS := 11

@export var name := ""
@export var spots: Array[FormationSpot] = []
@export var plays: Array[DefensivePlay] = []


static func make(formation_name: String, formation_spots: Array[FormationSpot]) -> DefensiveFormation:
	var f := DefensiveFormation.new()
	f.name = formation_name
	f.spots = formation_spots
	return f


func add_play(play: DefensivePlay) -> DefensivePlay:
	play.formation = self
	plays.append(play)
	return play


func remove_play(play: DefensivePlay) -> void:
	plays.erase(play)
	play.formation = null


func spot(slot: String) -> FormationSpot:
	for s in spots:
		if s.slot == slot:
			return s
	return null


func has_slot(slot: String) -> bool:
	return spot(slot) != null


func validate() -> Array[String]:
	var errs: Array[String] = []
	if spots.size() != PLAYERS:
		errs.append("%s has %d players, needs %d" % [name, spots.size(), PLAYERS])
	var seen := {}
	for s in spots:
		if seen.has(s.slot):
			errs.append("%s lists %s twice" % [name, s.slot])
		seen[s.slot] = true
	for p in plays:
		errs.append_array(p.validate())
	return errs


func is_legal() -> bool:
	return validate().is_empty()
