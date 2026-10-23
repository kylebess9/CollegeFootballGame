class_name FormationDraft
extends RefCounted
## A formation being built in the formation builder. Holds every player, whether they've
## been put on the field yet, and the rules for dragging them around: snapping to the line
## of scrimmage and to the spot behind the center, no overlapping, and (on offense) handing
## the snap to whoever ends up closest behind the center.
##
## Nothing here touches the playbook until apply_to() / to_formation() is called, so the
## builder can be cancelled.

## Positions the new-formation dialog asks for, per side, with default counts.
const OFFENSE_POSITIONS := {"QB": 1, "RB": 1, "WR": 3, "TE": 1, "OL": 5}
const DEFENSE_POSITIONS := {"DL": 4, "LB": 3, "CB": 2, "S": 2}
const PLAYERS := 11
const MIN_OL := 5

## Where offensive linemen stand (yards behind the ball) and how far apart.
const OL_X := -0.8
const OL_GAP := 1.4
## Where a defender "on the ball" lines up.
const DEF_LINE_X := 1.0
## Drop within this many yards of the line and the player snaps onto it.
const LINE_SNAP := 0.8
## Drop within this many yards across of the center, behind him, and the player lines up
## directly behind him.
const CENTER_SNAP := 1.0
## Players' centers can't be closer than this (yards).
const MIN_GAP := 1.2
## How far the builder lets players line up from the ball.
const MAX_DEPTH := 15.0
const MAX_WIDTH := 23.0
## Where the snap drop-down puts the player it hands the snap to: under center.
const UNDER_CENTER := 1.3

var offense := true
var name := ""
var snap_slot := ""
var spots: Array[FormationSpot] = []
var placed := {} # slot -> true once the player is on the field
## The slot that can't be moved: the center, who snaps the ball.
var center_slot := ""
## Defenders who line up over a receiver (FormationSpot.align) rather than at a fixed spot:
## slot -> how far across they're drawn, over where that receiver usually is. Moving one
## pins him to the spot he's dropped on instead.
var aligned := {}
## Where the receiver each align names usually lines up (yards across), for drawing them.
const ALIGN_DRAW_Y := {"left_1": -13.0, "left_2": -6.0, "left_3": -3.0, "right_1": 15.0, "right_2": 6.0, "right_3": 3.0}


## A new formation with `counts` players at each position (e.g. {"QB": 1, "OL": 5, ...}).
## Offensive linemen start on the line, centered on the ball; everyone else starts off the
## field, waiting to be dragged on.
static func create(formation_name: String, is_offense: bool, counts: Dictionary) -> FormationDraft:
	var d := FormationDraft.new()
	d.offense = is_offense
	d.name = formation_name
	var order: Dictionary = OFFENSE_POSITIONS if is_offense else DEFENSE_POSITIONS
	for pos in order:
		for slot in slot_names(pos, int(counts.get(pos, 0))):
			d.spots.append(FormationSpot.make(slot, pos, Vector2.ZERO))
	if is_offense:
		d._layout_line()
	return d


## A draft of an existing formation, everyone where they already line up.
static func from_formation(f: Resource) -> FormationDraft:
	var d := FormationDraft.new()
	d.offense = f is OffensiveFormation
	d.name = f.name
	for s in f.spots:
		var copy: FormationSpot = s.duplicate()
		if copy.align != "":
			d.aligned[copy.slot] = ALIGN_DRAW_Y.get(copy.align, 0.0)
			copy.offset.y += d.aligned[copy.slot]
		d.spots.append(copy)
		d.placed[s.slot] = true
	if d.offense:
		d.snap_slot = f.snap_slot
		var c: FormationSpot = d._as_formation().center_spot()
		d.center_slot = c.slot if c != null else ""
	return d


## Slot names for `count` players at a position. Uses the names the depth chart knows when
## the count matches the standard lineup, so the right starters fill them.
static func slot_names(pos: String, count: int) -> Array[String]:
	var out: Array[String] = []
	var standard := {
		"OL": ["LT", "LG", "C", "RG", "RT"], "DL": ["DE1", "DT1", "DT2", "DE2"],
		"LB": ["WILL", "MIKE", "SAM"], "S": ["SS", "FS"],
	}
	if standard.has(pos) and count == standard[pos].size():
		out.assign(standard[pos])
		return out
	if pos == "OL":
		out.assign(standard["OL"])
		for i in range(5, count):
			out.append("OL%d" % (i + 1))
		return out
	for i in count:
		if pos in ["QB", "RB", "TE"]:
			out.append(pos if i == 0 else "%s%d" % [pos, i + 1])
		else:
			out.append("%s%d" % [pos, i + 1])
	return out


## Lines the offensive linemen up on the ball, the center over it. Past the standard five,
## extra linemen go on the ends, alternating right and left.
func _layout_line() -> void:
	var order: Array[FormationSpot] = []
	var extra := 0
	for s in spots:
		if s.position != "OL":
			continue
		if order.size() < 5:
			order.append(s)
		else:
			if extra % 2 == 0:
				order.append(s)
			else:
				order.push_front(s)
			extra += 1
	for i in order.size():
		order[i].offset = Vector2(OL_X, i * OL_GAP)
		placed[order[i].slot] = true
	center_slot = "C"
	var mid := spot(center_slot).offset.y
	for s in order:
		s.offset.y -= mid


func spot(slot: String) -> FormationSpot:
	for s in spots:
		if s.slot == slot:
			return s
	return null


func is_placed(slot: String) -> bool:
	return placed.has(slot)


func can_move(slot: String) -> bool:
	return slot != center_slot


func placed_spots() -> Array[FormationSpot]:
	var out: Array[FormationSpot] = []
	for s in spots:
		if is_placed(s.slot):
			out.append(s)
	return out


func unplaced_spots() -> Array[FormationSpot]:
	var out: Array[FormationSpot] = []
	for s in spots:
		if not is_placed(s.slot):
			out.append(s)
	return out


## Where a player dropped at `at` (yards from the ball) actually lines up: kept on his own
## side of the ball and on the field, snapped onto the line when close to it, and (on
## offense) snapped directly behind the center when close to that.
func snap_point(slot: String, at: Vector2) -> Vector2:
	var p := at
	p.y = clampf(p.y, -MAX_WIDTH, MAX_WIDTH)
	if offense:
		p.x = clampf(p.x, -MAX_DEPTH, OL_X)
		if absf(p.x - OL_X) < LINE_SNAP:
			p.x = OL_X
		var c := spot(center_slot)
		if c != null and slot != center_slot and p.x < c.offset.x - 0.5 and absf(p.y - c.offset.y) < CENTER_SNAP:
			p.y = c.offset.y
	else:
		p.x = clampf(p.x, DEF_LINE_X, MAX_DEPTH)
		if absf(p.x - DEF_LINE_X) < LINE_SNAP:
			p.x = DEF_LINE_X
	return p


## The player already standing where `slot` would go, if any.
func blocker_at(slot: String, at: Vector2) -> FormationSpot:
	for s in placed_spots():
		if s.slot != slot and s.offset.distance_to(at) < MIN_GAP:
			return s
	return null


## Moves a player to `at` (snapped). Returns false, leaving everything as it was, if the
## player can't move or would overlap someone.
func place(slot: String, at: Vector2) -> bool:
	var s := spot(slot)
	if s == null or not can_move(slot):
		return false
	var p := snap_point(slot, at)
	if blocker_at(slot, p) != null:
		return false
	s.offset = p
	s.align = ""
	aligned.erase(slot)
	placed[slot] = true
	_update_snap()
	return true


## Takes a player back off the field.
func remove(slot: String) -> void:
	if can_move(slot):
		placed.erase(slot)
		_update_snap()


## Gives the snap to whoever is closest behind the center (offense only).
func _update_snap() -> void:
	if not offense:
		return
	var c: FormationSpot = _as_formation().snap_candidate()
	snap_slot = c.slot if c != null else ""


## The snap drop-down: moves `slot` under center so he's the closest player behind it.
## Whoever was there swaps to where `slot` was (or off the field, if `slot` wasn't on yet).
func give_snap(slot: String) -> void:
	var s := spot(slot)
	var c := spot(center_slot)
	if s == null or c == null or slot == snap_slot or not can_move(slot):
		return
	var target := Vector2(c.offset.x - UNDER_CENTER, c.offset.y)
	var old := spot(snap_slot)
	if old != null and old.offset.x > target.x:
		target = old.offset # someone's already tighter to the center: take his spot
	var from := s.offset
	var was_placed := is_placed(slot)
	var in_way := blocker_at(slot, target)
	if in_way != null:
		if was_placed:
			in_way.offset = from
		else:
			placed.erase(in_way.slot)
	s.offset = target
	placed[slot] = true
	_update_snap()


## A formation built from just the players on the field, for the rule checks.
func _as_formation() -> Resource:
	var on: Array[FormationSpot] = placed_spots()
	var f: Resource
	if offense:
		f = OffensiveFormation.make(name, on)
		f.snap_slot = snap_slot
	else:
		f = DefensiveFormation.make(name, on)
	return f


## Counts for the right panel: on the line and in the backfield (offense).
func line_counts() -> Dictionary:
	var f: Resource = _as_formation()
	var line := 0
	for s in placed_spots():
		if offense and f.on_line(s):
			line += 1
	return {"line": line, "backfield": placed_spots().size() - line}


## Why this formation isn't legal yet; empty when it is.
func problems() -> Array[String]:
	var errs: Array[String] = []
	if name.strip_edges() == "":
		errs.append("Give the formation a name.")
	var waiting := unplaced_spots()
	if not waiting.is_empty():
		var who: Array[String] = []
		for s in waiting:
			who.append(s.slot)
		errs.append("Still to place: %s." % ", ".join(who))
	if not waiting.is_empty():
		return errs # the rule checks below only make sense with everyone on the field
	if offense and snap_slot == "":
		errs.append("Nobody is lined up behind the center to take the snap.")
		return errs
	errs.append_array(_as_formation().validate())
	return errs


func is_legal() -> bool:
	return problems().is_empty()


## A new formation from this draft.
func to_formation() -> Resource:
	var f: Resource = OffensiveFormation.make(name, _copy_spots()) if offense \
		else DefensiveFormation.make(name, _copy_spots())
	if offense:
		f.snap_slot = snap_slot
	return f


## Writes this draft back over an existing formation, keeping its plays.
func apply_to(f: Resource) -> void:
	f.name = name
	f.spots = _copy_spots()
	if offense:
		f.snap_slot = snap_slot


func _copy_spots() -> Array[FormationSpot]:
	var out: Array[FormationSpot] = []
	for s in spots:
		var copy: FormationSpot = s.duplicate()
		if aligned.has(copy.slot):
			copy.offset.y -= aligned[copy.slot]
		out.append(copy)
	return out
