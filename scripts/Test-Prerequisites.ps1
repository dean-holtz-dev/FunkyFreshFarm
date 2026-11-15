#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies local prerequisites for the Funky Fresh Farm Umbraco lab.

.DESCRIPTION
    Read-only checks for the operating system, PowerShell, .NET SDK and runtimes,
    Git, NuGet sources, the ASP.NET Core HTTPS development certificate, the
    Umbraco project template, and the repository's Git state.

    Nothing is installed, trusted, generated, or modified. The .NET first-run
    experience (which can generate a dev certificate) is suppressed for the
    duration of the script and the environment is restored afterwards.

.PARAMETER RepositoryRoot
    Repository root to inspect. Defaults to the parent of this script's folder.

.PARAMETER RequiredSdkMajor
    Major version of the .NET SDK and runtimes that must be installed.

.PARAMETER ExpectedUmbracoTemplateVersion
    Version of Umbraco.Templates the project was scaffolded from.

.PARAMETER SkipNetwork
    Skip the nuget.org connectivity check.

.PARAMETER Strict
    Treat warnings as failures.

.EXAMPLE
    pwsh ./scripts/Test-Prerequisites.ps1

.EXAMPLE
    pwsh ./scripts/Test-Prerequisites.ps1 -Strict -SkipNetwork

.NOTES
    Exit codes:
      0  No failed checks (warnings may be present unless -Strict).
      1  One or more checks failed (or warnings present with -Strict).
      2  The script itself encountered an unexpected error.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [int]$RequiredSdkMajor = 10,
    [string]$ExpectedUmbracoTemplateVersion = '17.8.1',
    [switch]$SkipNetwork,
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 does not populate $PSScriptRoot inside param() defaults.
if (-not $RepositoryRoot) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

$results =[System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][ValidateSet('Pass', 'Warn', 'Fail', 'Info')][string]$Status,
        [Parameter(Mandatory)][string]$Detail
    )
    $results.Add([pscustomobject]@{ Check = $Check; Status = $Status; Detail = $Detail })
}

# Runs a native command without letting stderr or a non-zero exit code terminate the script.
function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = (Get-Location).Path
    )
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    Push-Location -LiteralPath $WorkingDirectory
    try {
        $output = & $FilePath @Arguments 2>&1 | ForEach-Object { "$_" }
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
    }
    finally {
        Pop-Location
    }
}

function Test-CommandAvailable([string]$Name) {
    [bool](Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue)
}

function Test-OperatingSystem {
    # Not $IsWindows: that is a read-only automatic variable in PowerShell 7 and absent in 5.1.
    $runningOnWindows = $env:OS -eq 'Windows_NT'
    $description = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim()
    if ($runningOnWindows) {
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem
            $description = "$($os.Caption) $($os.Version) (build $($os.BuildNumber), $($os.OSArchitecture))"
        }
        catch {
            # CIM can be unavailable in restricted sessions; the runtime description is sufficient.
        }
        Add-Result 'Operating system' 'Pass' $description
    }
    else {
        Add-Result 'Operating system' 'Warn' "$description - this lab is documented for Windows only."
    }
}

function Test-PowerShellVersion {
    $version = $PSVersionTable.PSVersion
    $edition = $PSVersionTable.PSEdition
    if ($version.Major -ge 7) {
        Add-Result 'PowerShell' 'Pass' "$version ($edition)"
    }
    else {
        Add-Result 'PowerShell' 'Warn' "$version ($edition) - works, but the docs assume PowerShell 7+."
    }
}

function Test-DotNet {
    if (-not (Test-CommandAvailable 'dotnet')) {
        Add-Result '.NET CLI' 'Fail' 'dotnet was not found on PATH. Install the .NET 10 SDK.'
        return $false
    }

    $sdks = Invoke-Native 'dotnet' @('--list-sdks')
    $sdkVersions = @($sdks.Output | ForEach-Object { if ($_ -match '^(\S+)\s+\[') { $Matches[1] } })
    $matching = @($sdkVersions | Where-Object { $_ -match "^$RequiredSdkMajor\." })
    if ($matching.Count -gt 0) {
        Add-Result ".NET $RequiredSdkMajor SDK" 'Pass' "Installed: $($matching -join ', ') (all SDKs: $($sdkVersions -join ', '))"
    }
    else {
        Add-Result ".NET $RequiredSdkMajor SDK" 'Fail' "No $RequiredSdkMajor.x SDK found. Installed: $($sdkVersions -join ', ')"
    }

    # `dotnet --version` honours global.json, so run it from the repository root.
    $resolved = Invoke-Native 'dotnet' @('--version') -WorkingDirectory $RepositoryRoot
    $resolvedVersion = ($resolved.Output | Select-Object -First 1)
    if ($resolved.ExitCode -eq 0 -and $resolvedVersion -match "^$RequiredSdkMajor\.") {
        Add-Result 'SDK resolved in repo' 'Pass' "$resolvedVersion (honours global.json if present)"
    }
    elseif ($resolved.ExitCode -eq 0) {
        Add-Result 'SDK resolved in repo' 'Fail' "$resolvedVersion resolves in $RepositoryRoot; expected $RequiredSdkMajor.x"
    }
    else {
        Add-Result 'SDK resolved in repo' 'Fail' ("dotnet --version failed (exit $($resolved.ExitCode)): " + ($resolved.Output -join ' '))
    }

    $runtimes = Invoke-Native 'dotnet' @('--list-runtimes')
    foreach ($framework in 'Microsoft.NETCore.App', 'Microsoft.AspNetCore.App') {
        $found = @($runtimes.Output | ForEach-Object {
                if ($_ -match "^$([regex]::Escape($framework))\s+($RequiredSdkMajor\.\S+)\s+\[") { $Matches[1] }
            })
        if ($found.Count -gt 0) {
            Add-Result "$framework $RequiredSdkMajor" 'Pass' "Installed: $($found -join ', ')"
        }
        else {
            Add-Result "$framework $RequiredSdkMajor" 'Fail' "No $RequiredSdkMajor.x runtime found."
        }
    }
    return $true
}

function Test-Git {
    if (-not (Test-CommandAvailable 'git')) {
        Add-Result 'Git' 'Fail' 'git was not found on PATH.'
        return $false
    }
    $version = Invoke-Native 'git' @('--version')
    Add-Result 'Git' 'Pass' ($version.Output -join ' ')

    # Report presence only; identity values are not echoed into logs.
    $name = Invoke-Native 'git' @('config', '--get', 'user.name')
    $email = Invoke-Native 'git' @('config', '--get', 'user.email')
    if ($name.ExitCode -eq 0 -and $email.ExitCode -eq 0) {
        Add-Result 'Git identity' 'Pass' 'user.name and user.email are configured.'
    }
    else {
        Add-Result 'Git identity' 'Warn' 'user.name and/or user.email are not configured; commits will fail.'
    }
    return $true
}

function Test-NuGet {
    $list = Invoke-Native 'dotnet' @('nuget', 'list', 'source')
    if ($list.ExitCode -ne 0) {
        Add-Result 'NuGet sources' 'Fail' ("dotnet nuget list source failed: " + ($list.Output -join ' '))
        return
    }

    # Output pairs a "N.  Name [Enabled]" line with an indented URL line.
    $sources = @()
    for ($i = 0; $i -lt $list.Output.Count; $i++) {
        if ($list.Output[$i] -match '^\s*\d+\.\s+(.+?)\s+\[(Enabled|Disabled)\]') {
            $url = if ($i + 1 -lt $list.Output.Count) { $list.Output[$i + 1].Trim() } else { '' }
            $sources += [pscustomobject]@{ Name = $Matches[1]; Enabled = $Matches[2] -eq 'Enabled'; Url = $url }
        }
    }

    $nugetOrg = @($sources | Where-Object { $_.Url -like '*api.nuget.org/v3/index.json*' })
    $summary = ($sources | ForEach-Object { "$($_.Name)=$(if ($_.Enabled) { 'on' } else { 'off' })" }) -join '; '
    if ($nugetOrg.Count -gt 0 -and $nugetOrg[0].Enabled) {
        Add-Result 'NuGet sources' 'Pass' "nuget.org enabled. Sources: $summary"
    }
    elseif ($nugetOrg.Count -gt 0) {
        Add-Result 'NuGet sources' 'Fail' "nuget.org is registered but disabled. Sources: $summary"
    }
    else {
        Add-Result 'NuGet sources' 'Fail' "nuget.org is not registered. Sources: $summary"
    }

    if ($SkipNetwork) {
        Add-Result 'nuget.org reachable' 'Info' 'Skipped (-SkipNetwork).'
        return
    }
    try {
        $response = Invoke-WebRequest -Uri 'https://api.nuget.org/v3/index.json' -Method Head -UseBasicParsing -TimeoutSec 15
        Add-Result 'nuget.org reachable' 'Pass' "HTTP $([int]$response.StatusCode)"
    }
    catch {
        Add-Result 'nuget.org reachable' 'Fail' "Could not reach api.nuget.org: $($_.Exception.Message)"
    }
}

function Test-DevCertificate {
    # --check only inspects the certificate store; it never creates or trusts a certificate.
    $trusted = Invoke-Native 'dotnet' @('dev-certs', 'https', '--check', '--trust')
    if ($trusted.ExitCode -eq 0) {
        Add-Result 'HTTPS dev certificate' 'Pass' 'A valid, trusted localhost development certificate exists.'
        return
    }
    $exists = Invoke-Native 'dotnet' @('dev-certs', 'https', '--check')
    if ($exists.ExitCode -eq 0) {
        Add-Result 'HTTPS dev certificate' 'Warn' "Certificate exists but is not trusted. Browsers will warn on https://localhost. To trust it, run: dotnet dev-certs https --trust"
    }
    else {
        Add-Result 'HTTPS dev certificate' 'Warn' "No valid development certificate found. To create and trust one, run: dotnet dev-certs https --trust"
    }
}

function Test-UmbracoTemplate {
    # With no package argument, `dotnet new uninstall` only lists installed template packages.
    $installed = Invoke-Native 'dotnet' @('new', 'uninstall')
    $text = $installed.Output -join "`n"
    if ($text -match '(?ms)^\s*Umbraco\.Templates\s*$.*?Version:\s*(\S+)') {
        $version = $Matches[1]
        if ($version -eq $ExpectedUmbracoTemplateVersion) {
            Add-Result 'Umbraco.Templates' 'Pass' "Installed: $version"
        }
        else {
            Add-Result 'Umbraco.Templates' 'Warn' "Installed: $version; expected $ExpectedUmbracoTemplateVersion. Run: dotnet new install Umbraco.Templates@$ExpectedUmbracoTemplateVersion"
        }
    }
    else {
        Add-Result 'Umbraco.Templates' 'Warn' "Not installed (only needed to scaffold). Run: dotnet new install Umbraco.Templates@$ExpectedUmbracoTemplateVersion"
    }
}

function Test-Repository {
    if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) {
        Add-Result 'Repository root' 'Fail' "$RepositoryRoot does not exist."
        return
    }
    $root = (Resolve-Path -LiteralPath $RepositoryRoot).Path.TrimEnd('\', '/')
    Add-Result 'Repository root' 'Info' $root

    $top = Invoke-Native 'git' @('rev-parse', '--show-toplevel') -WorkingDirectory $root
    if ($top.ExitCode -ne 0) {
        Add-Result 'Git repository' 'Warn' 'Not a Git repository yet.'
        return
    }
    $topLevel = ($top.Output | Select-Object -First 1) -replace '/', '\'
    if ($topLevel.TrimEnd('\') -ne $root) {
        Add-Result 'Git repository' 'Warn' "Nested inside another repository rooted at $topLevel."
        return
    }

    $branch = (Invoke-Native 'git' @('branch', '--show-current') -WorkingDirectory $root).Output | Select-Object -First 1
    $head = Invoke-Native 'git' @('rev-parse', '--short', 'HEAD') -WorkingDirectory $root
    $revision = if ($head.ExitCode -eq 0) { $head.Output | Select-Object -First 1 } else { '(no commits)' }
    $status = Invoke-Native 'git' @('status', '--porcelain') -WorkingDirectory $root
    $changes = @($status.Output | Where-Object { $_ }).Count
    Add-Result 'Git repository' 'Pass' "Branch '$branch' at $revision; $changes uncommitted change(s)."

    # Local runtime state must never be tracked (ls-files includes staged files before the first commit).
    $tracked = (Invoke-Native 'git' @('ls-files') -WorkingDirectory $root).Output
    $forbidden = @($tracked | Where-Object {
            $_ -match '\.(sqlite|db|db-shm|db-wal|sqlite\.db)$' -or
            $_ -match '(^|/)umbraco/(Data|Logs|mediacache)/' -or
            $_ -match '(^|/)wwwroot/media/' -or
            $_ -match '(^|/)appsettings\.Local\.json$' -or
            $_ -match '\.log$'
        })
    if ($forbidden.Count -eq 0) {
        Add-Result 'Git hygiene' 'Pass' 'No databases, logs, media, or appsettings.Local.json are tracked.'
    }
    else {
        Add-Result 'Git hygiene' 'Fail' ("Tracked local-state files: " + ($forbidden -join ', '))
    }

    # The Umbraco installer writes a generated HMACSecretKey into appsettings.json; it belongs in appsettings.Local.json.
    $secrets = Invoke-Native 'git' @('grep', '--cached', '-l', '-E', '"(HMACSecretKey|umbracoDbDSN)"[[:space:]]*:[[:space:]]*"[^"]+', '--', '*.json') -WorkingDirectory $root
    $secretFiles = @($secrets.Output | Where-Object { $_ })
    if ($secrets.ExitCode -eq 1 -and $secretFiles.Count -eq 0) {
        Add-Result 'Tracked secrets' 'Pass' 'No tracked JSON file sets HMACSecretKey or umbracoDbDSN.'
    }
    elseif ($secrets.ExitCode -eq 0) {
        Add-Result 'Tracked secrets' 'Fail' ("Move these values to appsettings.Local.json: " + ($secretFiles -join ', '))
    }
    else {
        Add-Result 'Tracked secrets' 'Warn' ("git grep failed (exit $($secrets.ExitCode)): " + ($secrets.Output -join ' '))
    }
}

function Write-Report {
    $colors = @{ Pass = 'Green'; Warn = 'Yellow'; Fail = 'Red'; Info = 'Cyan' }
    Write-Host ''
    Write-Host 'Funky Fresh Farm - prerequisite check' -ForegroundColor White
    Write-Host ('=' * 60)
    foreach ($result in $results) {
        Write-Host ('[{0}] ' -f $result.Status.ToUpperInvariant().PadRight(4)) -ForegroundColor $colors[$result.Status] -NoNewline
        Write-Host ('{0,-28} {1}' -f $result.Check, $result.Detail)
    }
    Write-Host ('=' * 60)
}

# Suppress the .NET first-run experience so that a read-only check never generates a certificate.
$guardedVariables = 'DOTNET_NOLOGO', 'DOTNET_GENERATE_ASPNET_CERTIFICATE'
$savedEnvironment = @{}
foreach ($name in $guardedVariables) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
    $env:DOTNET_NOLOGO = '1'
    $env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'

    Test-OperatingSystem
    Test-PowerShellVersion
    $hasDotNet = Test-DotNet
    $hasGit = Test-Git
    if ($hasDotNet) {
        Test-NuGet
        Test-DevCertificate
        Test-UmbracoTemplate
    }
    if ($hasGit) {
        Test-Repository
    }

    Write-Report

    $failed = @($results | Where-Object Status -EQ 'Fail').Count
    $warned = @($results | Where-Object Status -EQ 'Warn').Count
    $passed = @($results | Where-Object Status -EQ 'Pass').Count
    $exitCode = if ($failed -gt 0 -or ($Strict -and $warned -gt 0)) { 1 } else { 0 }
    $summaryColor = if ($exitCode -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("Passed: {0}  Warnings: {1}  Failed: {2}  Exit code: {3}" -f $passed, $warned, $failed, $exitCode) -ForegroundColor $summaryColor
}
catch {
    Write-Host "Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    $exitCode = 2
}
finally {
    foreach ($name in $guardedVariables) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}

exit $exitCode
