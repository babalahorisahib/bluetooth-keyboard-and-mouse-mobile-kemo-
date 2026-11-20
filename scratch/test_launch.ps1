$p = [System.Diagnostics.Process]::Start("C:\bluetooth keyboard and mouse\MobileKemo.exe")
Write-Host "Started PID: $($p.Id)"
$p.WaitForExit()
Write-Host "Exited with code: $($p.ExitCode)"
