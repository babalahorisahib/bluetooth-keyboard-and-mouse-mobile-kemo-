$code = @"
using System;
using System.Runtime.InteropServices;
public class WinTest {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);
}
"@
Add-Type -TypeDefinition $code
$h = [WinTest]::FindWindow("MobileKemoMainWindowClass", $null)
$procId = [uint32]0
$tid = [WinTest]::GetWindowThreadProcessId($h, [ref]$procId)
Write-Output "Hwnd: $h, IsWindow: $([WinTest]::IsWindow($h)), PID: $procId, TID: $tid"
if ($procId -gt 0) {
    Get-Process -Id $procId | Format-List Id, ProcessName, Path, StartTime
}
