using System.Net;
using System.Text;

namespace TestRunner;

/// Builds a single self-contained HTML page (no external files) from the results.
static class HtmlReport
{
    public sealed record RunInfo(DateTime Started, TimeSpan Duration, string GodotPath, string GodotVersion,
        string ProjectRoot, string Machine, int Parallel);

    static string H(string s) => WebUtility.HtmlEncode(s);

    static string Secs(TimeSpan t) => t.TotalSeconds < 60 ? $"{t.TotalSeconds:0.0}s" : $"{(int)t.TotalMinutes}m {t.Seconds:00}s";

    static (string css, string label) Badge(TestStatus s) => s switch
    {
        TestStatus.Passed => ("pass", "Passed"),
        TestStatus.Failed => ("fail", "Failed"),
        TestStatus.Error => ("error", "Error"),
        TestStatus.Running => ("running", "Running"),
        TestStatus.Queued => ("queued", "Queued"),
        _ => ("report", "Report"),
    };

    static string KindLabel(TestKind k) => k switch
    {
        TestKind.Check => "Check",
        TestKind.Scan => "Regression scan",
        _ => "Report",
    };

    /// live: the run is still going. The page then shows running and queued tests, the
    /// output so far, and reloads itself every few seconds (keeping open rows and scroll).
    public static string Build(IReadOnlyList<TestResult> results, RunInfo info, bool live = false)
    {
        int running = results.Count(r => r.Status == TestStatus.Running);
        int queued = results.Count(r => r.Status == TestStatus.Queued);
        int done = results.Count - running - queued;
        int passed = results.Count(r => r.Status == TestStatus.Passed);
        int failed = results.Count(r => r.Status == TestStatus.Failed);
        int errors = results.Count(r => r.Status == TestStatus.Error);
        int reports = results.Count(r => r.Status == TestStatus.Report);
        bool allGood = failed + errors == 0;

        var sb = new StringBuilder();
        sb.Append($$"""
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            {{(live ? "<meta http-equiv=\"refresh\" content=\"4\">" : "")}}
            <title>Test Results</title>
            <style>
            :root {
              --bg: #f6f7f9; --surface: #ffffff; --text: #1d2330; --muted: #5f6b7d; --border: #dde2ea;
              --pass: #1f7a3d; --pass-bg: #e3f4e8; --fail: #b42318; --fail-bg: #fde8e6;
              --error: #9a5b00; --error-bg: #fff1d6; --report: #2b5fa8; --report-bg: #e5eefb;
              --code-bg: #f1f3f6; --fail-line: #fde8e6; --run: #6a3fb5; --run-bg: #efe7fb; --queued: #5f6b7d; --queued-bg: #eceff3;
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --bg: #12151b; --surface: #1b1f27; --text: #e6e9ef; --muted: #98a2b3; --border: #2c323d;
                --pass: #5fd08a; --pass-bg: #173322; --fail: #ff7b6e; --fail-bg: #3a1a17;
                --error: #f3b552; --error-bg: #382a12; --report: #7fb0ff; --report-bg: #182a45;
                --code-bg: #14171d; --fail-line: #3a1a17; --run: #c3a3ff; --run-bg: #2b2042; --queued: #98a2b3; --queued-bg: #252a33;
              }
            }
            * { box-sizing: border-box; }
            body { margin: 0; background: var(--bg); color: var(--text);
              font: 15px/1.5 -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
            main { max-width: 1100px; margin: 0 auto; padding: 24px 16px 48px; }
            h1 { font-size: 24px; margin: 0 0 4px; }
            .meta { color: var(--muted); font-size: 13px; margin-bottom: 20px; word-break: break-all; }
            .verdict { display: inline-block; padding: 2px 10px; border-radius: 999px; font-weight: 600; font-size: 14px; margin-left: 8px; vertical-align: middle; }
            .tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px; margin-bottom: 20px; }
            .tile { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 12px 16px; }
            .tile .n { font-size: 28px; font-weight: 700; font-variant-numeric: tabular-nums; }
            .tile .l { color: var(--muted); font-size: 13px; }
            .tile.pass .n { color: var(--pass); } .tile.fail .n { color: var(--fail); }
            .tile.error .n { color: var(--error); } .tile.report .n { color: var(--report); } .tile.running .n { color: var(--run); }
            .toolbar { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 12px; }
            .toolbar button { background: var(--surface); color: var(--text); border: 1px solid var(--border);
              border-radius: 8px; padding: 6px 12px; font: inherit; font-size: 13px; cursor: pointer; }
            .toolbar button[aria-pressed="true"] { border-color: var(--report); color: var(--report); }
            .test { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; margin-bottom: 8px; overflow: hidden; }
            .test summary { list-style: none; cursor: pointer; padding: 10px 14px; display: grid;
              grid-template-columns: 76px minmax(0, 220px) minmax(0, 1fr) auto; gap: 12px; align-items: center; }
            .test summary::-webkit-details-marker { display: none; }
            .name { font-weight: 600; font-family: ui-monospace, Consolas, monospace; font-size: 14px; overflow-wrap: anywhere; }
            .kind { color: var(--muted); font-size: 12px; font-weight: 400; font-family: inherit; display: block; }
            .detail { color: var(--muted); font-size: 13px; overflow-wrap: anywhere; }
            .dur { color: var(--muted); font-size: 13px; font-variant-numeric: tabular-nums; white-space: nowrap; }
            .badge { text-align: center; border-radius: 999px; padding: 2px 8px; font-size: 12px; font-weight: 600; }
            .pass { color: var(--pass); background: var(--pass-bg); } .fail { color: var(--fail); background: var(--fail-bg); }
            .error { color: var(--error); background: var(--error-bg); } .report { color: var(--report); background: var(--report-bg); }
            .tile.pass, .tile.fail, .tile.error, .tile.report, .tile.running { background: var(--surface); }
            .body { border-top: 1px solid var(--border); padding: 12px 14px; }
            .facts { color: var(--muted); font-size: 13px; margin-bottom: 8px; }
            .faillist { margin: 0 0 10px; padding-left: 18px; color: var(--fail); font-size: 13px; }
            pre { margin: 0; background: var(--code-bg); border-radius: 8px; padding: 10px 12px; overflow: auto; max-height: 520px;
              font: 12.5px/1.45 ui-monospace, Consolas, "Cascadia Mono", monospace; }
            pre span { display: block; white-space: pre; }
            pre .f { background: var(--fail-line); color: var(--fail); font-weight: 600; }
            pre .o { color: var(--pass); }
            pre .e { color: var(--error); }
            .running { color: var(--run); background: var(--run-bg); } .queued { color: var(--queued); background: var(--queued-bg); }
            .verdict.running::before { content: ""; display: inline-block; width: 8px; height: 8px; border-radius: 50%;
              background: currentColor; margin-right: 6px; vertical-align: 1px; animation: pulse 1.2s ease-in-out infinite; }
            @keyframes pulse { 50% { opacity: .25; } }
            .bar { height: 6px; border-radius: 999px; background: var(--border); overflow: hidden; margin: -8px 0 20px; }
            .bar div { height: 100%; background: var(--run); }
            .hidden { display: none; }
            @media (max-width: 640px) {
              .test summary { grid-template-columns: 70px minmax(0, 1fr) auto; }
              .detail { grid-column: 1 / -1; }
            }
            </style>
            </head>
            <body>
            <main>
            <h1>Test results <span class="verdict {{(live ? "running" : allGood ? "pass" : "fail")}}">{{(live ? $"Running: {done} of {results.Count} done" + (failed + errors > 0 ? $", {failed + errors} problem(s)" : "") : allGood ? "All checks passed" : $"{failed + errors} problem(s)")}}</span></h1>
            <div class="meta">
              {{H(info.Started.ToString("dddd d MMMM yyyy, HH:mm"))}} · {{(live ? $"running for {Secs(info.Duration)}, updated {DateTime.Now:HH:mm:ss}" : $"took {Secs(info.Duration)}")}} · {{info.Parallel}} at a time · {{H(info.Machine)}}<br>
              Godot {{H(info.GodotVersion)}} · {{H(info.GodotPath)}}<br>
              Project {{H(info.ProjectRoot)}}
            </div>
            <div class="tiles">
              <div class="tile pass"><div class="n">{{passed}}</div><div class="l">Passed</div></div>
              <div class="tile fail"><div class="n">{{failed}}</div><div class="l">Failed</div></div>
              <div class="tile error"><div class="n">{{errors}}</div><div class="l">Errors (crash, timeout, no summary)</div></div>
              <div class="tile report"><div class="n">{{reports}}</div><div class="l">Reports (no pass/fail)</div></div>
            {{(live ? $"<div class=\"tile running\"><div class=\"n\">{running}</div><div class=\"l\">Running now ({queued} queued)</div></div>" : "")}}
            </div>
            {{(live ? $"<div class=\"bar\"><div style=\"width:{(results.Count == 0 ? 0 : done * 100 / results.Count)}%\"></div></div>" : "")}}
            <div class="toolbar">
              <button type="button" id="onlyProblems" aria-pressed="false">Show only problems</button>
              <button type="button" id="expandAll">Expand all</button>
              <button type="button" id="collapseAll">Collapse all</button>
            </div>

            """);

        // Running first, then problems, checks, reports and queued, each in name order.
        var ordered = results
            .OrderBy(r => r.Status switch
            {
                TestStatus.Running => 0, TestStatus.Failed => 1, TestStatus.Error => 2,
                TestStatus.Passed => 3, TestStatus.Report => 4, _ => 5,
            })
            .ThenBy(r => r.Test.Name, StringComparer.OrdinalIgnoreCase);

        foreach (var r in ordered)
        {
            var (css, label) = Badge(r.Status);
            bool problem = r.Status is TestStatus.Failed or TestStatus.Error;
            bool isRunning = r.Status == TestStatus.Running;
            List<string> output;
            lock (r.Output) output = new List<string>(r.Output);
            TimeSpan duration = isRunning ? DateTime.Now - (r.StartedAt ?? DateTime.Now) : r.Duration;
            string detail = r.Status switch
            {
                TestStatus.Running => $"{output.Count} lines so far" + (output.LastOrDefault(l => l.Trim().Length > 0) is string last ? $" · {last.Trim()}" : ""),
                TestStatus.Queued => "Waiting for a free slot",
                _ => r.Detail,
            };
            sb.Append($"""<details class="test" id="t-{H(r.Test.Name)}" data-problem="{(problem ? "1" : "0")}" data-running="{(isRunning ? "1" : "0")}"{(problem || isRunning ? " open" : "")}>""");
            sb.Append($"""<summary><span class="badge {css}">{label}</span>""");
            sb.Append($"""<span class="name">{H(r.Test.Name)}<span class="kind">{KindLabel(r.Test.Kind)}</span></span>""");
            sb.Append($"""<span class="detail">{H(detail)}</span><span class="dur">{(r.Status == TestStatus.Queued ? "" : Secs(duration))}</span></summary>""");
            sb.Append("""<div class="body">""");
            if (r.Status == TestStatus.Queued)
            {
                sb.Append("""<div class="facts">Not started yet. """ + H(r.Test.ResPath) + "</div></div></details>\n");
                continue;
            }

            var facts = new List<string>();
            if (isRunning) facts.Add($"started {r.StartedAt:HH:mm:ss}, still running");
            else facts.Add($"exit code {(r.TimedOut ? "n/a (timed out)" : r.ExitCode.ToString())}");
            if (r.Test.Kind != TestKind.Report && !isRunning) facts.Add($"{r.OkCount} ok line(s), {r.FailLines.Count} FAIL line(s)");
            if (r.ScriptErrors > 0) facts.Add($"{r.ScriptErrors} engine/script error line(s)");
            facts.Add($"{output.Count} output line(s)");
            facts.Add(H(r.Test.ResPath));
            sb.Append($"""<div class="facts">{string.Join(" · ", facts)}</div>""");

            if (r.FailLines.Count > 0)
            {
                sb.Append("""<ul class="faillist">""");
                foreach (string f in r.FailLines) sb.Append($"<li>{H(f)}</li>");
                sb.Append("</ul>");
            }

            sb.Append("<pre>");
            foreach (string line in output)
            {
                string t = line.TrimStart();
                string cls = t.StartsWith("FAIL", StringComparison.Ordinal) ? " class=\"f\""
                    : t.StartsWith("ok ", StringComparison.Ordinal) ? " class=\"o\""
                    : t.StartsWith("SCRIPT ERROR", StringComparison.Ordinal) || t.StartsWith("ERROR:", StringComparison.Ordinal)
                      || t.StartsWith("Parse Error", StringComparison.Ordinal) || t.StartsWith("WARNING:", StringComparison.Ordinal) ? " class=\"e\""
                    : "";
                sb.Append($"<span{cls}>{(line.Length == 0 ? " " : H(line))}</span>");
            }
            if (output.Count == 0) sb.Append(isRunning ? "<span>(no output yet)</span>" : "<span>(no output)</span>");
            sb.Append("</pre></div></details>\n");
        }

        sb.Append("""
            </main>
            <script>
            (function () {
              var tests = Array.prototype.slice.call(document.querySelectorAll('.test'));
              // The live page reloads every few seconds; keep what the viewer opened, closed,
              // filtered and scrolled to. Storage can be unavailable, so every use is guarded.
              var KEY = 'testRunnerView:' + location.pathname;
              var saved = null;
              try { saved = JSON.parse(sessionStorage.getItem(KEY) || 'null'); } catch (e) {}
              if (saved) {
                tests.forEach(function (t) { if (t.id in saved.open) t.open = saved.open[t.id]; });
              }
              tests.forEach(function (t) {
                if (t.dataset.running === '1') { var pre = t.querySelector('pre'); if (pre) pre.scrollTop = pre.scrollHeight; }
              });
              if (saved && saved.y) window.scrollTo(0, saved.y);
              window.addEventListener('beforeunload', function () {
                var open = {};
                tests.forEach(function (t) { open[t.id] = t.open; });
                var only = document.getElementById('onlyProblems').getAttribute('aria-pressed') === 'true';
                try { sessionStorage.setItem(KEY, JSON.stringify({ open: open, only: only, y: window.scrollY })); } catch (e) {}
              });
              var only = document.getElementById('onlyProblems');
              only.addEventListener('click', function () {
                var on = only.getAttribute('aria-pressed') !== 'true';
                only.setAttribute('aria-pressed', on ? 'true' : 'false');
                tests.forEach(function (t) { t.classList.toggle('hidden', on && t.dataset.problem !== '1'); });
              });
              document.getElementById('expandAll').addEventListener('click', function () { tests.forEach(function (t) { t.open = true; }); });
              document.getElementById('collapseAll').addEventListener('click', function () { tests.forEach(function (t) { t.open = false; }); });
              if (saved && saved.only) only.click();
            })();
            </script>
            </body>
            </html>

            """);
        return sb.ToString();
    }
}
