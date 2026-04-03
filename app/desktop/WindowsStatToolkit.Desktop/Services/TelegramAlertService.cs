using System.Net.Http;
using System.Net.Http.Json;
using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Services;

public sealed class TelegramAlertService(HttpClient httpClient)
{
    public async Task SendAsync(TelegramSettings settings, string message, CancellationToken cancellationToken)
    {
        if (!settings.Enabled ||
            string.IsNullOrWhiteSpace(settings.BotToken) ||
            string.IsNullOrWhiteSpace(settings.ChatId))
        {
            return;
        }

        var url = $"https://api.telegram.org/bot{settings.BotToken}/sendMessage";
        var payload = new
        {
            chat_id = settings.ChatId,
            text = message
        };

        using var response = await httpClient.PostAsJsonAsync(url, payload, cancellationToken);
        response.EnsureSuccessStatusCode();
    }
}
