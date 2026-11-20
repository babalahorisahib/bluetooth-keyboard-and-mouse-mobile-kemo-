Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile("C:\Users\Administrator\.gemini\antigravity\brain\54670178-9eb0-4591-ab90-9aa619e89fb4\.user_uploaded\media_1794552459398_11ed4052.jpg")
Write-Output "Image size: $($img.Width) x $($img.Height)"
for ($y = 100; $y -lt $img.Height; $y += 200) {
    $c = $img.GetPixel([int]($img.Width / 2), $y)
    Write-Output "Y=$y : R=$($c.R), G=$($c.G), B=$($c.B) (Hex: #$($c.R.ToString('X2'))$($c.G.ToString('X2'))$($c.B.ToString('X2')))"
}
$img.Dispose()
