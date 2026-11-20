$p2 = Start-Process -FilePath "C:\bluetooth keyboard and mouse\MobileKemo.exe" -PassThru
Start-Sleep -Seconds 1
Write-Output "Second instance PID: $($p2.Id), HasExited: $($p2.HasExited)"
Get-Content "C:\bluetooth keyboard and mouse\exit_reason.log" -ErrorAction SilentlyContinue
