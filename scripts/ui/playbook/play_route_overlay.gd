class_name PlayRouteOverlay
extends RouteCanvas
## Lies over the playbook editor's field. Clicking a player who runs a route in the selected
## pass play picks him; his route's points then show on the field to drag, add to (hover the
## line between two points and click) and right-click away, as in Playbook Routes. The first
## change makes the route the play's own (PassPlay.customize()), so the playbook's routes are
## left alone and his drop-down shows "Custom"; picking a route there swaps it back out.

## The player clicked on, "" when the click wasn't on a route runner.
signal player_selected(slot: String)
## The selected player's route has just become the play's own.
signal customized

const FieldView := preload("res://scripts/ui/field_view.gd")
## The sim keeps route points this far inside the sidelines.
const SIDELINE_MARGIN := 1.5

var field: FieldView # the field this lies over
var play: PassPlay
var sim: PlaySim
var slot := ""
var _actor: SimActor
var _side := 1.0


func _ready() -> void:
	super()
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Points the overlay at the play as the field now shows it. Call it after every redraw of
## the play, since that sets up a new sim.
func attach(p: Resource, s: PlaySim) -> void:
	play = p as PassPlay
	sim = s
	_refresh()


## Picks a player (by slot) whose route to show, or nobody with "".
func select(s: String) -> void:
	slot = s
	_dragging = -1
	_hover_point = -1
	_ghost_index = -1
	_ghost = Vector2.INF
	_refresh()
	player_selected.emit(s)


func _refresh() -> void:
	route = null
	_actor = null
	if play != null and sim != null and play.routes.has(slot) and sim.slots.has("O:" + slot):
		_actor = sim.slots["O:" + slot]
		_side = sim.route_side(_actor)
		route = play.routes[slot]
	editable = route != null
	if not editable:
		_dragging = -1
	set_process(editable)
	queue_redraw()


## The route runner whose dot is at this point on screen, "" if none.
func slot_at(screen: Vector2) -> String:
	if play == null or sim == null:
		return ""
	var reach := (FieldView.DOT_R + 0.5) * _yard()
	for a in sim.offense():
		if play.routes.has(a.slot) and field.to_screen(a.pos).distance_to(screen) <= reach:
			return a.slot
	return ""


# ---------------------------------------------------------------- coordinates

## Pixels per yard on the field.
func _yard() -> float:
	return field.to_screen(Vector2(1, 0)).distance_to(field.to_screen(Vector2.ZERO))


## A route point to the field, the way the sim lays it out for this player.
func _to_field(p: Vector2) -> Vector2:
	var f := _actor.start_pos + Vector2(p.x, p.y * _side)
	return Vector2(minf(f.x, PlaySim.END_LINE_STOP), clampf(f.y, SIDELINE_MARGIN, PlaySim.FIELD_W - SIDELINE_MARGIN))


func to_screen(p: Vector2) -> Vector2:
	return field.to_screen(_to_field(p)) if _actor != null else Vector2.ZERO


func to_route(screen: Vector2) -> Vector2:
	var f := field.to_field(screen)
	f = Vector2(minf(f.x, PlaySim.END_LINE_STOP), clampf(f.y, SIDELINE_MARGIN, PlaySim.FIELD_W - SIDELINE_MARGIN))
	var p := Vector2(f.x - _actor.start_pos.x, (f.y - _actor.start_pos.y) * _side)
	return (p / GRID).round() * GRID


# ---------------------------------------------------------------- editing

func move_point(i: int, to: Vector2) -> bool:
	if not can_move(i, to):
		return false
	_customize()
	return super(i, to)


func insert_point(index: int, at: Vector2) -> void:
	_customize()
	super(index, at)


func remove_point(i: int) -> bool:
	if route.points.size() <= 1:
		return false
	_customize()
	return super(i)


func _customize() -> void:
	if route.name != Route.CUSTOM:
		route = play.customize(slot)
		customized.emit()


func _gui_input(event: InputEvent) -> void:
	if editable:
		super(event)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_clicked_off(event.position)


func _clicked_off(at: Vector2) -> void:
	select(slot_at(at))


func _process(_delta: float) -> void:
	queue_redraw() # the field can move under us (resizes, relayouts)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if not editable or _actor == null:
		return
	var col := UiStyle.ACCENT
	var at := field.to_screen(_actor.pos)
	draw_arc(at, (FieldView.DOT_R + 0.7) * _yard(), 0, TAU, 28, col, 3.0)
	var path := _path()
	for i in range(path.size() - 1):
		draw_line(to_screen(path[i]), to_screen(path[i + 1]), col, 3.0)
	_draw_points()
