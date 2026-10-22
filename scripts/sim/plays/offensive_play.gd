class_name OffensivePlay
extends Resource
## An offensive call. Every play belongs to one OffensiveFormation, which says where everyone
## lines up; PassPlay and RunPlay say what they do after the snap.

const PASS := "pass"
const RUN := "run"

@export var name := ""
@export var description := ""
var type := ""

## The formation this play runs from. Held weakly: the formation owns its plays, and a strong
## reference both ways would be a cycle that never gets freed.
var formation: OffensiveFormation:
	get:
		return null if _formation == null else _formation.get_ref() as OffensiveFormation
	set(value):
		_formation = null if value == null else weakref(value)
var _formation: WeakRef = null


func is_run() -> bool:
	return type == RUN


func validate() -> Array[String]:
	var errs: Array[String] = []
	if formation == null:
		errs.append("Play %s has no formation" % name)
	return errs
