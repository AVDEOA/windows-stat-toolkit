using System.Diagnostics;
using System.IO;
using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Services;

public sealed class SshCommandRunner
{
    public async Task<string> RunCommandAsync(
        HostDefinition host,
        string executable,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        var sshPath = ResolveSshPath();
        var psi = new ProcessStartInfo
        {
            FileName = sshPath,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        psi.ArgumentList.Add("-o");
        psi.ArgumentList.Add("BatchMode=yes");
        psi.ArgumentList.Add("-o");
        psi.ArgumentList.Add("ConnectTimeout=10");
        psi.ArgumentList.Add("-o");
        psi.ArgumentList.Add("StrictHostKeyChecking=accept-new");
        psi.ArgumentList.Add("-p");
        psi.ArgumentList.Add(host.Port.ToString());

        if (!string.IsNullOrWhiteSpace(host.KeyPath))
        {
            psi.ArgumentList.Add("-i");
            psi.ArgumentList.Add(host.KeyPath);
        }

        psi.ArgumentList.Add($"{host.UserName}@{host.Address}");
        psi.ArgumentList.Add(executable);

        foreach (var argument in arguments)
        {
            psi.ArgumentList.Add(argument);
        }

        using var process = new Process { StartInfo = psi };
        process.Start();

        var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);

        var stdout = await stdoutTask;
        var stderr = await stderrTask;

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(
                $"SSH command failed for {host.Name}: {executable} {string.Join(' ', arguments)}{Environment.NewLine}{stderr}{Environment.NewLine}{stdout}".Trim());
        }

        return stdout;
    }

    private static string ResolveSshPath()
    {
        var windowsPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            "System32",
            "OpenSSH",
            "ssh.exe");

        if (File.Exists(windowsPath))
        {
            return windowsPath;
        }

        return "ssh.exe";
    }
}
