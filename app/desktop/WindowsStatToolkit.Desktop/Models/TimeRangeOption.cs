namespace WindowsStatToolkit.Desktop.Models;

public sealed record TimeRangeOption(string Label, int? Days)
{
    public override string ToString() => Label;
}
