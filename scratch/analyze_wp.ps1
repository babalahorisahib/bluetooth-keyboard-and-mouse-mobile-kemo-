Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile("c:\windows\web\wallpaper\theme1\img13.jpg")
Write-Output "Wallpaper size: $($img.Width) x $($img.Height)"
$c = $img.GetPixel([int]($img.Width / 2), [int]($img.Height / 2))
Write-Output "Center : R=$($c.R), G=$($c.G), B=$($c.B) (Hex: #$($c.R.ToString('X2'))$($c.G.ToString('X2'))$($c.B.ToString('X2')))"
$img.Dispose()
