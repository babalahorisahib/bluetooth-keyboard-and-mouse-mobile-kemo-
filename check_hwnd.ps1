$code = @"
using System;
using System.Runtime.InteropServices;

public class WinCheck {
    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);
}
"@
Add-Type -TypeDefinition $code
$val = [IntPtr]0xb0020
Write-Output "IsWindow(0xb0020): $([WinCheck]::IsWindow($val))"
