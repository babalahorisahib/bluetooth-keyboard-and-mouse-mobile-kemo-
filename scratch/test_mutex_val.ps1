$def = @'
using System;
using System.Runtime.InteropServices;
public class Win {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateMutexW(IntPtr lpSecurity, bool bInitialOwner, string lpName);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);
}
'@
Add-Type -TypeDefinition $def
$h = [Win]::CreateMutexW([IntPtr]::Zero, $true, "Global\MobileKemoDesktopSingleInstanceMutex")
$err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host "Handle: $h, LastError: $err"
if ($h -ne [IntPtr]::Zero) { [Win]::CloseHandle($h) }
