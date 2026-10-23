class_name RunPlay
extends OffensivePlay
## A handoff to the RB. run_path is "inside" (between the tackles) or "outside" (to the edge).
## The QB waits time_delay seconds for the RB to reach him (PlaySim.HANDOFF_RADIUS). If he gets
## there in time it's a handoff; if not, the QB pitches it to him instead.

const INSIDE := "inside"
const OUTSIDE := "outside"
## Every run path, in the order the editor lists them. Add new paths here (and teach
## PlaySim._build_offense how to run them).
const PATHS: Array[String] = [INSIDE, OUTSIDE]
const DEFAULT_TIME_DELAY := 0.55
const MIN_TIME_DELAY := 0.2
const MAX_TIME_DELAY := 3.0

@export var run_path := INSIDE
## Seconds after the snap the QB waits for the handoff before he pitches the ball instead.
@export var time_delay := DEFAULT_TIME_DELAY


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
	if not run_path in PATHS:
		errs.append("%s: run_path must be one of %s" % [name, ", ".join(PATHS)])
	if time_delay < MIN_TIME_DELAY or time_delay > MAX_TIME_DELAY:
		errs.append("%s: time_delay must be %.1f to %.1f seconds" % [name, MIN_TIME_DELAY, MAX_TIME_DELAY])
	if formation != null and not formation.has_slot("RB"):
		errs.append("%s is a run but %s has no RB" % [name, formation.name])
	return errs
