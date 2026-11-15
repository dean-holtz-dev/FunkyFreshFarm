# Manual Test Checklist — Milestone 1

Checks that need a person: browser interaction, logins, and visual confirmation. Automated
checks are recorded separately in [verification-log.md](verification-log.md). An item is ticked
only after the owner confirms it.

Legend: `[x] Pass` · `[ ] Pass` (not yet confirmed) · record failures in **Notes**.

## Summary

| ID | Test | Outcome | Date |
|---|---|---|---|
| MT-01 | HTTPS development certificate trusted | Pass | 2026-11-15 |
| MT-02 | Interactive installer completes with SQLite | Pass | 2026-11-15 |
| MT-03 | Administrator account created manually | Pass | 2026-11-15 |
| MT-04 | Backoffice login over HTTP is rejected (negative test) | Pass | 2026-11-15 |
| MT-05 | Backoffice login over HTTPS | Pass | 2026-11-15 |
| MT-06 | System information reports the expected stack | Pass | 2026-11-15 |
| MT-07 | Backoffice still works after an application restart | Pass | 2026-11-15 |
| MT-08 | Graceful Ctrl+C stop and restart in your own terminal | Pass | 2026-11-15 |
| MT-09 | Front-end placeholder page renders | Pass | 2026-11-15 |

---

## MT-01 — HTTPS development certificate trusted

**Steps**

1. Run `dotnet dev-certs https --trust` and accept the Windows confirmation dialog.

**Expected:** the dialog completes; `dotnet dev-certs https --check --trust` exits 0; browsers open
`https://localhost:44370` without a certificate warning.

- [x] Pass
- [ ] Fail

**Notes:** owner chose to trust the certificate (2026-11-15). Automated cross-check: exit code 0,
thumbprint `5DE1BA19…0AD2`, valid to 2027-09-12.

## MT-02 — Interactive installer completes with SQLite

**Steps**

1. With no connection string configured, start the app and open the backoffice URL.
2. Complete the user step, choose **SQLite** at the database step, and select **Install**.

**Expected:** installation finishes without an error page; `umbraco/Data/Umbraco.sqlite.db` (+ `-wal`, `-shm`) exists.

- [x] Pass
- [ ] Fail

**Notes:** completed 2026-11-15 at 14:23 local time. The first attempt used
`http://localhost:41388`; the install succeeded, but the login that follows failed (see MT-04).
The log contains a harmless newsletter-subscription `TaskCanceledException`.

## MT-03 — Administrator account created manually

**Steps**

1. In the installer's user step, enter a name, an email, and a password of at least 10 characters.

**Expected:** credentials exist only in the database (hashed); no configuration file contains them.

- [x] Pass
- [ ] Fail

**Notes:** owner created the account. System information shows `User is admin: Yes`. Automated
checks: no configuration file under `src/` contains `UnattendedUserName`, `UnattendedUserEmail`,
`UnattendedUserPassword`, `InstallUnattended`, or a `Password` key; a copy of the database has exactly 1 user.

## MT-04 — Backoffice login over HTTP is rejected (negative test)

**Steps**

1. Open `http://localhost:41388/umbraco` and attempt to log in.

**Expected:** OpenIddict rejects the request with `error:invalid_request`, error `ID2083`
("This server only accepts HTTPS requests"). This is by design: `UseHttps` defaults to `true`.

- [x] Pass (behaved as expected)
- [ ] Fail

**Notes:** observed by the owner on 2026-11-15 right after installation.

## MT-05 — Backoffice login over HTTPS

**Steps**

1. Open `https://localhost:44370/umbraco`.
2. Log in with the administrator account.

**Expected:** the backoffice loads with the Content, Media, Settings, Packages, Users, Members, and
Translation sections.

- [x] Pass
- [ ] Fail

**Notes:** confirmed 2026-11-15; all seven sections visible.

## MT-06 — System information reports the expected stack

**Steps**

1. In the backoffice, open the Umbraco logo menu → **System information**.

**Expected:** Umbraco 17.8.1, .NET 10.0.x, SQLite, Kestrel.

- [x] Pass
- [ ] Fail

**Notes:** reported 2026-11-15: Umbraco Version 17.8.1 (build `17.8.1+89c87c2`), Server Framework
.NET 10.0.15, Kestrel, Database Provider "System.Data.SQLite" (display label; the actual provider
is `Microsoft.Data.Sqlite`), Models Builder `InMemoryAuto`, Runtime Mode `BackofficeDevelopment`,
Debug `True`, client 17.8.1, UI Library 2.1.1, Server Role `Single`.

## MT-07 — Backoffice still works after an application restart

The application was stopped and restarted after MT-05 (most recently at 14:37 local time).
Automated checks after the restart: runtime level `Run - Run`, `serverStatus: Run`, install API
returns 428.

**Steps**

1. Open (or refresh) `https://localhost:44370/umbraco`.
2. If prompted, log in again.

**Expected:** the login screen or backoffice appears, **not** the installer; after login the
sections from MT-05 are present.

- [x] Pass
- [ ] Fail

**Notes:** confirmed by the owner on 2026-11-15.

## MT-08 — Graceful Ctrl+C stop and restart in your own terminal

Claude Code's verification stopped the app by terminating the process. This test covers the
normal developer workflow.

Commands work in Windows PowerShell 5.1 and PowerShell 7. Copy each block exactly.

**Steps**

1. Stop any instance that is already running (for example one started by Claude Code). Check:

   ```powershell
   Get-Process -Name FunkyFreshFarm.UmbracoLab -ErrorAction SilentlyContinue
   ```

   If that lists a process, stop it, then re-run the check; it should print nothing:

   ```powershell
   Get-Process -Name FunkyFreshFarm.UmbracoLab -ErrorAction SilentlyContinue | Stop-Process
   ```

2. Go to the repository root and start the app in the foreground:

   ```powershell
   Set-Location C:\dev\FunkyFreshFarm
   dotnet run --project src/FunkyFreshFarm.UmbracoLab --launch-profile Umbraco.Web.UI
   ```

3. Wait for `Application started. Press Ctrl+C to shut down.` Then click in that terminal
   window and press **Ctrl+C** once.
4. Start it again in the same terminal (press the Up arrow, then Enter), wait for
   `Application started`, and open `https://localhost:44370/umbraco`.

**Expected:** step 3 logs `Application is shutting down...` and returns to the `PS C:\dev\FunkyFreshFarm>`
prompt without errors or stack traces. Step 4 shows the login screen or backoffice, not the installer.

- [x] Pass
- [ ] Fail

**Notes:** confirmed by the owner on 2026-11-15 in Windows PowerShell 5.1: all steps succeeded.
The first attempt at step 1 failed only because a trailing period was copied with the command
(`Stop-Process.`); the steps above now use code blocks to avoid that.

## MT-09 — Front-end placeholder page renders

**Steps**

1. Open `https://localhost:44370/`.

**Expected:** Umbraco's "Welcome to your Umbraco installation" / "No Published Content" page
(there is no content yet in Milestone 1).

- [x] Pass
- [ ] Fail

**Notes:** confirmed by the owner on 2026-11-15. Automated check: page title is `Umbraco: No Published Content`.
