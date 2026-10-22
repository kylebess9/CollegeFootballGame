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

## Code layout
- `scripts/data/` players, teams, random team generator
- `scripts/sim/` dice, playbook (all plays are data), play simulation, game rules, CPU coach
- `scripts/ui/` menu, roster screen, match screen, field drawing
- `tests/balance_test.gd` runs thousands of plays and prints averages per matchup:
  `godot --headless --script res://tests/balance_test.gd`
- `tests/game_log.gd` prints a whole CPU vs CPU game
- `tests/playbook_check.gd` checks the stock playbook is legal and that illegal formations are caught

## Adding a play
Plays live in a `Playbook` (`scripts/sim/playbook.gd`); each team gets one through `GameState`.
The building blocks are in `scripts/sim/plays/`:

- `OffensiveFormation`: where the 11 players line up (`FormationSpot`s) and the plays run from it.
  Must be legal: 11 players, at least 7 on the line, at most 4 in the backfield, QB behind the center.
- `PassPlay` / `RunPlay` (both `OffensivePlay`): a pass uses `Route`s (stock ones in `Playbook.ROUTES`).
- `DefensiveFormation`: where the 11 defenders line up; corners and safeties can align over receivers.
- `DefensivePlay`: a `CoverageAssignment` (man, zone or blitz) for every player off the line. Zone
  defenders guard a `Zone` (depth shallow/intermediate/deep, spot left/center/right, width, radius).
- `KickPlay`: Punt and Field Goal.

To add a stock play, add it to its formation in `Playbook.make_default()`, then run
`tests/playbook_check.gd` to make sure it's legal.
