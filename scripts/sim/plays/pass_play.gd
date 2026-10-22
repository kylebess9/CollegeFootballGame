class_name PassPlay
extends OffensivePlay
## A pass call.
##   drop        - yards the QB drops back before setting up
##   read_start  - seconds after the snap before the QB starts his progression
##   play_action - fake a handoff to the RB first
##   routes      - slot -> Route for everyone running a pattern; other skill players block
##   protect     - slots kept in to block
##   reads       - the QB's progression, in order

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


func validate() -> Array[String]:
	var errs := super()
	var f := formation
	if f == null:
		return errs
	for slot in routes:
		if not f.has_slot(slot):
			errs.append("%s: %s runs a route but isn't in %s" % [name, slot, f.name])
		errs.append_array(routes[slot].validate())
	for slot in reads:
		if not routes.has(slot):
			errs.append("%s: QB reads %s, who isn't running a route" % [name, slot])
	if reads.is_empty():
		errs.append("%s has no reads" % name)
	if play_action and not f.has_slot("RB"):
		errs.append("%s is play action but %s has no RB to fake to" % [name, f.name])
	return errs
