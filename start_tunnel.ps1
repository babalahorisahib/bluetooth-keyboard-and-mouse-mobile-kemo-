# Ensure host entry exists for api.trycloudflare.com
$hostsFile = "C:\Windows\System32\drivers\etc\hosts"
$hostsContent = Get-Content $hostsFile -Raw -ErrorAction SilentlyContinue
if ($hostsContent -notmatch "104\.16\.231\.132\s+api\.trycloudflare\.com") {
    Add-Content -Path $hostsFile -Value "`n104.16.231.132 api.trycloudflare.com"
}

while ($true) {
    Write-Output "Starting Cloudflare Quick Tunnel..."
    $proc = Start-Process -FilePath "C:\bluetooth keyboard and mouse\cloudflared.exe" `
        -ArgumentList "tunnel", "--edge-ip-version", "4", "--protocol", "http2", "--url", "http://127.0.0.1:58921" `
        -PassThru -RedirectStandardError "C:\bluetooth keyboard and mouse\tunnel.log"

    $tunnelFound = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Path "C:\bluetooth keyboard and mouse\tunnel.log") {
            $content = Get-Content "C:\bluetooth keyboard and mouse\tunnel.log" -Tail 40
            $match = $content | Select-String "https://[a-zA-Z0-9-]+\.trycloudflare\.com"
            if ($match) {
                $url = $match.Matches[0].Value
                if ($url -notmatch "api\.trycloudflare" -and $url -notmatch "pkg\.trycloudflare") {
                    Set-Content -Path "C:\bluetooth keyboard and mouse\tunnel_active.txt" -Value $url -Force
                    Write-Output "ACTIVE_TUNNEL: $url"
                    $tunnelFound = $true
                    break
                }
            }
        }
        if ($proc.HasExited) { break }
    }

    $proc.WaitForExit()
    Write-Output "Cloudflare process exited with code $($proc.ExitCode). Restarting in 3s..."
    Start-Sleep -Seconds 3
}
