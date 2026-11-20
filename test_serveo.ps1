$proc = Start-Process -FilePath "ssh" -ArgumentList "-R", "80:127.0.0.1:58921", "-o", "StrictHostKeyChecking=no", "serveo.net" -PassThru -RedirectStandardOutput "C:\bluetooth keyboard and mouse\serveo.log" -RedirectStandardError "C:\bluetooth keyboard and mouse\serveo_err.log"
Start-Sleep -Seconds 6
$out = Get-Content "C:\bluetooth keyboard and mouse\serveo.log" -ErrorAction SilentlyContinue
$err = Get-Content "C:\bluetooth keyboard and mouse\serveo_err.log" -ErrorAction SilentlyContinue
Write-Output "OUT: $out"
Write-Output "ERR: $err"
Stop-Process -Id $proc.Id -Force
