Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinList {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
[WinList]::EnumWindows({ param($hWnd, $lParam)
    if ([WinList]::IsWindowVisible($hWnd)) {
        $sb = New-Object System.Text.StringBuilder(256)
        $len = [WinList]::GetWindowText($hWnd, $sb, 256)
        if ($len -gt 0) {
            $rect = New-Object WinList+RECT
            [WinList]::GetWindowRect($hWnd, [ref]$rect) | Out-Null
            Write-Output "$($sb.ToString()) | Bounds: $($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)"
        }
    }
    return $true
}, [IntPtr]::Zero)
