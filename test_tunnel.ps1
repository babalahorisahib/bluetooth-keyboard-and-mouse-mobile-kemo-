$proc = Start-Process -FilePath "C:\bluetooth keyboard and mouse\cloudflared.exe" -ArgumentList "tunnel", "--url", "http://127.0.0.1:58921" -PassThru -RedirectStandardError "C:\bluetooth keyboard and mouse\tunnel.log"
Start-Sleep -Seconds 10
$content = Get-Content "C:\bluetooth keyboard and mouse\tunnel.log"
Write-Output $content
Stop-Process -Id $proc.Id -Force
