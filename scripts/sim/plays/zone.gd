class_name Zone
extends Resource
## An area of the field a zone defender guards.
##
## depth sets how far past the line the zone sits (each depth has a default distance in
## yards, which a zone can override with `yards`). spot picks the side of the field, and
## `width` how far toward that sideline the zone sits, as a fraction of the room between the
## ball and the sideline (0 = in line with the ball, 1 = on the sideline). Center zones sit
## in line with the ball. `radius` is how much ground the defender covers around that spot.

enum Depth { SHALLOW, INTERMEDIATE, DEEP }
enum Spot { LEFT, CENTER, RIGHT }

const DEFAULT_YARDS := {Depth.SHALLOW: 6.0, Depth.INTERMEDIATE: 8.0, Depth.DEEP: 17.0}
const FIELD_W := 53.333

@export var name := ""
@export var radius := 5.0
@export var depth := Depth.SHALLOW
@export var spot := Spot.CENTER
@export var width := 0.5
## Yards past the line of scrimmage. Negative means "use the default for this depth".
@export var yards := -1.0


static func make(zone_name: String, zone_depth: Depth, zone_spot: Spot, zone_radius: float,
		zone_width := 0.5, zone_yards := -1.0) -> Zone:
	var z := Zone.new()
	z.name = zone_name
	z.depth = zone_depth
	z.spot = zone_spot
	z.radius = zone_radius
	z.width = zone_width
	z.yards = zone_yards
	return z


func depth_yards() -> float:
	return yards if yards >= 0.0 else float(DEFAULT_YARDS[depth])


func is_deep() -> bool:
	return depth == Depth.DEEP


## Center of the zone on the field, for a ball snapped from (los, ball_y). Lower y is the
## offense's left.
func center(los: float, ball_y: float) -> Vector2:
	var y := ball_y
	match spot:
		Spot.LEFT:
			y = ball_y - ball_y * width
		Spot.RIGHT:
			y = ball_y + (FIELD_W - ball_y) * width
	return Vector2(los + depth_yards(), y)


func validate() -> Array[String]:
	var errs: Array[String] = []
	if radius <= 0.0:
		errs.append("Zone %s needs a positive radius" % name)
	if width < 0.0 or width > 1.0:
		errs.append("Zone %s width must be between 0 and 1" % name)
	return errs
