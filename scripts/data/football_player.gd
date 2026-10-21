class_name FootballPlayer
extends Resource
## One football player. Ratings run from 1 (poor) to 6 (elite), like Blood Bowl stats.
## Most dice tests use "7 - rating" as the number you need on a d6,
## so a rating of 4 means you need a 3+ (67%), and a rating of 6 means 2+ (83%).

const ATTRS: Array[String] = ["spd", "str", "agi", "hnd", "pas", "tkl", "awr", "kck"]

const ATTR_NAMES := {
	"spd": "Speed",
	"str": "Strength",
	"agi": "Agility",
	"hnd": "Hands",
	"pas": "Passing",
	"tkl": "Tackling",
	"awr": "Awareness",
	"kck": "Kicking",
}

const ATTR_HELP := {
	"spd": "How fast the player runs. Decides who wins footraces and how much separation receivers get.",
	"str": "Blocking power. Compared on both sides of a block to decide how many block dice are rolled and who picks.",
	"agi": "Elusiveness and route cuts. Ball carriers with high agility make tackles harder.",
	"hnd": "Catching, interceptions and holding on to the ball.",
	"pas": "Throw accuracy. Accuracy roll needs (7 - Passing)+, harder for longer throws and under pressure.",
	"tkl": "Tackling. A tackle needs 2+, one step harder for every 2 points the runner's Agility beats your Tackling. Teammates nearby make it easier.",
	"awr": "Football IQ. Reaction time in coverage, QB read speed, biting on play action.",
	"kck": "Kicking power and accuracy for field goals and punts.",
}

## Skills work like Blood Bowl skills: small, specific advantages that matter in certain matchups.
const SKILLS := {
	"Soft Hands": "Re-roll a failed catch.",
	"Ball Security": "Re-roll a failed roll to hold on to the ball when hit.",
	"Elusive": "Tacklers need +1 on their tackle roll against this player.",
	"Sure Tackler": "Re-roll a failed tackle.",
	"Pass Rusher": "+1 Strength when rushing the passer.",
	"Road Grader": "+1 Strength when run blocking.",
	"Anchor": "+1 Strength when pass blocking.",
	"Ball Hawk": "Re-roll a failed interception, and can make a play on the ball from further away.",
	"Accurate": "-1 to the number needed on pass accuracy rolls.",
	"Cannon Arm": "Long and deep throws are one step easier.",
	"Field General": "Reads the field faster and rarely misreads coverage.",
	"Route Technician": "Loses almost no speed when cutting on routes.",
	"Shutdown": "Reacts faster in man coverage.",
}

@export var first_name := ""
@export var last_name := ""
@export var position := "WR"
@export var number := 0
@export var year := 1 # 1 = Freshman ... 4 = Senior
@export var ratings: Dictionary = {}
@export var skills: Array[String] = []


func r(attr: String) -> int:
	return int(ratings.get(attr, 1))


func has_skill(skill: String) -> bool:
	return skills.has(skill)


func short_name() -> String:
	if first_name.is_empty():
		return last_name
	return "%s. %s" % [first_name.substr(0, 1), last_name]


func full_name() -> String:
	return "%s %s" % [first_name, last_name]


func year_label() -> String:
	return ["FR", "SO", "JR", "SR"][clampi(year - 1, 0, 3)]


## A rough 0-99 overall rating, weighted by what matters for the position.
func overall() -> int:
	var w: Dictionary = POSITION_WEIGHTS.get(position, {})
	var total := 0.0
	var wsum := 0.0
	for a in w:
		total += r(a) * float(w[a])
		wsum += float(w[a])
	if wsum <= 0.0:
		return 0
	var avg := total / wsum # 1..6
	return clampi(int(round(40.0 + (avg - 1.0) * 11.8)) + skills.size() * 2, 0, 99)


const POSITION_WEIGHTS := {
	"QB": {"pas": 4, "awr": 3, "agi": 1, "spd": 1},
	"RB": {"spd": 3, "agi": 3, "hnd": 1, "str": 1},
	"WR": {"spd": 3, "hnd": 3, "agi": 2},
	"TE": {"hnd": 2, "str": 2, "spd": 1, "agi": 1},
	"OL": {"str": 4, "awr": 1, "agi": 1},
	"DL": {"str": 3, "tkl": 2, "spd": 1, "agi": 1},
	"LB": {"tkl": 3, "awr": 2, "spd": 2, "str": 1},
	"CB": {"spd": 3, "awr": 2, "agi": 2, "hnd": 1, "tkl": 1},
	"S": {"awr": 3, "spd": 2, "tkl": 2, "hnd": 1},
	"K": {"kck": 1},
}
