$proc = Start-Process -FilePath "ssh" -ArgumentList "-R", "80:127.0.0.1:58921", "-o", "StrictHostKeyChecking=no", "-o", "ServerAliveInterval=30", "nokey@localhost.run" -PassThru -RedirectStandardOutput "C:\bluetooth keyboard and mouse\lhrun.log" -RedirectStandardError "C:\bluetooth keyboard and mouse\lhrun_err.log"
Start-Sleep -Seconds 6
$out = Get-Content "C:\bluetooth keyboard and mouse\lhrun.log" -ErrorAction SilentlyContinue
$err = Get-Content "C:\bluetooth keyboard and mouse\lhrun_err.log" -ErrorAction SilentlyContinue
Write-Output "OUT: $out"
Write-Output "ERR: $err"
Stop-Process -Id $proc.Id -Force
