# Verification Log — Milestone 1

| | |
|---|---|
| Date | 2026-11-15 (times are local, UTC−06:00) |
| Scope | Installation and project foundation |
| Automated checks | Claude Code |
| Manual checks | Repository owner (see [manual-test-checklist.md](manual-test-checklist.md)) |
| Git revision | Baseline: none (empty directory, no repository). This log is part of the initial commit; find it with `git log --oneline -- docs/verification-log.md` |
| Environment | Windows 11 Pro 10.0.26200 x64 · PowerShell 7.6.10 · .NET SDK 10.0.404 · runtime 10.0.15 · Git 2.52.0 |

Result values: **PASS**, **FAIL**, **NOT RUN**. **FINDING** marks an investigation outcome that
changed the plan, and **INFO** marks a recorded fact.

## Phase 1 — Prerequisites

| # | Command / action | Result | Evidence |
|---|---|---|---|
| 1 | `$PSVersionTable`; `Get-CimInstance Win32_OperatingSystem` | PASS | PowerShell 7.6.10 (Core); Windows 11 Pro 10.0.26200, 64-bit |
| 2 | `dotnet --info`; `--list-sdks`; `--list-runtimes` | PASS | SDKs 7.0.302 and 10.0.404; Microsoft.NETCore.App and Microsoft.AspNetCore.App 10.0.15. The first CLI call printed the .NET first-run banner; the only dev certificate afterwards is dated 2026-09-12, so no new certificate was created |
| 3 | `git --version`; `git config` | PASS | 2.52.0.windows.1; identity configured; `core.autocrlf=true` at system scope |
| 4 | `dotnet nuget list source` | PASS | nuget.org enabled; "Microsoft Visual Studio Offline Packages" enabled |
| 5 | `dotnet dev-certs https --check --trust` | FAIL → PASS | Initially exit 7 (certificate present but not trusted). After the owner ran `--trust`: exit 0, thumbprint `5DE1BA19…0AD2` |
| 6 | `Get-ChildItem`, `git rev-parse` in `C:\dev\FunkyFreshFarm` | INFO | Directory empty, not a Git repository |
| 7 | NuGet flat-container index for `umbraco.templates` and `umbraco.cms` | PASS | 17.8.1 is the newest 17.x stable release of both |
| 8 | `vswhere -all -prerelease` | INFO | Only Visual Studio Community 2022 17.6 installed (cannot build .NET 10). VS Code installed |
| 9 | `pwsh scripts/Test-Prerequisites.ps1` (first run) | PASS | Exit 0: 10 pass, 3 warnings (untrusted cert, template not installed, no repository). First attempt exited 2 because `$isWindows` clashed with the read-only `$IsWindows`; renamed |
| 10 | Same under Windows PowerShell 5.1 | PASS | Exit 0. The first attempt failed because 5.1 leaves `$PSScriptRoot` empty in `param()` defaults; the default is now resolved in the script body |
| 11 | `Test-Prerequisites.ps1 -Strict` with warnings present | PASS | Exit 1, as designed |
| 12 | Hygiene negative test: scratch repo with a staged `appsettings.Local.json` and a fake `HMACSecretKey` | PASS | "Git hygiene" FAIL + "Tracked secrets" FAIL, exit 1, as designed |
| 13 | Environment restoration after the script | PASS | `DOTNET_GENERATE_ASPNET_CERTIFICATE` empty in the calling session afterwards |

## Phase 2 — Scaffold

| # | Command / action | Result | Evidence |
|---|---|---|---|
| 14 | `dotnet new install Umbraco.Templates@17.8.1` | PASS | Installed `umbraco`, `umbraco-extension`, `umbraco-compose` |
| 15 | `dotnet new umbraco -h` | PASS | `--release` accepts `Latest\|LTS`; `--development-database-type` accepts `None\|SQLite\|LocalDB` (default `None`) |
| 16 | Inspect `UmbracoProject/.template.config/template.json` | FINDING | `LTS` → package version `17.*` (floating); `Latest` → `17.8.1`; both → `net10.0`. Chose `--release Latest` |
| 17 | `dotnet new umbraco ... --dry-run` | PASS | 15 files; the CLI also reports Umbraco.Templates 18.3.1 is available (not LTS, ignored) |
| 18 | `dotnet new umbraco --name FunkyFreshFarm.UmbracoLab --output src/FunkyFreshFarm.UmbracoLab --release Latest --development-database-type SQLite --no-restore --no-update-check` | PASS | Created; the SQLite option was reverted later (#29) |
| 19 | `dotnet new globaljson --sdk-version 10.0.100 --roll-forward latestFeature`; `dotnet --version` | PASS | Resolves 10.0.404 |
| 20 | `dotnet new sln --name FunkyFreshFarm`; `dotnet sln add ...` | PASS | `FunkyFreshFarm.slnx` with the project under `/src/` |
| 21 | `git init -b main` | PASS | Empty repository on `main` |
| 22 | `dotnet restore FunkyFreshFarm.slnx` | PASS | 26.6 s |
| 23 | `dotnet list package --include-transitive` | PASS | Umbraco.Cms and Umbraco.Cms.DevelopmentMode.Backoffice 17.8.1 requested and resolved; all `Umbraco.Cms.*` transitive packages 17.8.1; Microsoft.Data.Sqlite 10.0.12; SQLitePCLRaw 2.1.12 (lib 2.1.13); OpenIddict 7.7.1; Examine 3.10.0; Serilog.AspNetCore 9.0.0; Microsoft.ICU.ICU4C.Runtime 72.1.0.3 |
| 24 | `dotnet list package --vulnerable --include-transitive` | PASS | "no vulnerable packages given the current sources" |
| 25 | `dotnet build FunkyFreshFarm.slnx --no-restore -c Debug` | PASS | 0 warnings, 0 errors; target `net10.0` |

## Phase 3 — Build, run, install, restart

| # | Command / action | Result | Evidence |
|---|---|---|---|
| 26 | Run 1: `dotnet run ... --launch-profile Umbraco.Web.UI` (SQLite connection string preconfigured, no database) | FAIL | Listening on https://localhost:44370 and http://localhost:41388, but `/`, `/umbraco`, `/umbraco/install` → HTTP 500 `BootFailedException`; 5× `SQLite Error 14: 'unable to open database file'` |
| 27 | Run 2 with `Serilog__MinimumLevel__Default=Debug` | FINDING | `Runtime level: BootFailed - InstallMissingDatabase` |
| 28 | Read Umbraco source at `release-17.8.1` (and 17.8.0, 17.7.2) | FINDING | `ConfigureSqliteConnectionStringMode` forces `Mode=ReadWrite`; `RuntimeState.cs:206-211` sets `BootFailed`; only `UnattendedInstaller` (`InstallUnattended=true`) creates the database. Behaviour is the same in 17.7.2 and 17.8.0 |
| 29 | Scaffold a `--development-database-type None` copy and compare | PASS | Only differences: the 4-line `ConnectionStrings` block in `appsettings.Development.json`, random `Global:Id`, ports. Removed the block |
| 30 | Run 3 (no connection string) | PASS | `Runtime level: Install - InstallNoDatabase`; `/`, `/umbraco`, `/umbraco/install` → 200; install settings API offers SQLite (`Microsoft.Data.Sqlite`, default name `Umbraco`) |
| 31 | Interactive install by the owner (14:23) | PASS | Log: `DatabaseConfigureStep`, `DatabaseInstallStep`, `RestartRuntimeStep` → `Runtime level: Run - Run`. Database files created |
| 32 | Post-install configuration diff against pre-install snapshot | FINDING | Connection string written to the untracked `appsettings.Local.json`. `Imaging:HMACSecretKey` written to the **tracked** `appsettings.json`; moved to `appsettings.Local.json` (value verified identical); `appsettings.json` restored byte-for-byte (SHA-256 prefix `AC43B4D8F5A99283`) |
| 33 | Backoffice login over HTTP (owner) | PASS (expected rejection) | OpenIddict `ID2083`. Cause: `GlobalSettings.UseHttps` defaults to `true` (`GlobalSettings.cs:45`); `ConfigureOpenIddict.cs:26` |
| 34 | Backoffice login over HTTPS (owner) | PASS | Sections visible; System information: Umbraco 17.8.1 (`17.8.1+89c87c2`), .NET 10.0.15, Kestrel, SQLite, `InMemoryAuto`, `BackofficeDevelopment` |
| 35 | Stop: terminate the `dotnet run` and app processes | PASS | 0 processes, 0 listeners on 44370/41388. Database files: main 4,096 B, WAL 3,040,592 B (no checkpoint) |
| 36 | `dotnet build FunkyFreshFarm.slnx -c Debug` | PASS | 0 warnings, 0 errors; `bin/` config copies refreshed (connection string only in `appsettings.Local.json`) |
| 37 | Run 4: restart | PASS | `Runtime level: Run - Run`; `server/status` → `{"serverStatus":"Run"}`; install settings API → 428 "Runtime level Install is required"; HTTPS probes succeed without `-k`; no untrusted-certificate warning |
| 38 | `GET https://localhost:44370/` | PASS | Title "Umbraco: No Published Content" |
| 39 | Backup procedure from `docs/01-installation.md` §11 (app stopped) | PASS | `backups/20261115-143711/`: `.db`, `-wal`, `-shm`, `appsettings.Local.json`, `media/`; `git check-ignore` matches `.gitignore:36:backups/` |
| 40 | Open copies of the backup with a .NET 10 file-based app (Microsoft.Data.Sqlite 10.0.12) | PASS | Full set: `journal_mode=wal`, 79 tables, 1 user, 5 user groups, 48 nodes, 8 content types, 37 data types, 1 language. `.db` copied alone: **0 tables** |
| 41 | Run 5: restart with default logging | PASS | `Application started`, `serverStatus: Run`, no warnings at startup |
| 42 | Backoffice usable after restart (owner, MT-07) | NOT RUN | Pending owner confirmation |
| 43 | Graceful Ctrl+C stop and restart in owner's terminal (MT-08) | NOT RUN | Automated stops terminated the process; the graceful path is untested |

## Phase 4 — Documentation and Git hygiene

| # | Command / action | Result | Evidence |
|---|---|---|---|
| 44 | `git add -A`; `git diff --cached --name-status` | PASS | 24 files staged: repository scaffolding, docs, script, and template sources only |
| 45 | `git status --ignored` | PASS | Ignored: `appsettings.Local.json`, `umbraco/` (Data, Logs, TEMP), `bin/`, `obj/`, generated schema files, `backups/` |
| 46 | `pwsh scripts/Test-Prerequisites.ps1` with files staged | PASS | Exit 0: 15 pass, 0 warnings, 0 failures (incl. "Git hygiene", "Tracked secrets") |
| 47 | `git grep --cached -E 'HMACSecretKey\|umbracoDbDSN\|Password\|sqlite\.db'` (excluding docs) | PASS | Only `.gitignore` patterns match; no secret values |
| 48 | Search `src/**/*.json` for unattended credential keys | PASS | 0 matches for `UnattendedUser*`, `InstallUnattended`, `Password` |

## Known issues

| Issue | Impact | Status / workaround |
|---|---|---|
| A preconfigured SQLite connection string with no file boots as `BootFailed` (attended install) | Template option `--development-database-type SQLite` unusable without unattended credentials | Worked around: no preconfigured connection string; attended installer |
| Installer writes `Imaging:HMACSecretKey` to the tracked `appsettings.json` | Secret could be committed | Moved to `appsettings.Local.json`; guarded by the prerequisite script |
| Backoffice requires HTTPS (ID2083 over HTTP) | HTTP URL works for the website only | Use https://localhost:44370/umbraco. Optional later: HTTP→HTTPS redirect |
| Newsletter subscription `TaskCanceledException` at end of install | None | Ignore |
| "Application URL auto-detection is disabled" warning | Email links unavailable | Set `WebRouting:UmbracoApplicationUrl` when email is needed |
| `appsettings.Local.json` loads only in DEBUG builds | A Release build has no connection string and enters install mode | Provide configuration through the environment for non-DEBUG runs (future milestone) |
| Data lives mostly in the SQLite WAL file | Copying only `.db` yields an empty database | Back up all three files with the app stopped |
| Visual Studio 2022 17.6 cannot build .NET 10 / open `.slnx` | No VS debugging | Use VS Code + C# Dev Kit, VS 2026, or Rider |
| Backoffice labels the database provider "System.Data.SQLite" | Cosmetic | Actual provider is `Microsoft.Data.Sqlite` 10.0.12 |
| Restore and reset procedures not yet exercised | Untested docs | Exercise in a later milestone |
