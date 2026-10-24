# TestRunner

A .NET console app that runs every Godot test script in `tests/` with headless Godot, decides
pass/fail for each, and writes an HTML report you can open in a browser.

## What you need

- The **.NET 8 SDK** or newer (`dotnet --version` to check; get it from
  https://dotnet.microsoft.com/download). It also runs on .NET 9/10 if that's all you have.
- The **console** build of Godot 4.7, e.g. `Godot_v4.7-stable_win64_console.exe`. The normal
  exe doesn't give the runner any output to read.

## Telling it where Godot is

Pick one (the first one found wins):

1. On the command line: `--godot "C:\Godot\Godot_v4.7-stable_win64_console.exe"`
2. An environment variable, `GODOT_PATH`. In PowerShell, for the current window:
   `$env:GODOT_PATH = "C:\Godot\Godot_v4.7-stable_win64_console.exe"`
   or for good: `[Environment]::SetEnvironmentVariable("GODOT_PATH", "C:\Godot\Godot_v4.7-stable_win64_console.exe", "User")`
3. A config file: copy `testrunner.example.json` to `testrunner.json` in this folder and edit
   `godotPath`. `testrunner.json` is git-ignored, so your path stays on your machine.
4. A `godot` (or `godot4`) command on your `PATH`.

## Running it

From the repo folder (the one with `project.godot`), in PowerShell:

```powershell
dotnet run --project tools\TestRunner -- --open
```

Everything after `--` goes to the runner. That runs every test, one at a time, prints a line per
test as it finishes, writes the report to
`tools\TestRunner\TestResults\test-report-<date>-<time>.html` and, with `--open`, opens it.

Some handy variations:

```powershell
# Just the pass/fail checks (leaves out balance_test and game_log, the slow reports)
dotnet run --project tools\TestRunner -- --checks-only --open

# A few named tests
dotnet run --project tools\TestRunner -- --only catch_check,handoff_check

# Two at a time (each test keeps one CPU core busy, so don't go above your core count)
dotnet run --project tools\TestRunner -- --parallel 2
```

The app exits with code 0 when every check passed and 1 when anything failed or errored
(`$LASTEXITCODE` in PowerShell), so it can be used in scripts too.

If the project has never been imported (no `.godot\global_script_class_cache.cfg`), the runner
runs `godot --headless --import` first, since without the class cache every test fails with
"Identifier not declared". `--import` forces that step, `--no-import` skips it.

### All the options

| Option | What it does |
|---|---|
| `--godot <path>` | Godot executable |
| `--project <folder>` | Folder with `project.godot` (default: found by walking up from the current folder) |
| `--only <a,b>` | Run just these tests (names without `.gd`) |
| `--skip <a,b>` | Leave these tests out |
| `--checks-only` | Skip the report-only scripts |
| `--parallel <n>` | Run n tests at once (default 1) |
| `--timeout <sec>` | Stop a test that runs longer than this (default 1800) |
| `--out <file.html>` | Where to write the report |
| `--open` | Open the report when done |
| `--import` / `--no-import` | Always / never run the import step first |
| `--config <file>` | Use this JSON file instead of `testrunner.json` |

`testrunner.json` can also set `timeoutSeconds`, `parallel`, `checksOnly`, `open` and a `skip`
list; command-line options override it.

## How pass/fail is decided

| Kind | Scripts | Passes when |
|---|---|---|
| Check | every `*_check.gd` except `redzone_check` | the summary line says `OK` or `PASS`, no line starts with `FAIL`, and the exit code is 0 |
| Regression scan | `redzone_check` | both `plays ending in end zone without TD=` and `made out of bounds=` are 0 |
| Report | `balance_test`, `game_log` | never pass/fail; the report shows the output to read |

A check is an **Error** (rather than a Fail) when it crashes, hits the timeout, or never prints a
summary line, which usually means a script error; the output in the report shows why. The
summary and FAIL lines are read even for `catch_check` and `pass_speed_check`, which exit 0 on
failure. A new script dropped into `tests/` is picked up automatically: as a check if its name
ends in `_check`, otherwise as a report.

## The report

One self-contained HTML file (no internet needed), with a count of passed, failed, errored and
report tests, then one row per test. Problems are listed first and opened, showing the FAIL lines
and the full output with FAIL lines highlighted; click any other row to see its output. "Show only
problems" hides the rest.

## Notes

- `tools/.gdignore` keeps Godot from importing this folder (and its `bin`/`obj` build output).
- The tests are CPU-heavy; some take several minutes each, and `balance_test` is the slowest.
- `playbook_editor_check` saves to `user://test_playbooks`, never your real playbooks.
