using System.Diagnostics;
using TestRunner;

Options opts;
try
{
    opts = Options.Parse(args);
}
catch (ArgumentException ex)
{
    Console.Error.WriteLine(ex.Message);
    return 2;
}
if (opts.ShowHelp)
{
    Console.WriteLine(Options.HelpText);
    return 0;
}

string? projectRoot = opts.ProjectPath != null
    ? Path.GetFullPath(opts.ProjectPath)
    : FindProjectRoot(Environment.CurrentDirectory) ?? FindProjectRoot(AppContext.BaseDirectory);
if (projectRoot == null || !File.Exists(Path.Combine(projectRoot, "project.godot")))
{
    Console.Error.WriteLine("Couldn't find project.godot. Run this from inside the repo or pass --project <folder>.");
    return 2;
}

try
{
    opts.ApplyEnvironmentAndConfig(projectRoot, args);
}
catch (Exception ex) when (ex is ArgumentException or System.Text.Json.JsonException or InvalidOperationException)
{
    Console.Error.WriteLine($"Bad config: {ex.Message}");
    return 2;
}

string? godot = ResolveGodot(opts.GodotPath);
if (godot == null)
{
    Console.Error.WriteLine(opts.GodotPath != null
        ? $"Godot not found at '{opts.GodotPath}'."
        : "Godot not found. Pass --godot <path>, set GODOT_PATH, or put godotPath in testrunner.json.");
    return 2;
}

var tests = TestCatalog.Discover(projectRoot);
var unknown = opts.Only.Concat(opts.Skip).Where(n => tests.All(t => !t.Name.Equals(n, StringComparison.OrdinalIgnoreCase))).ToList();
if (unknown.Count > 0)
    Console.Error.WriteLine($"Warning: no test named {string.Join(", ", unknown)} in tests/.");
if (opts.Only.Count > 0)
    tests = tests.Where(t => opts.Only.Contains(t.Name, StringComparer.OrdinalIgnoreCase)).ToList();
tests = tests.Where(t => !opts.Skip.Contains(t.Name, StringComparer.OrdinalIgnoreCase)).ToList();
if (opts.ChecksOnly)
    tests = tests.Where(t => t.Kind != TestKind.Report).ToList();
if (tests.Count == 0)
{
    Console.Error.WriteLine("No tests to run.");
    return 2;
}

var runner = new GodotRunner(godot, projectRoot);
string version = await runner.VersionAsync();
Console.WriteLine($"Godot:   {godot} ({version})");
Console.WriteLine($"Project: {projectRoot}");
if (opts.ConfigPath != null) Console.WriteLine($"Config:  {opts.ConfigPath}");

// Without the class cache every test fails with "Identifier not declared".
string classCache = Path.Combine(projectRoot, ".godot", "global_script_class_cache.cfg");
if (!opts.NoImport && (opts.ForceImport || !File.Exists(classCache)))
{
    Console.WriteLine("Importing the project (builds the class cache the tests need)...");
    var imp = await runner.ImportAsync(TimeSpan.FromMinutes(10));
    Console.WriteLine(imp.TimedOut ? "  import timed out, carrying on" : $"  done in {imp.Duration.TotalSeconds:0}s");
}

Console.WriteLine($"Running {tests.Count} test(s), {opts.Parallel} at a time, timeout {opts.TimeoutSeconds}s each.");
Console.WriteLine();

var started = DateTime.Now;
var total = Stopwatch.StartNew();
var results = new TestResult[tests.Count];
int finished = 0;
using var gate = new SemaphoreSlim(opts.Parallel);
var consoleLock = new object();

await Task.WhenAll(tests.Select(async (test, i) =>
{
    await gate.WaitAsync();
    try
    {
        var r = new TestResult { Test = test };
        try
        {
            var run = await runner.RunScriptAsync(test, TimeSpan.FromSeconds(opts.TimeoutSeconds));
            r.Output = run.Lines;
            r.ExitCode = run.ExitCode;
            r.TimedOut = run.TimedOut;
            r.Duration = run.Duration;
            TestCatalog.Evaluate(r);
        }
        catch (InvalidOperationException ex)
        {
            r.Status = TestStatus.Error;
            r.Detail = ex.Message;
        }
        results[i] = r;
        lock (consoleLock)
        {
            finished++;
            var old = Console.ForegroundColor;
            Console.Write($"[{finished,2}/{tests.Count}] {test.Name,-28} ");
            Console.ForegroundColor = r.Status switch
            {
                TestStatus.Passed => ConsoleColor.Green,
                TestStatus.Failed => ConsoleColor.Red,
                TestStatus.Error => ConsoleColor.Yellow,
                _ => ConsoleColor.Cyan,
            };
            Console.Write(StatusLabel(r.Status).PadRight(7));
            Console.ForegroundColor = old;
            Console.WriteLine($" {r.Duration.TotalSeconds,6:0.0}s  {r.Detail}");
            foreach (string f in r.FailLines.Take(5)) Console.WriteLine($"        {f}");
            if (r.FailLines.Count > 5) Console.WriteLine($"        ... and {r.FailLines.Count - 5} more");
        }
    }
    finally
    {
        gate.Release();
    }
}));
total.Stop();

string outPath = opts.OutputPath != null
    ? Path.GetFullPath(opts.OutputPath)
    : Path.Combine(projectRoot, "tools", "TestRunner", "TestResults", $"test-report-{started:yyyyMMdd-HHmmss}.html");
Directory.CreateDirectory(Path.GetDirectoryName(outPath)!);
File.WriteAllText(outPath, HtmlReport.Build(results, new HtmlReport.RunInfo(
    started, total.Elapsed, godot, version, projectRoot, Environment.MachineName, opts.Parallel)));

int passed = results.Count(r => r.Status == TestStatus.Passed);
int failed = results.Count(r => r.Status == TestStatus.Failed);
int errors = results.Count(r => r.Status == TestStatus.Error);
int reports = results.Count(r => r.Status == TestStatus.Report);
Console.WriteLine();
Console.WriteLine($"{passed} passed, {failed} failed, {errors} errors, {reports} reports in {total.Elapsed:hh\\:mm\\:ss}");
Console.WriteLine($"Report: {outPath}");

if (opts.Open)
{
    try { Process.Start(new ProcessStartInfo(outPath) { UseShellExecute = true }); }
    catch (Exception ex) { Console.Error.WriteLine($"Couldn't open the report: {ex.Message}"); }
}

return failed + errors > 0 ? 1 : 0;

static string StatusLabel(TestStatus s) => s switch
{
    TestStatus.Passed => "PASS",
    TestStatus.Failed => "FAIL",
    TestStatus.Error => "ERROR",
    _ => "REPORT",
};

static string? FindProjectRoot(string start)
{
    for (var dir = new DirectoryInfo(start); dir != null; dir = dir.Parent)
        if (File.Exists(Path.Combine(dir.FullName, "project.godot"))) return dir.FullName;
    return null;
}

// A path that exists, or a bare command name found on PATH.
static string? ResolveGodot(string? configured)
{
    if (configured != null)
    {
        if (File.Exists(configured)) return Path.GetFullPath(configured);
        if (configured.IndexOfAny(new[] { '/', '\\' }) >= 0) return null;
        return FindOnPath(configured);
    }
    foreach (string name in new[] { "godot", "godot4", "Godot_v4.7-stable_win64_console" })
        if (FindOnPath(name) is string found) return found;
    return null;
}

static string? FindOnPath(string name)
{
    string[] exts = OperatingSystem.IsWindows()
        ? (Environment.GetEnvironmentVariable("PATHEXT") ?? ".EXE;.CMD;.BAT").Split(';').Prepend("").ToArray()
        : new[] { "" };
    foreach (string dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
    {
        if (dir.Length == 0) continue;
        foreach (string ext in exts)
        {
            string p = Path.Combine(dir.Trim('"'), name + ext);
            if (File.Exists(p)) return p;
        }
    }
    return null;
}
