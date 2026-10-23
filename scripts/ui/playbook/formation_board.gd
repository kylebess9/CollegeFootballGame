class_name FormationBoard
extends Control
## The formation builder's field: a close-up of the line of scrimmage, drawn the way a
## playbook diagram is (offense going up the screen, the offense's left on the left).
## Players are dragged here from the tray, and around the field; while dragging, a ghost
## shows where the player will snap to, red when someone's already standing there.

signal changed

## Yards across shown each side of the ball, and yards shown past / behind the line.
const HALF_WIDTH := 25.0
const AHEAD := 5.0
const BEHIND := 18.0
const DOT_R := 0.6 # yards; under half of FormationDraft.MIN_GAP so dots never touch
const POSITION_COLORS := {
	"QB": Color("#f2b134"), "RB": Color("#5fd38a"), "WR": Color("#4ea1ff"), "TE": Color("#b48cff"),
	"OL": Color("#8a96a8"), "DL": Color("#8a96a8"), "LB": Color("#ff9f43"), "CB": Color("#4ea1ff"),
	"S": Color("#b48cff"),
}

var draft: FormationDraft
var font: Font
var _scale := 20.0
var _origin := Vector2.ZERO # screen point of the ball
var _drag_slot := "" # the player being dragged, hidden from his old spot
var _hover := Vector2.INF # snapped drop point (yards) while a drag is over the board
var _hover_ok := false


func _ready() -> void:
	font = get_theme_default_font()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


## Draws one player: a colored dot with his slot name in it. Shared with the tray.
static func draw_player(ci: CanvasItem, f: Font, at: Vector2, radius: float, s: FormationSpot, alpha := 1.0) -> void:
	var col: Color = POSITION_COLORS.get(s.position, UiStyle.TEXT)
	col.a = alpha
	ci.draw_circle(at, radius, col)
	ci.draw_arc(at, radius, 0, TAU, 24, Color(0, 0, 0, 0.6 * alpha), 1.5)
	var fs := int(clampf(radius * (0.9 if s.slot.length() <= 2 else 0.7), 8, 16))
	var w := f.get_string_size(s.slot, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(f, at + Vector2(-w * 0.5, fs * 0.36), s.slot, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.07, 0.1, alpha))


func dot_radius() -> float:
	return DOT_R * _scale


# ---------------------------------------------------------------- coordinates

## The window of yards (relative to the ball) this side's players can use.
func _top() -> float:
	return AHEAD if draft == null or draft.offense else BEHIND


func _depth() -> float:
	return AHEAD + BEHIND


func _layout() -> void:
	_scale = minf(size.x / (HALF_WIDTH * 2.0), size.y / _depth())
	var used := Vector2(HALF_WIDTH * 2.0, _depth()) * _scale
	var corner := (size - used) * 0.5
	_origin = corner + Vector2(HALF_WIDTH, _top()) * _scale


## Formation offset (yards downfield, yards across) to a point on screen.
func to_screen(offset: Vector2) -> Vector2:
	return _origin + Vector2(offset.y, -offset.x) * _scale


func to_offset(screen: Vector2) -> Vector2:
	var d := (screen - _origin) / _scale
	return Vector2(-d.y, d.x)


func spot_at(screen: Vector2) -> FormationSpot:
	if draft == null:
		return null
	for s in draft.placed_spots():
		if to_screen(s.offset).distance_to(screen) <= dot_radius() + 3.0:
			return s
	return null


# ---------------------------------------------------------------- drag and drop

func _get_drag_data(at: Vector2) -> Variant:
	var s := spot_at(at)
	if s == null or not draft.can_move(s.slot):
		return null
	_drag_slot = s.slot
	set_drag_preview(DotPreview.make(s, dot_radius(), font))
	queue_redraw()
	return {"formation_slot": s.slot}


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if draft == null or not (data is Dictionary and data.has("formation_slot")):
		return false
	var slot: String = data["formation_slot"]
	_hover = draft.snap_point(slot, to_offset(at))
	_hover_ok = draft.blocker_at(slot, _hover) == null
	queue_redraw()
	return _hover_ok


func _drop_data(at: Vector2, data: Variant) -> void:
	var slot: String = data["formation_slot"]
	draft.place(slot, to_offset(at))
	_end_drag()
	changed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2.INF
		if what == NOTIFICATION_DRAG_END:
			_drag_slot = ""
		queue_redraw()


func _end_drag() -> void:
	_drag_slot = ""
	_hover = Vector2.INF
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var s := spot_at(event.position)
		if s == null:
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			tooltip_text = ""
		elif draft.aligned.has(s.slot):
			mouse_default_cursor_shape = Control.CURSOR_DRAG
			tooltip_text = "Lines up over a receiver (%s). Move him to pin him to a spot instead." % s.align.replace("_", " #")
		elif not draft.can_move(s.slot):
			mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
			tooltip_text = "The center stays over the ball."
		else:
			mouse_default_cursor_shape = Control.CURSOR_DRAG
			tooltip_text = ""


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	_layout()
	_draw_field()
	if draft == null:
		return
	_draw_guides()
	for s in draft.placed_spots():
		if s.slot != _drag_slot:
			draw_player(self, font, to_screen(s.offset), dot_radius(), s)
	if draft.offense and draft.snap_slot != "":
		var q := to_screen(draft.spot(draft.snap_slot).offset)
		draw_arc(q, dot_radius() + 3.0, 0, TAU, 28, Color.WHITE, 2.0)
	if _hover != Vector2.INF:
		var col := Color(1, 1, 1, 0.55) if _hover_ok else Color(UiStyle.BAD, 0.7)
		draw_arc(to_screen(_hover), dot_radius(), 0, TAU, 28, col, 2.5)


func _draw_field() -> void:
	var top_left := to_screen(Vector2(_top(), -HALF_WIDTH))
	var bottom_right := to_screen(Vector2(_top() - _depth(), HALF_WIDTH))
	draw_rect(Rect2(top_left, bottom_right - top_left), Color("#2f7d3a"))
	# A yard line every 5 yards from the line of scrimmage.
	var x := floorf(_top())
	while x >= _top() - _depth():
		if int(x) % 5 == 0:
			var a := to_screen(Vector2(x, -HALF_WIDTH))
			var b := to_screen(Vector2(x, HALF_WIDTH))
			draw_line(a, b, Color(1, 1, 1, 0.35 if x != 0 else 0.0), 1.0)
		x -= 1.0
	# Line of scrimmage and the ball.
	draw_line(to_screen(Vector2(0, -HALF_WIDTH)), to_screen(Vector2(0, HALF_WIDTH)), Color("#3fa9f5"), 3.0)
	var ball := to_screen(Vector2.ZERO)
	draw_set_transform(ball, PI * 0.5, Vector2(1.0, 0.65))
	draw_circle(Vector2.ZERO, _scale * 0.4, Color("#8b5a2b"))
	draw_set_transform(Vector2.ZERO, 0.0)
	# Sidelines of the shown area.
	draw_rect(Rect2(top_left, bottom_right - top_left), Color(1, 1, 1, 0.6), false, 2.0)


## While a drop is snapped onto the line or behind the center, show the line it snapped to.
func _draw_guides() -> void:
	if _hover == Vector2.INF:
		return
	var guide := Color(1, 1, 0.75, 0.5)
	var line_x := FormationDraft.OL_X if draft.offense else FormationDraft.DEF_LINE_X
	if is_equal_approx(_hover.x, line_x):
		draw_dashed_line(to_screen(Vector2(line_x, -HALF_WIDTH)), to_screen(Vector2(line_x, HALF_WIDTH)), guide, 1.5, 6.0)
	var c := draft.spot(draft.center_slot)
	if draft.offense and c != null and is_equal_approx(_hover.y, c.offset.y) and _hover.x < c.offset.x:
		draw_dashed_line(to_screen(c.offset), to_screen(Vector2(_top() - _depth(), c.offset.y)), guide, 1.5, 6.0)


## What follows the mouse while a player is being dragged.
class DotPreview extends Control:
	var spot: FormationSpot
	var radius := 12.0
	var dot_font: Font

	static func make(s: FormationSpot, r: float, f: Font) -> Control:
		var p := DotPreview.new()
		p.spot = s
		p.radius = r
		p.dot_font = f
		return p

	func _draw() -> void:
		FormationBoard.draw_player(self, dot_font, Vector2.ZERO, radius, spot, 0.8)
