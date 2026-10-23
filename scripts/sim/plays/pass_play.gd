class_name PassPlay
extends OffensivePlay
## A pass call.
##   drop        - yards the QB drops back before setting up
##   read_start  - seconds after the snap before the QB starts his progression
##   play_action - fake a handoff to the RB first
##   routes      - slot -> Route for everyone running a pattern; other skill players block
##   protect     - slots kept in to block
##   reads       - the QB's progression, in order
##
## The editor changes a player's job with set_route() / set_block(), which keep routes,
## protect and reads consistent with each other.

## What job() returns for a player who isn't running a route.
const BLOCK := "block"

@export var drop := 7.0
@export var read_start := 1.3
@export var play_action := false
@export var routes: Dictionary[String, Route] = {}
@export var protect: Array[String] = []
@export var reads: Array[String] = []


func _init() -> void:
	type = PASS


static func make(play_name: String, desc: String, drop_yds: float, read_at: float, fake: bool,
		play_routes: Dictionary[String, Route], play_protect: Array[String], play_reads: Array[String]) -> PassPlay:
	var p := PassPlay.new()
	p.name = play_name
	p.description = desc
	p.drop = drop_yds
	p.read_start = read_at
	p.play_action = fake
	p.routes = play_routes
	p.protect = play_protect
	p.reads = play_reads
	return p


## A new pass play with every receiver (WR/TE) running a go route and everyone else
## blocking, so it's legal from the start and the user edits from there.
static func blank(play_name: String, fake: bool, f: OffensiveFormation) -> PassPlay:
	var p := PassPlay.new()
	p.name = play_name
	p.play_action = fake
	p.formation = f
	for s in f.spots:
		if s.position in ["WR", "TE"] and f.is_eligible(s.slot):
			p.set_route(s.slot, Playbook.route("go"))
		elif f.is_eligible(s.slot):
			p.set_block(s.slot)
	return p


## The name of the route this slot runs, or BLOCK.
func job(slot: String) -> String:
	return routes[slot].name if routes.has(slot) else BLOCK


## Sends a player out on a route. New route runners are added to the end of the QB's reads.
func set_route(slot: String, r: Route) -> void:
	routes[slot] = r
	protect.erase(slot)
	if not slot in reads:
		reads.append(slot)


## Keeps a player in to block.
func set_block(slot: String) -> void:
	routes.erase(slot)
	reads.erase(slot)
	if not slot in protect:
		protect.append(slot)


func validate() -> Array[String]:
	var errs := super()
	var f := formation
	if f == null:
		return errs
	for slot in routes:
		if not f.has_slot(slot):
			errs.append("%s: %s runs a route but isn't in %s" % [name, slot, f.name])
		errs.append_array(routes[slot].validate())
	if routes.has(f.snap_slot) or f.snap_slot in reads:
		errs.append("%s: %s takes the snap, so can't run a route" % [name, f.snap_slot])
	for slot in reads:
		if not routes.has(slot):
			errs.append("%s: QB reads %s, who isn't running a route" % [name, slot])
	if reads.is_empty():
		errs.append("%s has no reads" % name)
	if play_action and not f.has_slot("RB"):
		errs.append("%s is play action but %s has no RB to fake to" % [name, f.name])
	return errs
