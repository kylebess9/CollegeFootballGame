extends Control
## Root of the game. Owns the teams and switches between screens.

const MainMenu := preload("res://scripts/ui/main_menu.gd")
const RosterScreen := preload("res://scripts/ui/roster_screen.gd")
const MatchScreen := preload("res://scripts/ui/match_screen.gd")
const PracticeScreen := preload("res://scripts/ui/practice_screen.gd")
const PlaybooksScreen := preload("res://scripts/ui/playbooks_screen.gd")
const PlaybookEditor := preload("res://scripts/ui/playbook_editor.gd")

var my_team: Team
var cpu_team: Team
var quarter_minutes := 8.0
var current: Control


func _ready() -> void:
	theme = UiStyle.make_theme()
	var bg := ColorRect.new()
	bg.color = UiStyle.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	new_teams()
	show_menu()


func new_teams() -> void:
	var gen := TeamGenerator.new()
	var schools := range(TeamGenerator.SCHOOLS.size())
	schools.shuffle()
	var colors := range(TeamGenerator.COLORS.size())
	colors.shuffle()
	my_team = gen.make_team(schools[0], TeamGenerator.COLORS[colors[0]])
	cpu_team = gen.make_team(schools[1], TeamGenerator.COLORS[colors[1]])


func _swap(screen: Control) -> void:
	if current != null:
		current.queue_free()
	current = screen
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)


func show_menu() -> void:
	var m := MainMenu.new()
	m.main = self
	_swap(m)


func show_roster(team: Team) -> void:
	var r := RosterScreen.new()
	r.main = self
	r.team = team
	_swap(r)


func show_match() -> void:
	var m := MatchScreen.new()
	m.main = self
	_swap(m)


func show_practice() -> void:
	var p := PracticeScreen.new()
	p.main = self
	_swap(p)


func show_playbooks() -> void:
	var p := PlaybooksScreen.new()
	p.main = self
	_swap(p)


func show_playbook_editor(pb: Playbook) -> void:
	var e := PlaybookEditor.new()
	e.main = self
	e.playbook = pb
	_swap(e)
