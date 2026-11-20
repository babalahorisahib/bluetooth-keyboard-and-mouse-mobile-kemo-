$p = Start-Process -FilePath "C:\bluetooth keyboard and mouse\MobileKemo.exe" -WorkingDirectory "C:\bluetooth keyboard and mouse" -PassThru
Write-Output "Started PID: $($p.Id)"
$p.WaitForExit()
Write-Output "Process has exited! ExitCode: $($p.ExitCode)"
