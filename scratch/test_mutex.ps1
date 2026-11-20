$first = Start-Process -FilePath "C:\bluetooth keyboard and mouse\MobileKemo.exe" -PassThru
Start-Sleep -Seconds 3

Write-Host "First Instance Id: $($first.Id), HasExited: $($first.HasExited)"

# Start a second instance
$second = Start-Process -FilePath "C:\bluetooth keyboard and mouse\MobileKemo.exe" -PassThru -Wait
Write-Host "Second Instance ExitCode: $($second.ExitCode)"

Start-Sleep -Seconds 2
Write-Host "First Instance after second closed: HasExited: $($first.HasExited)"

$net = netstat -ano | findstr 58921
Write-Host "Port 58921 listeners: $net"

# Stop first instance to keep environment clean
Stop-Process -Id $first.Id -Force
