# CLAUDE.md

Conventions for any Claude session working on this repo. Read this before making changes.

## What this is

A college football management/sim game in Godot 4 (GDScript only — no C#, for web-export
portability). Plays resolve automatically (no manual player control, unlike Blood Bowl);
dice decide contested moments, and roster attributes set the odds. See `README.md` for the
dice-mechanics table and code layout.

## Workflow: Issues + PRs, always

The user tracks work as **GitHub Issues** and reviews changes as **Pull Requests**. Never
push directly to `main`.

1. Start from an issue (the user will give you a number or describe the work; if it's not
   filed yet, you can create the issue yourself with `gh api repos/kylebess9/collegefootballgame/issues`).
2. Branch from `main`: `git checkout main && git pull && git checkout -b fix/short-name` or
   `feature/short-name`.
3. Make the change.
4. Run the relevant headless tests before opening the PR (see Testing below). Don't skip this
   — several past bugs (touchdown scoring, out-of-bounds catches) were only caught by running
   thousands of simulated plays, not by reading the code.
5. Commit, push, open a PR with `gh api repos/kylebess9/collegefootballgame/pulls` that
   references/closes the issue (`Closes #N`).
6. Leave it for the user to review and merge in GitHub Desktop. Don't merge it yourself unless
   asked.

**`gh issue create` / `gh pr create` fail in this environment with a GraphQL 403.** Use the
REST endpoints instead:
```
gh api repos/kylebess9/collegefootballgame/issues -f title="..." -f body="..."
gh api repos/kylebess9/collegefootballgame/pulls -f title="..." -f head="branch-name" -f base="main" -f body="..."
```

## Testing

Headless Godot runs a `.gd` script with no editor/display:
```
godot --headless --script res://tests/balance_test.gd
```
- `tests/balance_test.gd` — runs each offense/defense play matchup thousands of times, prints
  average yards, success rate, completion %, sack/turnover/big-play rates, and simulates 20
  full CPU-vs-CPU games for points-per-game. Use this to compare before/after a change so you
  can see its effect, but there is no target points-per-game or yards-per-play right now —
  the sim is still being actively reworked (blocking/pursuit logic especially) and scoring
  levels are expected to swing a lot run to run. Report notable before/after swings when you
  make a change, but don't treat hitting an old number as a goal in itself.
- `tests/game_log.gd` — prints full play-by-play of one CPU-vs-CPU game. Use for spot-checking
  a specific mechanic's behavior in context.
- `tests/playbook_check.gd` — checks the stock playbook is legal and that illegal formations and
  plays are rejected. Run it after adding or changing plays.
- `tests/playbook_editor_check.gd` — user playbooks (Manage Playbooks): new ones start legal,
  edits save and reload, and the editor screens build and can be clicked through. Run it after
  touching the playbook classes, `playbook_store.gd` or the editor UI. It saves to
  `user://test_playbooks`, never the user's own playbooks.
- `tests/redzone_check.gd` — regression test: scans every play for scoring/boundary bugs
  (a play ending in the end zone without being scored as a TD, a catch/interception recorded
  out of bounds). Extend this file's checks when you fix a new class of edge-case bug, so it
  stays caught.

When touching `scripts/sim/play_sim.gd`, `game_state.gd`, or `dice.gd`, always run
`balance_test.gd` before and after (e.g. via `git stash`) and compare, since small probability
changes compound over thousands of plays.

If running headless Godot repeatedly in one session, call `sim.dispose()` on each `PlaySim`
after use — it has reference cycles that leak memory otherwise (see existing test scripts for
the pattern).

## Code layout

- `scripts/data/` — `football_player.gd` (attributes, skills, overall rating),
  `team.gd`, `team_generator.gd` (random roster generation — there's no recruiting/drafting
  system yet, this is a placeholder), `playbook_store.gd` (saves the user's playbooks).
- `scripts/sim/` — `dice.gd`, `playbook.gd` (a team's playbook; the stock one is built in
  `Playbook.make_default()` — plays are data, not code, add new plays there), `plays/` (the
  formation/play/route/zone classes a playbook is made of; formations validate their own legality),
  `sim_actor.gd`, `play_sim.gd` (**the core simulation; largest and most sensitive file** —
  movement, QB decision logic, blocking, catching, tackling, boundaries, scoring),
  `game_state.gd` (score/clock/downs/possession), `coach_ai.gd` (CPU play-calling).
- `scripts/ui/` — menu, roster screen, match screen, field drawing (`field_view.gd`),
  `playbooks_screen.gd` (Manage Playbooks) and `playbook_editor.gd`, whose parts (formation list,
  play options panel, dialogs, drawn icon buttons, and the formation builder: `formation_draft.gd`
for its rules, `formation_board.gd` / `player_tray.gd` / `formation_panel.gd` for its UI) are in
`scripts/ui/playbook/`. Custom
  playbooks aren't used in games yet; `GameState` still gives both teams the stock one.
- `tests/` — see Testing above.

## Design constraints to respect

- **No fantasy/violence elements.** No killing or injuring players as a mechanic.
- **GDScript only**, not C# — this is a hard requirement for web export.
- **Luck is manipulable through team building.** Every dice roll in `play_sim.gd` should trace
  back to a player attribute or skill. If you add a new contested moment, give it a
  `(7 - rating)+` style formula (or similar) rather than a flat probability.
- **In-game AI favors learnability over realism.** Mistakes the player can learn from should
  be obvious (e.g. a zone defender who doesn't react until a receiver crosses into their zone).
  Don't make AI so clever that bad outcomes look arbitrary.
- **Field coordinates**: x = 0..120 (0-10 own end zone, 10 own goal line, 110 opponent goal
  line, 110-120 opponent end zone), y = 0..53.333 (sideline to sideline).

## Known pending work (not yet started, no issue needed to mention them, but check before
assuming they exist)

- No recruiting/drafting/trading/player-development loop yet — only random team generation.
- No touch-friendly UI pass for mobile yet.
