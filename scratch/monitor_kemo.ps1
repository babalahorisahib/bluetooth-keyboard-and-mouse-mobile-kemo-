$p = Start-Process -FilePath "C:\bluetooth keyboard and mouse\MobileKemo.exe" -PassThru
Write-Host "Started MobileKemo PID: $($p.Id)"

for ($i = 1; $i -le 10; $i++) {
    Start-Sleep -Seconds 1
    $proc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
    $alive = if ($proc) { "ALIVE (Responding: $($proc.Responding), WS: $($proc.WorkingSet64 / 1MB) MB)" } else { "DEAD" }
    $conn = Get-NetTCPConnection -LocalPort 58921 -ErrorAction SilentlyContinue
    $portStatus = if ($conn) { "Port 58921: $($conn.State)" } else { "Port 58921: CLOSED" }
    Write-Host "T+${i}s: PID $($p.Id) $alive | $portStatus"
    if (-not $proc) {
        break
    }
}
