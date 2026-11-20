Remove-Item "C:\bluetooth keyboard and mouse\*.log" -Force -ErrorAction SilentlyContinue
$p = Start-Process -FilePath "C:\bluetooth keyboard and mouse\MobileKemo.exe" -PassThru
Start-Sleep -Seconds 3
Write-Output "PID: $($p.Id), HasExited: $($p.HasExited)"
Get-ChildItem "C:\bluetooth keyboard and mouse\*.log" | Select-Object Name, Length, LastWriteTime
