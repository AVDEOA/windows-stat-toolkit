using System.IO;
using System.Security.Cryptography;
using System.Text;
using Renci.SshNet;
using Renci.SshNet.Common;
using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Services;

public sealed class SshCommandRunner
{
    public async Task<string> RunCommandTextAsync(
        HostDefinition host,
        string commandText,
        CancellationToken cancellationToken)
    {
        return await Task.Run(() =>
        {
            using var client = CreateClient(host);
            client.Connect();
            try
            {
                using var command = client.CreateCommand(commandText);
                command.CommandTimeout = TimeSpan.FromMinutes(3);
                var stdout = command.Execute();
                var stderr = command.Error?.Trim() ?? string.Empty;

                if (command.ExitStatus != 0)
                {
                    throw new InvalidOperationException(
                        $"Remote command failed on {host.Name}. Exit status: {command.ExitStatus}. {TrimForUi(stderr)}");
                }

                return stdout ?? string.Empty;
            }
            finally
            {
                if (client.IsConnected)
                {
                    client.Disconnect();
                }
            }
        }, cancellationToken);
    }

    public async Task<string> TestConnectivityAsync(HostDefinition host, CancellationToken cancellationToken)
    {
        return await RunCommandTextAsync(host, @"cmd.exe /c hostname", cancellationToken);
    }

    private static SshClient CreateClient(HostDefinition host)
    {
        var authenticationMethods = CreateAuthenticationMethods(host);
        var connectionInfo = new ConnectionInfo(host.Address, host.Port, host.UserName, authenticationMethods.ToArray())
        {
            Timeout = TimeSpan.FromSeconds(20)
        };

        var client = new SshClient(connectionInfo);
        client.HostKeyReceived += (_, args) =>
        {
            var fingerprint = BuildFingerprint(args.HostKey);
            if (string.IsNullOrWhiteSpace(host.KnownHostFingerprint))
            {
                host.KnownHostFingerprint = fingerprint;
                args.CanTrust = true;
                return;
            }

            if (string.Equals(host.KnownHostFingerprint, fingerprint, StringComparison.OrdinalIgnoreCase))
            {
                args.CanTrust = true;
                return;
            }

            throw new InvalidOperationException(
                $"SSH host key mismatch for {host.Name}. Saved fingerprint: {host.KnownHostFingerprint}. Current fingerprint: {fingerprint}.");
        };

        return client;
    }

    private static List<AuthenticationMethod> CreateAuthenticationMethods(HostDefinition host)
    {
        var methods = new List<AuthenticationMethod>();
        var password = SecretProtector.Unprotect(host.PasswordProtected);

        if (!string.IsNullOrWhiteSpace(host.KeyPath))
        {
            if (!File.Exists(host.KeyPath))
            {
                throw new InvalidOperationException($"SSH key file not found: {host.KeyPath}");
            }

            methods.Add(new PrivateKeyAuthenticationMethod(host.UserName, new PrivateKeyFile(host.KeyPath)));
        }

        if (!string.IsNullOrWhiteSpace(password))
        {
            methods.Add(new PasswordAuthenticationMethod(host.UserName, password));
        }

        if (methods.Count == 0)
        {
            throw new InvalidOperationException(
                "SSH authentication is not configured. Fill in either an SSH password or an SSH key path.");
        }

        return methods;
    }

    private static string BuildFingerprint(byte[] hostKey)
    {
        var hash = SHA256.HashData(hostKey);
        return $"SHA256:{Convert.ToBase64String(hash)}";
    }

    private static string TrimForUi(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "No remote error text was returned.";
        }

        var compact = value.Replace(Environment.NewLine, " ").Replace('\n', ' ').Replace('\r', ' ').Trim();
        return compact.Length <= 320 ? compact : $"{compact[..320]}...";
    }
}
