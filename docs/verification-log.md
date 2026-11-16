# Verification Log

- [Milestone 1 — Installation and project foundation](#milestone-1--installation-and-project-foundation)
- [Milestone 2 — Content modelling and Razor rendering](#milestone-2--content-modelling-and-razor-rendering)
- [Milestone 3 — Content Delivery API and .NET extensibility](#milestone-3--content-delivery-api-and-net-extensibility)

# Milestone 1 — Installation and project foundation

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
| 42 | Backoffice usable after restart (owner, MT-07) | PASS | Confirmed by the owner; login screen/backoffice, not the installer |
| 42a | Front-end placeholder page (owner, MT-09) | PASS | Confirmed by the owner; "No Published Content" page |
| 43 | Graceful Ctrl+C stop and restart in owner's terminal (MT-08) | PASS | Confirmed by the owner (Windows PowerShell 5.1): clean Ctrl+C shutdown, restart without the installer |

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

---

# Milestone 2 — Content modelling and Razor rendering

| | |
|---|---|
| Date | 2026-11-15 (times are local, UTC−06:00) |
| Scope | Content model, backoffice content, Razor rendering, publishing behaviour, smoke test |
| Automated checks | Claude Code (read-only: files, HTTP, logs, generated models, database **snapshots** taken with SQLite's online backup API from a read-only connection; the live database was never written) |
| Manual checks | Repository owner (MT-10 to MT-20 in [manual-test-checklist.md](manual-test-checklist.md)) |
| Git revision | Baseline `0d36ebc`. This log is part of the Milestone 2 commit; find it with `git log --oneline -- docs/verification-log.md` |
| Environment | As Milestone 1; Umbraco 17.8.1, .NET 10.0.15 |

## Baseline (before any change)

| # | Command / action | Result | Evidence |
|---|---|---|---|
| M2-1 | `git status`, `git log` | PASS | Clean at `0d36ebc` |
| M2-2 | `Test-Prerequisites.ps1 -SkipNetwork` | PASS | 14 pass, 0 warnings, 0 failures |
| M2-3 | `dotnet build FunkyFreshFarm.slnx -c Debug` | PASS | 0 warnings, 0 errors |
| M2-4 | Start app; `server/status`, `/`, `/umbraco` | PASS | `Run`; 200; title "Umbraco: No Published Content" |
| M2-5 | Database files after the owner's MT-08 Ctrl+C shutdown | INFO | Single 1 MB file: the clean shutdown checkpointed the WAL |

## Phase 1–2 — Model design and backoffice configuration

| # | Command / action | Result | Evidence |
|---|---|---|---|
| M2-6 | List built-in Data Types from a backup copy | INFO | Textstring, Textarea, Richtext editor (Tiptap), Image Media Picker (images only, single), Radiobox (no options) |
| M2-7 | Verify backoffice labels in `Umbraco.Web.UI.Client/src/assets/lang/en.ts` (17.8.1) | PASS | "Document Type with Template", "Add group", "Add property", "Available configurations", "Allow at root", "Allowed child node types", "Save and publish", "Add option", "Publication Status", "Published (pending changes)", "Unpublish" |
| M2-8 | Generate placeholder PNGs (scratch .NET file-based app, no dependencies) | PASS | 3 × 800×600 RGB, 9–14 KB; decoded by GDI+; visually checked |
| M2-9 | Checkpoint C: template files | PASS | `Views/HomePage.cshtml`, `PlantIndexPage.cshtml`, `PlantPage.cshtml`, `GuidePage.cshtml` with matching `UmbracoViewPage<ContentModels.X>` |
| M2-10 | Checkpoint C: snapshot of Document Types | FAIL → PASS | All aliases, Data Types, structure rules, and templates correct; `heroHeadline` `mandatory=0`. After the owner's fix: `mandatory=1` |
| M2-11 | Checkpoint C: log since app start | PASS | 0 errors; 1 known warning (Application URL) |
| M2-12 | Confirm the snapshot does not write the live DB | PASS | WAL timestamp advances every ~5 s with no reads (app's InstructionProcessJob) |
| M2-13 | Checkpoint E: snapshot of content and media | PASS | Tree: Home (L1); Plants and Growing Guide (L2, siblings); 3 plants (L3). All published, `edited=0`. `plantImage` keys match media items; Basil `commonName` empty; Zinnia no image |
| M2-14 | Uploaded media vs placeholder sources (SHA-256) | PASS | Byte-identical |
| M2-15 | Rich-text body and toolbar configuration | FINDING | Body has h2/p/ul/strong; typo "planing"; default toolbar has **no heading button** |
| M2-16 | Public routes with empty templates | PASS | 6 routes 200 (empty body); unknown URL 404; media file 200 `image/png` |
| M2-17 | `models.generated.cs` | PASS | `HomePage`, `PlantIndexPage`, `PlantPage` (`PlantImage: MediaWithCrops`), `GuidePage` (`BodyText: IHtmlEncodedString`) |
| M2-18 | Log since Checkpoint C | PASS | 0 errors; 29 × "Notifications can not be sent, no site URL is set" (known) |

## Phase 3 — Razor rendering

| # | Command / action | Result | Evidence |
|---|---|---|---|
| M2-19 | Verify APIs in 17.8.1 source | PASS | `Root()`, `Children<T>()`, `Parent()`, `AncestorsOrSelf()`, `Url()`; `GetCropUrl(MediaWithCrops, width, height, imageCropMode)`; `Html.ReplaceLineBreaks` encodes first; `UmbracoViewPage` writes `IHtmlEncodedString` raw; default `NoopHtmlSanitizer`; view locations `/Views/`, `/Views/Shared/`, `/Views/Partials/` |
| M2-20 | Request all routes after adding views and CSS (no restart) | PASS | 6 pages 200 with correct titles; no compilation errors; CSS 200; unknown 404 |
| M2-21 | Inspect markup | PASS | Hero/intro with `<br />`; nav `aria-current`; section highlighting; signed image URLs; Zinnia placeholder and no `<figure>`; Basil Name fallback; rich text unencoded; apostrophe encoded |
| M2-22 | Fetch processed images | PASS | 480×360 and 800×600 `image/png`; tampered `hmac` → **400** |
| M2-23 | ImageSharp cache location | PASS | `umbraco/Data/TEMP/MediaCache/` |
| M2-24 | Owner's visual check (MT-14) | PASS | "Phase 3 visual check passed" |

## Phase 4 — Publishing behaviour

| # | Stage | Result | Evidence (snapshot + HTTP) |
|---|---|---|---|
| M2-25 | Baseline | INFO | Home v5 published, v6 current; cache rows draft `rv=1`, published `rv=0` |
| M2-26 | A: Save only | PASS | `edited=1`; still 2 versions; v6 updated in place; published cache row unchanged; public `<h1>` old ×3 |
| M2-27 | B: Save and publish | PASS | `edited=0`; v6 published; new current v20; published cache row `rv` 0→1; public `<h1>` new; audit log 4 entries = History |
| M2-28 | C: create Mint | PASS | Level 3 under Plants, sort 3; v21/v22; directory 4 cards in order; `/plants/mint/` 200 |
| M2-29 | D: unpublish Mint | PASS | `published=0`, `edited=1`, not trashed; no new version; published cache row deleted; directory 3 cards; `/plants/mint/` 404 |
| M2-30 | E: Ctrl+C restart | PASS | New PID; clean shutdown and startup in log; state identical to D; owner saw a single DB file after shutdown |
| M2-31 | Source confirmation | PASS | `DocumentRepository.cs:1355-1425` (versions), `DocumentCacheService.RefreshContentAsync` (cache), `DocumentRepository.cs:1298-1306, 1516-1522` (unpublish) |

## Phase 5–7 — Smoke test, documentation, build, Git

| # | Command / action | Result | Evidence |
|---|---|---|---|
| M2-32 | `pwsh scripts/Test-Site.ps1` | PASS | 10 passed, 0 failed, exit 0 |
| M2-33 | Same under Windows PowerShell 5.1 | PASS | 10 passed, exit 0 |
| M2-34 | `Test-Site.ps1 -BaseUrl http://localhost:41388` | PASS | 10 passed, exit 0 |
| M2-35 | Negative: unreachable port | PASS | "Site reachable" FAIL, exit 1 |
| M2-36 | Negative: wrong marker (scratch copy) | PASS | "missing '<h1>Our Plantz</h1>'", exit 1 |
| M2-37 | Verify routing classes for docs | FINDING | URL finder is `ContentFinderByUrlNew` (`IDocumentUrlService`); `ContentFinderByUrl` is obsolete and unregistered; docs corrected |
| M2-38 | `dotnet build FunkyFreshFarm.slnx -c Debug` (app running) | PASS | 0 warnings, 0 errors (incremental; app unaffected) |
| M2-39 | Final `Test-Site.ps1` | PASS | 10/10 |
| M2-40 | Owner runs `Test-Site.ps1` (MT-20) | PASS | Owner's terminal: `Passed: 10  Failed: 0  Exit code: 0` |

## Known issues (Milestone 2)

| Issue | Impact | Status / workaround |
|---|---|---|
| Content model, content, and media are database/filesystem state | A fresh clone renders nothing until recreated | Documented recreation (02-content-model.md §5–§6) and backup/restore |
| `InMemoryAuto` + `RazorCompileOnBuild=false` | View/alias errors appear only at request time | `Test-Site.ps1`; consider `SourceCodeAuto` later |
| Rich text is unsanitised (`NoopHtmlSanitizer`) | Editors can inject arbitrary HTML | Acceptable for a single-admin lab; register a real `IHtmlSanitizer` to harden |
| "Notifications can not be sent, no site URL is set" (3 per save/publish) | Log noise; no email notifications | Set `Umbraco:CMS:WebRouting:UmbracoApplicationUrl` when email is needed |
| Default Richtext editor toolbar has no heading button | Headings need `##` + space or Source code | Documented in 02-content-model.md §6 |
| Growing Guide body typo "planing" | Cosmetic | Owner's content; not changed |
| Mint exists unpublished | None; tests do not count cards | Republish or delete as desired |
| Owner's `assets/images/` (12 PNGs, 32.6 MB) | Untracked | Not committed pending the owner's decision |

---

# Milestone 3 — Content Delivery API and .NET extensibility

| | |
|---|---|
| Date | 2026-11-15 (times are local, UTC−06:00) |
| Scope | Delivery API, `ContentPublishedNotification` handler, unit tests, API verification script, end-to-end trace |
| Automated checks | Claude Code (read-only: files, HTTP, logs, source at `release-17.8.1`, database snapshots via SQLite's online backup API) |
| Manual checks | Repository owner (MT-21 to MT-26 in [manual-test-checklist.md](manual-test-checklist.md)) |
| Git revision | Baseline `8ee7dc3`. This log is part of the Milestone 3 commit; find it with `git log --oneline -- docs/verification-log.md` |

## Baseline and research

| # | Command / action | Result | Evidence |
|---|---|---|---|
| M3-1 | `git status`; owner's app instance | INFO | Clean at `8ee7dc3` (only untracked `assets/images/`); app running (PID 30776) |
| M3-2 | `Test-Prerequisites.ps1 -SkipNetwork`; `Test-Site.ps1` | PASS | 14/0/0; 10/10 |
| M3-3 | Delivery API before enabling | FINDING | `/v2/content/item/` → 500 "Unable to resolve service … IRequestSegmentService" (with stack trace in Development); `/v1/` → 400 |
| M3-4 | Template `--use-delivery-api` output | PASS | Adds `.AddDeliveryApi()` to `Program.cs` and `DeliveryApi:Enabled: true` to `appsettings.json` |
| M3-5 | Official docs (17.latest) and `DeliveryApiSettings.cs` | PASS | Defaults: `Enabled=false`, `PublicAccess=true`, `ApiKey=null`, `RichTextOutputAsJson=false`, `Media.Enabled=false`, `OutputCache.Enabled=false` |
| M3-6 | Notification pipeline source | PASS | "-ing" published immediately; "-ed" queued until scope completes; commit precedes dispatch (`Scope.DisposeLastScope`); handlers transient, invoked sequentially, no try/catch |
| M3-7 | Index source | PASS | `RebuildOnStartupHandler` rebuilds empty indexes one minute after the first request on warm boot |

## Implementation and automated verification

| # | Command / action | Result | Evidence |
|---|---|---|---|
| M3-8 | Edit `Program.cs`, `appsettings.json`; add `Notifications/` handler and composer | PASS | — |
| M3-9 | `dotnet new xunit`; trim; add NSubstitute 6.2.0, Diagnostics.Testing 10.11.0 (11.0.0 rejected: wrong wave); project reference | PASS | Restore without warnings |
| M3-10 | `dotnet test ... --output <scratch>` (app still running) | PASS | 3/3; scratch output (contained `appsettings.Local.json`) deleted |
| M3-11 | Umbraco schema files copied into `tests/` | FINDING | `Umbraco.Cms.Targets` has no opt-out; root `.gitignore` now ignores them |
| M3-12 | Owner restart (MT-21) | PASS | New PID 28456; DLL contains `ContentPublishedLoggingHandler` |
| M3-13 | Endpoints after restart | PASS | Home, Plants, Tomato items 200 JSON; children query 200; Mint 404; Delivery Swagger 200 |
| M3-14 | JSON shapes | PASS | `contentType`, `name`, dates, `route{path,startItem}`, `id` (GUID), `properties`, `cultures`; media picker → array; rich text → `{markup, blocks}`; empty → `null` |
| M3-15 | Children query immediately after restart | FINDING | `total: 0`; became `total: 3` at 20:33:30 (index auto-built) |
| M3-16 | Query features | PASS | `fetch=children`, `filter=contentType`, `sort`, `skip`/`take`, `fetch=children:/`, item by GUID, `fields` (2,344 → 1,176 bytes) |
| M3-17 | Security probes | PASS | Mint 404; `Preview: true` without/forged key 401; media 401; unknown 404 |
| M3-18 | `ApiAccessService.cs:11-17` | PASS | Access formulas documented in 03 §6 |
| M3-19 | Swagger document | PASS | 8 GET endpoints, all v2; query and header parameters listed |
| M3-20 | `Test-DeliveryApi.ps1` (PS 7) | PASS | 14/14, exit 0 (after fixing a `$total:` parse error and an array-return bug during development) |
| M3-21 | Same under Windows PowerShell 5.1 | PASS | 14/14 |
| M3-22 | `-BaseUrl http://localhost:41388 -UnpublishedRoute ''` | PASS | 13/13 |
| M3-23 | Negative: unreachable; wrong expectation (scratch copy) | PASS | Exit 1 with "Site reachable" / "scientificName is 'Solanum lycopersicum'" |
| M3-24 | `dotnet build FunkyFreshFarm.slnx`; `dotnet test FunkyFreshFarm.slnx --no-build`; `Test-Site.ps1` | PASS | 0 warnings, 0 errors; 3/3; 10/10 |

## End-to-end trace (owner + verification)

| # | Stage | Result | Evidence |
|---|---|---|---|
| M3-25 | T1: Save Zinnia only (MT-22) | PASS | 0 handler entries; API 2 lines; Razor 1 `<br />`; snapshot: draft v17 3 lines ("Sow seeds"), published v14 2 lines; `edited=1`; draft cache row only |
| M3-26 | T2: Save and publish (MT-23) | PASS | One handler entry 20:42:04.581, structured `ContentTypeAlias=plantPage`, `ContentName=Zinnia`, `ContentId=1073`, `ContentKey=41af6409-…` |
| M3-27 | Request correlation | FINDING | Same `RequestPath` `/umbraco/management/api/v1/document/{key}/update-and-publish`, `ActionName` `UpdateAndPublishDocumentController.Update`, `ThreadId=38`, `HttpRequestNumber=6` as `ContentService` "has been published" (20:42:04.449). Umbraco's `UserNotificationsHandler` ran first. Prediction of `PublishDocumentController` corrected |
| M3-28 | API and Razor after publish | PASS | Item and query: 3 lines, `updateDate` 02:42:04Z; Razor: 2 `<br />` |
| M3-29 | Snapshot after publish | PASS | v17 published, new current v23, `edited=0`; published cache row `rv` 1→2 |
| M3-30 | Smoke tests after trace | PASS | Site 10/10; Delivery API 14/14 |
| M3-31 | Owner runs `Test-DeliveryApi.ps1` (MT-24) | NOT RUN | Pending owner |
| M3-32 | Swagger / Postman inspection (MT-25, optional) | NOT RUN | Pending owner |
| M3-33 | Debugger breakpoint in handler (MT-26, optional) | NOT RUN | Pending owner |

## Known issues (Milestone 3)

| Issue | Impact | Status / workaround |
|---|---|---|
| All published content is publicly listable via the API | No private-by-obscurity pages | By design; use disallowed types, `PublicAccess: false` + key, or member auth when needed |
| Query endpoint empty for ~1 minute after startup | Clients/tests may see `total: 0` | Wait, or rebuild in Examine Management; the script reports it explicitly |
| API returns raw values (no Razor fallbacks) | Clients must implement presentation logic | Documented (03 §2) |
| Delivery API answers over HTTP | No transport enforcement locally | Production should redirect/terminate HTTP |
| Misconfigured API returns a stack trace in Development | Information disclosure in dev only | Not applicable in Production |
| Handler exceptions surface after commit | Editor may see an error for a successful publish | Handler kept trivial; documented (03 §9) |
| Schema files copied into `tests/` | Noise | Gitignored |
| Owner's `assets/images/` | Untracked | Not committed pending the owner's decision |