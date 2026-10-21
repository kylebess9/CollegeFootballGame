class_name Team
extends Resource
## A college program: its roster plus team-wide traits.

@export var school := ""
@export var mascot := ""
@export var abbrev := ""
@export var color := Color.BLUE
@export var roster: Array[FootballPlayer] = []

const OFFENSE_SLOTS: Array[String] = ["QB", "RB", "WR1", "WR2", "WR3", "TE", "LT", "LG", "C", "RG", "RT"]
const DEFENSE_SLOTS: Array[String] = ["DE1", "DT1", "DT2", "DE2", "WILL", "MIKE", "SAM", "CB1", "CB2", "SS", "FS"]


func display_name() -> String:
	return "%s %s" % [school, mascot]


func players_at(pos: String) -> Array[FootballPlayer]:
	var out: Array[FootballPlayer] = []
	for p in roster:
		if p.position == pos:
			out.append(p)
	out.sort_custom(func(a: FootballPlayer, b: FootballPlayer) -> bool: return a.overall() > b.overall())
	return out


## Picks the best player for every starting slot. A real depth chart editor comes later.
func depth_chart() -> Dictionary:
	var d := {}
	var qbs := players_at("QB")
	var rbs := players_at("RB")
	var wrs := players_at("WR")
	var tes := players_at("TE")
	var ol := players_at("OL")
	var dl := players_at("DL")
	var lbs := players_at("LB")
	var cbs := players_at("CB")
	var ss := players_at("S")
	var ks := players_at("K")
	d["QB"] = qbs[0]
	d["RB"] = rbs[0]
	d["WR1"] = wrs[0]
	d["WR2"] = wrs[1]
	d["WR3"] = wrs[2]
	d["TE"] = tes[0]
	# Best two linemen protect the edges, then center, then guards.
	d["LT"] = ol[0]
	d["RT"] = ol[1]
	d["C"] = ol[2]
	d["LG"] = ol[3]
	d["RG"] = ol[4]
	# Faster DL on the edge, stronger inside.
	var top_dl := dl.slice(0, 4)
	top_dl.sort_custom(func(a: FootballPlayer, b: FootballPlayer) -> bool: return a.r("spd") > b.r("spd"))
	d["DE1"] = top_dl[0]
	d["DE2"] = top_dl[1]
	d["DT1"] = top_dl[2]
	d["DT2"] = top_dl[3]
	d["WILL"] = lbs[0]
	d["MIKE"] = lbs[1]
	d["SAM"] = lbs[2]
	d["CB1"] = cbs[0]
	d["CB2"] = cbs[1]
	var top_s := ss.slice(0, 2)
	top_s.sort_custom(func(a: FootballPlayer, b: FootballPlayer) -> bool: return a.r("tkl") > b.r("tkl"))
	d["SS"] = top_s[0]
	d["FS"] = top_s[1]
	d["K"] = ks[0]
	return d


func team_overall() -> int:
	var dc := depth_chart()
	var total := 0
	for slot in OFFENSE_SLOTS + DEFENSE_SLOTS:
		total += (dc[slot] as FootballPlayer).overall()
	return int(round(total / 22.0))
