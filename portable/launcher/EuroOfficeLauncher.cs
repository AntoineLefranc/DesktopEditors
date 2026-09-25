// Euro-Office Portable - lanceur sans console.
//
// Petit exécutable Windows (sous-système GUI) placé à la racine du dossier
// portable. Il exécute Launcher\EuroOffice-Portable.ps1 avec Windows
// PowerShell SANS fenêtre de console (CreateNoWindow) : contrairement à
// "powershell -WindowStyle Hidden", aucune fenêtre n'est jamais créée, même
// quand Windows Terminal est le terminal par défaut (Windows 11).
//
// Compilation (csc.exe du .NET Framework 4.x, présent sur tout Windows) :
//   csc /target:winexe /win32icon:euro-office.ico /out:Euro-Office.exe EuroOfficeLauncher.cs

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Euro-Office Portable")]
[assembly: AssemblyProduct("Euro-Office Portable")]
[assembly: AssemblyDescription("Lance Euro-Office en mode portable")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

static class EuroOfficeLauncher
{
    const string Title = "Euro-Office Portable";

    [STAThread]
    static int Main(string[] args)
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, "Launcher", "EuroOffice-Portable.ps1");
        string powershell = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            @"WindowsPowerShell\v1.0\powershell.exe");

        if (!File.Exists(script))
        {
            MessageBox.Show("Script introuvable :\n" + script, Title,
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        var arguments = new StringBuilder();
        arguments.Append("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ");
        arguments.Append(Quote(script));
        foreach (string arg in args)   // documents passés par glisser-déposer
        {
            arguments.Append(' ').Append(Quote(arg));
        }

        var startInfo = new ProcessStartInfo(powershell, arguments.ToString())
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = root,
        };

        try
        {
            Process.Start(startInfo);
        }
        catch (Exception e)
        {
            MessageBox.Show("Impossible de lancer Windows PowerShell :\n" + e.Message, Title,
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }

    // Guillemets selon les règles de la ligne de commande Windows
    // (un chemin de fichier ne contient jamais de guillemet).
    static string Quote(string value)
    {
        if (value.EndsWith("\\")) value += "\\";
        return "\"" + value + "\"";
    }
}
