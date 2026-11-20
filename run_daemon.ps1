$proc = Start-Process "C:\bluetooth keyboard and mouse\MobileKemo.exe" -PassThru
Start-Sleep -Seconds 2
Write-Output "MobileKemo PID: $($proc.Id), Responding: $($proc.Responding)"
$proc.WaitForExit()
