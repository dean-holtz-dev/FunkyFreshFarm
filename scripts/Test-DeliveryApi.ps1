#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies the Funky Fresh Farm content through Umbraco's Content Delivery API (v2).

.DESCRIPTION
    Sends GET requests to /umbraco/delivery/api/v2, parses the JSON, and makes semantic assertions:
    content types, routes, property values, ordering, paging, media references, and the security
    boundaries (unpublished content, preview without an API key, media delivery disabled).

    Read-only: GET requests only, no credentials, no API key, no backoffice access.

    Prerequisites (see docs/03-api-and-extensions.md):
      - The application is running at -BaseUrl with .AddDeliveryApi() and
        Umbraco:CMS:DeliveryApi:Enabled = true.
      - The DeliveryApiContentIndex has been built. Umbraco builds it about one minute after the first
        request following startup, or on demand via Settings > Examine Management > Rebuild index.
      - The Milestone 2 baseline content is published (docs/02-content-model.md §13), and the node
        at -UnpublishedRoute exists but is unpublished (Mint, after Milestone 2 Phase 4).

.PARAMETER BaseUrl
    Root URL of the site, without a trailing slash.

.PARAMETER UnpublishedRoute
    Route of a node that exists but is unpublished; it must not be delivered. Pass an empty string
    to skip that check.

.PARAMETER TimeoutSec
    Per-request timeout in seconds.

.EXAMPLE
    pwsh ./scripts/Test-DeliveryApi.ps1

.EXAMPLE
    pwsh ./scripts/Test-DeliveryApi.ps1 -BaseUrl http://localhost:41388 -UnpublishedRoute ''

.NOTES
    Exit codes:
      0  All checks passed.
      1  One or more checks failed (including an unreachable site or disabled API).
      2  The script itself encountered an unexpected error.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'https://localhost:44370',
    [string]$UnpublishedRoute = '/plants/mint/',
    [int]$TimeoutSec = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ApiRoot = '/umbraco/delivery/api/v2'
$results = [System.Collections.Generic.List[object]]::new()
$client = $null

function Add-Result([string]$Check, [bool]$Passed, [string]$Detail) {
    $results.Add([pscustomobject]@{ Check = $Check; Passed = $Passed; Detail = $Detail })
}

# GET an API path; returns status, body, and parsed JSON (when the response is JSON).
function Invoke-Api([string]$PathAndQuery, [hashtable]$Headers = @{}) {
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $BaseUrl + $ApiRoot + $PathAndQuery)
    foreach ($name in $Headers.Keys) {
        $null = $request.Headers.TryAddWithoutValidation($name, [string]$Headers[$name])
    }
    $response = $client.SendAsync($request).GetAwaiter().GetResult()
    try {
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $json = $null
        $mediaType = ''
        if ($null -ne $response.Content.Headers.ContentType) { $mediaType = $response.Content.Headers.ContentType.MediaType }
        if ($mediaType -eq 'application/json' -and $body) { $json = $body | ConvertFrom-Json }
        [pscustomobject]@{ Path = $ApiRoot + $PathAndQuery; Status = [int]$response.StatusCode; Body = $body; Json = $json }
    }
    finally {
        $response.Dispose()
        $request.Dispose()
    }
}

# Reads a dotted path (e.g. 'properties.commonName') from parsed JSON; $null if any segment is missing.
function Get-Field($Object, [string]$Path) {
    $current = $Object
    foreach ($segment in $Path.Split('.')) {
        if ($null -eq $current) { return $null }
        $property = $current.PSObject.Properties[$segment]
        if ($null -eq $property) { return $null }
        $current = $property.Value
    }
    return $current
}

function Get-Count($Value) {
    if ($null -eq $Value) { return 0 }
    return @($Value).Count
}

function Assert-That($Failures, [bool]$Condition, [string]$Message) {
    if (-not $Condition) { $Failures.Add($Message) }
}

function Assert-Status($Failures, $Response, [int]$Expected) {
    if ($Response.Status -eq $Expected) { return $true }
    $excerpt = ($Response.Body -replace '\s+', ' ')
    if ($excerpt.Length -gt 160) { $excerpt = $excerpt.Substring(0, 160) + '...' }
    $hint = ''
    if ($Response.Status -eq 500 -and $Response.Body -match 'Unable to resolve service') {
        $hint = ' Hint: .AddDeliveryApi() is missing from Program.cs, or the app was not restarted.'
    }
    elseif ($Response.Status -eq 401 -and $Expected -eq 200) {
        $hint = ' Hint: is Umbraco:CMS:DeliveryApi:Enabled true, and PublicAccess not disabled?'
    }
    $Failures.Add("GET $($Response.Path) -> $($Response.Status), expected $Expected. Body: '$excerpt'.$hint")
    return $false
}

# Runs one named check. The script block receives a failure list and returns a success detail string.
function Invoke-Check([string]$Name, [scriptblock]$Body) {
    $failures = [System.Collections.Generic.List[string]]::new()
    $detail = ''
    try {
        $detail = (& $Body $failures | Out-String).Trim()
    }
    catch {
        $failures.Add("Exception: $($_.Exception.GetBaseException().Message)")
    }
    if ($failures.Count -eq 0) { Add-Result $Name $true $detail } else { Add-Result $Name $false ($failures -join ' | ') }
}

$checks = {
    $script:tomatoId = $null

    Invoke-Check 'Homepage item (route /)' {
        param($f)
        $r = Invoke-Api '/content/item/'
        if (-not (Assert-Status $f $r 200)) { return }
        $j = $r.Json
        Assert-That $f ((Get-Field $j 'contentType') -eq 'homePage') "contentType is '$(Get-Field $j 'contentType')', expected 'homePage'"
        Assert-That $f ((Get-Field $j 'route.path') -eq '/') "route.path is '$(Get-Field $j 'route.path')', expected '/'"
        $headline = Get-Field $j 'properties.heroHeadline'
        Assert-That $f (-not [string]::IsNullOrWhiteSpace($headline)) 'properties.heroHeadline is empty'
        Assert-That $f (-not [string]::IsNullOrWhiteSpace((Get-Field $j 'properties.introText'))) 'properties.introText is empty'
        "GET $($r.Path) -> 200 homePage, heroHeadline '$headline'"
    }

    Invoke-Check 'Plant directory item (route /plants/)' {
        param($f)
        $r = Invoke-Api '/content/item/plants/'
        if (-not (Assert-Status $f $r 200)) { return }
        $j = $r.Json
        Assert-That $f ((Get-Field $j 'contentType') -eq 'plantIndexPage') "contentType is '$(Get-Field $j 'contentType')', expected 'plantIndexPage'"
        Assert-That $f ((Get-Field $j 'properties.pageTitle') -eq 'Our Plants') "properties.pageTitle is '$(Get-Field $j 'properties.pageTitle')', expected 'Our Plants'"
        "GET $($r.Path) -> 200 plantIndexPage 'Our Plants'"
    }

    Invoke-Check 'Directory children query (tree order)' {
        param($f)
        $r = Invoke-Api '/content?fetch=children:/plants/&sort=sortOrder:asc'
        if (-not (Assert-Status $f $r 200)) { return }
        $j = $r.Json
        $total = [int](Get-Field $j 'total')
        if ($total -eq 0) {
            $f.Add('total is 0: the DeliveryApiContentIndex is empty. Umbraco builds it about one minute after the first request following startup; wait and rerun, or rebuild it in Settings > Examine Management.')
            return
        }
        $items = @(Get-Field $j 'items')
        $names = @($items | ForEach-Object { Get-Field $_ 'name' })
        $firstThree = ($names | Select-Object -First 3) -join ', '
        Assert-That $f ($firstThree -eq 'Heirloom Tomato, Basil, Zinnia') "first three names are '$firstThree', expected 'Heirloom Tomato, Basil, Zinnia'"
        $wrongType = @($items | Where-Object { (Get-Field $_ 'contentType') -ne 'plantPage' })
        Assert-That $f ($wrongType.Count -eq 0) "$($wrongType.Count) item(s) are not plantPage"
        $wrongRoute = @($items | Where-Object { (Get-Field $_ 'route.path') -notlike '/plants/*/' })
        Assert-That $f ($wrongRoute.Count -eq 0) "$($wrongRoute.Count) item(s) have routes outside /plants/"
        "GET $($r.Path) -> 200 total=${total}: $($names -join ', ')"
    }

    Invoke-Check 'Plant item: Heirloom Tomato' {
        param($f)
        $r = Invoke-Api '/content/item/plants/heirloom-tomato/'
        if (-not (Assert-Status $f $r 200)) { return }
        $j = $r.Json
        $script:tomatoId = Get-Field $j 'id'
        Assert-That $f ((Get-Field $j 'contentType') -eq 'plantPage') "contentType is '$(Get-Field $j 'contentType')'"
        Assert-That $f ((Get-Field $j 'properties.commonName') -eq 'Heirloom Tomato') "commonName is '$(Get-Field $j 'properties.commonName')'"
        Assert-That $f ((Get-Field $j 'properties.scientificName') -eq 'Solanum lycopersicum') "scientificName is '$(Get-Field $j 'properties.scientificName')'"
        Assert-That $f ((Get-Field $j 'properties.sunExposure') -eq 'Full Sun') "sunExposure is '$(Get-Field $j 'properties.sunExposure')'"
        Assert-That $f ([string](Get-Field $j 'properties.description')).Contains("`n") 'description has no line break (two lines expected, delivered as plain text with \n)'
        $images = Get-Field $j 'properties.plantImage'
        Assert-That $f ((Get-Count $images) -eq 1) "plantImage has $(Get-Count $images) item(s), expected 1"
        if ((Get-Count $images) -ge 1) {
            $image = @($images)[0]
            # Structural, so it holds for the placeholder and for the botanical illustration (Milestone 5).
            Assert-That $f ((Get-Field $image 'mediaType') -eq 'Image') "plantImage mediaType is '$(Get-Field $image 'mediaType')'"
            Assert-That $f ([string](Get-Field $image 'url') -match '^/media/[^/]+/[^/]+\.(png|jpe?g|webp)$') "plantImage url is '$(Get-Field $image 'url')'"
            Assert-That $f ([int](Get-Field $image 'width') -gt 0 -and [int](Get-Field $image 'height') -gt 0) 'plantImage has no dimensions'
        }
        "GET $($r.Path) -> 200 Solanum lycopersicum, Full Sun, 1 image (id $script:tomatoId)"
    }

    Invoke-Check 'Plant item: Basil (raw empty commonName)' {
        param($f)
        $r = Invoke-Api '/content/item/plants/basil/'
        if (-not (Assert-Status $f $r 200)) { return }
        $j = $r.Json
        Assert-That $f ([string]::IsNullOrEmpty((Get-Field $j 'properties.commonName'))) "commonName is '$(Get-Field $j 'properties.commonName')'; the API should deliver the stored empty value (no Razor fallback)"
        Assert-That $f ((Get-Field $j 'name') -eq 'Basil') "name is '$(Get-Field $j 'name')'"
        Assert-That $f ((Get-Field $j 'properties.scientificName') -eq 'Ocimum basilicum') "scientificName is '$(Get-Field $j 'properties.scientificName')'"
        Assert-That $f ((Get-Count (Get-Field $j 'properties.plantImage')) -eq 1) 'plantImage should have 1 item'
        "GET $($r.Path) -> 200 commonName=null, name 'Basil', 1 image"
    }

    Invoke-Check 'Plant item: Zinnia' {
        param($f)
        $r = Invoke-Api '/content/item/plants/zinnia/'
        if (-not (Assert-Status $f $r 200)) { return }
        $j = $r.Json
        # Zinnia had no image until Milestone 5; either state is valid, but an image must be a single Image.
        $images = Get-Field $j 'properties.plantImage'
        $count = Get-Count $images
        Assert-That $f ($count -le 1) "plantImage has $count items, expected 0 or 1"
        if ($count -eq 1) {
            Assert-That $f ((Get-Field @($images)[0] 'mediaType') -eq 'Image') "plantImage mediaType is '$(Get-Field @($images)[0] 'mediaType')'"
        }
        Assert-That $f ((Get-Field $j 'properties.scientificName') -eq 'Zinnia elegans') "scientificName is '$(Get-Field $j 'properties.scientificName')'"
        "GET $($r.Path) -> 200 plantImage items=$count"
    }

    Invoke-Check 'Guide item (rich text as HTML markup)' {
        param($f)
        $r = Invoke-Api '/content/item/growing-guide/'
        if (-not (Assert-Status $f $r 200)) { return }
        $j = $r.Json
        Assert-That $f ((Get-Field $j 'properties.pageTitle') -eq "A Beginner's Growing Guide") "pageTitle is '$(Get-Field $j 'properties.pageTitle')'"
        $markup = [string](Get-Field $j 'properties.bodyText.markup')
        foreach ($tag in '<h2>', '<ul>', '<strong>') {
            Assert-That $f $markup.Contains($tag) "bodyText.markup has no $tag"
        }
        "GET $($r.Path) -> 200 bodyText.markup with <h2>, <ul>, <strong>"
    }

    Invoke-Check 'Item by GUID id' {
        param($f)
        if (-not $script:tomatoId) { $f.Add('Skipped: no id from the Heirloom Tomato check.'); return }
        $r = Invoke-Api "/content/item/$script:tomatoId"
        if (-not (Assert-Status $f $r 200)) { return }
        Assert-That $f ((Get-Field $r.Json 'route.path') -eq '/plants/heirloom-tomato/') "route.path is '$(Get-Field $r.Json 'route.path')'"
        "GET $ApiRoot/content/item/{id} -> 200 /plants/heirloom-tomato/"
    }

    Invoke-Check 'Filter by content type' {
        param($f)
        $r = Invoke-Api '/content?filter=contentType:plantPage&sort=name:asc'
        if (-not (Assert-Status $f $r 200)) { return }
        $items = @(Get-Field $r.Json 'items')
        $names = @($items | ForEach-Object { Get-Field $_ 'name' })
        foreach ($expected in 'Basil', 'Heirloom Tomato', 'Zinnia') {
            Assert-That $f ($names -contains $expected) "'$expected' missing from results"
        }
        $wrongType = @($items | Where-Object { (Get-Field $_ 'contentType') -ne 'plantPage' })
        Assert-That $f ($wrongType.Count -eq 0) "$($wrongType.Count) item(s) are not plantPage"
        "GET $($r.Path) -> 200 $($names -join ', ')"
    }

    Invoke-Check 'Paging (take=2)' {
        param($f)
        $r = Invoke-Api '/content?fetch=children:/plants/&sort=sortOrder:asc&take=2'
        if (-not (Assert-Status $f $r 200)) { return }
        $count = Get-Count (Get-Field $r.Json 'items')
        $total = [int](Get-Field $r.Json 'total')
        Assert-That $f ($count -eq 2) "returned $count items, expected 2"
        Assert-That $f ($total -ge 3) "total is $total, expected at least 3"
        "GET $($r.Path) -> 200 items=$count total=$total"
    }

    if ($UnpublishedRoute) {
        Invoke-Check "Unpublished content not delivered ($UnpublishedRoute)" {
            param($f)
            $r = Invoke-Api ('/content/item' + $UnpublishedRoute)
            $null = Assert-Status $f $r 404
            "GET $($r.Path) -> 404"
        }
    }

    Invoke-Check 'Preview without API key rejected' {
        param($f)
        $r = Invoke-Api '/content/item/' @{ 'Preview' = 'true' }
        $null = Assert-Status $f $r 401
        "GET $($r.Path) with 'Preview: true' and no Api-Key -> 401"
    }

    Invoke-Check 'Unknown route returns 404' {
        param($f)
        $r = Invoke-Api '/content/item/plants/this-page-does-not-exist/'
        $null = Assert-Status $f $r 404
        "GET $($r.Path) -> 404"
    }

    Invoke-Check 'Media delivery disabled (default)' {
        param($f)
        $r = Invoke-Api '/media?fetch=children:/'
        $null = Assert-Status $f $r 401
        "GET $($r.Path) -> 401 (DeliveryApi:Media:Enabled is false)"
    }
}

$exitCode = 2
try {
    Add-Type -AssemblyName System.Net.Http
    $BaseUrl = $BaseUrl.TrimEnd('/')
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)

    $reachable = $true
    try {
        $null = Invoke-Api '/content/item/'
    }
    catch {
        $reachable = $false
        Add-Result 'Site reachable' $false ("Cannot reach $BaseUrl ($($_.Exception.GetBaseException().Message)). Is the app running? For https, is the dev certificate trusted?")
    }

    if ($reachable) { & $checks }

    Write-Host ''
    Write-Host "Funky Fresh Farm - Delivery API test ($BaseUrl$ApiRoot)" -ForegroundColor White
    Write-Host ('=' * 78)
    foreach ($result in $results) {
        if ($result.Passed) { Write-Host '[PASS] ' -ForegroundColor Green -NoNewline } else { Write-Host '[FAIL] ' -ForegroundColor Red -NoNewline }
        Write-Host ('{0,-44} {1}' -f $result.Check, $result.Detail)
    }
    Write-Host ('=' * 78)
    $failed = @($results | Where-Object { -not $_.Passed }).Count
    $exitCode = if ($failed -eq 0) { 0 } else { 1 }
    $color = if ($exitCode -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("Passed: {0}  Failed: {1}  Exit code: {2}" -f ($results.Count - $failed), $failed, $exitCode) -ForegroundColor $color
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
