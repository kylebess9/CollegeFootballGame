class_name RunPlay
extends OffensivePlay
## A handoff to the ball carrier: the formation's first RB unless `carrier` names someone
## else (any QB, RB, TE or WR; the QB taking the snap keeps it himself). He runs run_path's
## stock path, "inside" (between the tackles) or "outside" (to the edge), unless the editor
## has drawn him his own `path`. The QB waits time_delay seconds for him to reach him
## (PlaySim.HANDOFF_RADIUS). If he gets there in time it's a handoff; if not, the QB pitches
## it to him instead.

const INSIDE := "inside"
const OUTSIDE := "outside"
## Every run path, in the order the editor lists them. Add new paths here (and teach
## PlaySim._build_offense how to run them).
const PATHS: Array[String] = [INSIDE, OUTSIDE]
const DEFAULT_TIME_DELAY := 0.55
const MIN_TIME_DELAY := 0.2
const MAX_TIME_DELAY := 3.0
## Who can be given the ball.
const CARRIER_POSITIONS: Array[String] = ["QB", "RB", "TE", "WR"]

@export var run_path := INSIDE
## Seconds after the snap the QB waits for the handoff before he pitches the ball instead.
@export var time_delay := DEFAULT_TIME_DELAY
## The ball carrier's slot; "" for the formation's first RB (default_carrier()).
@export var carrier := ""
## A path drawn for the carrier in the editor: points from where he lines up, (yards
## downfield, yards toward the offense's right; not mirrored). Empty: run_path's stock path.
@export var path: Array[Vector2] = []


func _init() -> void:
	type = RUN


static func make(play_name: String, desc: String, path: String) -> RunPlay:
	var p := RunPlay.new()
	p.name = play_name
	p.description = desc
	p.run_path = path
	return p


## The slot that gets the ball.
func ball_carrier() -> String:
	return carrier if carrier != "" else default_carrier(formation)


## The formation's first running back: the slot named RB, or else the first RB spot. "" if none.
static func default_carrier(f: OffensiveFormation) -> String:
	if f == null:
		return ""
	if f.has_slot("RB"):
		return "RB"
	for s in f.spots:
		if s.position == "RB":
			return s.slot
	return ""


func has_custom_path() -> bool:
	return not path.is_empty()


func validate() -> Array[String]:
	var errs := super()
	if not run_path in PATHS:
		errs.append("%s: run_path must be one of %s" % [name, ", ".join(PATHS)])
	if time_delay < MIN_TIME_DELAY or time_delay > MAX_TIME_DELAY:
		errs.append("%s: time_delay must be %.1f to %.1f seconds" % [name, MIN_TIME_DELAY, MAX_TIME_DELAY])
	if formation != null:
		var c := ball_carrier()
		var s := formation.spot(c) if c != "" else null
		if s == null:
			errs.append("%s is a run but nobody in %s is set to carry it" % [name, formation.name])
		elif not s.position in CARRIER_POSITIONS:
			errs.append("%s: %s (%s) can't carry the ball" % [name, c, s.position])
	return errs
