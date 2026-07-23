using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

internal static class AuralithTestLauncher
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetWindowText(IntPtr windowHandle, string title);

    [STAThread]
    private static int Main(string[] args)
    {
        string installPath = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        string executable = Path.Combine(installPath, "Auralith_Editer.exe");
        if (!File.Exists(executable))
        {
            return 2;
        }

        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = executable;
        startInfo.WorkingDirectory = installPath;
        startInfo.UseShellExecute = true;
        if (args.Length > 0 && !string.IsNullOrWhiteSpace(args[0]))
        {
            string document = Path.GetFullPath(args[0]);
            if (!File.Exists(document))
            {
                return 3;
            }

            startInfo.Arguments = "--log " + QuoteArgument(document);
        }

        Process.Start(startInfo);

        bool ownsMutex = false;
        using (Mutex mutex = new Mutex(
            false,
            "Local\\Auralith_Editer_Test_TitleBridge"
        ))
        {
            try
            {
                ownsMutex = mutex.WaitOne(0);
                if (!ownsMutex)
                {
                    return 0;
                }

                bool sawEditor = false;
                int startupPolls = 0;
                while (true)
                {
                    Process[] editors = GetManagedEditors(installPath);
                    if (editors.Length == 0)
                    {
                        if (sawEditor || startupPolls++ >= 120)
                        {
                            break;
                        }

                        Thread.Sleep(250);
                        continue;
                    }

                    sawEditor = true;
                    foreach (Process editor in editors)
                    {
                        try
                        {
                            editor.Refresh();
                            IntPtr windowHandle = editor.MainWindowHandle;
                            string currentTitle = editor.MainWindowTitle;
                            if (
                                windowHandle == IntPtr.Zero ||
                                string.IsNullOrWhiteSpace(currentTitle)
                            )
                            {
                                continue;
                            }

                            int separatorIndex = currentTitle.LastIndexOf(
                                " - ",
                                StringComparison.Ordinal
                            );
                            string auralithTitle = separatorIndex >= 0
                                ? currentTitle.Substring(0, separatorIndex) +
                                    " - Auralith_Editer"
                                : "Auralith_Editer";

                            if (!string.Equals(
                                currentTitle,
                                auralithTitle,
                                StringComparison.Ordinal
                            ))
                            {
                                SetWindowText(windowHandle, auralithTitle);
                            }
                        }
                        catch
                        {
                            // The editor may close or recreate its window mid-poll.
                        }
                        finally
                        {
                            editor.Dispose();
                        }
                    }

                    Thread.Sleep(500);
                }
            }
            finally
            {
                if (ownsMutex)
                {
                    mutex.ReleaseMutex();
                }
            }
        }

        return 0;
    }

    private static Process[] GetManagedEditors(string installPath)
    {
        Process[] candidates = Process.GetProcessesByName("editors");
        System.Collections.Generic.List<Process> matches =
            new System.Collections.Generic.List<Process>();
        string prefix = installPath + Path.DirectorySeparatorChar;

        foreach (Process candidate in candidates)
        {
            bool keep = false;
            try
            {
                string processPath = Path.GetFullPath(
                    candidate.MainModule.FileName
                );
                keep = processPath.StartsWith(
                    prefix,
                    StringComparison.OrdinalIgnoreCase
                );
            }
            catch
            {
                keep = false;
            }

            if (keep)
            {
                matches.Add(candidate);
            }
            else
            {
                candidate.Dispose();
            }
        }

        return matches.ToArray();
    }

    private static string QuoteArgument(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }
}
