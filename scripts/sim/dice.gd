class_name Dice
extends RefCounted
## Blood Bowl-style dice.
## A "test" rolls one d6 and succeeds when the roll is at least the target.
## Targets are always clamped to 2..6, so a 1 always fails and a 6 always succeeds.

enum Block { SHED, STALEMATE, PUSH, DRIVE, PANCAKE }

const BLOCK_NAMES := {
	Block.SHED: "Shed",
	Block.STALEMATE: "Stalemate",
	Block.PUSH: "Push",
	Block.DRIVE: "Drive",
	Block.PANCAKE: "Pancake",
}

## Faces of the block die, from the blocker's point of view (worst to best).
## Pass protection is about holding ground, so it has no pancakes and fewer sheds than you might fear.
const RUN_BLOCK_FACES := [Block.SHED, Block.STALEMATE, Block.PUSH, Block.PUSH, Block.DRIVE, Block.PANCAKE]
const PASS_BLOCK_FACES := [Block.SHED, Block.STALEMATE, Block.STALEMATE, Block.PUSH, Block.PUSH, Block.DRIVE]

var rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value


func d6() -> int:
	return rng.randi_range(1, 6)


static func clamp_target(target: int) -> int:
	return clampi(target, 2, 6)


## Chance (0..1) of passing a test with this target. Handy for UI and the AI.
static func odds(target: int) -> float:
	return (7.0 - clamp_target(target)) / 6.0


## Strength difference decides how many block dice and who chooses, like Blood Bowl:
## equal = 1 die, small edge = 2 dice, big edge = 3 dice. The stronger side picks the result.
static func block_dice_count(diff: int) -> int:
	if diff == 0:
		return 1
	if absi(diff) <= 2:
		return 2
	return 3


func roll_block(blocker_str: int, defender_str: int, pass_pro: bool) -> Dictionary:
	var diff := blocker_str - defender_str
	var n := block_dice_count(diff)
	var faces: Array = PASS_BLOCK_FACES if pass_pro else RUN_BLOCK_FACES
	var rolls: Array[int] = []
	for i in n:
		rolls.append(d6())
	var pick: int = rolls.max() if diff >= 0 else rolls.min()
	return {
		"rolls": rolls,
		"dice": n,
		"chooser": "blocker" if diff >= 0 else "defender",
		"face": faces[pick - 1],
	}


## Random direction for a bad throw, like the Blood Bowl scatter template.
func scatter(distance: float) -> Vector2:
	var dir := rng.randi_range(0, 7)
	return Vector2.RIGHT.rotated(dir * PI / 4.0) * distance
