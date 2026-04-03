namespace WindowsStatToolkit.Desktop.Models;

public sealed class TelegramSettings
{
    public string BotToken { get; set; } = string.Empty;
    public string ChatId { get; set; } = string.Empty;
    public bool Enabled { get; set; }
}
