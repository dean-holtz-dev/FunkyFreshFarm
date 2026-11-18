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

**Status:**

| Milestone | State |
|---|---|
| 1. Installation and project foundation | Complete |
| 2. Content modelling and Razor rendering | Complete: four Document Types, a homepage, a plant directory with plant pages, a growing guide, shared layout and navigation, responsive CSS, publishing exercises, and a site smoke test |
| 3. Content Delivery API and .NET extensibility | Complete: Delivery API v2 enabled (public, published content only, no preview key), a `ContentPublishedNotification` logging handler with unit tests, and an API verification script |
| 4. Source exploration and engineering review | Complete: source-backed architecture briefing against Umbraco commit `89c87c2` (tag `release-17.8.1`), operational review, and a tested hot-backup tool with a backup/restore runbook |
| 5. Visual identity ("Farmstand Funk") | Complete: design tokens, self-hosted Fraunces + DM Sans, branded header/footer, responsive art-directed hero, featured plants, farm story, botanical plant profiles, guide illustration, branded 404, brand-asset pipeline and test |

**The lab is complete.** [docs/06-retrospective.md](docs/06-retrospective.md) tells the story of how the site was built, milestone by milestone, and how much (or how little) code it took.

**Database-backed state.** The Document Types, Data Types, template records, pages, and media
exist only in the local SQLite database and `wwwroot/media/`, not in Git. A fresh clone has the
Razor views and CSS but no content model: recreate it by following
[docs/02-content-model.md §5–§6](docs/02-content-model.md#5-backoffice-recreation-instructions),
or restore a database backup ([docs/01-installation.md §11](docs/01-installation.md#11-backup-restore-and-restart)).

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
| Test stack | xUnit 2.9.3, Microsoft.NET.Test.Sdk 17.14.1, NSubstitute 6.2.0, Microsoft.Extensions.Diagnostics.Testing 10.11.0 | `tests/FunkyFreshFarm.UmbracoLab.Tests/*.csproj` |
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

### Smoke-test the public site

With the app running and the Milestone 2 content published:

```powershell
pwsh ./scripts/Test-Site.ps1
```

It runs 10 read-only checks (routes, status codes, content markers, image processing) and exits
`0` on success, `1` on any failure. Prerequisites and the required content are listed in
[docs/02-content-model.md §13](docs/02-content-model.md#13-testing-the-public-site).

### Test the Delivery API and the C# code

```powershell
pwsh ./scripts/Test-DeliveryApi.ps1    # 14 read-only checks of the JSON API
dotnet test FunkyFreshFarm.slnx        # unit tests for the notification handler
```

The API test needs the app running and the Delivery API index built (about a minute after the first
request following startup). See [docs/03-api-and-extensions.md §7](docs/03-api-and-extensions.md#7-running-the-verification).
C# changes require stopping the app before building, because the running process locks `bin/`.

### Brand assets

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Build-BrandAssets.ps1   # regenerate wwwroot/brand from assets/images
pwsh ./scripts/Test-BrandAssets.ps1                                      # files, serving, page markup, CMS illustrations
pwsh ./scripts/Test-BrandAssets.ps1 -SkipCms                             # skip the CMS-managed illustration checks
```

See [docs/05-assets.md](docs/05-assets.md) for which assets live in Git and which in the Media Library.

### Back up the database

```powershell
dotnet run scripts/backup-database.cs     # hot, consistent, verified copy into backups/<stamp>-hot/
```

The app can keep running; the live database is opened read-only. Copy `appsettings.Local.json` and
`wwwroot/media` alongside it, and see the full runbook (including restore) in
[docs/04-architecture.md §10](docs/04-architecture.md#10-local-backup-and-restore-runbook).

### First run on a new clone

The SQLite database and its connection string are local state and are not in Git. On a fresh
clone, Umbraco starts in install mode: open the backoffice URL below and follow
[docs/01-installation.md § First-run installation](docs/01-installation.md#6-first-run-interactive-installation).
Then recreate the content model and pages with
[docs/02-content-model.md §5–§6](docs/02-content-model.md#5-backoffice-recreation-instructions).

## Local access

| What | URL | Notes |
|---|---|---|
| Website | https://localhost:44370/ | Also served on http://localhost:41388/. Pages: `/`, `/plants/`, `/plants/heirloom-tomato/`, `/plants/basil/`, `/plants/zinnia/`, `/growing-guide/` |
| Backoffice | https://localhost:44370/umbraco | **HTTPS only.** Login over HTTP fails with OpenIddict error ID2083 |
| Server status API | https://localhost:44370/umbraco/management/api/v1/server/status | Returns `{"serverStatus":"Run"}` once installed |
| Content Delivery API | https://localhost:44370/umbraco/delivery/api/v2/content/item/ | Public, published content only. Example: `/umbraco/delivery/api/v2/content?fetch=children:/plants/` |
| Swagger UI | https://localhost:44370/umbraco/swagger | Select the **Umbraco Delivery API** definition; not available in Production runtime mode |

Ports come from `src/FunkyFreshFarm.UmbracoLab/Properties/launchSettings.json` (profile `Umbraco.Web.UI`).

## Repository organisation

```text
FunkyFreshFarm/
├─ CLAUDE.md                     Standing rules for Claude Code sessions
├─ README.md                     This file
├─ FunkyFreshFarm.slnx           Solution (XML .slnx format, .NET 10 default)
├─ global.json                   SDK selection (10.0.x, latest feature band)
├─ .gitignore / .gitattributes   Repository-wide ignores; line-ending normalisation
├─ assets/
│  ├─ images/                    Owner's original artwork (committed; inputs to Build-BrandAssets and Media uploads)
│  └─ placeholder-images/        Milestone 2 placeholder plant PNGs (superseded in the Media Library in Milestone 5)
├─ docs/
│  ├─ 01-installation.md         Installation, configuration, architecture, backup, troubleshooting
│  ├─ 02-content-model.md        Content model, backoffice recreation, Razor, publishing, testing
│  ├─ 03-api-and-extensions.md   Delivery API, security, notification handler, end-to-end trace
│  ├─ 04-architecture.md         Source-backed architecture briefing, operational review, backup runbook
│  ├─ 05-design-system.md        "Farmstand Funk" tokens, typography, components, responsive and accessibility rules
│  ├─ 05-assets.md               Asset inventory, provenance, Git versus Media Library, owner upload procedures
│  ├─ 06-retrospective.md        How the finished site was built, and how easy it turned out to be
│  ├─ manual-test-checklist.md   Human verification steps and outcomes
│  └─ verification-log.md        Commands run, results, evidence, known issues
├─ scripts/
│  ├─ Test-Prerequisites.ps1     Read-only environment and Git-hygiene checks
│  ├─ Test-Site.ps1              Read-only smoke test of the public site
│  ├─ Test-DeliveryApi.ps1       Read-only semantic test of the Content Delivery API
│  ├─ Test-BrandAssets.ps1       Read-only test of brand files, serving, markup, and CMS illustrations
│  ├─ Build-BrandAssets.ps1      Generates wwwroot/brand derivatives from the original artwork
│  └─ backup-database.cs         Hot SQLite backup + integrity check (.NET file-based app)
├─ tests/
│  └─ FunkyFreshFarm.UmbracoLab.Tests/  xUnit tests for the notification handler and its registration
└─ src/
   └─ FunkyFreshFarm.UmbracoLab/ The Umbraco web application (generated from Umbraco.Templates 17.8.1)
      ├─ Program.cs              Umbraco boot and middleware pipeline (+ AddDeliveryApi)
      ├─ Directory.Packages.props Central package versions (Umbraco pinned to 17.8.1)
      ├─ appsettings*.json       Configuration (see docs for what is tracked vs local)
      ├─ Notifications/          ContentPublishedLoggingHandler + NotificationsComposer
      ├─ Views/
      │  ├─ _Layout.cshtml        Shared layout (code-owned; not a backoffice template)
      │  ├─ HomePage.cshtml, PlantIndexPage.cshtml, PlantPage.cshtml, GuidePage.cshtml
      │  │                        Page templates (records in the database, markup in Git)
      │  └─ Partials/             Navigation.cshtml plus the template's block partials
      ├─ wwwroot/                Static files: css/site.css, brand/ (artwork derivatives), fonts/ (WOFF2 + OFL);
      │                          media uploads land in wwwroot/media (untracked)
      └─ umbraco/                Runtime state: Data (SQLite, TEMP), Logs — untracked
```

## Further documentation

- [Installation guide](docs/01-installation.md): setup, configuration, SQLite, startup architecture, backup, troubleshooting
- [Content model and rendering](docs/02-content-model.md): why Umbraco models content this way, Document Types, backoffice recreation, Razor, publishing lifecycle, testing
- [Delivery API and extensions](docs/03-api-and-extensions.md): API configuration, endpoints, JSON shapes, security, notification handler, end-to-end trace
- [Architecture and engineering review](docs/04-architecture.md): startup and lifecycle traced through Umbraco's source, project boundaries, operational risks, testing, upgrades, backup/restore runbook
- [Design system](docs/05-design-system.md) and [brand assets](docs/05-assets.md): palette and contrast, typography and licensing, components, responsive images, asset provenance and replacement
- [Retrospective](docs/06-retrospective.md): the build from empty folder to branded site, what was easy, where the friction was, and the numbers
- [Manual test checklist](docs/manual-test-checklist.md)
- [Verification log](docs/verification-log.md)
- [Umbraco 17 documentation](https://docs.umbraco.com/umbraco-cms/17.latest/)
- [Umbraco CMS source, `release-17.8.1`](https://github.com/umbraco/Umbraco-CMS/tree/release-17.8.1)
