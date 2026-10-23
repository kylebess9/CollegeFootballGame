extends SceneTree
## The QB read display (debug mode, and always in the playbook editor's Run Play):
##   godot --headless --script res://tests/qb_read_check.gd
## - before read_start the read clock is in its "drop" phase and runs down,
## - once he's reading, PlaySim.current_read() is the receiver in reads[read_index], and the
##   clock is in its "read" phase, refilling each time he moves to the next read,
## - once the ball is gone there's no read and no clock,
## - the field draws all of it without errors, and the playbook editor turns it on.
# Loaded once the game is up, since the field view uses the Settings autoload.
var FieldView: GDScript

var fails := 0


func _expect(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	FieldView = load("res://scripts/ui/field_view.gd")
	var gen := TeamGenerator.new(5)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var pb := Playbook.make_default()
	var gs := GameState.new(a, b, 15.0, Dice.new(1))

	var field: Control = FieldView.new()
	field.gs = gs
	field.size = Vector2(1200, 540)
	root.add_child(field)
	_expect(not field.show_qb_reads, "the field leaves the QB's reads off by default")
	await process_frame # the tree (and the Settings autoload) is up from the first frame
	var settings: Node = root.get_node("/root/Settings")
	settings.set_debug_mode(false)
	_expect(not field._qb_reads_on(), "and doesn't draw them outside debug mode")
	settings.set_debug_mode(true)
	_expect(field._qb_reads_on(), "debug mode draws them")
	settings.set_debug_mode(false)

	var drops := 0
	var drop_falls := true
	var reads_seen := 0
	var read_matches := true
	var refills := 0
	var after_throw_clear := true
	for play in pb.offense_plays():
		if not play is PassPlay:
			continue
		var pp := play as PassPlay
		for rep in 6:
			var sim := PlaySim.new()
			sim.setup(a, b, play, pb.defense_plays()[rep % pb.defense_plays().size()], 30.0, 26.6,
				{"down": 1, "to_go": 10}, Dice.new(rep * 31 + 7))
			field.sim = sim
			field.show_qb_reads = rep % 2 == 0
			var last_left := 2.0
			var last_index := -1
			var last_phase := ""
			while not sim.done and sim.t < 12.0:
				sim.step()
				var c := sim.read_clock()
				var read := sim.current_read()
				if not c.is_empty() and c["phase"] == "drop":
					drops += 1
					if float(c["left"]) > last_left + 0.0001:
						drop_falls = false
					last_left = c["left"]
				if read != null:
					reads_seen += 1
					if read != sim.slots["O:" + pp.reads[sim.read_index]] or c.is_empty() or c["phase"] != "read":
						read_matches = false
					if sim.read_index != last_index and last_phase == "read" and float(c["left"]) > 0.9:
						refills += 1
					last_index = sim.read_index
				if sim.qb_state in ["windup", "thrown", "scramble", "handed_off"] and (read != null or not c.is_empty()):
					after_throw_clear = false
				last_phase = "" if c.is_empty() else str(c["phase"])
				if sim.t < 1.0:
					field.queue_redraw()
					await process_frame
			field.sim = null
			sim.dispose()
	print("    drop ticks %d, read ticks %d, read changes %d" % [drops, reads_seen, refills])
	_expect(drops > 0 and drop_falls, "the drop clock runs down until read_start")
	_expect(reads_seen > 0 and read_matches, "the current read is reads[read_index], with the clock on its read phase")
	_expect(refills > 0, "the clock refills when the QB moves to his next read")
	_expect(after_throw_clear, "no read or clock once the ball is out or the QB runs")
	field.queue_free()

	var Editor: GDScript = load("res://scripts/ui/playbook_editor.gd")
	_expect(Editor != null and Editor.can_instantiate(), "the playbook editor compiles")
	var src := FileAccess.get_file_as_string("res://scripts/ui/playbook_editor.gd")
	_expect("field.show_qb_reads = true" in src, "the playbook editor turns the QB's reads on for Run Play")
	await process_frame
	print("qb_read_check: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
