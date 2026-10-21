# AI College Football

A college football management game with Blood Bowl-style dice. Plays run on their own;
dice decide the contested moments, and your roster decides the odds.

## How a play works
Players move automatically based on the play call. Dice settle the key moments:

| Moment | Roll |
|---|---|
| Block | Block dice. Equal Strength = 1 die; small edge = 2 dice; big edge = 3. Stronger side picks: Shed / Stalemate / Push / Drive / Pancake |
| Throw | d6 needs (7 - Passing)+. Quick throws easier, deep throws harder, +1 if hurried. Misses scatter the ball |
| Catch | d6 needs (7 - Hands)+, +1 per defender within 1.6 yds, +1 if off target |
| Interception | Only a defender closer to the ball than the receiver. d6 needs (10 - Hands)+ |
| Tackle | d6 needs 2+, +1 per 2 points runner Agility beats Tackling, -1 per helper, +1 diving |
| Play action | Each linebacker/SS rolls Awareness or bites on the fake |
| Fumble | A natural 6 tackle forces a roll to hold on |

Ratings are 1-6. Skills (Soft Hands, Pass Rusher, Ball Hawk...) give re-rolls or +1s.
Team re-rolls are spent automatically on key catches and tackles.

## Code layout
- `scripts/data/` players, teams, random team generator
- `scripts/sim/` dice, playbook (all plays are data), play simulation, game rules, CPU coach
- `scripts/ui/` menu, roster screen, match screen, field drawing
- `tests/balance_test.gd` runs thousands of plays and prints averages per matchup:
  `godot --headless --script res://tests/balance_test.gd`
- `tests/game_log.gd` prints a whole CPU vs CPU game

## Adding a play
Add an entry to `OFFENSE` or `DEFENSE` in `scripts/sim/playbook.gd`. Routes are listed in `ROUTES`.
