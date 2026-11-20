$p = Start-Process -FilePath "C:\bluetooth keyboard and mouse\MobileKemo.exe" -PassThru
Write-Host "Spawned PID: $($p.Id)"
Start-Sleep -Seconds 3
Get-Process -Id $p.Id | Select-Object Id, ProcessName, Responding, Path
Get-NetTCPConnection -LocalPort 58921 -ErrorAction SilentlyContinue | Select-Object LocalAddress, LocalPort, State
