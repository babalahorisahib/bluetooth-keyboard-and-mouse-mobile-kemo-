$p = Start-Process "C:\bluetooth keyboard and mouse\MobileKemo.exe" -PassThru
Start-Sleep -Seconds 2
Get-Process -Id $p.Id | Select-Object Id, ProcessName, Responding
Test-NetConnection -ComputerName 127.0.0.1 -Port 58921 | Select-Object TcpTestSucceeded
