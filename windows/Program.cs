using System.Windows.Forms;

namespace ConsoClaude;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        // Instance unique : une seule icône dans le tray.
        using var mutex = new Mutex(true, "ConsoClaude.SingleInstance", out bool isNew);
        if (!isNew) return;

        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        Application.Run(new TrayApp());

        GC.KeepAlive(mutex);
    }
}
