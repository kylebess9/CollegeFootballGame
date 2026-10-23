class_name Route
extends Resource
## A pass route, drawn relative to where the receiver lines up.
##
## Each point is (yards downfield, yards toward the sideline). Negative "toward the sideline"
## means cutting inside; the sim mirrors the route for receivers on the left. After the last
## point the receiver either keeps running in the same direction ("go") or settles where he
## is ("stop").

const STOP := "stop"
const GO := "go"
## The name of a route drawn for one player in one play, rather than picked from the tree.
const CUSTOM := "Custom"

@export var name := ""
@export var points: Array[Vector2] = []
@export var end := STOP


static func make(route_name: String, pts: Array[Vector2], end_kind: String) -> Route:
	var r := Route.new()
	r.name = route_name
	r.points = pts
	r.end = end_kind
	return r


func validate() -> Array[String]:
	var errs: Array[String] = []
	if points.is_empty():
		errs.append("Route %s has no points" % name)
	if end != STOP and end != GO:
		errs.append("Route %s must end with \"stop\" or \"go\", not \"%s\"" % [name, end])
	return errs
