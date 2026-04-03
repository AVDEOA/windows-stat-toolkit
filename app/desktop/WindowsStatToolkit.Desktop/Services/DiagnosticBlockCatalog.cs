using WindowsStatToolkit.Desktop.Models;

namespace WindowsStatToolkit.Desktop.Services;

public static class DiagnosticBlockCatalog
{
    private static readonly IReadOnlyList<DiagnosticBlockDefinition> Blocks =
    [
        new("block1", "Block 1 - General system information", "System configuration"),
        new("block2", "Block 2 - System statistics, uptime, and health overview", "System stats and uptime"),
        new("block3", "Block 3 - Driver and device initialization errors", "Driver and device errors"),
        new("block4", "Block 4 - Video driver and GPU errors", "GPU and video driver errors"),
        new("block5", "Block 5 - WHEA, PCIe, and hardware stability errors", "WHEA and PCIe hardware errors"),
        new("block6", "Block 6 - BSOD, crash, and dump history", "BSOD, crash and dump history"),
        new("block7", "Block 7 - Additional critical stability signals", "Additional critical stability signals")
    ];

    public static IReadOnlyList<DiagnosticBlockDefinition> GetBlocks() => Blocks;

    public static DiagnosticBlockDefinition Get(string blockId)
    {
        return Blocks.First(b => b.Id == blockId);
    }
}
