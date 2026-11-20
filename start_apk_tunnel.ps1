$proc = Start-Process -FilePath "C:\bluetooth keyboard and mouse\cloudflared.exe" -ArgumentList "tunnel", "--url", "http://127.0.0.1:8080" -PassThru -RedirectStandardError "C:\bluetooth keyboard and mouse\apk_tunnel.log"
Start-Sleep -Seconds 6
$match = Get-Content "C:\bluetooth keyboard and mouse\apk_tunnel.log" | Select-String "https://[a-zA-Z0-9-]+\.trycloudflare\.com"
if ($match) {
    Write-Output "APK_TUNNEL: $($match.Matches[0].Value)"
}
$proc.WaitForExit()
