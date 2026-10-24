using System.Text.Json;

namespace TestRunner;

/// Settings for one run, merged from (highest wins) command-line args, environment
/// variables, testrunner.json, then defaults.
sealed class Options
{
    public string? GodotPath;
    public string? ProjectPath;
    public string? OutputPath;
    public string? ConfigPath;
    public int TimeoutSeconds = 1800;
    public int Parallel = 1;
    public bool ChecksOnly;
    public bool Open;
    public bool ForceImport;
    public bool NoImport;
    public bool ShowHelp;
    public bool Verbose;
    public int HeartbeatSeconds = 30;
    public List<string> Only = new();
    public List<string> Skip = new();

    public const string HelpText = """
        Runs the Godot tests in tests/ with headless Godot and writes an HTML report.

        Usage: dotnet run --project tools/TestRunner -- [options]

          --godot <path>      Godot executable (use the *_console.exe build on Windows).
                              Also read from the GODOT_PATH env var or testrunner.json.
          --project <path>    Folder with project.godot (default: found by walking up
                              from the current folder).
          --only <a,b>        Run just these tests (names without .gd, e.g. catch_check).
          --skip <a,b>        Leave these tests out.
          --checks-only       Skip the report-only scripts (balance_test, game_log).
          --parallel <n>      Run n tests at once (default 1). The tests are CPU-heavy.
          --timeout <sec>     Kill a test that runs longer than this (default 1800).
          --out <file.html>   Where to write the report (default:
                              tools/TestRunner/TestResults/test-report-<time>.html).
          --open              Open the report in your browser at the start. It refreshes
                              itself while the tests run.
          --verbose           Echo every line of test output to the console as it comes.
          --heartbeat <sec>   Print what's still running this often (default 30, 0 = off).
          --import            Run 'godot --headless --import' first, even if the class
                              cache already exists (it runs automatically when missing).
          --no-import         Never run the import step.
          --config <file>     Read settings from this JSON file instead of testrunner.json.
          -h, --help          Show this help.

        A log of the run (every output line, timestamped) is written next to the report
        as it happens; tail it with: Get-Content <log> -Wait

        Exit code is 0 when every check passed, 1 when any failed or errored.
        """;

    public static Options Parse(string[] args)
    {
        var o = new Options();
        for (int i = 0; i < args.Length; i++)
        {
            string a = args[i];
            string Next()
            {
                if (i + 1 >= args.Length) throw new ArgumentException($"{a} needs a value");
                return args[++i];
            }
            switch (a)
            {
                case "--godot": o.GodotPath = Next(); break;
                case "--project": o.ProjectPath = Next(); break;
                case "--out": o.OutputPath = Next(); break;
                case "--config": o.ConfigPath = Next(); break;
                case "--only": o.Only.AddRange(SplitList(Next())); break;
                case "--skip": o.Skip.AddRange(SplitList(Next())); break;
                case "--checks-only": o.ChecksOnly = true; break;
                case "--open": o.Open = true; break;
                case "--verbose": o.Verbose = true; break;
                case "--heartbeat": o.HeartbeatSeconds = ParseInt(a, Next(), 0); break;
                case "--import": o.ForceImport = true; break;
                case "--no-import": o.NoImport = true; break;
                case "--parallel": o.Parallel = ParseInt(a, Next(), 1); break;
                case "--timeout": o.TimeoutSeconds = ParseInt(a, Next(), 1); break;
                case "-h": case "--help": case "/?": o.ShowHelp = true; break;
                default: throw new ArgumentException($"Unknown option '{a}'. Use --help.");
            }
        }
        return o;
    }

    /// Fills anything not given on the command line from the env var and config file.
    /// Must run after ProjectPath is resolved, since testrunner.json is looked for there.
    public void ApplyEnvironmentAndConfig(string projectRoot, string[] args)
    {
        GodotPath ??= NullIfEmpty(Environment.GetEnvironmentVariable("GODOT_PATH"))
                   ?? NullIfEmpty(Environment.GetEnvironmentVariable("GODOT"));

        string? configFile = ConfigPath ?? FindConfig(projectRoot);
        if (configFile == null) return;
        if (!File.Exists(configFile)) throw new ArgumentException($"Config file not found: {configFile}");
        ConfigPath = configFile;

        using var doc = JsonDocument.Parse(File.ReadAllText(configFile),
            new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true });
        var root = doc.RootElement;
        bool Given(string flag) => args.Contains(flag);

        if (GodotPath == null && root.TryGetProperty("godotPath", out var g)) GodotPath = NullIfEmpty(g.GetString());
        if (!Given("--timeout") && root.TryGetProperty("timeoutSeconds", out var t)) TimeoutSeconds = Math.Max(1, t.GetInt32());
        if (!Given("--parallel") && root.TryGetProperty("parallel", out var p)) Parallel = Math.Max(1, p.GetInt32());
        if (!Given("--checks-only") && root.TryGetProperty("checksOnly", out var c)) ChecksOnly = c.GetBoolean();
        if (!Given("--open") && root.TryGetProperty("open", out var op)) Open = op.GetBoolean();
        if (!Given("--verbose") && root.TryGetProperty("verbose", out var v)) Verbose = v.GetBoolean();
        if (!Given("--heartbeat") && root.TryGetProperty("heartbeatSeconds", out var hb)) HeartbeatSeconds = Math.Max(0, hb.GetInt32());
        if (root.TryGetProperty("skip", out var s) && s.ValueKind == JsonValueKind.Array)
            foreach (var e in s.EnumerateArray())
                if (e.GetString() is { Length: > 0 } name) Skip.Add(name);
    }

    static string? FindConfig(string projectRoot)
    {
        string[] candidates =
        {
            Path.Combine(Environment.CurrentDirectory, "testrunner.json"),
            Path.Combine(projectRoot, "tools", "TestRunner", "testrunner.json"),
            Path.Combine(AppContext.BaseDirectory, "testrunner.json"),
        };
        return candidates.FirstOrDefault(File.Exists);
    }

    static IEnumerable<string> SplitList(string v) =>
        v.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
         .Select(TestCatalog.NormalizeName);

    static int ParseInt(string flag, string v, int min) =>
        int.TryParse(v, out int n) && n >= min ? n : throw new ArgumentException($"{flag} needs a whole number >= {min}");

    static string? NullIfEmpty(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim().Trim('"');
}
