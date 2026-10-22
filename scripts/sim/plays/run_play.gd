class_name RunPlay
extends OffensivePlay
## A handoff to the RB. run_path is "inside" (between the tackles) or "outside" (to the edge).

const INSIDE := "inside"
const OUTSIDE := "outside"

@export var run_path := INSIDE


func _init() -> void:
	type = RUN


static func make(play_name: String, desc: String, path: String) -> RunPlay:
	var p := RunPlay.new()
	p.name = play_name
	p.description = desc
	p.run_path = path
	return p


func validate() -> Array[String]:
	var errs := super()
	if run_path != INSIDE and run_path != OUTSIDE:
		errs.append("%s: run_path must be inside or outside" % name)
	if formation != null and not formation.has_slot("RB"):
		errs.append("%s is a run but %s has no RB" % [name, formation.name])
	return errs
