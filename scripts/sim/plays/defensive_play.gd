class_name DefensivePlay
extends Resource
## A defensive call. Every call belongs to one DefensiveFormation. `assignments` gives each
## player off the line (linebackers and secondary) a job; down linemen always rush.
## run_first: everyone not in a deep zone attacks the line at the snap (strong vs the run,
## easy to fool with play action).

@export var name := ""
@export var description := ""
@export var assignments: Array[CoverageAssignment] = []
@export var run_first := false

## Held weakly for the same reason as OffensivePlay.formation.
var formation: DefensiveFormation:
	get:
		return null if _formation == null else _formation.get_ref() as DefensiveFormation
	set(value):
		_formation = null if value == null else weakref(value)
var _formation: WeakRef = null


static func make(play_name: String, desc: String, assigns: Array[CoverageAssignment], run_first_call := false) -> DefensivePlay:
	var p := DefensivePlay.new()
	p.name = play_name
	p.description = desc
	p.assignments = assigns
	p.run_first = run_first_call
	return p


func assignment(slot: String) -> CoverageAssignment:
	for a in assignments:
		if a.slot == slot:
			return a
	return null


func validate() -> Array[String]:
	var errs: Array[String] = []
	var f := formation
	if f == null:
		errs.append("Play %s has no formation" % name)
		return errs
	if f.spots.size() != DefensiveFormation.PLAYERS:
		errs.append("%s: %s doesn't put %d players on the field" % [name, f.name, DefensiveFormation.PLAYERS])
	for a in assignments:
		if not f.has_slot(a.slot):
			errs.append("%s assigns %s, who isn't in %s" % [name, a.slot, f.name])
		match a.type:
			CoverageAssignment.ZONE:
				if a.zone == null:
					errs.append("%s: %s is in zone with no zone" % [name, a.slot])
				else:
					errs.append_array(a.zone.validate())
			CoverageAssignment.MAN, CoverageAssignment.BLITZ:
				pass
			_:
				errs.append("%s: %s has unknown assignment type %s" % [name, a.slot, a.type])
	for s in f.spots:
		if s.position != "DL" and assignment(s.slot) == null:
			errs.append("%s gives %s no assignment" % [name, s.slot])
	return errs
