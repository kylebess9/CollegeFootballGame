class_name FormationSpot
extends Resource
## Where one player lines up in a formation.
##
## slot is the name the play refers to (QB, WR1, MIKE...). When the team's depth chart has
## that slot its starter takes it; otherwise the best unused player at `position` (the roster
## position: QB, RB, WR, TE, OL, DL, LB, CB, S) does.
##
## offset is (yards downfield, yards across) from the ball at the snap. Offensive players
## have negative x (behind the line), defensive players positive x. Lower y is the offense's
## left.
##
## Defense only: `align` lines the player up across from a receiver instead of the ball,
## e.g. "left_1" is the widest receiver on the offense's left, "right_2" the second widest
## on the right. offset.y is then measured from that receiver.

@export var slot := ""
@export var position := ""
@export var offset := Vector2.ZERO
@export var align := ""


static func make(spot_slot: String, spot_position: String, at: Vector2, spot_align := "") -> FormationSpot:
	var s := FormationSpot.new()
	s.slot = spot_slot
	s.position = spot_position
	s.offset = at
	s.align = spot_align
	return s
