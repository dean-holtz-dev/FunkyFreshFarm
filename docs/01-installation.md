# 01 — Installation and Project Foundation

This guide covers how the Funky Fresh Farm Umbraco lab was created, how to build and run it, how
it is configured, where its state lives, and how to back it up. Everything here was verified
against Umbraco **17.8.1** on .NET **10.0.15** (see [verification-log.md](verification-log.md)).

Contents:

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [One-time machine setup](#3-one-time-machine-setup)
4. [How the project was scaffolded](#4-how-the-project-was-scaffolded)
5. [Build and run](#5-build-and-run)
6. [First-run interactive installation](#6-first-run-interactive-installation)
7. [Configuration overview](#7-configuration-overview)
8. [SQLite database](#8-sqlite-database)
9. [Umbraco startup architecture](#9-umbraco-startup-architecture)
10. [Source-controlled versus local state](#10-source-controlled-versus-local-state)
11. [Backup, restore, and restart](#11-backup-restore-and-restart)
12. [Troubleshooting](#12-troubleshooting)
13. [References](#13-references)

---

## 1. Overview

The application is a standard ASP.NET Core web app (`Microsoft.NET.Sdk.Web`) generated from the
official `Umbraco.Templates` 17.8.1 package. Umbraco plugs into the generic host through
`Program.cs`, stores content and configuration in SQLite, and serves both the public website and
the backoffice (the editor UI) from the same Kestrel process.

## 2. Prerequisites

| Requirement | Verified version | Notes |
|---|---|---|
| Windows | 11 Pro, build 26200 | |
| PowerShell | 7.6.10 | The prerequisite script also runs on Windows PowerShell 5.1 |
| .NET SDK | 10.0.404 | `global.json` requires 10.0.100+ within the 10.0 line |
| .NET runtimes | Microsoft.NETCore.App and Microsoft.AspNetCore.App 10.0.15 | |
| Git | 2.52.0 | `user.name` / `user.email` configured |
| NuGet | nuget.org enabled and reachable | |
| HTTPS dev certificate | present **and trusted** | Required for backoffice login (see §12) |

Run the read-only check:

```powershell
pwsh ./scripts/Test-Prerequisites.ps1            # all checks
pwsh ./scripts/Test-Prerequisites.ps1 -SkipNetwork -Strict   # offline; warnings fail
```

The script never installs, trusts, or modifies anything. It suppresses the .NET first-run
experience (which can generate a dev certificate) and restores the environment afterwards.

| Exit code | Meaning |
|---|---|
| 0 | No failed checks (warnings allowed unless `-Strict`) |
| 1 | At least one failed check, or any warning with `-Strict` |
| 2 | The script itself hit an unexpected error |

It also guards Git hygiene: it fails if a database, log, media file, or `appsettings.Local.json`
is tracked, or if a tracked JSON file sets `HMACSecretKey` or `umbracoDbDSN`.

**IDE note.** Visual Studio 2022 17.6, the only Visual Studio installed when this lab started,
cannot build .NET 10 projects. Use VS Code with the C# Dev Kit, Visual Studio 2026 (18.x), or
JetBrains Rider for debugging.

## 3. One-time machine setup

These change per-user state outside the repository. Each is done once per machine.

```powershell
# Umbraco project templates (stored under %USERPROFILE%\.templateengine)
dotnet new install Umbraco.Templates@17.8.1

# Trust the ASP.NET Core development certificate (shows a Windows confirmation dialog;
# adds the localhost cert to the CurrentUser Trusted Root store)
dotnet dev-certs https --trust
```

`dotnet new` reports that Umbraco.Templates 18.x exists. Ignore it: 18 is not the LTS line
this lab targets.

## 4. How the project was scaffolded

Recorded for reproducibility; **you do not need to run this** on a clone.

```powershell
dotnet new globaljson --sdk-version 10.0.100 --roll-forward latestFeature
dotnet new umbraco --name FunkyFreshFarm.UmbracoLab --output src/FunkyFreshFarm.UmbracoLab `
    --release Latest --no-restore --no-update-check
dotnet new sln --name FunkyFreshFarm            # creates FunkyFreshFarm.slnx
dotnet sln FunkyFreshFarm.slnx add src/FunkyFreshFarm.UmbracoLab/FunkyFreshFarm.UmbracoLab.csproj
git init -b main
```

Two deliberate deviations from the "obvious" template arguments, both verified in the template
and the Umbraco source:

1. **`--release Latest`, not `--release LTS`.** In Umbraco.Templates 17.8.1 the `LTS` choice
   writes the floating version `17.*` into `Directory.Packages.props` (and enables
   `CentralPackageFloatingVersionsEnabled`), so a future restore would silently move to a later
   17.x. `Latest` writes the exact pin `17.8.1`. Both target `net10.0`, and 17 *is* the LTS line.
2. **No preconfigured SQLite connection string.** The project was first scaffolded with
   `--development-database-type SQLite`, which booted as **`BootFailed`** (every request returned
   HTTP 500). The 4-line `ConnectionStrings` block that option adds to
   `appsettings.Development.json` was removed. A file comparison confirmed the result matches
   the template's default (`--development-database-type None`) output, apart from the randomly
   generated `Global:Id` and ports. The reason is explained in [§12](#bootfailed--installmissingdatabase-on-first-run).

Other template defaults kept: central package management (`Directory.Packages.props` beside the
project), `BackofficeDevelopment` runtime mode, `InMemoryAuto` Models Builder mode, no starter
kit, no Delivery API, no HTTPS redirect, no Docker.

## 5. Build and run

```powershell
dotnet restore FunkyFreshFarm.slnx
dotnet build FunkyFreshFarm.slnx            # expect: 0 Warning(s), 0 Error(s)
dotnet run --project src/FunkyFreshFarm.UmbracoLab --launch-profile Umbraco.Web.UI
```

Expected console output once ready:

```text
[INF] Now listening on: https://localhost:44370
[INF] Now listening on: http://localhost:41388
[INF] Application started. Press Ctrl+C to shut down.
[INF] Hosting environment: Development
```

Stop with **Ctrl+C**. The build copies `appsettings-schema*.json` and `umbraco-package-schema.json`
into the project folder; they are gitignored.

| What | URL |
|---|---|
| Website | https://localhost:44370/ (also http://localhost:41388/) |
| Backoffice | **https://localhost:44370/umbraco** (HTTPS only) |
| Health check | https://localhost:44370/umbraco/management/api/v1/server/status → `{"serverStatus":"Run"}` |

## 6. First-run interactive installation

On a fresh clone there is no database and no connection string, so Umbraco boots at runtime level
`Install` (reason `InstallNoDatabase`) and the backoffice URL serves the installer.

1. Make sure the dev certificate is trusted (`dotnet dev-certs https --check --trust` exits 0).
2. Run the app (§5) and open **https://localhost:44370/umbraco**.
3. **User step:** enter the administrator's name, email, and password (minimum **10** characters),
   and choose a telemetry level (Minimal, Basic, or Detailed). Credentials are entered here only;
   they are never written to configuration files.
4. **Database step:** choose **SQLite** and keep the default database name `Umbraco`.
5. Select **Install**. The installer runs `FilePermissionsStep`, `HmacSecretKeyStep`,
   `DatabaseConfigureStep`, `DatabaseInstallStep` (creates 79 tables), and `RestartRuntimeStep`,
   after which the runtime level is `Run` without a process restart.
6. Log in. The backoffice shows the Content, Media, Settings, Packages, Users, Members, and
   Translation sections.
7. **Post-install hygiene (required):** the installer writes a generated
   `Umbraco:CMS:Imaging:HMACSecretKey` into the *tracked* `appsettings.json`. Move that `Imaging`
   block into `appsettings.Local.json` (same `Umbraco:CMS` path) and confirm `appsettings.json` is
   unchanged with `git diff`. The prerequisite script's "Tracked secrets" check fails until this
   is done (once the file is staged).

What the installer writes:

| Item | Location | Tracked? |
|---|---|---|
| `ConnectionStrings:umbracoDbDSN` (+ `_ProviderName`) | `appsettings.Local.json` | No |
| `Umbraco:CMS:Imaging:HMACSecretKey` | `appsettings.json` → **move to** `appsettings.Local.json` | No (after moving) |
| Database (`Umbraco.sqlite.db`, `-wal`, `-shm`) | `umbraco/Data/` | No |
| Administrator account (hashed password) | `umbracoUser` table | No |

## 7. Configuration overview

### Files

| File | Tracked | Loaded when | Purpose |
|---|---|---|---|
| `appsettings.json` | Yes | Always | Serilog levels, `Umbraco:CMS` defaults, `Global:Id` |
| `appsettings.Development.json` | Yes | `ASPNETCORE_ENVIRONMENT=Development` | Console logging, `Hosting:Debug=true` |
| `appsettings.Local.json` | **No** | **DEBUG builds only** (`#if DEBUG` in `Program.cs`) | Connection string, HMAC secret, personal overrides |
| `Properties/launchSettings.json` | Yes | `dotnet run` / IDE | URLs, `ASPNETCORE_ENVIRONMENT=Development` |
| `Directory.Packages.props` | Yes | Build | Exact package versions |

### Precedence

`WebApplication.CreateBuilder(args)` registers, lowest to highest priority: `appsettings.json` →
`appsettings.{Environment}.json` → environment variables → command-line arguments. (User secrets
are *not* added: the project has no `UserSecretsId`.) `Program.cs` then appends
`appsettings.Local.json` **last**, so in DEBUG builds it overrides environment variables and
command-line arguments too. This differs from a typical ASP.NET Core app.

Environment variables still work for keys that `appsettings.Local.json` does not set, using `__` as the
separator. For example, `$env:Serilog__MinimumLevel__Default = 'Debug'` exposes Umbraco's
debug-level boot messages such as `Runtime level: Run - Run`.

### Notable settings

| Key | Value | Where | Effect |
|---|---|---|---|
| `Umbraco:CMS:Global:Id` | GUID | `appsettings.json` | Anonymous site identifier for telemetry. Not a secret |
| `Umbraco:CMS:Global:UseHttps` | *(unset → `true`)* | default | Requires HTTPS for backoffice auth (OpenIddict) |
| `Umbraco:CMS:Hosting:Debug` | `true` | Development | Detailed boot-failure exceptions instead of the friendly error page |
| `Umbraco:CMS:Unattended:UpgradeUnattended` | `true` | `appsettings.json` | Runs database migrations automatically after a package upgrade |
| `Umbraco:CMS:Content:ContentVersionCleanupPolicy:EnableCleanup` | `true` | `appsettings.json` | Prunes old content versions in the background |
| `Umbraco:CMS:Security:AllowConcurrentLogins` | `false` | `appsettings.json` | One active backoffice session per user |
| Runtime mode | `BackofficeDevelopment` | default | Allows schema changes in the backoffice; runtime Razor compilation |
| Models Builder mode | `InMemoryAuto` | default | Strongly typed models generated in memory, available in views only |

The project file sets `RazorCompileOnBuild=false` and `RazorCompileOnPublish=false` because
`InMemoryAuto` compiles views at runtime. `UmbracoUseAppLocalIcu` ships ICU 72.1.0.3 so
globalisation behaves identically on Windows and Linux.

## 8. SQLite database

**Location:** `src/FunkyFreshFarm.UmbracoLab/umbraco/Data/Umbraco.sqlite.db`, plus
`Umbraco.sqlite.db-wal` and `Umbraco.sqlite.db-shm`.

The connection string uses `Data Source=|DataDirectory|/Umbraco.sqlite.db`. Umbraco's
`AddUmbraco()` sets the `DataDirectory` AppDomain value to `<content root>\umbraco\Data`
(`Umbraco.Web.Common/DependencyInjection/UmbracoBuilderExtensions.cs:149` in 17.8.1) and
substitutes it when reading the connection string.

Behaviour to know:

- **WAL mode.** The database is created in write-ahead-log mode. Committed changes go to the
  `-wal` file and are checkpointed into the main file later. During this milestone the main file
  stayed at 4 KB while the WAL grew to about 3.5 MB: *all* installed data was in the WAL.
  A copy of the `.db` file alone had **0 tables**; the full three-file set had 79.
- **No implicit creation.** Umbraco post-configures SQLite connections from `Mode=ReadWriteCreate`
  to `Mode=ReadWrite` (`ConfigureSqliteConnectionStringMode`), so a wrong path fails loudly
  instead of silently creating an empty database.
- **Single process.** Run one instance at a time against a given database file.

**What it stores:** content and media metadata, document/media/member types, data types,
template metadata (the `.cshtml` files are on disk), dictionary items, languages, domains,
redirects, relations, tags, users, user groups, permissions, members, audit and log-viewer
queries, webhooks, content schedules, distributed locks (`umbracoLock`), server registrations
and cache instructions, migration state (`umbracoKeyValue`), and OpenIddict applications,
tokens, and authorizations (`umbracoOpenIddict*`, managed by EF Core).

**What it does not store:** uploaded media files (`wwwroot/media/`), Examine/Lucene indexes and
generated models (`umbraco/Data/TEMP/`), logs (`umbraco/Logs/`), and configuration (JSON files).

## 9. Umbraco startup architecture

`Program.cs` walk-through, with what each step does in 17.8.1:

| # | Code | What happens |
|---|---|---|
| 1 | `WebApplication.CreateBuilder(args)` | Standard ASP.NET Core host: configuration, logging, DI container builder |
| 2 | `AddJsonFile("appsettings.Local.json")` | DEBUG only; appended as the highest-priority configuration source |
| 3 | `builder.CreateUmbracoBuilder()` | Applies Umbraco host defaults (Serilog), enables static web assets unless in Production runtime mode, calls `services.AddUmbraco()`: type loader (assembly scanning), app caches, profiler, `DataDirectory`, core services |
| 4 | `.AddBackOffice()` | Management API, backoffice identity, OpenIddict server, backoffice static assets |
| 5 | `.AddWebsite()` | Front-end routing, `RenderController`, surface controllers, view engines, Models Builder |
| 6 | `.AddComposers()` | Discovers every `IComposer` with the type loader, orders them by `[ComposeAfter]`/`[ComposeBefore]`, and runs `Compose()`. Eleven ran here (SQLite, SQL Server, EF Core, ImageSharp, backoffice development mode, Management API, Examine, migrations) |
| 7 | `.Build()` | Flushes Umbraco's *collection builders* (ordered lists such as content finders and property value converters) into `IServiceCollection` |
| 8 | `builder.Build()` | Builds the DI container |
| 9 | `await app.BootUmbracoAsync()` | Starts `IRuntime` (`CoreRuntime`) **before** the pipeline is built: acquires MainDom, publishes `RuntimeUnattendedInstallNotification`, determines the runtime level, runs upgrades if needed, publishes `UmbracoApplicationStarting`. Registers `StopAsync` on `ApplicationStopping` for graceful shutdown |
| 10 | `app.UseUmbraco().WithMiddleware(...)` | Adds Umbraco's required middleware in a fixed order (core and boot-failed handling, request logging, Umbraco routing, media file provider, static files, `UseRouting`, authentication, authorization, antiforgery, localization, session), with `IUmbracoPipelineFilter` hooks around it; then your callback: `UseBackOffice()`, `UseWebsite()` |
| 11 | `.WithEndpoints(...)` | `UseBackOfficeEndpoints()` maps the Management API, auth endpoints, and backoffice; `UseWebsiteEndpoints()` maps surface routes and the dynamic content route |
| 12 | `await app.RunAsync()` | Kestrel starts; recurring background jobs start (temp-file cleanup, instruction processing, server touch, telemetry report, cache-size reporting) |

### Runtime levels

`CoreRuntime` decides the runtime level at step 9, from the configuration and the database state:

| Level – reason | Observed when | Effect |
|---|---|---|
| `Install – InstallNoDatabase` | No connection string (fresh clone) | `/umbraco` serves the installer; install API enabled |
| `BootFailed – InstallMissingDatabase` | SQLite connection string set, file missing, no unattended install | Every request returns 500 |
| `Run – Run` | Installed database at the current schema version | Normal operation; install API returns 428 |
| `Upgrade` / `Upgrading` | Schema older than the packages | Upgrade UI, or automatic migration with `UpgradeUnattended` |

Because Umbraco boots before the pipeline is built, the runtime level can change how the app
behaves. `BootFailedMiddleware`, for example, short-circuits every request.

## 10. Source-controlled versus local state

| Path | Tracked | Contents |
|---|---|---|
| `src/**/*.cs`, `*.csproj`, `Directory.Packages.props` | Yes | Code and package versions |
| `appsettings.json`, `appsettings.Development.json` | Yes | Non-secret configuration |
| `Properties/launchSettings.json` | Yes | Local URLs and environment |
| `Views/**/*.cshtml`, `wwwroot/favicon.ico` | Yes | Templates and static assets |
| `FunkyFreshFarm.slnx`, `global.json`, `.git*`, `docs/`, `scripts/` | Yes | Repository scaffolding |
| `appsettings.Local.json` | **No** | Connection string, HMAC secret |
| `umbraco/Data/*.sqlite.db*` | **No** | The database |
| `umbraco/Data/TEMP/` | **No** | Examine indexes, InMemoryAuto models, MainDom, temp uploads (regenerated) |
| `umbraco/Logs/` | **No** | `UmbracoTraceLog.<machine>.<yyyyMMdd>.json` (Serilog compact JSON) |
| `wwwroot/media/` | **No** | Uploaded media files |
| `appsettings-schema*.json`, `umbraco-package-schema.json` | **No** | Copied in by every build |
| `bin/`, `obj/`, `.vs/`, `backups/` | **No** | Build output, IDE state, local backups |

Content and schema (document types, data types) exist **only in the local database** for now.
A later milestone can decide whether to source-control schema (for example as code or
through a serialisation approach).

## 11. Backup, restore, and restart

### Backup (tested)

Stop the app first (Ctrl+C). Copy **all** database files plus the local secrets and media:

```powershell
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$app   = 'src/FunkyFreshFarm.UmbracoLab'
$dest  = "backups/$stamp"
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item "$app/umbraco/Data/Umbraco.sqlite.db*" $dest      # .db, -wal, -shm
Copy-Item "$app/appsettings.Local.json" $dest                # connection string + HMAC key
if (Test-Path "$app/wwwroot/media") { Copy-Item "$app/wwwroot/media" "$dest/media" -Recurse }
Get-ChildItem $dest
```

`backups/` is gitignored. Treat it as sensitive: it holds password hashes and the HMAC key.
Never copy only `Umbraco.sqlite.db`, because without the `-wal` file it can be an empty database.

### Restore (not yet exercised against the live app)

The integrity of a backup set was verified by opening a copy of it (79 tables, 1 user); the
in-place restore below has not been run yet. With the app stopped:

```powershell
$src = 'backups/<stamp>'
$app = 'src/FunkyFreshFarm.UmbracoLab'
Remove-Item "$app/umbraco/Data/Umbraco.sqlite.db*"           # remove all three, so no stale WAL remains
Copy-Item "$src/Umbraco.sqlite.db*" "$app/umbraco/Data/"
Copy-Item "$src/appsettings.Local.json" $app
if (Test-Path "$src/media") { Copy-Item "$src/media" "$app/wwwroot/" -Recurse -Force }
Remove-Item "$app/umbraco/Data/TEMP" -Recurse -Force -ErrorAction SilentlyContinue   # indexes rebuild
```

Then start the app and confirm `serverStatus` is `Run`.

### Restart

Ctrl+C, then `dotnet run ...` again. Expected: no installer, `Run` level, and existing
backoffice sessions may need to log in again. Installation state lives in the database, so it
survives restarts. Verified both ways: a graceful Ctrl+C restart, and a forced process kill.

### Reset to a fresh install (destructive, not yet exercised)

Back up first, stop the app, then delete `umbraco/Data/Umbraco.sqlite.db*`, `umbraco/Data/TEMP/`,
and the `ConnectionStrings` block in `appsettings.Local.json`. The next start enters `Install` mode.

## 12. Troubleshooting

### BootFailed / InstallMissingDatabase on first run

**Symptom:** HTTP 500 on every URL. The log has five `SQLite Error 14: 'unable to open database file'`
warnings, then `BootFailedException: Boot failed: Umbraco cannot run`.
**Cause:** a SQLite connection string is configured but the file does not exist. Umbraco forces
`Mode=ReadWrite`, so the availability check cannot create it, and `RuntimeState` sets
`BootFailed / InstallMissingDatabase` (`RuntimeState.cs:206-211`). Only the *unattended* installer
(`UnattendedInstaller.cs:70-84`, `InstallUnattended=true`) creates the database in that state,
and that requires admin credentials in configuration.
**Fix:** remove the connection string, as this project does, and use the attended installer. To
diagnose similar boot failures, set `$env:Serilog__MinimumLevel__Default='Debug'` and look for
`Runtime level: <level> - <reason>`.

### OpenIddict ID2083 "This server only accepts HTTPS requests"

**Symptom:** after installing over `http://localhost:41388`, login fails with
`error:invalid_request ... ID2083`.
**Cause:** `GlobalSettings.UseHttps` defaults to `true` in 17.8.1, and `ConfigureOpenIddict` sets
`DisableTransportSecurityRequirement = !UseHttps`.
**Fix:** use https://localhost:44370/umbraco. Do not turn off `UseHttps` to work around a
certificate warning.

### Browser warns about the certificate / "developer certificate is not trusted"

Run `dotnet dev-certs https --trust` and accept the prompt. Check with
`dotnet dev-certs https --check --trust` (exit code 0 means trusted). Firefox uses its own
certificate store and may still warn.

### HMACSecretKey appears in `appsettings.json`

Expected after an install. Move it to `appsettings.Local.json` (§6, step 7).

### "Exception occurred while trying to subscribe the user ... to the Umbraco newsletter"

Logged at the end of installation (`TaskCanceledException`). Harmless: the newsletter request was
cancelled. The installation completes normally.

### "Application URL auto-detection is disabled and no explicit URL is configured"

A warning on the first request. Without `Umbraco:CMS:WebRouting:UmbracoApplicationUrl`, emails
(invitations, password resets) cannot contain links. Not needed for this lab yet; set it (for
example to `https://localhost:44370`) in `appsettings.Local.json` if email is added later.

### Build fails with "file is locked by FunkyFreshFarm.UmbracoLab"

The app is still running. Stop it (Ctrl+C) before building.

### Port already in use

Another instance is running. Find it with
`Get-NetTCPConnection -LocalPort 44370 -State Listen | Select-Object OwningProcess`.

### Visual Studio cannot open or build the solution

VS 2022 17.6 does not support .NET 10 or `.slnx`. Use VS 2026, Rider, or VS Code + C# Dev Kit.

### Logs

`src/FunkyFreshFarm.UmbracoLab/umbraco/Logs/UmbracoTraceLog.<machine>.<yyyyMMdd>.json`
(one JSON object per line), also viewable in the backoffice under Settings → Log Viewer. In
Development the console shows the same events.

## 13. References

- Umbraco 17 docs: https://docs.umbraco.com/umbraco-cms/17.latest/
- Template package: https://www.nuget.org/packages/Umbraco.Templates/17.8.1
- Source at this version: https://github.com/umbraco/Umbraco-CMS/tree/release-17.8.1
  - `src/Umbraco.Infrastructure/Runtime/RuntimeState.cs`
  - `src/Umbraco.Infrastructure/Runtime/CoreRuntime.cs`
  - `src/Umbraco.Infrastructure/Install/UnattendedInstaller.cs`
  - `src/Umbraco.Cms.Persistence.Sqlite/Configuration/ConfigureSqliteConnectionStringMode.cs`
  - `src/Umbraco.Cms.Api.Common/Configuration/ConfigureOpenIddict.cs`
  - `src/Umbraco.Web.Common/ApplicationBuilder/UmbracoApplicationBuilder.cs`
  - `src/Umbraco.Web.Common/Extensions/WebApplicationExtensions.cs`
