using System.Text.RegularExpressions;

namespace TestRunner;

enum TestKind
{
    /// Prints ok/FAIL lines and a summary line, and should exit 0 when everything passed.
    Check,
    /// redzone_check: passes when both of its bug counts are 0.
    Scan,
    /// balance_test, game_log: output to read, no pass/fail.
    Report,
}

enum TestStatus { Passed, Failed, Error, Report }

sealed record TestCase(string Name, string File, TestKind Kind)
{
    public string ResPath => $"res://tests/{File}";
}

sealed class TestResult
{
    public required TestCase Test;
    public TestStatus Status;
    /// One line for the report table: the summary line, or why it failed.
    public string Detail = "";
    public List<string> Output = new();
    public int ExitCode;
    public bool TimedOut;
    public TimeSpan Duration;
    public int OkCount;
    public List<string> FailLines = new();
    public int ScriptErrors;
}

static partial class TestCatalog
{
    static readonly HashSet<string> Reports = new(StringComparer.OrdinalIgnoreCase) { "balance_test", "game_log" };
    static readonly HashSet<string> Scans = new(StringComparer.OrdinalIgnoreCase) { "redzone_check" };

    public static string NormalizeName(string name)
    {
        name = name.Trim().Replace('\\', '/');
        if (name.Contains('/')) name = name[(name.LastIndexOf('/') + 1)..];
        return name.EndsWith(".gd", StringComparison.OrdinalIgnoreCase) ? name[..^3] : name;
    }

    /// Every .gd script directly in tests/. A new script is treated as a check if its
    /// name ends in _check, otherwise as a report, so it shows up without changing this tool.
    public static List<TestCase> Discover(string projectRoot)
    {
        string dir = Path.Combine(projectRoot, "tests");
        if (!Directory.Exists(dir)) return new();
        return Directory.GetFiles(dir, "*.gd")
            .Select(Path.GetFileName)
            .OfType<string>()
            .OrderBy(f => f, StringComparer.OrdinalIgnoreCase)
            .Select(f =>
            {
                string name = NormalizeName(f);
                TestKind kind = Scans.Contains(name) ? TestKind.Scan
                    : Reports.Contains(name) ? TestKind.Report
                    : name.EndsWith("_check", StringComparison.OrdinalIgnoreCase) ? TestKind.Check
                    : TestKind.Report;
                return new TestCase(name, f, kind);
            })
            .ToList();
    }

    // "catch_check: OK", "handoff_check: PASS", "playbook_check: FAILED (2 failures)",
    // "catch_check: 3 FAILED", or a bare "OK" / "FAIL" (play_action_check, run_side_check).
    [GeneratedRegex(@"^(?:\w+:\s*)?(OK|PASS|FAILED|FAIL|\d+\s+FAILED)\b")]
    private static partial Regex SummaryRegex();

    [GeneratedRegex(@"without TD=(\d+)")]
    private static partial Regex NoTdRegex();

    [GeneratedRegex(@"out of bounds=(\d+)")]
    private static partial Regex OutOfBoundsRegex();

    [GeneratedRegex(@"^(SCRIPT ERROR|Parse Error|ERROR):")]
    private static partial Regex ScriptErrorRegex();

    /// Decides pass/fail from a finished run's output and exit code.
    public static void Evaluate(TestResult r)
    {
        foreach (string line in r.Output)
        {
            string t = line.Trim();
            if (t.StartsWith("ok ", StringComparison.Ordinal)) r.OkCount++;
            else if (t.StartsWith("FAIL", StringComparison.Ordinal)) r.FailLines.Add(t);
            if (ScriptErrorRegex().IsMatch(t)) r.ScriptErrors++;
        }

        if (r.TimedOut)
        {
            r.Status = TestStatus.Error;
            r.Detail = $"Timed out after {r.Duration.TotalSeconds:0}s and was stopped";
            return;
        }

        switch (r.Test.Kind)
        {
            case TestKind.Report:
                r.Status = r.ExitCode == 0 ? TestStatus.Report : TestStatus.Error;
                r.Detail = r.ExitCode == 0 ? $"{r.Output.Count} lines of output" : $"Exited with code {r.ExitCode}";
                break;

            case TestKind.Scan:
                EvaluateScan(r);
                break;

            default:
                EvaluateCheck(r);
                break;
        }
    }

    static void EvaluateCheck(TestResult r)
    {
        string? summary = r.Output.Select(l => l.Trim()).LastOrDefault(l => SummaryRegex().IsMatch(l));
        if (summary == null)
        {
            r.Status = TestStatus.Error;
            r.Detail = r.ScriptErrors > 0
                ? $"No summary line; {r.ScriptErrors} script error(s) - see output"
                : $"No summary line (exit code {r.ExitCode}) - did the script crash?";
            return;
        }

        string verdict = SummaryRegex().Match(summary).Groups[1].Value;
        bool summaryOk = verdict is "OK" or "PASS";
        // catch_check and pass_speed_check always exit 0, so the summary and FAIL lines
        // decide; the exit code still counts for the scripts that do set it.
        bool passed = summaryOk && r.FailLines.Count == 0 && r.ExitCode == 0;
        r.Status = passed ? TestStatus.Passed : TestStatus.Failed;
        r.Detail = summary;
        if (!passed && summaryOk && r.FailLines.Count > 0) r.Detail += $" (but {r.FailLines.Count} FAIL line(s))";
        else if (!passed && summaryOk) r.Detail += $" (but exit code {r.ExitCode})";
    }

    static void EvaluateScan(TestResult r)
    {
        string text = string.Join('\n', r.Output);
        var noTd = NoTdRegex().Match(text);
        var oob = OutOfBoundsRegex().Match(text);
        if (!noTd.Success || !oob.Success)
        {
            r.Status = TestStatus.Error;
            r.Detail = "Couldn't find the 'without TD=' and 'out of bounds=' counts in the output";
            return;
        }
        int a = int.Parse(noTd.Groups[1].Value), b = int.Parse(oob.Groups[1].Value);
        r.Status = a == 0 && b == 0 ? TestStatus.Passed : TestStatus.Failed;
        r.Detail = $"plays ending in end zone without TD={a}, catches/INTs out of bounds={b}";
    }
}
