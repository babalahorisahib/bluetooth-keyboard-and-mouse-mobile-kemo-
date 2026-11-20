$start = Get-Date
$process = Start-Process -FilePath "C:\bluetooth keyboard and mouse\MobileKemo.exe" -NoNewWindow -PassThru -Wait
$elapsed = (Get-Date) - $start
Write-Output "ExitCode: $($process.ExitCode), TotalSeconds: $($elapsed.TotalSeconds)"
