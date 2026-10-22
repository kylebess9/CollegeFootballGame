class_name KickPlay
extends Resource
## A special teams call (punt, field goal). These are resolved by the game rules in
## GameState, not by the play simulation.

const PUNT := "punt"
const FIELD_GOAL := "field_goal"

@export var name := ""
@export var kind := PUNT
@export var description := ""


static func make(play_name: String, kick_kind: String, desc: String) -> KickPlay:
	var k := KickPlay.new()
	k.name = play_name
	k.kind = kick_kind
	k.description = desc
	return k
