$proc = Start-Process -FilePath "ssh" -ArgumentList "-p", "443", "-R", "0:127.0.0.1:58921", "-o", "StrictHostKeyChecking=no", "-o", "ServerAliveInterval=10", "a.pinggy.io" -PassThru -RedirectStandardOutput "C:\bluetooth keyboard and mouse\pinggy.log" -RedirectStandardError "C:\bluetooth keyboard and mouse\pinggy_err.log"
Start-Sleep -Seconds 6
Get-Content "C:\bluetooth keyboard and mouse\pinggy.log" -ErrorAction SilentlyContinue
Get-Content "C:\bluetooth keyboard and mouse\pinggy_err.log" -ErrorAction SilentlyContinue
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
