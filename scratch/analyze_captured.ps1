Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile("C:\bluetooth keyboard and mouse\scratch\captured_frame.jpg")
Write-Output "Captured frame size: $($img.Width) x $($img.Height)"
$c = $img.GetPixel(600, 300)
Write-Output "Center : R=$($c.R), G=$($c.G), B=$($c.B) (Hex: #$($c.R.ToString('X2'))$($c.G.ToString('X2'))$($c.B.ToString('X2')))"
$img.Dispose()
