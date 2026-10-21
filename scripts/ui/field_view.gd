extends Control
## Draws the field from above with players as colored dots.
## The home team always attacks to the right. When the away team has the ball,
## the play simulation's coordinates are rotated 180 degrees.

const FIELD_LEN := 120.0
const FIELD_W := 53.333
const DOT_R := 0.85
const POPUP_LIFE := 1.8

var gs: GameState
var sim: PlaySim
var flip := false
var preview := false # true while showing the pre-snap lineup
var popups: Array[Dictionary] = [] # {text, pos (field), color, born}
var clock := 0.0
var font: Font

var _scale := 10.0
var _origin := Vector2.ZERO

const LETTER := {
	"QB": "Q", "RB": "R", "WR1": "W", "WR2": "W", "WR3": "W", "TE": "T",
	"WILL": "L", "MIKE": "M", "SAM": "L", "CB1": "C", "CB2": "C", "SS": "S", "FS": "S",
}


func _ready() -> void:
	font = get_theme_default_font()
	clip_contents = true


func _process(delta: float) -> void:
	clock += delta
	var keep: Array[Dictionary] = []
	for p in popups:
		if clock - float(p["born"]) < POPUP_LIFE:
			keep.append(p)
	popups = keep
	queue_redraw()


func add_popup(text: String, field_pos: Vector2, color: Color) -> void:
	# Store in screen-orientation field coordinates so it stays put if the next play flips.
	var p := field_pos
	if flip:
		p = Vector2(FIELD_LEN - p.x, FIELD_W - p.y)
	popups.append({"text": text, "pos": p, "color": color, "born": clock})


## Field coordinates (as the sim sees them) to screen pixels.
func to_screen(p: Vector2) -> Vector2:
	var q := p
	if flip:
		q = Vector2(FIELD_LEN - p.x, FIELD_W - p.y)
	return _origin + q * _scale


func _layout() -> void:
	_scale = minf(size.x / FIELD_LEN, size.y / FIELD_W)
	_origin = (size - Vector2(FIELD_LEN, FIELD_W) * _scale) * 0.5


func _draw() -> void:
	if gs == null:
		return
	_layout()
	_draw_field()
	_draw_markers()
	if sim != null:
		if not preview:
			_draw_routes()
		_draw_players()
		if not preview:
			_draw_ball()
	_draw_popups()


func _rect_yards(x0: float, x1: float) -> Rect2:
	return Rect2(_origin + Vector2(x0, 0) * _scale, Vector2(x1 - x0, FIELD_W) * _scale)


func _draw_field() -> void:
	var s := _scale
	# Grass stripes every 5 yards
	for i in 20:
		var x0 := 10.0 + i * 5.0
		var c := Color("#2f7d3a") if i % 2 == 0 else Color("#358a41")
		draw_rect(_rect_yards(x0, x0 + 5.0), c)
	# End zones: home defends the left, away defends the right
	var home: Team = gs.teams[GameState.HOME]
	var away: Team = gs.teams[GameState.AWAY]
	draw_rect(_rect_yards(0, 10), home.color.darkened(0.35))
	draw_rect(_rect_yards(110, 120), away.color.darkened(0.35))
	_draw_endzone_text(home.abbrev, 5.0, PI * 0.5)
	_draw_endzone_text(away.abbrev, 115.0, -PI * 0.5)
	# Yard lines
	var white := Color(1, 1, 1, 0.85)
	for i in 21:
		var x := 10.0 + i * 5.0
		var w := 2.0 if i % 2 == 0 else 1.0
		draw_line(_origin + Vector2(x, 0) * s, _origin + Vector2(x, FIELD_W) * s, white, w)
	# Hash marks
	for yd in range(11, 110):
		var x := float(yd)
		for hy in [1.0, PlaySim.HASH_LEFT, PlaySim.HASH_RIGHT, FIELD_W - 1.0]:
			draw_line(_origin + Vector2(x, hy - 0.4) * s, _origin + Vector2(x, hy + 0.4) * s, Color(1, 1, 1, 0.5), 1.0)
	# Numbers
	var fs := int(maxf(10.0, s * 2.2))
	for i in range(1, 10):
		var x := 10.0 + i * 10.0
		var n := i * 10 if i <= 5 else (10 - i) * 10
		var txt := str(n)
		for ny in [8.0, FIELD_W - 6.0]:
			var p := _origin + Vector2(x, ny) * s
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, p - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.55))
	# Border
	draw_rect(Rect2(_origin, Vector2(FIELD_LEN, FIELD_W) * s), Color.WHITE, false, 2.0)


func _draw_endzone_text(txt: String, x: float, angle: float) -> void:
	var fs := int(maxf(12.0, _scale * 4.5))
	var center := _origin + Vector2(x, FIELD_W * 0.5) * _scale
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_set_transform(center, angle)
	draw_string(font, Vector2(-w * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0)


## Line of scrimmage (blue) and first-down line (yellow), from the game state.
func _draw_markers() -> void:
	var off_right := gs.possession == GameState.HOME
	var los_abs := 10.0 + (gs.ball_on if off_right else 100.0 - gs.ball_on)
	var fd := gs.ball_on + gs.to_go
	if sim != null and not preview:
		# During and right after a play keep showing the line of scrimmage it started from.
		# gs.ball_on/to_go (and so fd) don't change until the play is applied, so the yellow
		# line-to-gain stays correct and visible the whole time too.
		los_abs = sim.los if not flip else FIELD_LEN - sim.los
	var s := _scale
	draw_line(_origin + Vector2(los_abs, 0) * s, _origin + Vector2(los_abs, FIELD_W) * s, Color("#3fa9f5"), 3.0)
	if fd > 0.0 and fd < 100.0:
		var fd_abs := 10.0 + (fd if off_right else 100.0 - fd)
		draw_line(_origin + Vector2(fd_abs, 0) * s, _origin + Vector2(fd_abs, FIELD_W) * s, Color("#ffd400"), 3.0)
	if sim == null or preview:
		var y := gs.spot_y if off_right else FIELD_W - gs.spot_y
		draw_circle(_origin + Vector2(los_abs, y) * s, s * 0.45, Color("#8b5a2b"))


## Planned routes are captured once at the snap, so the lines stay fixed while the play
## develops (players can then be seen breaking off their route, e.g. to go get a thrown ball).
var _routes_for: PlaySim = null
var _routes: Array = [] # each entry: PackedVector2Array of field points


func _capture_routes() -> void:
	_routes_for = sim
	_routes.clear()
	for a in sim.actors:
		if a.side != SimActor.Side.OFFENSE or a.path.is_empty():
			continue
		if not (a.job == "route" or a.job == "rb_run"):
			continue
		var pts := PackedVector2Array([a.start_pos])
		pts.append_array(PackedVector2Array(a.path))
		if a.job == "route" and a.path_end == "go":
			var last: Vector2 = a.path[a.path.size() - 1]
			var before: Vector2 = a.start_pos if a.path.size() == 1 else a.path[a.path.size() - 2]
			var dir := (last - before).normalized()
			var ext := last + dir * 8.0
			ext.y = clampf(ext.y, 1.0, FIELD_W - 1.0)
			ext.x = minf(ext.x, PlaySim.END_LINE_STOP)
			pts.append(ext)
		_routes.append(pts)


func _draw_routes() -> void:
	if _routes_for != sim:
		_capture_routes()
	for pts in _routes:
		for i in range(1, pts.size()):
			var alpha := 0.12 if i == pts.size() - 1 and pts.size() > 2 else 0.22
			draw_line(to_screen(pts[i - 1]), to_screen(pts[i]), Color(1, 1, 1, alpha), 2.0)


func _draw_players() -> void:
	var r := DOT_R * _scale
	# Blocks: a short gray bar between engaged players
	for a in sim.actors:
		if a.engaged != null and a.side == SimActor.Side.OFFENSE:
			draw_line(to_screen(a.pos), to_screen(a.engaged.pos), Color(1, 1, 1, 0.35), 3.0)
	var lfs := int(maxf(8.0, _scale * 1.0))
	for a in sim.actors:
		var team: Team = sim.off_team if a.side == SimActor.Side.OFFENSE else sim.def_team
		var col := team.color
		var p := to_screen(a.pos)
		if not a.is_up():
			col = col.darkened(0.55)
			col.a = 0.75
		draw_circle(p, r, col)
		draw_arc(p, r, 0, TAU, 20, Color(0, 0, 0, 0.6), 1.5)
		if a == sim.holder:
			draw_arc(p, r + 2.5, 0, TAU, 24, Color.WHITE, 2.5)
		if not a.is_up():
			var d := r * 0.6
			draw_line(p - Vector2(d, d), p + Vector2(d, d), Color(0, 0, 0, 0.8), 2.0)
			draw_line(p - Vector2(d, -d), p + Vector2(d, -d), Color(0, 0, 0, 0.8), 2.0)
		elif LETTER.has(a.slot):
			var t: String = LETTER[a.slot]
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
			draw_string(font, p + Vector2(-w * 0.5, lfs * 0.38), t, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(1, 1, 1, 0.95))


func _draw_ball() -> void:
	var bp := to_screen(sim.ball_pos)
	if sim.ball_in_air:
		var target := to_screen(sim.ball_to)
		var d := _scale * 0.6
		draw_line(target - Vector2(d, d), target + Vector2(d, d), Color("#ffd400"), 2.0)
		draw_line(target - Vector2(d, -d), target + Vector2(d, -d), Color("#ffd400"), 2.0)
		# Shadow plus a raised ball to suggest an arc
		var f := clampf(sim.ball_flight / maxf(sim.ball_flight_time, 0.01), 0.0, 1.0)
		var lift := sin(f * PI) * _scale * minf(4.0, sim.ball_flight_time * 2.0)
		draw_circle(bp, _scale * 0.35, Color(0, 0, 0, 0.35))
		_draw_football(bp - Vector2(0, lift), 1.3)
	elif sim.holder != null:
		_draw_football(bp + Vector2(_scale * 0.6, -_scale * 0.6), 1.0)
	elif not sim.done:
		_draw_football(bp, 1.0)


func _draw_football(p: Vector2, k: float) -> void:
	var rx := _scale * 0.55 * k
	var ry := _scale * 0.36 * k
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(p + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, Color("#8b5a2b"))
	draw_line(p - Vector2(rx * 0.5, 0), p + Vector2(rx * 0.5, 0), Color.WHITE, 1.0)


func _draw_popups() -> void:
	var fs := 15
	for pop in popups:
		var age := clock - float(pop["born"])
		var k := age / POPUP_LIFE
		var p := _origin + (pop["pos"] as Vector2) * _scale + Vector2(0, -_scale * 1.6 - age * 18.0)
		var txt: String = pop["text"]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col: Color = pop["color"]
		col.a = 1.0 - k * k
		var bg := Color(0, 0, 0, 0.55 * (1.0 - k * k))
		draw_rect(Rect2(p + Vector2(-w * 0.5 - 4, -fs), Vector2(w + 8, fs + 6)), bg)
		draw_string(font, p + Vector2(-w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
