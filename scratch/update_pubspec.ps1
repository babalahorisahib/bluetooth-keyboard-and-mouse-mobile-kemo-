$content = [System.IO.File]::ReadAllText("mobile\pubspec.yaml")
$newContent = $content.Replace("speech_to_text: ^7.5.0", "speech_to_text: ^7.5.0`r`n  crypto: ^3.0.3")
[System.IO.File]::WriteAllText("mobile\pubspec.yaml", $newContent)
Write-Output "Updated pubspec.yaml"
