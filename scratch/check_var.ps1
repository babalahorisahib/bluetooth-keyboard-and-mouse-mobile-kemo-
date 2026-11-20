Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile("C:\Users\Administrator\.gemini\antigravity\brain\54670178-9eb0-4591-ab90-9aa619e89fb4\.user_uploaded\media_1794552459398_11ed4052.jpg")
$pixels = @()
for ($x = 100; $x -lt 400; $x += 50) {
    for ($y = 300; $y -lt 800; $y += 100) {
        $c = $img.GetPixel($x, $y)
        $pixels += "$($c.R),$($c.G),$($c.B)"
    }
}
$img.Dispose()
Write-Output "Unique colors in area: $(($pixels | Select-Object -Unique).Count)"
$pixels | Select-Object -Unique | Select-Object -First 5
