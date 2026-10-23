class_name RouteCanvas
extends Control
## Draws one route on a patch of field and, when it's editable, lets the user reshape it:
## drag a point to move it, hover the line between two points to get a new point there and
## click to add it, right-click a point to remove it. Drawn like a playbook diagram: the
## receiver at the bottom on the line of scrimmage, downfield up the screen, and the
## sideline to the right (the sim mirrors routes for receivers on the left).

signal changed

## Yards shown behind / past the line, and each side of the receiver.
const BEHIND := 5.0
const AHEAD := 40.0
const HALF_WIDTH := 22.0
## Points land on this grid (yards).
const GRID := 0.5
const POINT_R := 7.0 # pixels
const GRAB := 12.0 # how close (pixels) the mouse must be to grab a point or a line

var route: Route
var editable := false
var font: Font
var _scale := 10.0
var _origin := Vector2.ZERO # screen point of the receiver
var _dragging := -1 # index into route.points
var _hover_point := -1
var _ghost := Vector2.INF # where a new point would go (yards), while hovering a line
var _ghost_index := -1 # the index it would be inserted at


func _ready() -> void:
	font = get_theme_default_font()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_route(r: Route, can_edit: bool) -> void:
	route = r
	editable = can_edit
	_dragging = -1
	_hover_point = -1
	_ghost = Vector2.INF
	queue_redraw()


# ---------------------------------------------------------------- coordinates

func _layout() -> void:
	_scale = minf(size.x / (HALF_WIDTH * 2.0), size.y / (BEHIND + AHEAD))
	var used := Vector2(HALF_WIDTH * 2.0, BEHIND + AHEAD) * _scale
	var corner := (size - used) * 0.5
	_origin = corner + Vector2(HALF_WIDTH, AHEAD) * _scale


## Route point (yards downfield, yards toward the sideline) to a point on screen.
func to_screen(p: Vector2) -> Vector2:
	return _origin + Vector2(p.y, -p.x) * _scale


func to_route(screen: Vector2) -> Vector2:
	var d := (screen - _origin) / _scale
	var p := Vector2(-d.y, d.x)
	p = (p / GRID).round() * GRID
	return Vector2(clampf(p.x, -BEHIND, AHEAD), clampf(p.y, -HALF_WIDTH, HALF_WIDTH))


## The line the route is drawn along: the receiver's start, then every point.
func _path() -> Array[Vector2]:
	var out: Array[Vector2] = [Vector2.ZERO]
	out.append_array(route.points)
	return out


# ---------------------------------------------------------------- editing

func point_at(screen: Vector2) -> int:
	for i in route.points.size():
		if to_screen(route.points[i]).distance_to(screen) <= GRAB:
			return i
	return -1


## Moves a point. Returns false if it would land on top of its neighbor.
func move_point(i: int, to: Vector2) -> bool:
	var path := _path()
	if path[i].is_equal_approx(to) or (i + 2 < path.size() and path[i + 2].is_equal_approx(to)):
		return false
	route.points[i] = to
	changed.emit()
	return true


## Adds a point at `at`, between path points `index` and `index + 1` (so it becomes
## route.points[index]); everything after it moves down one.
func insert_point(index: int, at: Vector2) -> void:
	route.points.insert(index, at)
	changed.emit()


## Removes a point, keeping at least one.
func remove_point(i: int) -> bool:
	if route.points.size() <= 1:
		return false
	route.points.remove_at(i)
	changed.emit()
	return true


## The segment of the route the mouse is over, away from its end points: where a new point
## would go and the index it would take. Index -1 if none.
func _segment_under(screen: Vector2) -> Array:
	var path := _path()
	for i in range(path.size() - 1):
		var a := to_screen(path[i])
		var b := to_screen(path[i + 1])
		var q := Geometry2D.get_closest_point_to_segment(screen, a, b)
		if q.distance_to(screen) <= GRAB and q.distance_to(a) > GRAB and q.distance_to(b) > GRAB:
			return [i, to_route(q)]
	return [-1, Vector2.INF]


func _gui_input(event: InputEvent) -> void:
	if route == null or not editable:
		return
	if event is InputEventMouseButton and event.pressed:
		var i := point_at(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if i >= 0:
				_dragging = i
			elif _ghost_index >= 0:
				insert_point(_ghost_index, _ghost)
				_dragging = _ghost_index
				_ghost_index = -1
				_ghost = Vector2.INF
		elif event.button_index == MOUSE_BUTTON_RIGHT and i >= 0:
			remove_point(i)
		queue_redraw()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = -1
		queue_redraw()
	elif event is InputEventMouseMotion:
		if _dragging >= 0:
			move_point(_dragging, to_route(event.position))
		else:
			_hover_point = point_at(event.position)
			var seg := _segment_under(event.position) if _hover_point < 0 else [-1, Vector2.INF]
			_ghost_index = seg[0]
			_ghost = seg[1]
			mouse_default_cursor_shape = Control.CURSOR_DRAG if _hover_point >= 0 \
				else (Control.CURSOR_POINTING_HAND if _ghost_index >= 0 else Control.CURSOR_ARROW)
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _dragging < 0:
		_hover_point = -1
		_ghost_index = -1
		_ghost = Vector2.INF
		queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	_layout()
	var top_left := to_screen(Vector2(AHEAD, -HALF_WIDTH))
	var bottom_right := to_screen(Vector2(-BEHIND, HALF_WIDTH))
	draw_rect(Rect2(top_left, bottom_right - top_left), Color("#2f7d3a"))
	var fs := 12
	for yd in range(-int(BEHIND), int(AHEAD) + 1):
		if yd % 5 != 0:
			continue
		var a := to_screen(Vector2(yd, -HALF_WIDTH))
		var b := to_screen(Vector2(yd, HALF_WIDTH))
		draw_line(a, b, Color("#3fa9f5") if yd == 0 else Color(1, 1, 1, 0.3), 3.0 if yd == 0 else 1.0)
		if yd > 0:
			draw_string(font, a + Vector2(4, -3), "%d" % yd, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.5))
	var side := "sideline  >"
	var w := font.get_string_size(side, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(bottom_right.x - w - 6, bottom_right.y - 6), side, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.6))
	draw_string(font, Vector2(top_left.x + 6, bottom_right.y - 6), "<  middle of the field", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.6))
	draw_rect(Rect2(top_left, bottom_right - top_left), Color(1, 1, 1, 0.6), false, 2.0)
	if route == null:
		return
	_draw_route()


func _draw_route() -> void:
	var path := _path()
	var col := Color(1, 1, 0.75, 0.95)
	for i in range(path.size() - 1):
		draw_line(to_screen(path[i]), to_screen(path[i + 1]), col, 3.0)
	# After the last point the receiver keeps going ("go") or settles ("stop").
	var last := to_screen(path[-1])
	var dir := (last - to_screen(path[-2])).normalized()
	if route.end == Route.GO:
		var tip := last + dir * 4.0 * _scale
		draw_dashed_line(last, tip, col, 2.0, 8.0)
		var s := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip + dir * 10.0, tip + s * 6.0, tip - s * 6.0]), col)
	else:
		var s := Vector2(-dir.y, dir.x)
		draw_line(last + s * 9.0, last - s * 9.0, col, 3.0)
	# The receiver.
	draw_circle(to_screen(Vector2.ZERO), 0.9 * _scale, Color("#4ea1ff"))
	draw_arc(to_screen(Vector2.ZERO), 0.9 * _scale, 0, TAU, 24, Color(0, 0, 0, 0.6), 1.5)
	if not editable:
		return
	for i in route.points.size():
		var p := to_screen(route.points[i])
		var hot := i == _hover_point or i == _dragging
		draw_circle(p, POINT_R + (2.0 if hot else 0.0), UiStyle.ACCENT if hot else Color.WHITE)
		draw_arc(p, POINT_R + (2.0 if hot else 0.0), 0, TAU, 20, Color(0, 0, 0, 0.7), 1.5)
		var n := str(i + 1)
		var nw := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, p + Vector2(-nw * 0.5, 4), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.05, 0.07, 0.1))
	if _ghost_index >= 0:
		var g := to_screen(_ghost)
		draw_circle(g, POINT_R, Color(1, 1, 1, 0.35))
		draw_arc(g, POINT_R, 0, TAU, 20, Color.WHITE, 1.5)
