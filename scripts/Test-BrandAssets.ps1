#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies the Funky Fresh Farm brand assets: local files, how the running site serves them, and
    the CMS-managed botanical illustrations.

.DESCRIPTION
    Read-only. Checks:
      1. Git-managed derivatives in wwwroot/brand: exist, real format signature, expected
         dimensions, size budget. Self-hosted fonts are WOFF2 with their OFL licence files.
      2. Original artwork in assets/images (untracked): present, so derivatives can be rebuilt.
         Missing originals are reported as warnings, not failures.
      3. HTTP against the running site: every asset is served with the right content type; pages
         reference the expected art (responsive hero, emblem, sticker, guide, 404, social card);
         the hero is not lazy-loaded; decorative images have empty alt text.
      4. CMS-managed images (skip with -SkipCms): each plant page shows its botanical illustration
         from the Media Library as signed WebP crops. Fails with "PENDING" until the owner has
         uploaded and assigned the illustrations (docs/05-assets.md).

.PARAMETER BaseUrl
    Root URL of the running site.

.PARAMETER SkipHttp
    Only check local files.

.PARAMETER SkipCms
    Skip the CMS-managed botanical illustration checks.

.EXAMPLE
    pwsh ./scripts/Test-BrandAssets.ps1

.EXAMPLE
    pwsh ./scripts/Test-BrandAssets.ps1 -SkipCms

.NOTES
    Exit codes: 0 = all checks passed (warnings allowed), 1 = a check failed, 2 = script error.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'https://localhost:44370',
    [switch]$SkipHttp,
    [switch]$SkipCms,
    [int]$TimeoutSec = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$webRoot = Join-Path $repoRoot 'src\FunkyFreshFarm.UmbracoLab\wwwroot'
$originalsDir = Join-Path $repoRoot 'assets\images'
$maxBytes = 500KB

# Expected Git-managed derivatives (must match scripts/Build-BrandAssets.ps1).
$brandFiles = @(
    @{ Name = 'emblem-96.png';        Width = 96;   Height = 96 }
    @{ Name = 'emblem-192.png';       Width = 192;  Height = 192 }
    @{ Name = 'favicon-32.png';       Width = 32;   Height = 32 }
    @{ Name = 'apple-touch-icon.png'; Width = 180;  Height = 180 }
    @{ Name = 'hero-wide-960.jpg';    Width = 960;  Height = 480 }
    @{ Name = 'hero-wide-1440.jpg';   Width = 1440; Height = 720 }
    @{ Name = 'hero-wide-1774.jpg';   Width = 1774; Height = 887 }
    @{ Name = 'hero-tall-480.jpg';    Width = 480;  Height = 600 }
    @{ Name = 'hero-tall-800.jpg';    Width = 800;  Height = 1000 }
    @{ Name = 'hero-tall-1122.jpg';   Width = 1122; Height = 1402 }
    @{ Name = 'story-640.jpg';        Width = 640;  Height = 427 }
    @{ Name = 'story-1280.jpg';       Width = 1280; Height = 853 }
    @{ Name = 'guide-640.jpg';        Width = 640;  Height = 427 }
    @{ Name = 'guide-1280.jpg';       Width = 1280; Height = 853 }
    @{ Name = 'lost-640.jpg';         Width = 640;  Height = 427 }
    @{ Name = 'lost-1280.jpg';        Width = 1280; Height = 853 }
    @{ Name = 'sticker-160.png';      Width = 160;  Height = 160 }
    @{ Name = 'sticker-320.png';      Width = 320;  Height = 320 }
    @{ Name = 'social-card-1200.jpg'; Width = 1200; Height = 628 }
)
$fontFiles = 'fraunces-latin-variable.woff2', 'dm-sans-latin-variable.woff2', 'dm-sans-latin-italic-variable.woff2'
$licenceFiles = 'OFL-Fraunces.txt', 'OFL-DMSans.txt'
$originals = @(
    'Retro Psychedelic Sprout Farm Emblem.png', 'Retro Screen-Print Farm Garden Sunset.png',
    'Farmstand Funk_ Sunlit Garden Harvest.png', 'Whimsical Harvest Garden.png', 'Retro Tomato Plant Life Cycle.png',
    'Radish at the Lost Garden Path.png', 'Dancing Retro Radish Sticker.png', 'Vintage Harvest Garden Panorama.png',
    'Vintage Heirloom Tomato Vine.png', 'Vintage Botanical Basil Print.png', 'Retro Zinnia Bouquet Screen Print.png'
)
# CMS-managed botanical illustrations: plant route -> pattern the uploaded media file name must match.
$botanicals = @(
    @{ Route = '/plants/heirloom-tomato/'; Pattern = 'tomato[-_ ]*vine';     Original = 'Vintage Heirloom Tomato Vine.png' }
    @{ Route = '/plants/basil/';           Pattern = 'basil[-_ ]*print';     Original = 'Vintage Botanical Basil Print.png' }
    @{ Route = '/plants/zinnia/';          Pattern = 'zinnia[-_ ]*bouquet';  Original = 'Retro Zinnia Bouquet Screen Print.png' }
)

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Check, [string]$Status, [string]$Detail) {
    $results.Add([pscustomobject]@{ Check = $Check; Status = $Status; Detail = $Detail })
}

# Returns format, width, height from the file header (PNG IHDR or JPEG SOF marker).
function Get-ImageInfo([string]$Path) {
    $b = [IO.File]::ReadAllBytes($Path)
    if ($b.Length -gt 24 -and $b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) {
        $w = ([int]$b[16] -shl 24) -bor ([int]$b[17] -shl 16) -bor ([int]$b[18] -shl 8) -bor [int]$b[19]
        $h = ([int]$b[20] -shl 24) -bor ([int]$b[21] -shl 16) -bor ([int]$b[22] -shl 8) -bor [int]$b[23]
        return [pscustomobject]@{ Format = 'png'; Width = $w; Height = $h; Bytes = $b.Length }
    }
    if ($b.Length -gt 4 -and $b[0] -eq 0xFF -and $b[1] -eq 0xD8) {
        $i = 2
        while ($i + 9 -lt $b.Length) {
            if ($b[$i] -ne 0xFF) { $i++; continue }
            $marker = $b[$i + 1]
            if ($marker -ge 0xC0 -and $marker -le 0xCF -and $marker -notin 0xC4, 0xC8, 0xCC) {
                $h = ([int]$b[$i + 5] -shl 8) -bor [int]$b[$i + 6]
                $w = ([int]$b[$i + 7] -shl 8) -bor [int]$b[$i + 8]
                return [pscustomobject]@{ Format = 'jpg'; Width = $w; Height = $h; Bytes = $b.Length }
            }
            $length = ([int]$b[$i + 2] -shl 8) -bor [int]$b[$i + 3]
            $i += 2 + $length
        }
    }
    return [pscustomobject]@{ Format = 'unknown'; Width = 0; Height = 0; Bytes = $b.Length }
}

function Test-LocalFiles {
    foreach ($file in $brandFiles) {
        $path = Join-Path $webRoot "brand\$($file.Name)"
        if (-not (Test-Path -LiteralPath $path)) { Add-Result "brand/$($file.Name)" 'FAIL' 'Missing. Run scripts/Build-BrandAssets.ps1.'; continue }
        $info = Get-ImageInfo $path
        $expectedFormat = [IO.Path]::GetExtension($file.Name).TrimStart('.')
        $problems = @()
        if ($info.Format -ne $expectedFormat) { $problems += "format $($info.Format), expected $expectedFormat" }
        if ($info.Width -ne $file.Width -or $info.Height -ne $file.Height) { $problems += "$($info.Width)x$($info.Height), expected $($file.Width)x$($file.Height)" }
        if ($info.Bytes -gt $maxBytes) { $problems += "$($info.Bytes) bytes exceeds $maxBytes" }
        if ($problems.Count -eq 0) { Add-Result "brand/$($file.Name)" 'PASS' ("{0} {1}x{2}, {3:N0} bytes" -f $info.Format, $info.Width, $info.Height, $info.Bytes) }
        else { Add-Result "brand/$($file.Name)" 'FAIL' ($problems -join '; ') }
    }
    foreach ($font in $fontFiles) {
        $path = Join-Path $webRoot "fonts\$font"
        if (-not (Test-Path -LiteralPath $path)) { Add-Result "fonts/$font" 'FAIL' 'Missing'; continue }
        $b = [IO.File]::ReadAllBytes($path)
        $signature = [Text.Encoding]::ASCII.GetString($b, 0, 4)
        Add-Result "fonts/$font" $(if ($signature -eq 'wOF2') { 'PASS' } else { 'FAIL' }) ("signature {0}, {1:N0} bytes" -f $signature, $b.Length)
    }
    foreach ($licence in $licenceFiles) {
        $path = Join-Path $webRoot "fonts\$licence"
        $ok = (Test-Path -LiteralPath $path) -and (Select-String -LiteralPath $path -Pattern 'SIL Open Font License, Version 1.1' -Quiet)
        Add-Result "fonts/$licence" $(if ($ok) { 'PASS' } else { 'FAIL' }) $(if ($ok) { 'SIL Open Font License 1.1' } else { 'Missing or not OFL 1.1' })
    }
    $missing = @($originals | Where-Object { -not (Test-Path -LiteralPath (Join-Path $originalsDir $_)) })
    if ($missing.Count -eq 0) { Add-Result 'Original artwork (assets/images)' 'PASS' "$($originals.Count) originals present (untracked; needed to rebuild derivatives)" }
    else { Add-Result 'Original artwork (assets/images)' 'WARN' ("Missing: " + ($missing -join ', ') + '. Derivatives cannot be rebuilt without them.') }
}

function Invoke-Get([string]$Url) {
    $response = $client.GetAsync($Url).GetAwaiter().GetResult()
    try {
        $mediaType = if ($null -ne $response.Content.Headers.ContentType) { $response.Content.Headers.ContentType.MediaType } else { '' }
        $isText = $mediaType -like 'text/*'
        [pscustomobject]@{
            Status = [int]$response.StatusCode
            MediaType = $mediaType
            Body = if ($isText) { $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } else { $null }
            Bytes = if ($isText) { 0 } else { $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult().Length }
        }
    }
    finally { $response.Dispose() }
}

function Test-Served {
    $expectedTypes = @{ '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.woff2' = 'font/woff2' }
    $failures = @()
    $paths = @($brandFiles | ForEach-Object { "/brand/$($_.Name)" }) + @($fontFiles | ForEach-Object { "/fonts/$_" })
    foreach ($path in $paths) {
        $r = Invoke-Get ($BaseUrl + $path)
        $expected = $expectedTypes[[IO.Path]::GetExtension($path)]
        if ($r.Status -ne 200 -or $r.MediaType -ne $expected) { $failures += "$path -> $($r.Status) $($r.MediaType)" }
    }
    Add-Result 'Static assets served' $(if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) $(if ($failures.Count -eq 0) { "$($paths.Count) files, 200 with expected content types" } else { $failures -join '; ' })
}

function Test-PageMarkup([string]$Name, [string]$Path, [int]$ExpectedStatus, [string[]]$Patterns) {
    $r = Invoke-Get ($BaseUrl + $Path)
    $problems = @()
    if ($r.Status -ne $ExpectedStatus) { $problems += "status $($r.Status), expected $ExpectedStatus" }
    foreach ($pattern in $Patterns) {
        if (-not [regex]::IsMatch([string]$r.Body, $pattern, 'Singleline')) { $problems += "no match for /$pattern/" }
    }
    Add-Result $Name $(if ($problems.Count -eq 0) { 'PASS' } else { 'FAIL' }) $(if ($problems.Count -eq 0) { "GET $Path -> $($r.Status)" } else { $problems -join '; ' })
    return $r
}

function Test-Pages {
    $homePage = Test-PageMarkup 'Home: responsive hero' '/' 200 @(
        '<source media="\(max-width: 47\.99rem\)"[^>]*hero-tall-480\.jpg 480w',
        '<img src="/brand/hero-wide-1440\.jpg"[^>]*fetchpriority="high"'
    )
    if ($null -ne $homePage.Body) {
        $heroImg = [regex]::Match($homePage.Body, '<img src="/brand/hero-wide-1440\.jpg"[^>]*>', 'Singleline').Value
        Add-Result 'Home: hero not lazy-loaded' $(if ($heroImg -and $heroImg -notmatch 'loading="lazy"') { 'PASS' } else { 'FAIL' }) 'Above-the-fold hero loads eagerly with fetchpriority=high'
    }
    $null = Test-PageMarkup 'Layout: emblem and live-text brand' '/' 200 @(
        '<img class="brand__emblem" src="/brand/emblem-96\.png"[^>]*alt=""',
        '<span class="brand__name">Funky Fresh Farm</span>'
    )
    $null = Test-PageMarkup 'Home: decorative sticker' '/' 200 @('<img class="sticker" src="/brand/sticker-160\.png"[^>]*alt=""')
    $null = Test-PageMarkup 'Guide: illustration with alt text' '/growing-guide/' 200 @('<img src="/brand/guide-1280\.jpg"[^>]*alt="[^"]+"')
    $null = Test-PageMarkup 'Branded 404 page' '/this-page-does-not-exist/' 404 @('<img src="/brand/lost-1280\.jpg"', 'class="brand__name"')

    $og = [regex]::Match([string]$homePage.Body, '<meta property="og:image" content="([^"]+)"').Groups[1].Value
    if ($og) {
        $r = Invoke-Get $og
        Add-Result 'Social sharing image (og:image)' $(if ($r.Status -eq 200 -and $r.MediaType -eq 'image/jpeg') { 'PASS' } else { 'FAIL' }) "$og -> $($r.Status) $($r.MediaType)"
    }
    else { Add-Result 'Social sharing image (og:image)' 'FAIL' 'No og:image meta tag on the homepage' }

    $css = Invoke-Get ($BaseUrl + '/css/site.css')
    $missing = @()
    foreach ($token in '--color-basil: #285c47', '--color-coral: #e4583e', '--color-marigold: #f3bb48', '--color-cream: #fff5dc', '--color-eggplant: #3e2a47', '--color-mint: #a9d7c3') {
        if (-not ([string]$css.Body).Contains($token)) { $missing += $token }
    }
    foreach ($font in $fontFiles) { if (-not ([string]$css.Body).Contains("/fonts/$font")) { $missing += "@font-face $font" } }
    Add-Result 'CSS design tokens and @font-face' $(if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' }) $(if ($missing.Count -eq 0) { '6 palette tokens, 3 font faces' } else { 'Missing: ' + ($missing -join ', ') })
}

function Test-Botanicals {
    foreach ($plant in $botanicals) {
        $r = Invoke-Get ($BaseUrl + $plant.Route)
        $img = [regex]::Match([string]$r.Body, '<figure class="plant__image">\s*<img[^>]*>', 'Singleline').Value
        if (-not $img) {
            Add-Result "Botanical: $($plant.Route)" 'FAIL' "PENDING owner step: no image on the page. Upload '$($plant.Original)' to Media > Plants and assign it as Plant Image."
            continue
        }
        $src = [System.Net.WebUtility]::HtmlDecode([regex]::Match($img, ' src="([^"]+)"').Groups[1].Value)
        $file = [regex]::Match($src, '^/media/[^/]+/([^?]+)').Groups[1].Value
        if ($file -notmatch "(?i)$($plant.Pattern)") {
            Add-Result "Botanical: $($plant.Route)" 'FAIL' "PENDING owner step: shows '$file', not the botanical illustration. Assign '$($plant.Original)'."
            continue
        }
        $served = Invoke-Get ($BaseUrl + $src)
        $ok = $served.Status -eq 200 -and $served.MediaType -eq 'image/webp' -and $src -match 'hmac='
        Add-Result "Botanical: $($plant.Route)" $(if ($ok) { 'PASS' } else { 'FAIL' }) "$file -> $($served.Status) $($served.MediaType), signed=$($src -match 'hmac=')"
    }
}

$exitCode = 2
$client = $null
try {
    Test-LocalFiles
    if (-not $SkipHttp) {
        Add-Type -AssemblyName System.Net.Http
        $BaseUrl = $BaseUrl.TrimEnd('/')
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect = $false
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        try {
            $null = Invoke-Get ($BaseUrl + '/')
            Test-Served
            Test-Pages
            if (-not $SkipCms) { Test-Botanicals }
        }
        catch [System.Net.Http.HttpRequestException] {
            Add-Result 'Site reachable' 'FAIL' "Cannot reach $BaseUrl ($($_.Exception.GetBaseException().Message)). Is the app running?"
        }
    }

    $colors = @{ PASS = 'Green'; FAIL = 'Red'; WARN = 'Yellow' }
    Write-Host ''
    Write-Host 'Funky Fresh Farm - brand asset test' -ForegroundColor White
    Write-Host ('=' * 78)
    foreach ($result in $results) {
        Write-Host ('[{0}] ' -f $result.Status) -ForegroundColor $colors[$result.Status] -NoNewline
        Write-Host ('{0,-38} {1}' -f $result.Check, $result.Detail)
    }
    Write-Host ('=' * 78)
    $failed = @($results | Where-Object Status -EQ 'FAIL').Count
    $warned = @($results | Where-Object Status -EQ 'WARN').Count
    $exitCode = if ($failed -eq 0) { 0 } else { 1 }
    Write-Host ("Passed: {0}  Warnings: {1}  Failed: {2}  Exit code: {3}" -f ($results.Count - $failed - $warned), $warned, $failed, $exitCode) -ForegroundColor $(if ($exitCode -eq 0) { 'Green' } else { 'Red' })
}
catch {
    Write-Host "Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    $exitCode = 2
}
finally {
    if ($null -ne $client) { $client.Dispose() }
}

exit $exitCode
