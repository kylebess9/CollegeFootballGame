extends Node
## Global game settings (autoload singleton: accessible anywhere as `Settings`).
## This is meant to grow into the backing store for a future settings menu -- add new
## settings here as plain typed fields, each with a setter that emits `changed` so any
## screen showing that setting (a checkbox, say) can stay in sync no matter where it was
## toggled from.

signal changed(key: String, value: Variant)

## When on: clicking a player (in the roster list or on the field during a game) opens
## an editor for their ratings and skills instead of their usual info.
var debug_mode := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		set_debug_mode(not debug_mode)


func set_debug_mode(on: bool) -> void:
	if on == debug_mode:
		return
	debug_mode = on
	changed.emit("debug_mode", debug_mode)
