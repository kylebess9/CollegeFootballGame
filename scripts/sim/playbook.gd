class_name Playbook
extends RefCounted
## All play calls live here as plain data so new plays are easy to add.
##
## Route waypoints are (yards downfield, yards toward the sideline) from where the player lines up.
## Negative "toward the sideline" means cutting inside. After the last point the player either
## keeps running in the same direction ("go") or settles where he is ("stop").

const ROUTES := {
	"go": {"points": [Vector2(45, 0)], "end": "go"},
	"slant": {"points": [Vector2(2, 0), Vector2(7, -5)], "end": "go"},
	"post": {"points": [Vector2(11, 0), Vector2(26, -8)], "end": "go"},
	"corner": {"points": [Vector2(10, 0), Vector2(22, 7)], "end": "go"},
	"curl": {"points": [Vector2(12, 0), Vector2(10.5, -1)], "end": "stop"},
	"out": {"points": [Vector2(8, 0), Vector2(8, 6)], "end": "go"},
	"dig": {"points": [Vector2(11, 0), Vector2(11, -12)], "end": "go"},
	"hitch": {"points": [Vector2(6, 0), Vector2(5, 0)], "end": "stop"},
	"seam": {"points": [Vector2(30, 0)], "end": "go"},
	"flat": {"points": [Vector2(1, 4), Vector2(3, 9)], "end": "stop"},
	"swing": {"points": [Vector2(-1, 4), Vector2(1, 9)], "end": "stop"},
}

const OFFENSE := {
	"Inside Run": {
		"type": "run", "run_path": "inside",
		"desc": "Handoff between the tackles. Linemen block the man in front of them; the center climbs to the middle linebacker.",
	},
	"Outside Run": {
		"type": "run", "run_path": "outside",
		"desc": "Toss to the edge. Needs a fast back and receivers who can block corners.",
	},
	"Quick Slants": {
		"type": "pass", "drop": 5.5, "read_start": 0.75, "play_action": false,
		"routes": {"WR1": "slant", "WR2": "slant", "WR3": "slant", "TE": "flat"},
		"protect": ["RB"],
		"reads": ["WR3", "WR1", "WR2", "TE"],
		"desc": "3-step drop, quick throw. Beats the blitz; weak against tight man coverage.",
	},
	"Curl Flat": {
		"type": "pass", "drop": 7.0, "read_start": 1.3, "play_action": false,
		"routes": {"WR1": "curl", "WR2": "curl", "WR3": "out", "TE": "seam", "RB": "swing"},
		"protect": [],
		"reads": ["WR1", "WR3", "WR2", "RB"],
		"desc": "Intermediate timing throws that sit down in holes in zone coverage.",
	},
	"Four Verticals": {
		"type": "pass", "drop": 8.0, "read_start": 1.9, "play_action": false,
		"routes": {"WR1": "go", "WR2": "go", "WR3": "seam", "TE": "seam"},
		"protect": ["RB"],
		"reads": ["WR3", "TE", "WR2", "WR1"],
		"desc": "Everyone goes deep. Big plays if the line holds and the receivers are fast.",
	},
	"PA Deep Shot": {
		"type": "pass", "drop": 8.0, "read_start": 2.2, "play_action": true,
		"routes": {"WR1": "post", "WR2": "corner", "WR3": "dig", "TE": "flat"},
		"protect": ["RB"],
		"reads": ["WR1", "WR2", "WR3", "TE"],
		"desc": "Fake handoff, then throw deep. Linebackers with low Awareness bite on the fake.",
	},
	"Dig Cross": {
		"type": "pass", "drop": 7.0, "read_start": 1.5, "play_action": false,
		"routes": {"WR1": "dig", "WR2": "post", "WR3": "hitch", "TE": "out", "RB": "swing"},
		"protect": [],
		"reads": ["WR1", "WR3", "TE", "RB"],
		"desc": "Crossing routes that punish man coverage with speed and route running.",
	},
}

## Special teams calls handled directly by the game rules, not the play simulation.
const SPECIAL := ["Punt", "Field Goal"]

## Defensive assignments.
##   rush  - rush the passer / attack the run
##   blitz - linebacker or DB rushing
##   man   - follow one receiver
##   zone  - guard an area: dx yards past the line, and either fy (fraction of field width)
##           or dy (yards from the ball), with radius r
const DEFENSE := {
	"Cover 3": {
		"desc": "Three deep, four underneath. Solid against everything, rarely great.",
		"assign": {
			"CB1": {"type": "zone", "dx": 17, "fy": 0.17, "r": 9},
			"CB2": {"type": "zone", "dx": 17, "fy": 0.83, "r": 9},
			"FS": {"type": "zone", "dx": 19, "fy": 0.5, "r": 10},
			"SS": {"type": "zone", "dx": 6, "dy": -10, "r": 6},
			"WILL": {"type": "zone", "dx": 7, "dy": -4, "r": 5},
			"MIKE": {"type": "zone", "dx": 7, "dy": 3, "r": 5},
			"SAM": {"type": "zone", "dx": 6, "dy": 10, "r": 6},
		},
	},
	"Cover 2": {
		"desc": "Corners squat in the flats, two safeties split the deep field. Weak deep down the middle.",
		"assign": {
			"CB1": {"type": "zone", "dx": 5, "fy": 0.13, "r": 6},
			"CB2": {"type": "zone", "dx": 5, "fy": 0.87, "r": 6},
			"SS": {"type": "zone", "dx": 17, "fy": 0.27, "r": 11},
			"FS": {"type": "zone", "dx": 17, "fy": 0.73, "r": 11},
			"WILL": {"type": "zone", "dx": 8, "dy": -6, "r": 5},
			"MIKE": {"type": "zone", "dx": 10, "dy": 0, "r": 5},
			"SAM": {"type": "zone", "dx": 8, "dy": 6, "r": 5},
		},
	},
	"Cover 1 Man": {
		"desc": "Man coverage on every receiver with one deep safety. Your DBs need speed and Awareness.",
		"assign": {
			"CB1": {"type": "man", "target": "WR1"},
			"CB2": {"type": "man", "target": "WR2"},
			"SS": {"type": "man", "target": "WR3"},
			"SAM": {"type": "man", "target": "TE"},
			"WILL": {"type": "man", "target": "RB"},
			"MIKE": {"type": "zone", "dx": 6, "dy": 0, "r": 6},
			"FS": {"type": "zone", "dx": 17, "fy": 0.5, "r": 14},
		},
	},
	"Blitz": {
		"desc": "Six rushers and man coverage with no safety help. High risk, high reward.",
		"assign": {
			"CB1": {"type": "man", "target": "WR1"},
			"CB2": {"type": "man", "target": "WR2"},
			"SS": {"type": "man", "target": "WR3"},
			"FS": {"type": "man", "target": "TE"},
			"SAM": {"type": "man", "target": "RB"},
			"WILL": {"type": "blitz"},
			"MIKE": {"type": "blitz"},
		},
	},
	"Run Stuff": {
		"desc": "Strong safety creeps down and linebackers attack the line on the snap. Vulnerable to play action.",
		"run_first": true,
		"assign": {
			"CB1": {"type": "zone", "dx": 15, "fy": 0.17, "r": 9},
			"CB2": {"type": "zone", "dx": 15, "fy": 0.83, "r": 9},
			"FS": {"type": "zone", "dx": 16, "fy": 0.5, "r": 11},
			"SS": {"type": "zone", "dx": 5, "dy": -6, "r": 5},
			"WILL": {"type": "zone", "dx": 5, "dy": -4, "r": 5},
			"MIKE": {"type": "zone", "dx": 5, "dy": 2, "r": 5},
			"SAM": {"type": "zone", "dx": 5, "dy": 7, "r": 5},
		},
	},
}


static func offense_names() -> Array:
	return OFFENSE.keys()


static func defense_names() -> Array:
	return DEFENSE.keys()


static func is_run(play_name: String) -> bool:
	return OFFENSE.has(play_name) and OFFENSE[play_name]["type"] == "run"
