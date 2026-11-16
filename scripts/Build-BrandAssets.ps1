#Requires -Version 5.1
<#
.SYNOPSIS
    Generates the web-optimized brand artwork served from wwwroot/brand/ from the original artwork.

.DESCRIPTION
    Reads the owner's original PNG artwork (never modified) and writes resized derivatives:
    JPEG for opaque illustrations, PNG for artwork with transparency. Uses System.Drawing (GDI+),
    which ships with Windows, so no image library, package, or licence key is needed.

    The derivative table below is the single source of truth for which original feeds which file.
    To replace artwork later: put the new original in -SourceDir under the same name (or edit the
    table), rerun this script, and commit the regenerated files in wwwroot/brand/.

    Plant illustrations are NOT generated here: they are CMS-managed and uploaded to the Media
    Library as originals (see docs/05-assets.md).

.PARAMETER SourceDir
    Folder containing the original artwork.

.PARAMETER OutputDir
    Folder for the generated web assets.

.PARAMETER JpegQuality
    JPEG quality, 1-100.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\Build-BrandAssets.ps1

.NOTES
    Exit codes: 0 = all derivatives written, 1 = a source file is missing, 2 = unexpected error.
    Windows only (GDI+).
#>
[CmdletBinding()]
param(
    [string]$SourceDir,
    [string]$OutputDir,
    [ValidateRange(1, 100)][int]$JpegQuality = 82
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $SourceDir) { $SourceDir = Join-Path $repoRoot 'assets\images' }
if (-not $OutputDir) { $OutputDir = Join-Path $repoRoot 'src\FunkyFreshFarm.UmbracoLab\wwwroot\brand' }

# Output name | original file | width | height (0 = keep aspect ratio) | format | background (for PNG on a solid colour)
$derivatives = @(
    @{ Name = 'emblem-96.png';           Source = 'Retro Psychedelic Sprout Farm Emblem.png';  Width = 96;   Format = 'png' }
    @{ Name = 'emblem-192.png';          Source = 'Retro Psychedelic Sprout Farm Emblem.png';  Width = 192;  Format = 'png' }
    @{ Name = 'favicon-32.png';          Source = 'Retro Psychedelic Sprout Farm Emblem.png';  Width = 32;   Format = 'png' }
    @{ Name = 'apple-touch-icon.png';    Source = 'Retro Psychedelic Sprout Farm Emblem.png';  Width = 180;  Format = 'png'; Background = 'FFF5DC'; Padding = 15 }
    @{ Name = 'hero-wide-960.jpg';       Source = 'Retro Screen-Print Farm Garden Sunset.png'; Width = 960;  Format = 'jpg' }
    @{ Name = 'hero-wide-1440.jpg';      Source = 'Retro Screen-Print Farm Garden Sunset.png'; Width = 1440; Format = 'jpg' }
    @{ Name = 'hero-wide-1774.jpg';      Source = 'Retro Screen-Print Farm Garden Sunset.png'; Width = 1774; Format = 'jpg' }
    @{ Name = 'hero-tall-480.jpg';       Source = 'Farmstand Funk_ Sunlit Garden Harvest.png'; Width = 480;  Format = 'jpg' }
    @{ Name = 'hero-tall-800.jpg';       Source = 'Farmstand Funk_ Sunlit Garden Harvest.png'; Width = 800;  Format = 'jpg' }
    @{ Name = 'hero-tall-1122.jpg';      Source = 'Farmstand Funk_ Sunlit Garden Harvest.png'; Width = 1122; Format = 'jpg' }
    @{ Name = 'story-640.jpg';           Source = 'Whimsical Harvest Garden.png';              Width = 640;  Format = 'jpg' }
    @{ Name = 'story-1280.jpg';          Source = 'Whimsical Harvest Garden.png';              Width = 1280; Format = 'jpg' }
    @{ Name = 'guide-640.jpg';           Source = 'Retro Tomato Plant Life Cycle.png';         Width = 640;  Format = 'jpg' }
    @{ Name = 'guide-1280.jpg';          Source = 'Retro Tomato Plant Life Cycle.png';         Width = 1280; Format = 'jpg' }
    @{ Name = 'lost-640.jpg';            Source = 'Radish at the Lost Garden Path.png';        Width = 640;  Format = 'jpg' }
    @{ Name = 'lost-1280.jpg';           Source = 'Radish at the Lost Garden Path.png';        Width = 1280; Format = 'jpg' }
    @{ Name = 'sticker-160.png';         Source = 'Dancing Retro Radish Sticker.png';          Width = 160;  Format = 'png' }
    @{ Name = 'sticker-320.png';         Source = 'Dancing Retro Radish Sticker.png';          Width = 320;  Format = 'png' }
    @{ Name = 'social-card-1200.jpg';    Source = 'Vintage Harvest Garden Panorama.png';       Width = 1200; Format = 'jpg' }
)

function Get-JpegEncoder {
    [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
}

function New-Derivative([System.Drawing.Image]$Source, [hashtable]$Spec, [string]$Path) {
    $width = [int]$Spec.Width
    $height = [int][Math]::Round($Source.Height * $width / $Source.Width)
    $padding = 0
    if ($Spec.ContainsKey('Padding')) { $padding = [int]$Spec.Padding }

    $bitmap = New-Object System.Drawing.Bitmap $width, $height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            if ($Spec.ContainsKey('Background')) {
                $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#' + $Spec.Background))
            }
            else {
                $graphics.Clear([System.Drawing.Color]::Transparent)
            }

            # TileFlipXY avoids the faint dark fringe GDI+ otherwise draws along resized edges.
            $attributes = New-Object System.Drawing.Imaging.ImageAttributes
            $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
            $target = New-Object System.Drawing.Rectangle $padding, $padding, ($width - 2 * $padding), ($height - 2 * $padding)
            $graphics.DrawImage($Source, $target, 0, 0, $Source.Width, $Source.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
            $attributes.Dispose()
        }
        finally {
            $graphics.Dispose()
        }

        if ($Spec.Format -eq 'jpg') {
            $parameters = New-Object System.Drawing.Imaging.EncoderParameters 1
            $parameters.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]$JpegQuality)
            $bitmap.Save($Path, (Get-JpegEncoder), $parameters)
            $parameters.Dispose()
        }
        else {
            $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        return "{0}x{1}" -f $width, $height
    }
    finally {
        $bitmap.Dispose()
    }
}

$exitCode = 2
try {
    Add-Type -AssemblyName System.Drawing
    if (-not (Test-Path -LiteralPath $SourceDir)) { throw "Source folder not found: $SourceDir" }
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    $missing = @($derivatives | ForEach-Object { $_.Source } | Sort-Object -Unique | Where-Object { -not (Test-Path -LiteralPath (Join-Path $SourceDir $_)) })
    if ($missing.Count -gt 0) {
        $missing | ForEach-Object { Write-Host "[MISSING] $_" -ForegroundColor Red }
        $exitCode = 1
    }
    else {
        $cache = @{}
        try {
            foreach ($spec in $derivatives) {
                $sourcePath = Join-Path $SourceDir $spec.Source
                if (-not $cache.ContainsKey($sourcePath)) {
                    $cache[$sourcePath] = [System.Drawing.Image]::FromFile($sourcePath)
                }
                $outPath = Join-Path $OutputDir $spec.Name
                $size = New-Derivative $cache[$sourcePath] $spec $outPath
                Write-Host ('[WRITE] {0,-26} {1,-10} {2,8:N0} bytes  <- {3}' -f $spec.Name, $size, (Get-Item -LiteralPath $outPath).Length, $spec.Source)
            }
        }
        finally {
            foreach ($image in $cache.Values) { $image.Dispose() }
        }
        $exitCode = 0
    }
}
catch {
    Write-Host "Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 2
}

exit $exitCode
