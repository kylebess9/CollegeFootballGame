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
        _ => ("report", "Report"),
    };

    static string KindLabel(TestKind k) => k switch
    {
        TestKind.Check => "Check",
        TestKind.Scan => "Regression scan",
        _ => "Report",
    };

    public static string Build(IReadOnlyList<TestResult> results, RunInfo info)
    {
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
            <title>Test Results</title>
            <style>
            :root {
              --bg: #f6f7f9; --surface: #ffffff; --text: #1d2330; --muted: #5f6b7d; --border: #dde2ea;
              --pass: #1f7a3d; --pass-bg: #e3f4e8; --fail: #b42318; --fail-bg: #fde8e6;
              --error: #9a5b00; --error-bg: #fff1d6; --report: #2b5fa8; --report-bg: #e5eefb;
              --code-bg: #f1f3f6; --fail-line: #fde8e6;
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --bg: #12151b; --surface: #1b1f27; --text: #e6e9ef; --muted: #98a2b3; --border: #2c323d;
                --pass: #5fd08a; --pass-bg: #173322; --fail: #ff7b6e; --fail-bg: #3a1a17;
                --error: #f3b552; --error-bg: #382a12; --report: #7fb0ff; --report-bg: #182a45;
                --code-bg: #14171d; --fail-line: #3a1a17;
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
            .tile.error .n { color: var(--error); } .tile.report .n { color: var(--report); }
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
            .tile.pass, .tile.fail, .tile.error, .tile.report { background: var(--surface); }
            .body { border-top: 1px solid var(--border); padding: 12px 14px; }
            .facts { color: var(--muted); font-size: 13px; margin-bottom: 8px; }
            .faillist { margin: 0 0 10px; padding-left: 18px; color: var(--fail); font-size: 13px; }
            pre { margin: 0; background: var(--code-bg); border-radius: 8px; padding: 10px 12px; overflow: auto; max-height: 520px;
              font: 12.5px/1.45 ui-monospace, Consolas, "Cascadia Mono", monospace; }
            pre span { display: block; white-space: pre; }
            pre .f { background: var(--fail-line); color: var(--fail); font-weight: 600; }
            pre .o { color: var(--pass); }
            pre .e { color: var(--error); }
            .hidden { display: none; }
            @media (max-width: 640px) {
              .test summary { grid-template-columns: 70px minmax(0, 1fr) auto; }
              .detail { grid-column: 1 / -1; }
            }
            </style>
            </head>
            <body>
            <main>
            <h1>Test results <span class="verdict {{(allGood ? "pass" : "fail")}}">{{(allGood ? "All checks passed" : $"{failed + errors} problem(s)")}}</span></h1>
            <div class="meta">
              {{H(info.Started.ToString("dddd d MMMM yyyy, HH:mm"))}} · took {{Secs(info.Duration)}} · {{info.Parallel}} at a time · {{H(info.Machine)}}<br>
              Godot {{H(info.GodotVersion)}} · {{H(info.GodotPath)}}<br>
              Project {{H(info.ProjectRoot)}}
            </div>
            <div class="tiles">
              <div class="tile pass"><div class="n">{{passed}}</div><div class="l">Passed</div></div>
              <div class="tile fail"><div class="n">{{failed}}</div><div class="l">Failed</div></div>
              <div class="tile error"><div class="n">{{errors}}</div><div class="l">Errors (crash, timeout, no summary)</div></div>
              <div class="tile report"><div class="n">{{reports}}</div><div class="l">Reports (no pass/fail)</div></div>
            </div>
            <div class="toolbar">
              <button type="button" id="onlyProblems" aria-pressed="false">Show only problems</button>
              <button type="button" id="expandAll">Expand all</button>
              <button type="button" id="collapseAll">Collapse all</button>
            </div>

            """);

        // Problems first, then checks, then reports, each in name order.
        var ordered = results
            .OrderBy(r => r.Status switch { TestStatus.Failed => 0, TestStatus.Error => 1, TestStatus.Passed => 2, _ => 3 })
            .ThenBy(r => r.Test.Name, StringComparer.OrdinalIgnoreCase);

        foreach (var r in ordered)
        {
            var (css, label) = Badge(r.Status);
            bool problem = r.Status is TestStatus.Failed or TestStatus.Error;
            sb.Append($"""<details class="test" data-problem="{(problem ? "1" : "0")}"{(problem ? " open" : "")}>""");
            sb.Append($"""<summary><span class="badge {css}">{label}</span>""");
            sb.Append($"""<span class="name">{H(r.Test.Name)}<span class="kind">{KindLabel(r.Test.Kind)}</span></span>""");
            sb.Append($"""<span class="detail">{H(r.Detail)}</span><span class="dur">{Secs(r.Duration)}</span></summary>""");
            sb.Append("""<div class="body">""");

            var facts = new List<string> { $"exit code {(r.TimedOut ? "n/a (timed out)" : r.ExitCode.ToString())}" };
            if (r.Test.Kind != TestKind.Report) facts.Add($"{r.OkCount} ok line(s), {r.FailLines.Count} FAIL line(s)");
            if (r.ScriptErrors > 0) facts.Add($"{r.ScriptErrors} engine/script error line(s)");
            facts.Add($"{r.Output.Count} output line(s)");
            facts.Add(H(r.Test.ResPath));
            sb.Append($"""<div class="facts">{string.Join(" · ", facts)}</div>""");

            if (r.FailLines.Count > 0)
            {
                sb.Append("""<ul class="faillist">""");
                foreach (string f in r.FailLines) sb.Append($"<li>{H(f)}</li>");
                sb.Append("</ul>");
            }

            sb.Append("<pre>");
            foreach (string line in r.Output)
            {
                string t = line.TrimStart();
                string cls = t.StartsWith("FAIL", StringComparison.Ordinal) ? " class=\"f\""
                    : t.StartsWith("ok ", StringComparison.Ordinal) ? " class=\"o\""
                    : t.StartsWith("SCRIPT ERROR", StringComparison.Ordinal) || t.StartsWith("ERROR:", StringComparison.Ordinal)
                      || t.StartsWith("Parse Error", StringComparison.Ordinal) || t.StartsWith("WARNING:", StringComparison.Ordinal) ? " class=\"e\""
                    : "";
                sb.Append($"<span{cls}>{(line.Length == 0 ? " " : H(line))}</span>");
            }
            if (r.Output.Count == 0) sb.Append("<span>(no output)</span>");
            sb.Append("</pre></div></details>\n");
        }

        sb.Append("""
            </main>
            <script>
            (function () {
              var tests = Array.prototype.slice.call(document.querySelectorAll('.test'));
              var only = document.getElementById('onlyProblems');
              only.addEventListener('click', function () {
                var on = only.getAttribute('aria-pressed') !== 'true';
                only.setAttribute('aria-pressed', on ? 'true' : 'false');
                tests.forEach(function (t) { t.classList.toggle('hidden', on && t.dataset.problem !== '1'); });
              });
              document.getElementById('expandAll').addEventListener('click', function () { tests.forEach(function (t) { t.open = true; }); });
              document.getElementById('collapseAll').addEventListener('click', function () { tests.forEach(function (t) { t.open = false; }); });
            })();
            </script>
            </body>
            </html>

            """);
        return sb.ToString();
    }
}
