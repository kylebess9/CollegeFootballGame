using System.Text;

namespace TestRunner;

/// Live view of a run: console lines as tests start and finish, a periodic "still running"
/// heartbeat, a timestamped log file written as output arrives, and the HTML report
/// rewritten every few seconds so an open browser tab follows along.
sealed class Progress : IDisposable
{
    readonly TestResult[] _results;
    readonly string _reportPath;
    readonly Func<bool, string> _buildReport;
    readonly bool _verbose;
    readonly StreamWriter _log;
    readonly object _consoleLock = new();
    readonly object _reportLock = new();
    int _finished;
    volatile bool _dirty = true;

    public string LogPath { get; }

    public Progress(TestResult[] results, string reportPath, string logPath, Func<bool, string> buildReport, bool verbose)
    {
        _results = results;
        _reportPath = reportPath;
        _buildReport = buildReport;
        _verbose = verbose;
        LogPath = logPath;
        Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
        // FileShare.ReadWrite so Get-Content -Wait (or an editor) can read it while it's written.
        var stream = new FileStream(logPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite);
        _log = new StreamWriter(stream, new UTF8Encoding(false)) { AutoFlush = true };
    }

    public void Log(string message)
    {
        lock (_log) _log.WriteLine($"[{DateTime.Now:HH:mm:ss}] {message}");
    }

    public void Started(TestResult r)
    {
        r.StartedAt = DateTime.Now;
        r.Status = TestStatus.Running;
        _dirty = true;
        Log($"START  {r.Test.Name}");
        lock (_consoleLock) WriteColored("  >>>   ", $"{r.Test.Name} started", ConsoleColor.DarkGray);
    }

    public void Line(TestResult r, string line)
    {
        lock (r.Output) r.Output.Add(line);
        _dirty = true;
        Log($"{r.Test.Name} | {line}");
        if (_verbose)
            lock (_consoleLock) Console.WriteLine($"   {r.Test.Name} | {line}");
    }

    public void Finished(TestResult r)
    {
        _dirty = true;
        int n = Interlocked.Increment(ref _finished);
        Log($"FINISH {r.Test.Name}: {Label(r.Status)} in {r.Duration.TotalSeconds:0.0}s - {r.Detail}");
        lock (_consoleLock)
        {
            Console.Write($"[{n,2}/{_results.Length}] {r.Test.Name,-28} ");
            WriteColored("", Label(r.Status).PadRight(7), Color(r.Status), newline: false);
            Console.WriteLine($" {r.Duration.TotalSeconds,6:0.0}s  {r.Detail}");
            foreach (string f in r.FailLines.Take(5)) Console.WriteLine($"        {f}");
            if (r.FailLines.Count > 5) Console.WriteLine($"        ... and {r.FailLines.Count - 5} more");
        }
        WriteReport(live: true);
    }

    /// Ticks once a second until the run is done: rewrites the report when something changed
    /// (at most every few seconds) and prints the heartbeat.
    public async Task RunTickerAsync(int heartbeatSeconds, CancellationToken done)
    {
        var lastReport = DateTime.MinValue;
        var lastBeat = DateTime.Now;
        try
        {
            while (!done.IsCancellationRequested)
            {
                await Task.Delay(1000, done);
                var now = DateTime.Now;
                if (_dirty && now - lastReport >= TimeSpan.FromSeconds(3))
                {
                    WriteReport(live: true);
                    lastReport = now;
                }
                if (heartbeatSeconds > 0 && now - lastBeat >= TimeSpan.FromSeconds(heartbeatSeconds))
                {
                    Heartbeat();
                    lastBeat = now;
                }
            }
        }
        catch (OperationCanceledException) { }
    }

    void Heartbeat()
    {
        var running = _results.Where(r => r.Status == TestStatus.Running).ToList();
        if (running.Count == 0) return;
        int queued = _results.Count(r => r.Status == TestStatus.Queued);
        var parts = running.Select(r =>
        {
            int lines;
            string last;
            lock (r.Output)
            {
                lines = r.Output.Count;
                last = r.Output.LastOrDefault(l => l.Trim().Length > 0)?.Trim() ?? "";
            }
            if (last.Length > 50) last = last[..47] + "...";
            var t = DateTime.Now - (r.StartedAt ?? DateTime.Now);
            return $"{r.Test.Name} {(int)t.TotalMinutes}m{t.Seconds:00}s, {lines} lines{(last.Length > 0 ? $", last: {last}" : "")}";
        });
        string msg = $"{_finished}/{_results.Length} done, {queued} queued. Running: {string.Join(" | ", parts)}";
        Log($"STATUS {msg}");
        lock (_consoleLock) WriteColored("  ...   ", msg, ConsoleColor.DarkGray);
    }

    /// Writes to a temp file and moves it over the report, so a refreshing browser never
    /// reads half a page.
    public void WriteReport(bool live)
    {
        lock (_reportLock)
        {
            _dirty = false;
            Directory.CreateDirectory(Path.GetDirectoryName(_reportPath)!);
            string tmp = _reportPath + ".tmp";
            try
            {
                File.WriteAllText(tmp, _buildReport(live));
                File.Move(tmp, _reportPath, overwrite: true);
            }
            catch (IOException ex)
            {
                // A browser or virus scanner holding the file just delays this update.
                Log($"couldn't update the report yet: {ex.Message}");
                _dirty = true;
            }
        }
    }

    public static string Label(TestStatus s) => s switch
    {
        TestStatus.Passed => "PASS",
        TestStatus.Failed => "FAIL",
        TestStatus.Error => "ERROR",
        TestStatus.Running => "RUNNING",
        TestStatus.Queued => "QUEUED",
        _ => "REPORT",
    };

    static ConsoleColor Color(TestStatus s) => s switch
    {
        TestStatus.Passed => ConsoleColor.Green,
        TestStatus.Failed => ConsoleColor.Red,
        TestStatus.Error => ConsoleColor.Yellow,
        _ => ConsoleColor.Cyan,
    };

    static void WriteColored(string prefix, string text, ConsoleColor color, bool newline = true)
    {
        Console.Write(prefix);
        var old = Console.ForegroundColor;
        Console.ForegroundColor = color;
        Console.Write(text);
        Console.ForegroundColor = old;
        if (newline) Console.WriteLine();
    }

    public void Dispose()
    {
        lock (_log) _log.Dispose();
    }
}
