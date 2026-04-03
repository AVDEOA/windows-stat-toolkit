using System.IO;
using System.Text.Json;
using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Services;

public sealed class AppStateService
{
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        WriteIndented = true
    };

    public string StateRoot { get; }
    public string ReportsRoot { get; }
    public string StateFilePath { get; }

    public AppStateService()
    {
        StateRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WindowsStatToolkit");
        ReportsRoot = Path.Combine(StateRoot, "reports");
        StateFilePath = Path.Combine(StateRoot, "app-state.json");

        Directory.CreateDirectory(StateRoot);
        Directory.CreateDirectory(ReportsRoot);
    }

    public async Task<AppState> LoadAsync()
    {
        if (!File.Exists(StateFilePath))
        {
            return new AppState();
        }

        await using var stream = File.OpenRead(StateFilePath);
        return await JsonSerializer.DeserializeAsync<AppState>(stream, _jsonOptions) ?? new AppState();
    }

    public async Task SaveAsync(AppState state)
    {
        Directory.CreateDirectory(StateRoot);
        await using var stream = File.Create(StateFilePath);
        await JsonSerializer.SerializeAsync(stream, state, _jsonOptions);
    }

    public async Task<string> SaveReportAsync(string hostName, string suffix, string extension, string content)
    {
        var safeHost = MakeSafeName(hostName);
        var fileName = $"{DateTime.Now:yyyy-MM-dd_HH-mm-ss}_{safeHost}_{suffix}.{extension}";
        var path = Path.Combine(ReportsRoot, fileName);
        await File.WriteAllTextAsync(path, content);
        return path;
    }

    public IReadOnlyList<string> GetRecentReportFiles(int take = 50)
    {
        if (!Directory.Exists(ReportsRoot))
        {
            return [];
        }

        return Directory
            .GetFiles(ReportsRoot)
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .Take(take)
            .ToArray();
    }

    private static string MakeSafeName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars();
        return new string(value.Select(ch => invalid.Contains(ch) ? '_' : ch).ToArray());
    }
}
