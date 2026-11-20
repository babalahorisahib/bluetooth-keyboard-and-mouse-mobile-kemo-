$procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "MobileKemo|keylink" }
foreach ($p in $procs) {
    Write-Host "Killing old process: $($p.Id) - $($p.ProcessName)"
    Stop-Process -Id $p.Id -Force
}
Start-Sleep -Seconds 1
$newP = Start-Process -FilePath "C:\bluetooth keyboard and mouse\MobileKemo.exe" -PassThru
Write-Host "Started new process: $($newP.Id)"
Start-Sleep -Seconds 3
Get-Process -Id $newP.Id
Get-NetTCPConnection -LocalPort 58921 -ErrorAction SilentlyContinue
