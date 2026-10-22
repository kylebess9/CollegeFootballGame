class_name CoverageAssignment
extends Resource
## One defender's job on a defensive call.
##   man   - follow a receiver. The sim gives each man defender, in the play's order, the
##           closest receiver nobody has yet; `target` (a slot, e.g. "TE") overrides that.
##   zone  - guard `zone`
##   blitz - rush the passer / attack the run

const MAN := "man"
const ZONE := "zone"
const BLITZ := "blitz"

@export var slot := ""
@export var type := ZONE
@export var target := ""
@export var zone: Zone


static func man(who: String, man_target := "") -> CoverageAssignment:
	var a := CoverageAssignment.new()
	a.slot = who
	a.type = MAN
	a.target = man_target
	return a


static func in_zone(who: String, z: Zone) -> CoverageAssignment:
	var a := CoverageAssignment.new()
	a.slot = who
	a.type = ZONE
	a.zone = z
	return a


static func blitz(who: String) -> CoverageAssignment:
	var a := CoverageAssignment.new()
	a.slot = who
	a.type = BLITZ
	return a
