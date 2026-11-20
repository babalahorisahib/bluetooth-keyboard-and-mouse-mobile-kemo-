$code = @"
using System;
using System.Runtime.InteropServices;
public class WinFind {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
"@
Add-Type -TypeDefinition $code
$hwnd = [WinFind]::FindWindow("MobileKemoMainWindowClass", $null)
Write-Host "HWND: $hwnd"
if ($hwnd -ne [IntPtr]::Zero) {
    $procId = 0
    [WinFind]::GetWindowThreadProcessId($hwnd, [ref]$procId)
    Write-Host "PID: $procId"
    Get-Process -Id $procId -ErrorAction SilentlyContinue | Format-List Id, ProcessName, Path
} else {
    Write-Host "No window with MobileKemoMainWindowClass found."
}
