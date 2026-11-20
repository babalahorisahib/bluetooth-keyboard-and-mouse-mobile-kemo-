Get-Process -Name "*MobileKemo*", "*keylink*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

Copy-Item -Path "D:\cargo_target\release\keylink-desktop.exe" -Destination "C:\bluetooth keyboard and mouse\desktop\bin\MobileKemo.exe" -Force
Copy-Item -Path "D:\cargo_target\release\keylink-desktop.exe" -Destination "C:\bluetooth keyboard and mouse\MobileKemo.exe" -Force

$wsh = New-Object -ComObject WScript.Shell
$desktopPaths = @(
    "C:\Users\Administrator\OneDrive\Desktop",
    "C:\Users\Administrator\Desktop"
)

foreach ($dp in $desktopPaths) {
    if (Test-Path $dp) {
        $lnkPath = Join-Path $dp "Mobile Kemo.lnk"
        $shortcut = $wsh.CreateShortcut($lnkPath)
        $shortcut.TargetPath = "C:\bluetooth keyboard and mouse\MobileKemo.exe"
        $shortcut.WorkingDirectory = "C:\bluetooth keyboard and mouse"
        $shortcut.IconLocation = "C:\bluetooth keyboard and mouse\icon.ico,0"
        $shortcut.Description = "Mobile Kemo - Wireless Keyboard, Mouse & Screen Server"
        $shortcut.Save()
        Write-Output "Created shortcut at: $lnkPath"
    }
}
