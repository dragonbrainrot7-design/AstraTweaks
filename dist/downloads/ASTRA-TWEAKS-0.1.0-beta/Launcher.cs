using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using System.Reflection;
[assembly: AssemblyTitle("ASTRA TWEAKS")]
[assembly: AssemblyDescription("Centre de contrôle Windows portable")]
[assembly: AssemblyVersion("0.1.0.0")]
internal static class Launcher {
    [STAThread] private static void Main() {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, "Astra.ps1");
        if (!File.Exists(script)) { MessageBox.Show("Extrayez toute l'archive ASTRA avant de lancer l'application.", "ASTRA TWEAKS"); return; }
        string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        try {
            // Process-scoped policy only: no persisted execution-policy or security changes.
            var start = new ProcessStartInfo(powershell, "-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File \"" + script + "\"");
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.WorkingDirectory = root;
            using (Process child = Process.Start(start)) { child.WaitForExit(); }
        } catch (Exception ex) { MessageBox.Show(ex.Message, "ASTRA TWEAKS"); }
    }
}
