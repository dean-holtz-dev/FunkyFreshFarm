#Requires -Version 5.1
<#
.SYNOPSIS
    Smoke-tests the public Funky Fresh Farm website.

.DESCRIPTION
    Requests the public routes with HTTP GET and checks status codes, content types, and content
    markers that prove the Razor templates rendered the published content correctly. Also checks
    that resized image URLs work and that a tampered image signature is rejected.

    The script is read-only: GET requests only, no credentials, no backoffice access. The only
    side effect is that ImageSharp may cache a resized image under umbraco/Data/TEMP/MediaCache.

    Prerequisites (see docs/02-content-model.md §13):
      - The application is running and reachable at -BaseUrl.
      - For https, the ASP.NET Core development certificate is trusted
        (or pass -BaseUrl http://localhost:41388; the public site also answers over HTTP).
      - The Milestone 2 baseline content is published: Home, Plants ("Our Plants"),
        Heirloom Tomato, Basil, Zinnia, and Growing Guide, with the values in
        docs/02-content-model.md §6.

.PARAMETER BaseUrl
    Root URL of the site, without a trailing slash.

.PARAMETER TimeoutSec
    Per-request timeout in seconds.

.EXAMPLE
    pwsh ./scripts/Test-Site.ps1

.EXAMPLE
    pwsh ./scripts/Test-Site.ps1 -BaseUrl http://localhost:41388

.NOTES
    Exit codes:
      0  All checks passed.
      1  One or more checks failed (including an unreachable site).
      2  The script itself encountered an unexpected error.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'https://localhost:44370',
    [int]$TimeoutSec = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Expected routes and markers. Contains/NotContains/Matches are evaluated against the HTML-decoded
# body; RawContains against the body as served (used to prove HTML encoding). Update these when
# the baseline content changes.
$pageChecks = @(
    @{
        Name     = 'Home page'
        Path     = '/'
        Status   = 200
        Type     = 'text/html'
        Contains = @('<title>Funky Fresh Farm</title>', 'href="/plants/"', 'href="/growing-guide/"')
        Matches  = @('<section class="hero">\s*<h1>[^<]+</h1>', 'aria-current="page">Home</a>')
    },
    @{
        Name     = 'Plant directory'
        Path     = '/plants/'
        Status   = 200
        Type     = 'text/html'
        Contains = @('<title>Our Plants | Funky Fresh Farm</title>', '<h1>Our Plants</h1>')
        Matches  = @(
            'plant-card__name">Heirloom Tomato</h2>.*plant-card__name">Basil</h2>.*plant-card__name">Zinnia</h2>',
            'heirloom-tomato\.png\?width=480&height=360&[^"]*hmac=',
            'basil\.png\?width=480&height=360&[^"]*hmac=',
            'image-placeholder"[^>]*>No image yet</div>\s*<h2 class="plant-card__name">Zinnia</h2>'
        )
    },
    @{
        Name     = 'Plant page: Heirloom Tomato'
        Path     = '/plants/heirloom-tomato/'
        Status   = 200
        Type     = 'text/html'
        Contains = @('<h1>Heirloom Tomato</h1>', 'Solanum lycopersicum', '<figure class="plant__image">', '<dd>Full Sun</dd>', 'Back to Plants')
        Matches  = @('<p class="plant__description">[^<]+<br />[^<]+</p>')
    },
    @{
        Name     = 'Plant page: Basil (common-name fallback)'
        Path     = '/plants/basil/'
        Status   = 200
        Type     = 'text/html'
        Contains = @('<h1>Basil</h1>', 'Ocimum basilicum', '<figure class="plant__image">')
    },
    @{
        Name        = 'Plant page: Zinnia (missing-image fallback)'
        Path        = '/plants/zinnia/'
        Status      = 200
        Type        = 'text/html'
        Contains    = @('<h1>Zinnia</h1>', 'Zinnia elegans')
        NotContains = @('<figure')
    },
    @{
        Name        = 'Growing guide (rich text)'
        Path        = '/growing-guide/'
        Status      = 200
        Type        = 'text/html'
        Contains    = @("<h1>A Beginner's Growing Guide</h1>", '<div class="rich-text">', '<strong>')
        RawContains = @('A Beginner&#x27;s Growing Guide')
        Matches     = @('<div class="rich-text">.*<h2>.*<ul>.*</ul>')
    },
    @{
        Name   = 'Stylesheet'
        Path   = '/css/site.css'
        Status = 200
        Type   = 'text/css'
    },
    @{
        Name   = 'Unknown URL returns 404'
        Path   = '/plants/this-page-does-not-exist/'
        Status = 404
    }
)

$results = [System.Collections.Generic.List[object]]::new()

function Add-Result([string]$Check, [bool]$Passed, [string]$Detail) {
    $results.Add([pscustomobject]@{ Check = $Check; Passed = $Passed; Detail = $Detail })
}

function Invoke-Get([System.Net.Http.HttpClient]$Client, [string]$Url) {
    $response = $Client.GetAsync($Url).GetAwaiter().GetResult()
    try {
        $mediaType = ''
        if ($null -ne $response.Content.Headers.ContentType) {
            $mediaType = $response.Content.Headers.ContentType.MediaType
        }
        [pscustomobject]@{
            Status    = [int]$response.StatusCode
            MediaType = $mediaType
            Body      = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
    }
    finally {
        $response.Dispose()
    }
}

function Test-Page([System.Net.Http.HttpClient]$Client, [hashtable]$Spec) {
    $url = $BaseUrl + $Spec.Path
    $response = Invoke-Get $Client $url
    $failures = [System.Collections.Generic.List[string]]::new()

    if ($response.Status -ne $Spec.Status) {
        $failures.Add("status $($response.Status), expected $($Spec.Status)")
    }
    if ($Spec.ContainsKey('Type') -and $response.MediaType -ne $Spec.Type) {
        $failures.Add("content type '$($response.MediaType)', expected '$($Spec.Type)'")
    }

    $decoded = [System.Net.WebUtility]::HtmlDecode($response.Body)
    if ($Spec.ContainsKey('Contains')) {
        foreach ($marker in $Spec.Contains) {
            if (-not $decoded.Contains($marker)) { $failures.Add("missing '$marker'") }
        }
    }
    if ($Spec.ContainsKey('NotContains')) {
        foreach ($marker in $Spec.NotContains) {
            if ($decoded.Contains($marker)) { $failures.Add("unexpected '$marker'") }
        }
    }
    if ($Spec.ContainsKey('RawContains')) {
        foreach ($marker in $Spec.RawContains) {
            if (-not $response.Body.Contains($marker)) { $failures.Add("raw HTML missing '$marker'") }
        }
    }
    if ($Spec.ContainsKey('Matches')) {
        foreach ($pattern in $Spec.Matches) {
            if (-not [regex]::IsMatch($decoded, $pattern, 'Singleline')) { $failures.Add("no match for /$pattern/") }
        }
    }

    $detail = if ($failures.Count -eq 0) { "GET $($Spec.Path) -> $($response.Status)" } else { "GET $($Spec.Path): " + ($failures -join '; ') }
    Add-Result $Spec.Name ($failures.Count -eq 0) $detail
    return $response
}

# Resized images: the signed URL from the directory must serve an image; a tampered signature must not.
function Test-Images([System.Net.Http.HttpClient]$Client, [string]$DirectoryBody) {
    $match = [regex]::Match($DirectoryBody, '<img class="plant-card__image" src="([^"]+)"')
    if (-not $match.Success) {
        Add-Result 'Resized image' $false 'No plant-card image found on /plants/.'
        Add-Result 'Tampered image signature rejected' $false 'Skipped: no image URL to tamper with.'
        return
    }
    $path = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)

    $image = Invoke-Get $Client ($BaseUrl + $path)
    $ok = $image.Status -eq 200 -and $image.MediaType -like 'image/*'
    Add-Result 'Resized image' $ok ("GET {0} -> {1} {2}" -f ($path -replace 'hmac=[0-9a-f]+', 'hmac=...'), $image.Status, $image.MediaType)

    $tampered = $path -replace 'hmac=[0-9a-f]{4}', 'hmac=0000'
    $rejected = Invoke-Get $Client ($BaseUrl + $tampered)
    Add-Result 'Tampered image signature rejected' ($rejected.Status -eq 400) ("altered hmac -> {0} (expected 400)" -f $rejected.Status)
}

$exitCode = 2
$client = $null
try {
    Add-Type -AssemblyName System.Net.Http
    $BaseUrl = $BaseUrl.TrimEnd('/')

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)

    $reachable = $true
    try {
        $null = Invoke-Get $client ($BaseUrl + '/')
    }
    catch {
        $reachable = $false
        $reason = $_.Exception.GetBaseException().Message
        Add-Result 'Site reachable' $false "Cannot reach $BaseUrl ($reason). Is the app running? For https, is the dev certificate trusted?"
    }

    if ($reachable) {
        $directoryBody = $null
        foreach ($spec in $pageChecks) {
            $response = Test-Page $client $spec
            if ($spec.Path -eq '/plants/') { $directoryBody = $response.Body }
        }
        Test-Images $client $directoryBody
    }

    Write-Host ''
    Write-Host "Funky Fresh Farm - site smoke test ($BaseUrl)" -ForegroundColor White
    Write-Host ('=' * 70)
    foreach ($result in $results) {
        if ($result.Passed) { Write-Host '[PASS] ' -ForegroundColor Green -NoNewline } else { Write-Host '[FAIL] ' -ForegroundColor Red -NoNewline }
        Write-Host ('{0,-44} {1}' -f $result.Check, $result.Detail)
    }
    Write-Host ('=' * 70)
    $failed = @($results | Where-Object { -not $_.Passed }).Count
    $passed = $results.Count - $failed
    $exitCode = if ($failed -eq 0) { 0 } else { 1 }
    $color = if ($exitCode -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("Passed: {0}  Failed: {1}  Exit code: {2}" -f $passed, $failed, $exitCode) -ForegroundColor $color
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
