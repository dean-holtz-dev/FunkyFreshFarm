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

## Common commands

```powershell
pwsh ./scripts/Test-Prerequisites.ps1          # environment + Git hygiene checks
dotnet build FunkyFreshFarm.slnx
dotnet run --project src/FunkyFreshFarm.UmbracoLab --launch-profile Umbraco.Web.UI
```

Site: https://localhost:44370 · Backoffice: https://localhost:44370/umbraco

## Layout

- `src/FunkyFreshFarm.UmbracoLab/` — the Umbraco web application
- `scripts/` — PowerShell helpers
- `docs/` — installation guide, manual test checklist, verification log
