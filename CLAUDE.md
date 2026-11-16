# CLAUDE.md — Funky Fresh Farm (Umbraco Lab)

Standing instructions for Claude Code sessions in this repository.

## Context

- Personal learning lab: a fictional farm website built on open-source Umbraco CMS.
- The owner is an experienced C#/.NET developer and engineering leader. Act as senior .NET
  architect and mentor: explain Umbraco-specific concepts, skip introductory .NET material.
- Work proceeds in milestones. Do only the current milestone, then stop.

## Technical baseline (do not change without explicit approval)

- Umbraco CMS **17.8.1** (LTS line), pinned exactly in `src/FunkyFreshFarm.UmbracoLab/Directory.Packages.props`
- .NET 10 (`net10.0`); SDK selected by `global.json` (10.0.100, `rollForward: latestFeature`)
- Windows, PowerShell 7, local Kestrel hosting, SQLite, Git
- Out of scope: Docker, Azure, Shopify, React, commerce plugins, commercial or paid extensions
- References:
  - Docs: https://docs.umbraco.com/umbraco-cms/17.latest/
  - Template: https://www.nuget.org/packages/Umbraco.Templates/17.8.1
  - Source: https://github.com/umbraco/Umbraco-CMS/tree/release-17.8.1

## Working protocol

**INSPECT → PLAN → IMPLEMENT → VERIFY → EXPLAIN → STOP.**

- Never assume a command succeeded. Read its output and exit code.
- Keep changes small and focused. Touch only this repository; `C:\dev` holds unrelated
  repositories that must not be modified.
- When behaviour is surprising, read the Umbraco source at the `release-17.8.1` tag rather than guessing.
- Separate automated verification from checks that need the owner's confirmation (browser,
  login, visual results). Never mark a manual check as passed without that confirmation.
- Record results in `docs/verification-log.md` and manual steps in `docs/manual-test-checklist.md`.
- Ask before system-level changes: SDK or tool installs, certificate trust, global Git/NuGet config.

## Human-in-the-loop instruction standard

The owner is an experienced .NET engineer who is new to Umbraco and learns by doing the backoffice
work personally. Whenever a milestone needs manual action from the owner:

**Give a complete, self-contained procedure in the response itself.** Keep the canonical docs
updated too, but never just point to a document section. For each manual task include:

1. **Purpose** — what we are doing and why it matters.
2. **Starting location** — exact application, page, or directory.
3. **Navigation** — specific buttons, menus, tabs, and controls.
4. **Input values** — exact names, aliases, configuration, and values.
5. **Saving** — exactly how to save or publish.
6. **Expected result** — what the owner should see afterwards.
7. **Verification** — how the owner can independently confirm it worked.
8. **Troubleshooting** — common problems and what evidence to collect.
9. **Stop point** — whether to continue or wait for Claude's verification.

Use tables for field definitions and numbered steps for UI procedures. Do not assume knowledge of
Umbraco navigation or terminology; explain the Umbraco concept the task illustrates where practical.
Use the UI labels of the version actually running (verify against the `release-17.8.1` source,
e.g. `src/Umbraco.Web.UI.Client/src/assets/lang/en.ts`) and state any remaining uncertainty
instead of guessing. Put every copyable value in its own code block or table cell, never followed
by sentence punctuation.

### Checkpoint discipline

At every manual checkpoint:

- Stop implementation work and state exactly what the owner needs to do.
- Give a concise checklist of expected results and the exact confirmation phrase wanted.
- Never assume a manual action was completed; do not advance until the owner confirms.
- After confirmation, verify independently and report the results. Verification must be
  read-only: files on disk, public HTTP responses, logs, generated models, and — for database
  state — a snapshot taken with SQLite's online backup API from a read-only connection. Never
  modify the database directly.

## Never commit

- SQLite files: `umbraco/Data/*.sqlite.db`, `*.sqlite.db-wal`, `*.sqlite.db-shm`
- `umbraco/Logs/`, `umbraco/Data/TEMP/`, `wwwroot/media/`, `backups/`
- `appsettings.Local.json` — holds the connection string and `Umbraco:CMS:Imaging:HMACSecretKey`
- Administrator credentials or any other secret

Run `pwsh ./scripts/Test-Prerequisites.ps1` after staging and before committing; the
"Git hygiene" and "Tracked secrets" checks must pass.

## Umbraco 17.8.1 behaviour learned in Milestone 1

- `dotnet new umbraco --release LTS` writes a floating `17.*` version; `--release Latest` pins `17.8.1`.
- A preconfigured SQLite connection string with no database file boots as
  `BootFailed / InstallMissingDatabase` unless an *unattended* install is configured. This project
  uses the attended installer instead, so `appsettings.Development.json` has no connection string.
- The installer writes the connection string to `appsettings.Local.json` (good) but writes
  `Imaging:HMACSecretKey` to `appsettings.json` (bad). Move it to `appsettings.Local.json`.
- `appsettings.Local.json` is loaded only in DEBUG builds (`#if DEBUG` in `Program.cs`), and it is
  added last, so it overrides environment variables and command-line arguments.
- `Umbraco:CMS:Global:UseHttps` defaults to `true`, so backoffice login over HTTP fails with
  OpenIddict error ID2083. Use https://localhost:44370/umbraco.
- SQLite runs in WAL mode; most data can live in the `-wal` file. Back up all three files with the app stopped.

## Umbraco 17.8.1 behaviour learned in Milestone 2

- The content model (Document Types, Data Types, template records, content, media) lives only in
  the database and `wwwroot/media/`. Views reference it by alias. See `docs/02-content-model.md` §8.
- Templates created with a Document Type get a **PascalCase** alias and file (`HomePage.cshtml`),
  while the Document Type alias stays camelCase (`homePage`).
- `InMemoryAuto` models exist only at runtime (`umbraco/Data/TEMP/InMemoryAuto/models.generated.cs`)
  and `RazorCompileOnBuild=false`, so `dotnet build` never compiles views. Use
  `scripts/Test-Site.ps1` to catch view errors.
- Template file **contents** are owned by Git; do not edit them in the backoffice.
- The default Richtext editor toolbar has no heading button. Rich-text HTML is not sanitised
  (`NoopHtmlSanitizer`) and renders unencoded.
- Save updates the draft in place; publish creates a new version and refreshes the published cache
  (`cmsContentNu`); unpublish deletes the published cache row. History is the audit log, not versions.
- The URL content finder is `ContentFinderByUrlNew` (`IDocumentUrlService`); `ContentFinderByUrl`
  is obsolete and unregistered.

## Umbraco 17.8.1 behaviour learned in Milestone 3

- The Delivery API needs **both** `.AddDeliveryApi()` in `Program.cs` (restart required) and
  `Umbraco:CMS:DeliveryApi:Enabled = true`. Only `/umbraco/delivery/api/v2/` is served.
- Item endpoints read the published cache; the query endpoint reads the Examine
  `DeliveryApiContentIndex`, which is built about one minute after the first request following
  startup. `{"total":0}` right after a restart means "index not built yet".
- No `ApiKey` is configured, so preview and drafts can never be delivered; failed access checks return
  401 (`ApiAccessService`). Media delivery is off (401). If an API key is ever added, it is a secret:
  keep it in `appsettings.Local.json`.
- The API returns stored values: Razor fallbacks (e.g. Name for empty `commonName`) do not apply.
- Backoffice **Save and publish** calls `PUT .../document/{key}/update-and-publish`
  (`UpdateAndPublishDocumentController`), not `PublishDocumentController`.
- "-ed" notification handlers run **after the database commit**, synchronously on the publishing
  request's thread; an exception surfaces to the editor although the content is already published.
- C# changes cannot be built into `bin/` while the app runs. To compile-check without stopping it,
  build or test with `--output` into the scratchpad, then delete that output: it contains a copy
  of `appsettings.Local.json`.
- `Umbraco.Cms.Targets` copies JSON schema files into every project that references Umbraco,
  including tests; the root `.gitignore` covers them.
- `Microsoft.Extensions.*` test helpers must stay on the 10.x line; Umbraco 17 constrains them
  to `(,10.0.32767]`.

## Milestone 4 notes (source exploration)

- Umbraco source of truth: tag `release-17.8.1` = commit `89c87c2f768418d877281d3dcaba9c0a7e806461`
  (matches the running build `17.8.1+89c87c2`). Read it from a shallow clone **outside** `C:\dev`
  (the scratchpad); on Windows the clone needs `git config --local core.longpaths true`.
  Never build or modify that clone. Link to it with commit permalinks.
- `dotnet test FunkyFreshFarm.slnx` rebuilds first and fails with MSB3027 while the app runs;
  use `--no-build` when the app is running.
- Hot database backups: `dotnet run scripts/backup-database.cs` (read-only on the live database,
  refuses to overwrite, integrity-checked). Restoring over the live database requires explicit
  owner approval.

## Milestone 5 notes (visual identity)

- Brand artwork has two homes: **Git** (`wwwroot/brand/`, generated by `scripts/Build-BrandAssets.ps1`
  from the owner's untracked originals in `assets/images/`) and the **Media Library** (plant
  illustrations, rendered through `Views/Partials/PlantIllustration.cshtml`). Never hard-code
  `/media/` paths. Never invent or substitute artwork; document missing assets.
- `Build-BrandAssets.ps1` uses System.Drawing on purpose: SixLabors.ImageSharp 3.2 warns that
  Release builds require a licence key when referenced directly.
- Razor and CSS changes are picked up live (runtime compilation); only C# changes need a restart.
- When a template needs a property the owner has not added yet, read it with
  `Model.Value<string>("alias")`; a generated property would not compile until it exists (InMemoryAuto).
- `Umbraco:CMS:Global:NotFoundViewPath` is read through `IOptionsMonitor`, so it applies without a
  restart. The 404 view has no content model; `_Layout.cshtml` must tolerate `Model == null`.
- Visual verification: drive headless Edge over the DevTools Protocol with device emulation;
  plain `--window-size` screenshots below about 500 px are distorted by the desktop minimum window width.
- PowerShell pitfalls hit in this lab: helper names `H`/`R` resolve to aliases (`h`, `r`);
  variables named `$IsWindows`/`$home` collide with automatic variables; `"$var:"` parses as a
  scope or drive; `pwsh -File` passes `1,2,3` as a single string.

## Common commands

```powershell
pwsh ./scripts/Test-Prerequisites.ps1          # environment + Git hygiene checks
dotnet build FunkyFreshFarm.slnx
dotnet run --project src/FunkyFreshFarm.UmbracoLab --launch-profile Umbraco.Web.UI
pwsh ./scripts/Test-Site.ps1                   # read-only smoke test of the running site
pwsh ./scripts/Test-DeliveryApi.ps1            # read-only Delivery API test of the running site
pwsh ./scripts/Test-BrandAssets.ps1            # brand files, serving, markup, CMS illustrations
dotnet test FunkyFreshFarm.slnx                # unit tests (add --no-build while the app runs)
```

Site: https://localhost:44370 · Backoffice: https://localhost:44370/umbraco

## Layout

- `src/FunkyFreshFarm.UmbracoLab/` — the Umbraco web application (`Views/`, `wwwroot/css/`, `Notifications/`)
- `tests/FunkyFreshFarm.UmbracoLab.Tests/` — xUnit tests (not under central package management; versions in the csproj)
- `scripts/` — PowerShell helpers (`Test-Prerequisites.ps1`, `Test-Site.ps1`, `Test-DeliveryApi.ps1`)
- `docs/` — installation, content model, API and extensions, architecture, manual test checklist, verification log
- `assets/placeholder-images/` — placeholder PNGs uploaded through the backoffice
- `assets/images/` — the owner's original artwork; untracked; read-only input; do not modify or commit without the owner's decision
- `src/FunkyFreshFarm.UmbracoLab/wwwroot/brand/`, `wwwroot/fonts/` — generated brand derivatives and self-hosted fonts (committed)
