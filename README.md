# Funky Fresh Farm — Umbraco Lab

A personal learning exercise: building a website for **Funky Fresh Farm**, a fictional farm,
on open-source [Umbraco CMS](https://umbraco.com/products/umbraco-cms/).

## Purpose and scope

The lab explores how Umbraco works as an ASP.NET Core application: its boot process, content
modelling, rendering, extension points, and operational concerns. It runs entirely on a local
Windows machine.

**In scope:** Umbraco CMS (open source), .NET 10, SQLite, local Kestrel hosting, Git.

**Out of scope:** Docker, Azure or other cloud hosting, Shopify, React front ends, commerce plugins,
and commercial or paid Umbraco extensions.

**Status:** Milestone 1 (installation and project foundation) is complete. The site has no
content, document types, or templates yet; browsing to `/` shows Umbraco's
"No Published Content" page.

## Technology versions

Exact versions verified on 2026-11-15 (see [docs/verification-log.md](docs/verification-log.md)).

| Component | Version | Source of truth |
|---|---|---|
| Umbraco CMS (`Umbraco.Cms`) | **17.8.1** (build `17.8.1+89c87c2`) | `src/FunkyFreshFarm.UmbracoLab/Directory.Packages.props` |
| Umbraco project template (`Umbraco.Templates`) | 17.8.1 | `dotnet new install` |
| Backoffice client / UI Library | 17.8.1 / 2.1.1 | Backoffice → System information |
| Target framework | `net10.0` | `FunkyFreshFarm.UmbracoLab.csproj` |
| .NET SDK | 10.0.404 (`global.json`: 10.0.100, `latestFeature`) | `dotnet --version` |
| .NET / ASP.NET Core runtime | 10.0.15 | `dotnet --list-runtimes` |
| Microsoft.Data.Sqlite | 10.0.12 (transitive) | `dotnet list package --include-transitive` |
| SQLitePCLRaw (`e_sqlite3`) | 2.1.12 (native lib 2.1.13) | transitive |
| OpenIddict | 7.7.1 (transitive) | transitive |
| Examine (Lucene search) | 3.10.0 (transitive) | transitive |
| Microsoft.ICU.ICU4C.Runtime | 72.1.0.3 | `Directory.Packages.props` |
| Windows / PowerShell / Git | Windows 11 Pro 26200 / 7.6.10 / 2.52.0 | `scripts/Test-Prerequisites.ps1` |

## Setup

### Prerequisites

- Windows with PowerShell 7+ (recommended) or Windows PowerShell 5.1; the documented commands work in both
- .NET 10 SDK (10.0.100 or later feature band)
- Git
- A trusted ASP.NET Core HTTPS development certificate (`dotnet dev-certs https --trust`)

Check them, read-only:

```powershell
pwsh ./scripts/Test-Prerequisites.ps1
```

Exit code `0` means no failed checks; `1` means at least one check failed (or a warning with `-Strict`);
`2` means the script itself errored.

### Build and run

```powershell
dotnet restore FunkyFreshFarm.slnx
dotnet build FunkyFreshFarm.slnx
dotnet run --project src/FunkyFreshFarm.UmbracoLab --launch-profile Umbraco.Web.UI
```

Stop the application with **Ctrl+C**.

### First run on a new clone

The SQLite database and its connection string are local state and are not in Git. On a fresh
clone, Umbraco starts in install mode: open the backoffice URL below and follow
[docs/01-installation.md § First-run installation](docs/01-installation.md#6-first-run-interactive-installation).

## Local access

| What | URL | Notes |
|---|---|---|
| Website | https://localhost:44370/ | Also served on http://localhost:41388/ |
| Backoffice | https://localhost:44370/umbraco | **HTTPS only.** Login over HTTP fails with OpenIddict error ID2083 |
| Server status API | https://localhost:44370/umbraco/management/api/v1/server/status | Returns `{"serverStatus":"Run"}` once installed |

Ports come from `src/FunkyFreshFarm.UmbracoLab/Properties/launchSettings.json` (profile `Umbraco.Web.UI`).

## Repository organisation

```text
FunkyFreshFarm/
├─ CLAUDE.md                     Standing rules for Claude Code sessions
├─ README.md                     This file
├─ FunkyFreshFarm.slnx           Solution (XML .slnx format, .NET 10 default)
├─ global.json                   SDK selection (10.0.x, latest feature band)
├─ .gitignore / .gitattributes   Repository-wide ignores; line-ending normalisation
├─ docs/
│  ├─ 01-installation.md         Installation, configuration, architecture, backup, troubleshooting
│  ├─ manual-test-checklist.md   Human verification steps and outcomes
│  └─ verification-log.md        Commands run, results, evidence, known issues
├─ scripts/
│  └─ Test-Prerequisites.ps1     Read-only environment and Git-hygiene checks
└─ src/
   └─ FunkyFreshFarm.UmbracoLab/ The Umbraco web application (generated from Umbraco.Templates 17.8.1)
      ├─ Program.cs              Umbraco boot and middleware pipeline
      ├─ Directory.Packages.props Central package versions (Umbraco pinned to 17.8.1)
      ├─ appsettings*.json       Configuration (see docs for what is tracked vs local)
      ├─ Views/                  Razor views and block partials
      ├─ wwwroot/                Static files (media uploads land in wwwroot/media, untracked)
      └─ umbraco/                Runtime state: Data (SQLite, TEMP), Logs — untracked
```

## Further documentation

- [Installation guide](docs/01-installation.md): setup, configuration, SQLite, startup architecture, backup, troubleshooting
- [Manual test checklist](docs/manual-test-checklist.md)
- [Verification log](docs/verification-log.md)
- [Umbraco 17 documentation](https://docs.umbraco.com/umbraco-cms/17.latest/)
- [Umbraco CMS source, `release-17.8.1`](https://github.com/umbraco/Umbraco-CMS/tree/release-17.8.1)
