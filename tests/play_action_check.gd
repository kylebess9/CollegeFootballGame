extends SceneTree
## Play-action fakes: linebackers and shallow safeties must read the fake whatever the
## formation calls them, and deep safeties and corners must not. Uses the stock 4-3 and a
## custom nickel front (two LBs, three corners, safeties named S1/S2) like one built in the
## playbook editor.
##   godot --headless --script res://tests/play_action_check.gd

const RUNS := 300

var fails := 0
var _keep: Array[DefensiveFormation] = [] # plays hold their formation weakly


func _init() -> void:
	var gen := TeamGenerator.new(3)
	var dice := Dice.new(4)
	var a := gen.make_team(0, Color.BLUE)
	var b := gen.make_team(1, Color.RED)
	var pb := Playbook.make_default()
	var pa := pb.offense_play("PA Deep Shot")

	_check("Stock 4-3 Cover 3", _bites(a, b, pa, pb.defense_play("Cover 3"), dice),
		["WILL", "MIKE", "SAM", "SS"], ["FS", "CB1", "CB2"])
	_check("Custom nickel", _bites(a, b, pa, _nickel(), dice),
		["LB1", "LB2", "S1"], ["S2", "CB1", "CB2", "CB3"])

	_keep.clear()
	print("FAIL" if fails > 0 else "OK")
	quit(1 if fails > 0 else 0)


## How many times each defensive slot bit on the fake over RUNS plays.
func _bites(a: Team, b: Team, off: OffensivePlay, de: DefensivePlay, dice: Dice) -> Dictionary:
	var count := {}
	for i in RUNS:
		var sim := PlaySim.new()
		sim.setup(a, b, off, de, 40.0, 26.67, {"down": 1, "to_go": 10}, dice)
		sim.run_to_end()
		for e in sim.events:
			var txt: String = e["text"]
			if txt.contains("bites on the fake"):
				var slot := txt.split(" ")[0]
				count[slot] = count.get(slot, 0) + 1
		sim.dispose()
	return count


func _check(label: String, bites: Dictionary, should: Array, never: Array) -> void:
	print("%s: %s" % [label, bites])
	for s in should:
		if bites.get(s, 0) == 0:
			print("  %s never bit on the fake" % s)
			fails += 1
	for s in never:
		if bites.get(s, 0) > 0:
			print("  %s bit on the fake but shouldn't read it" % s)
			fails += 1


## Four down linemen, two linebackers, three corners, a box safety and a deep safety, all
## in zone, using the generic slot names the formation builder gives non-standard counts.
func _nickel() -> DefensivePlay:
	var spots: Array[FormationSpot] = [
		FormationSpot.make("DL1", "DL", Vector2(1.0, -4.0)),
		FormationSpot.make("DL2", "DL", Vector2(1.0, -1.0)),
		FormationSpot.make("DL3", "DL", Vector2(1.0, 1.2)),
		FormationSpot.make("DL4", "DL", Vector2(1.0, 3.7)),
		FormationSpot.make("LB1", "LB", Vector2(5.0, -2.5)),
		FormationSpot.make("LB2", "LB", Vector2(5.0, 2.5)),
		FormationSpot.make("CB1", "CB", Vector2(6.0, 0.0), "left_1"),
		FormationSpot.make("CB2", "CB", Vector2(6.0, 0.0), "right_1"),
		FormationSpot.make("CB3", "CB", Vector2(5.0, 0.0), "left_2"),
		FormationSpot.make("S1", "S", Vector2(7.0, 3.0)),
		FormationSpot.make("S2", "S", Vector2(13.0, 0.0)),
	]
	var f := DefensiveFormation.make("Nickel", spots)
	var L := Zone.Spot.LEFT
	var R := Zone.Spot.RIGHT
	var C := Zone.Spot.CENTER
	var SH := Zone.Depth.SHALLOW
	var MID := Zone.Depth.INTERMEDIATE
	var DP := Zone.Depth.DEEP
	var play := f.add_play(DefensivePlay.make("Nickel 3", "", [
		CoverageAssignment.in_zone("CB1", Zone.make("Deep Third Left", DP, L, 9, 0.66, 17)),
		CoverageAssignment.in_zone("CB2", Zone.make("Deep Third Right", DP, R, 9, 0.66, 17)),
		CoverageAssignment.in_zone("S2", Zone.make("Deep Middle", DP, C, 10, 0.0, 19)),
		CoverageAssignment.in_zone("CB3", Zone.make("Curl Flat Left", SH, L, 6, 0.375, 6)),
		CoverageAssignment.in_zone("S1", Zone.make("Curl Flat Right", SH, R, 6, 0.375, 6)),
		CoverageAssignment.in_zone("LB1", Zone.make("Hook Left", MID, L, 5, 0.15, 7)),
		CoverageAssignment.in_zone("LB2", Zone.make("Hook Right", MID, R, 5, 0.11, 7)),
	]))
	if not f.is_legal():
		print("Nickel formation is illegal: %s" % [f.validate()])
		fails += 1
	_keep.append(f)
	return play
