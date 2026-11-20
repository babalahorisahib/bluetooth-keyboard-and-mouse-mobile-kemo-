$signature = @'
[DllImport("user32.dll", SetLastError = true)]
public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

[DllImport("user32.dll", SetLastError = true)]
public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
'@

$type = Add-Type -MemberDefinition $signature -Name "Win32Utils" -Namespace "Win32" -PassThru
$hwnd = $type::FindWindow("MobileKemoMainWindowClass", $null)
Write-Host "Found HWND: $hwnd"
if ($hwnd -ne [IntPtr]::Zero) {
    $pidOut = 0
    $threadId = $type::GetWindowThreadProcessId($hwnd, [ref]$pidOut)
    Write-Host "Window Thread ID: $threadId, Process ID: $pidOut"
    Get-Process -Id $pidOut | Select-Object Id, ProcessName, Path
}
