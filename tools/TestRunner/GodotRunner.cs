using System.Diagnostics;
using System.Text.RegularExpressions;

namespace TestRunner;

/// Starts headless Godot and collects its output.
sealed partial class GodotRunner
{
    readonly string _godot;
    readonly string _project;

    public GodotRunner(string godotPath, string projectRoot)
    {
        _godot = godotPath;
        _project = projectRoot;
    }

    [GeneratedRegex(@"\x1B\[[0-9;?]*[ -/]*[@-~]")]
    private static partial Regex AnsiRegex();

    public sealed record RunOutput(List<string> Lines, int ExitCode, bool TimedOut, TimeSpan Duration);

    /// onLine is called with each output line as it arrives (from a background thread).
    public async Task<RunOutput> RunAsync(IEnumerable<string> args, TimeSpan timeout, Action<string>? onLine = null)
    {
        var psi = new ProcessStartInfo(_godot)
        {
            WorkingDirectory = _project,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (string a in args) psi.ArgumentList.Add(a);

        var lines = new List<string>();
        void Add(string? line)
        {
            if (line == null) return;
            line = AnsiRegex().Replace(line, "").TrimEnd('\r');
            lock (lines) lines.Add(line);
            onLine?.Invoke(line);
        }

        var sw = Stopwatch.StartNew();
        using var proc = new Process { StartInfo = psi };
        proc.OutputDataReceived += (_, e) => Add(e.Data);
        proc.ErrorDataReceived += (_, e) => Add(e.Data);
        try
        {
            proc.Start();
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException($"Couldn't start Godot at '{_godot}': {ex.Message}", ex);
        }
        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();

        bool timedOut = false;
        using (var cts = new CancellationTokenSource(timeout))
        {
            try
            {
                await proc.WaitForExitAsync(cts.Token);
            }
            catch (OperationCanceledException)
            {
                timedOut = true;
                try { proc.Kill(entireProcessTree: true); } catch { /* already gone */ }
                await proc.WaitForExitAsync();
            }
        }
        // The no-arg WaitForExit flushes the async output readers.
        proc.WaitForExit();
        sw.Stop();

        List<string> copy;
        lock (lines) copy = new List<string>(lines);
        return new RunOutput(copy, timedOut ? -1 : proc.ExitCode, timedOut, sw.Elapsed);
    }

    public Task<RunOutput> RunScriptAsync(TestCase test, TimeSpan timeout, Action<string>? onLine = null) =>
        RunAsync(new[] { "--headless", "--path", _project, "--script", test.ResPath }, timeout, onLine);

    public Task<RunOutput> ImportAsync(TimeSpan timeout) =>
        RunAsync(new[] { "--headless", "--path", _project, "--import" }, timeout);

    public async Task<string> VersionAsync()
    {
        try
        {
            var r = await RunAsync(new[] { "--version" }, TimeSpan.FromSeconds(30));
            return r.Lines.FirstOrDefault(l => l.Trim().Length > 0)?.Trim() ?? "unknown";
        }
        catch (InvalidOperationException)
        {
            return "unknown";
        }
    }
}
