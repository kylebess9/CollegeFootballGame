class_name SimActor
extends RefCounted
## One player on the field during a single play.

enum Side { OFFENSE, DEFENSE }

const HISTORY_LEN := 45

var id := 0
var player: FootballPlayer
var side := Side.OFFENSE
var slot := ""
var position := "" # the formation spot's position (QB, LB, S...), not the player's own
var pos := Vector2.ZERO
var start_pos := Vector2.ZERO
var vel := Vector2.ZERO
var top_speed := 6.0
var react_time := 0.4

## What this player is doing right now: qb, route, block, rb_run, carry, rush, man, zone, pursue, escort, idle
var job := "idle"

# Timers (seconds)
var down_time := 0.0        # on the ground
var block_cooldown := 0.0   # can't engage in a block
var tackle_cooldown := 0.0  # can't try another tackle
var slow_time := 0.0        # stumbling after a broken tackle
var cut_time := 0.0         # slowing for a route cut

# Blocking
var engaged: SimActor = null
var block_target: SimActor = null
var block_timer := 0.0
var shove := Vector2.ZERO

# Routes and run paths: absolute field points
var path: Array[Vector2] = []
var path_index := 0
var path_end := "stop"
var path_dir := Vector2.RIGHT

# Coverage
var man_target: SimActor = null
var zone_center := Vector2.ZERO
var zone_radius := 5.0
var pursue_at := INF    # time this defender starts chasing the ball carrier
var bite_until := -1.0  # fooled by play action until this time
var run_first := false

var history: Array[Vector2] = []


func r(attr: String) -> int:
	return player.r(attr)


func has_skill(skill: String) -> bool:
	return player.has_skill(skill)


func is_up() -> bool:
	return down_time <= 0.0


func is_free() -> bool:
	return down_time <= 0.0 and engaged == null


func tag() -> String:
	return "%s #%d %s" % [slot, player.number, player.last_name]


func record_history() -> void:
	history.append(pos)
	if history.size() > HISTORY_LEN:
		history.pop_front()


## Where this player was `seconds` ago. Defenders react to what they saw, not what is happening now.
func pos_ago(seconds: float, dt: float) -> Vector2:
	if history.is_empty():
		return pos
	var steps := int(seconds / dt)
	var i := maxi(0, history.size() - 1 - steps)
	return history[i]


func disengage() -> void:
	if engaged != null:
		engaged.engaged = null
		engaged = null
