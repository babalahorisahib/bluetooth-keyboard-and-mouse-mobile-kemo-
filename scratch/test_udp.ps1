$client = New-Object System.Net.Sockets.UdpClient
$client.Client.ReceiveTimeout = 2000
$ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, 58922)
$bytes = [System.Text.Encoding]::UTF8.GetBytes("DISCOVER_KEMO")
[void]$client.Send($bytes, $bytes.Length, $ep)
$sender = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
$recv = $client.Receive([ref]$sender)
$resp = [System.Text.Encoding]::UTF8.GetString($recv)
Write-Output "UDP Response: $resp"
$client.Close()
