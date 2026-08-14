# Image optimization pipeline for the Zhang Lab website.
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\optimize-images.ps1
#
# Resizes and recompresses images in assets/images/ IN PLACE so the site
# never ships multi-megabyte camera files. Safe to re-run; already-small
# images are left untouched. Uses built-in .NET (no installs required).
#
# Rules:
#   - Team headshots (assets/images/team/*.jpg): max 600 px wide, JPEG q82
#   - Group/wide photos (assets/images/*.jpg + lab-* in team/): max 1800 px wide, JPEG q80
#   - PNG logos are resized via dedicated parameters below.
#
# Add new photos at any size, run this script, then commit.

Add-Type -AssemblyName System.Drawing

function Get-ExifRotated([System.Drawing.Image]$img) {
    # Respect EXIF orientation (tag 274) so photos don't come out sideways.
    if ($img.PropertyIdList -contains 274) {
        $o = $img.GetPropertyItem(274).Value[0]
        switch ($o) {
            3 { $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
            6 { $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
            8 { $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
        }
        try { $img.RemovePropertyItem(274) } catch {}
    }
    return $img
}

function Optimize-Jpeg([string]$path, [int]$maxWidth, [int]$quality) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $ms = New-Object System.IO.MemoryStream(,$bytes)
    $img = [System.Drawing.Image]::FromStream($ms)
    $img = Get-ExifRotated $img
    $w = $img.Width; $h = $img.Height
    $needsResize = $w -gt $maxWidth
    $needsRecode = $bytes.Length -gt 400KB
    if (-not ($needsResize -or $needsRecode)) { $img.Dispose(); $ms.Dispose(); return }
    if ($needsResize) {
        $nw = $maxWidth; $nh = [int]([math]::Round($h * ($maxWidth / $w)))
    } else { $nw = $w; $nh = $h }
    $bmp = New-Object System.Drawing.Bitmap($nw, $nh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.DrawImage($img, 0, 0, $nw, $nh)
    $g.Dispose(); $img.Dispose(); $ms.Dispose()
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$quality)
    $bmp.Save($path, $codec, $ep)
    $bmp.Dispose()
    $kb = [math]::Round((Get-Item $path).Length / 1KB)
    Write-Host "optimized $path -> ${nw}x${nh}, ${kb} KB"
}

function Resize-Png([string]$src, [string]$dest, [int]$maxHeight) {
    $bytes = [System.IO.File]::ReadAllBytes($src)
    $ms = New-Object System.IO.MemoryStream(,$bytes)
    $img = [System.Drawing.Image]::FromStream($ms)
    if ($img.Height -le $maxHeight -and $src -eq $dest) { $img.Dispose(); $ms.Dispose(); return }
    $nh = [math]::Min($maxHeight, $img.Height)
    $nw = [int]([math]::Round($img.Width * ($nh / $img.Height)))
    $bmp = New-Object System.Drawing.Bitmap($nw, $nh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($img, 0, 0, $nw, $nh)
    $g.Dispose(); $img.Dispose(); $ms.Dispose()
    $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $kb = [math]::Round((Get-Item $dest).Length / 1KB)
    Write-Host "png $dest -> ${nw}x${nh}, ${kb} KB"
}

$root = Split-Path $PSScriptRoot -Parent
$team = Join-Path $root 'assets\images\team'

# Group / wide photos: 1800 px is plenty for a full-bleed hero.
foreach ($f in @('lab-psa-2025.jpg', 'lab-bbq-2025.jpg')) {
    $p = Join-Path $team $f
    if (Test-Path $p) { Optimize-Jpeg $p 1800 80 }
}

# Headshots: displayed at ~300 px in the people grid; 600 px covers retina.
Get-ChildItem $team -File | Where-Object { $_.Extension -match '\.(jpe?g|JPG)$' -and $_.Name -notlike 'lab-*' } | ForEach-Object {
    Optimize-Jpeg $_.FullName 600 82
}

# Logo: navbar shows it at 48 px; 192 px source covers 4x displays.
$logo = Join-Path $root 'assets\images\lab-logo.png'
if (Test-Path $logo) { Resize-Png $logo $logo 192 }
