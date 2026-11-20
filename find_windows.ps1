$code = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class WindowFinder {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    public static void FindWindowsForPid(uint targetPid) {
        EnumWindows((hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == targetPid) {
                var sbTitle = new StringBuilder(256);
                GetWindowText(hWnd, sbTitle, 256);
                var sbClass = new StringBuilder(256);
                GetClassName(hWnd, sbClass, 256);
                bool visible = IsWindowVisible(hWnd);
                Console.WriteLine("HWND: " + hWnd.ToString("X") + " Class: " + sbClass.ToString() + " Visible: " + visible + " Title: " + sbTitle.ToString());
            }
            return true;
        }, IntPtr.Zero);
    }
}
"@

Add-Type -TypeDefinition $code
$targetPid = (Get-Process -Name MobileKemo -ErrorAction SilentlyContinue | Select-Object -First 1).Id
if ($targetPid) {
    Write-Output "Checking windows for PID: $targetPid"
    [WindowFinder]::FindWindowsForPid($targetPid)
} else {
    Write-Output "No MobileKemo process found"
}
