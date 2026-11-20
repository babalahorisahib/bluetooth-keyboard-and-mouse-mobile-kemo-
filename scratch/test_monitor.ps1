$p = Start-Process -FilePath "C:\bluetooth keyboard and mouse\MobileKemo.exe" -WorkingDirectory "C:\bluetooth keyboard and mouse" -PassThru
Write-Output "Started PID: $($p.Id)"
for ($i = 0; $i -lt 12; $i++) {
    Start-Sleep -Milliseconds 500
    $proc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Output "[$i] Alive! WorkingSet: $($proc.WorkingSet64) Threads: $($proc.Threads.Count)"
    } else {
        Write-Output "[$i] Process has terminated!"
        break
    }
}
