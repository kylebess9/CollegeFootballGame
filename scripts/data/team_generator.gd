class_name TeamGenerator
extends RefCounted
## Builds random teams. Later this will be replaced by recruiting, but it gives us opponents now.

const ROSTER_COUNTS := {
	"QB": 2, "RB": 3, "WR": 5, "TE": 2, "OL": 8,
	"DL": 6, "LB": 5, "CB": 4, "S": 3, "K": 1,
}

## Average rating for each position (1-6 scale). Players vary around these.
const ARCHETYPES := {
	"QB": {"spd": 3.0, "str": 2.0, "agi": 3.0, "hnd": 2.5, "pas": 4.0, "tkl": 1.0, "awr": 3.8, "kck": 1.0},
	"RB": {"spd": 4.5, "str": 3.0, "agi": 4.0, "hnd": 3.0, "pas": 1.0, "tkl": 1.5, "awr": 3.0, "kck": 1.0},
	"WR": {"spd": 4.8, "str": 2.0, "agi": 4.0, "hnd": 4.0, "pas": 1.0, "tkl": 1.0, "awr": 3.0, "kck": 1.0},
	"TE": {"spd": 3.5, "str": 3.8, "agi": 3.0, "hnd": 3.5, "pas": 1.0, "tkl": 1.5, "awr": 3.0, "kck": 1.0},
	"OL": {"spd": 1.5, "str": 4.3, "agi": 2.0, "hnd": 1.0, "pas": 1.0, "tkl": 1.0, "awr": 3.0, "kck": 1.0},
	"DL": {"spd": 2.5, "str": 4.3, "agi": 2.5, "hnd": 1.5, "pas": 1.0, "tkl": 3.5, "awr": 3.0, "kck": 1.0},
	"LB": {"spd": 3.5, "str": 3.5, "agi": 3.0, "hnd": 2.5, "pas": 1.0, "tkl": 4.0, "awr": 3.5, "kck": 1.0},
	"CB": {"spd": 4.8, "str": 2.0, "agi": 4.0, "hnd": 3.0, "pas": 1.0, "tkl": 3.0, "awr": 3.3, "kck": 1.0},
	"S": {"spd": 4.3, "str": 2.5, "agi": 3.5, "hnd": 3.0, "pas": 1.0, "tkl": 3.5, "awr": 3.8, "kck": 1.0},
	"K": {"spd": 2.0, "str": 1.5, "agi": 2.0, "hnd": 1.5, "pas": 1.5, "tkl": 1.0, "awr": 2.5, "kck": 4.0},
}

const POSITION_SKILLS := {
	"QB": ["Accurate", "Cannon Arm", "Field General", "Elusive"],
	"RB": ["Elusive", "Ball Security", "Soft Hands"],
	"WR": ["Soft Hands", "Route Technician", "Elusive", "Ball Security"],
	"TE": ["Soft Hands", "Road Grader", "Anchor", "Route Technician"],
	"OL": ["Road Grader", "Anchor"],
	"DL": ["Pass Rusher", "Sure Tackler"],
	"LB": ["Sure Tackler", "Pass Rusher", "Ball Hawk"],
	"CB": ["Shutdown", "Ball Hawk", "Sure Tackler"],
	"S": ["Ball Hawk", "Sure Tackler", "Shutdown"],
	"K": [],
}

const FIRST_NAMES := [
	"Aaron", "Andre", "Ben", "Brady", "Caleb", "Cam", "Carter", "Chris", "Cole", "Corey",
	"Dante", "Darius", "Devin", "Drew", "Eli", "Evan", "Gavin", "Grant", "Hunter", "Isaiah",
	"Jace", "Jalen", "Jamal", "Jordan", "Josh", "Justin", "Kade", "Keon", "Kyle", "Landon",
	"Logan", "Malik", "Marcus", "Mason", "Miles", "Nate", "Noah", "Owen", "Quinn", "Reggie",
	"Ryan", "Sam", "Terrell", "Trey", "Tyler", "Wade", "Xavier", "Zach",
]

const LAST_NAMES := [
	"Adams", "Allen", "Baker", "Banks", "Bell", "Brooks", "Bryant", "Carter", "Coleman", "Cooper",
	"Davis", "Dixon", "Ellis", "Fields", "Fisher", "Foster", "Graham", "Grant", "Hayes", "Henderson",
	"Hill", "Holmes", "Howard", "Jackson", "James", "Jenkins", "Johnson", "Kelly", "King", "Lewis",
	"Marshall", "Mason", "Mitchell", "Moore", "Morgan", "Murray", "Nelson", "Owens", "Parker", "Patterson",
	"Price", "Reed", "Reynolds", "Robinson", "Russell", "Sanders", "Simmons", "Stewart", "Thomas", "Turner",
	"Walker", "Ward", "Washington", "Watson", "Wells", "White", "Williams", "Wright", "Young",
]

const SCHOOLS := [
	["Carver State", "Comets", "CSU"], ["Lakemont", "Lumberjacks", "LKM"],
	["Ridgeview Tech", "Rams", "RVT"], ["Pinecrest", "Panthers", "PIN"],
	["Bay City", "Mariners", "BAY"], ["Granite Falls", "Grizzlies", "GRF"],
	["Southmoor", "Stallions", "SMR"], ["Westbrook A&M", "Wranglers", "WAM"],
	["Harbor Point", "Herons", "HPT"], ["Ironwood", "Owls", "IRW"],
]

const COLORS := [
	Color("#2f6fde"), Color("#d23b3b"), Color("#2fa35a"), Color("#e08a1e"),
	Color("#8a4fd1"), Color("#1fa7a7"), Color("#c9a227"), Color("#d14f9a"),
]

const NUMBER_RANGES := {
	"QB": [1, 19], "RB": [20, 39], "WR": [1, 19], "TE": [80, 89], "OL": [50, 79],
	"DL": [90, 99], "LB": [40, 59], "CB": [20, 39], "S": [20, 49], "K": [1, 19],
}

var rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value


## talent shifts every rating up or down (0.0 = average program).
func make_team(school_index: int, color: Color, talent: float = 0.0) -> Team:
	var t := Team.new()
	var s: Array = SCHOOLS[school_index % SCHOOLS.size()]
	t.school = s[0]
	t.mascot = s[1]
	t.abbrev = s[2]
	t.color = color
	t.rerolls = rng.randi_range(2, 4)
	var used_numbers := {}
	for pos in ROSTER_COUNTS:
		for i in int(ROSTER_COUNTS[pos]):
			t.roster.append(make_player(pos, talent, used_numbers))
	return t


func make_player(pos: String, talent: float = 0.0, used_numbers: Dictionary = {}) -> FootballPlayer:
	var p := FootballPlayer.new()
	p.position = pos
	p.first_name = FIRST_NAMES[rng.randi() % FIRST_NAMES.size()]
	p.last_name = LAST_NAMES[rng.randi() % LAST_NAMES.size()]
	p.year = rng.randi_range(1, 4)
	var arch: Dictionary = ARCHETYPES[pos]
	var ratings := {}
	for a in FootballPlayer.ATTRS:
		var mean: float = float(arch[a]) + talent + (p.year - 2.5) * 0.15
		var v := int(round(rng.randfn(mean, 0.75)))
		ratings[a] = clampi(v, 1, 6)
	p.ratings = ratings
	var pool: Array = POSITION_SKILLS[pos]
	if not pool.is_empty() and rng.randf() < 0.3:
		p.skills.append(pool[rng.randi() % pool.size()])
		if rng.randf() < 0.2:
			var second: String = pool[rng.randi() % pool.size()]
			if not p.skills.has(second):
				p.skills.append(second)
	var nr: Array = NUMBER_RANGES[pos]
	for attempt in 50:
		var n := rng.randi_range(nr[0], nr[1])
		if not used_numbers.has(n):
			used_numbers[n] = true
			p.number = n
			break
	return p
