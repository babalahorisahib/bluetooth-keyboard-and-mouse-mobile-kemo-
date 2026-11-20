$s = 'kemo_rendezvous:waseem:179887'
$sha = [System.Security.Cryptography.SHA256]::Create()
$bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
$hex = [System.BitConverter]::ToString($bytes).Replace('-','').ToLower()
$topic = 'kemo_v2_' + $hex.Substring(0, 20)
Write-Output "Topic: $topic"
