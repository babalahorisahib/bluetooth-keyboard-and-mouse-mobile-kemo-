$proc = Start-Process -FilePath "C:\bluetooth keyboard and mouse\MobileKemo.exe" -PassThru
for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 1
    Write-Host "Second ${i} HasExited=$($proc.HasExited) ExitCode=$($proc.ExitCode)"
    if ($proc.HasExited) { break }
}
