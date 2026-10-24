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

string outPath = opts.OutputPath != null
    ? Path.GetFullPath(opts.OutputPath)
    : Path.Combine(projectRoot, "tools", "TestRunner", "TestResults", $"test-report-{DateTime.Now:yyyyMMdd-HHmmss}.html");
string logPath = Path.ChangeExtension(outPath, ".log");

var started = DateTime.Now;
var total = Stopwatch.StartNew();
var results = tests.Select(t => new TestResult { Test = t, Status = TestStatus.Queued }).ToArray();
string BuildReport(bool live) => HtmlReport.Build(results, new HtmlReport.RunInfo(
    started, total.Elapsed, godot, version, projectRoot, Environment.MachineName, opts.Parallel), live);

using var progress = new Progress(results, outPath, logPath, BuildReport, opts.Verbose);
progress.Log($"Godot {version} at {godot}; project {projectRoot}; {tests.Count} test(s), {opts.Parallel} at a time");
progress.WriteReport(live: true);

Console.WriteLine($"Running {tests.Count} test(s), {opts.Parallel} at a time, timeout {opts.TimeoutSeconds}s each.");
Console.WriteLine($"Live report: {outPath}");
Console.WriteLine($"Live log:    {logPath}");
Console.WriteLine();
if (opts.Open) OpenInBrowser(outPath);

using var doneCts = new CancellationTokenSource();
var ticker = progress.RunTickerAsync(opts.HeartbeatSeconds, doneCts.Token);
using var gate = new SemaphoreSlim(opts.Parallel);

await Task.WhenAll(results.Select(async r =>
{
    await gate.WaitAsync();
    try
    {
        progress.Started(r);
        try
        {
            var run = await runner.RunScriptAsync(r.Test, TimeSpan.FromSeconds(opts.TimeoutSeconds),
                line => progress.Line(r, line));
            r.ExitCode = run.ExitCode;
            r.TimedOut = run.TimedOut;
            r.Duration = run.Duration;
            TestCatalog.Evaluate(r);
        }
        catch (InvalidOperationException ex)
        {
            r.Status = TestStatus.Error;
            r.Detail = ex.Message;
            r.Duration = DateTime.Now - r.StartedAt!.Value;
        }
        progress.Finished(r);
    }
    finally
    {
        gate.Release();
    }
}));
total.Stop();
doneCts.Cancel();
await ticker;
progress.WriteReport(live: false);

int passed = results.Count(r => r.Status == TestStatus.Passed);
int failed = results.Count(r => r.Status == TestStatus.Failed);
int errors = results.Count(r => r.Status == TestStatus.Error);
int reports = results.Count(r => r.Status == TestStatus.Report);
Console.WriteLine();
Console.WriteLine($"{passed} passed, {failed} failed, {errors} errors, {reports} reports in {total.Elapsed:hh\\:mm\\:ss}");
Console.WriteLine($"Report: {outPath}");
Console.WriteLine($"Log:    {logPath}");


return failed + errors > 0 ? 1 : 0;

static void OpenInBrowser(string path)
{
    try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
    catch (Exception ex) { Console.Error.WriteLine($"Couldn't open the report: {ex.Message}"); }
}

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
