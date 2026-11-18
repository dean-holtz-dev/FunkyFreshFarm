# Manual Test Checklist

Checks that need a person: browser interaction, logins, and visual confirmation. Automated
checks are recorded separately in [verification-log.md](verification-log.md). An item is ticked
only after the owner confirms it.

- [Milestone 1 — Installation](#milestone-1--installation) (MT-01 to MT-09)
- [Milestone 2 — Content model and rendering](#milestone-2--content-model-and-rendering) (MT-10 to MT-20)
- [Milestone 3 — Delivery API and extensibility](#milestone-3--delivery-api-and-extensibility) (MT-21 to MT-26)
- [Milestone 5 — Visual identity](#milestone-5--visual-identity) (MT-27 to MT-32)

# Milestone 1 — Installation

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

---

# Milestone 2 — Content model and rendering

Detailed procedures for MT-10 to MT-14 are in
[02-content-model.md §5](02-content-model.md#5-backoffice-recreation-instructions); MT-15 to MT-20
were given step by step during the session and are summarised below. For every item, Claude Code
also ran an independent read-only verification (database snapshot via SQLite's online backup API,
public HTTP requests, generated models, logs). Results are in the verification log.

## Summary

| ID | Test | Outcome | Date |
|---|---|---|---|
| MT-10 | Sun Exposure Data Type created (Radio Button List: Full Sun, Partial Sun, Shade) | Pass | 2026-11-15 |
| MT-11 | Four Document Types with templates, properties, and structure rules (Checkpoint C) | Pass after one fix | 2026-11-15 |
| MT-12 | Placeholder images uploaded to Media → Plants | Pass | 2026-11-15 |
| MT-13 | Content tree created and published; images on Tomato and Basil only (Checkpoint E) | Pass | 2026-11-15 |
| MT-14 | Visual check of all pages, phone width, keyboard focus (Phase 3) | Pass | 2026-11-15 |
| MT-15 | Stage A: Save without publishing leaves the public site unchanged | Pass | 2026-11-15 |
| MT-16 | Stage B: Save and publish makes the change public immediately | Pass | 2026-11-15 |
| MT-17 | Stage C: a new plant (Mint) appears in the directory | Pass | 2026-11-15 |
| MT-18 | Stage D: unpublishing Mint removes it publicly but keeps it in the tree | Pass | 2026-11-15 |
| MT-19 | Stage E: state persists across a Ctrl+C restart | Pass | 2026-11-15 |
| MT-20 | Run `scripts/Test-Site.ps1` in your own terminal | Pass | 2026-11-15 |

## MT-10 to MT-13 — Backoffice configuration and content

**Expected:** as in 02-content-model.md §3–§6.

- [x] MT-10 Pass
- [x] MT-11 Pass. **Notes:** at Checkpoint C, `heroHeadline` was not mandatory. The owner fixed it
  and a second snapshot confirmed `mandatory = 1`. Property display names were entered in Title Case
  ("Hero Headline"); the docs were updated to match. Template aliases are PascalCase (`HomePage`).
- [x] MT-12 Pass. **Notes:** media items are named `Heirloom Tomato`, `Basil`, `Zinnia` (no
  "placeholder" suffix); uploaded files are byte-identical to `assets/placeholder-images/`.
- [x] MT-13 Pass. **Notes:** Growing Guide body contains the typo "planing" (left as entered; corrected to "planting" by the owner on 2026-11-17).
  Headings were created without a toolbar heading button (there is none in 17.8.1).

## MT-14 — Visual check of the rendered site

**Steps:** open every page after Ctrl+F5; check the header, navigation, and current-section
underline; three plant cards with two images and a "No image yet" placeholder; plant detail pages;
the guide's headings, list, and bold text; phone width via F12 → Ctrl+Shift+M; Tab shows
"Skip to content" and focus outlines.

- [x] Pass. **Notes:** confirmed by the owner ("Phase 3 visual check passed").

## MT-15 to MT-19 — Publishing behaviour

| ID | Steps | Expected | Owner observed |
|---|---|---|---|
| MT-15 | Change Home's Hero Headline to `Funky flavors, fresh from our fields`; **Save** only; reload the public page | Status **Published (pending changes)**; public headline unchanged | Published (pending changes) |
| MT-16 | **Save and publish** Home; reload | Status **Published**; new headline public immediately | Published; History showed 4 entries |
| MT-17 | Create Mint (Plant Page, Partial Sun, no image) under Plants; **Save and publish** | Directory shows 4 cards; `/plants/mint/` renders | Done |
| MT-18 | Hover Mint → **…** → **Unpublish** | Status **Unpublished**; Mint grey in tree; directory back to 3; `/plants/mint/` 404 | Unpublished; grey in tree |
| MT-19 | Ctrl+C, list `umbraco\Data` files, restart | Clean shutdown; new headline kept; Mint still unpublished | One database file after shutdown |

- [x] MT-15 Pass
- [x] MT-16 Pass
- [x] MT-17 Pass
- [x] MT-18 Pass
- [x] MT-19 Pass

## MT-20 — Run the site smoke test yourself

**Purpose:** confirm the test runs from your own shell. Claude Code has run it, but not in your terminal.

1. Make sure the app is running in another window.
2. In a PowerShell window at `C:\dev\FunkyFreshFarm`, run:

   ```powershell
   pwsh ./scripts/Test-Site.ps1
   ```

   Or, in Windows PowerShell 5.1:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\Test-Site.ps1
   ```

**Expected:** ten `[PASS]` lines and `Passed: 10  Failed: 0  Exit code: 0`.

- [x] Pass
- [ ] Fail

**Notes:** confirmed by the owner on 2026-11-15: `Passed: 10  Failed: 0  Exit code: 0`.

---

# Milestone 3 — Delivery API and extensibility

Procedures were given step by step during the session; details and evidence are in
[03-api-and-extensions.md](03-api-and-extensions.md) §10 and the verification log.

## Summary

| ID | Test | Outcome | Date |
|---|---|---|---|
| MT-21 | Restart with `AddDeliveryApi()`, the new configuration, and the handler (dotnet run rebuilds) | Pass | 2026-11-15 |
| MT-22 | Stage T1: edit Zinnia's Description, **Save** only; no publish log, API and Razor unchanged | Pass | 2026-11-15 |
| MT-23 | Stage T2: **Save and publish**; handler log line appears; API and Razor show the change | Pass | 2026-11-15 |
| MT-24 | Run `scripts/Test-DeliveryApi.ps1` in your own terminal | Pass | 2026-11-15 |
| MT-25 | Inspect a Delivery API request in Swagger UI or Postman (optional) | Skipped (owner decision) | 2026-11-15 |
| MT-26 | Hit a breakpoint in `ContentPublishedLoggingHandler.Handle` with an attached debugger (optional) | Skipped (owner decision) | 2026-11-15 |

## MT-21 to MT-23 — Restart and end-to-end trace

| ID | Steps | Expected | Owner observed |
|---|---|---|---|
| MT-21 | Ctrl+C; `dotnet run --project src/FunkyFreshFarm.UmbracoLab --launch-profile Umbraco.Web.UI`; open the home page once | Builds, starts without errors; home page unchanged | "Restart done" |
| MT-22 | In Zinnia's Description add the line `Sow seeds directly in warm soil after the last frost.`; **Save** | Published (pending changes); no `Published plantPage Zinnia` console line; API and page show 2 lines | "Stage T1 done" |
| MT-23 | **Save and publish** Zinnia | One console line `Published plantPage Zinnia (id 1073, key …)`; API JSON and page show 3 lines | `[20:42:04 INF] Published plantPage Zinnia (id 1073, key 41af6409-1759-4c16-bffb-23078a1d57ea)` |

- [x] MT-21 Pass
- [x] MT-22 Pass
- [x] MT-23 Pass

## MT-24 — Run the Delivery API test yourself

1. With the app running, in a PowerShell window at `C:\dev\FunkyFreshFarm`, run:

   ```powershell
   pwsh ./scripts/Test-DeliveryApi.ps1
   ```

   Or, in Windows PowerShell 5.1:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\Test-DeliveryApi.ps1
   ```

**Expected:** fourteen `[PASS]` lines and `Passed: 14  Failed: 0  Exit code: 0`. If the
"Directory children query" check reports `total is 0`, wait a minute after the app's first request and rerun.

- [x] Pass
- [ ] Fail

**Notes:** confirmed by the owner on 2026-11-15: `Passed: 14  Failed: 0  Exit code: 0`.

## MT-25 — Inspect a request in Swagger UI or Postman (optional)

1. Open `https://localhost:44370/umbraco/swagger` and select the **Umbraco Delivery API** definition.
2. Expand `GET /umbraco/delivery/api/v2/content/item/{path}`, **Try it out**, enter `plants/zinnia`, **Execute**.
3. Or in Postman: GET `https://localhost:44370/umbraco/delivery/api/v2/content/item/plants/zinnia/`
   (use `http://localhost:41388/...` if Postman rejects the certificate); then add header `Preview: true`.

**Expected:** 200 with Zinnia's JSON (three description lines); with `Preview: true`, 401.

- [ ] Pass
- [ ] Fail

**Notes:** skipped by the owner's decision on 2026-11-15 (optional; time constraints). Not a failure.

## MT-26 — Breakpoint in the notification handler (optional)

1. With the app running, attach the C# debugger (VS Code + C# Dev Kit, or Visual Studio 2026) to the
   `FunkyFreshFarm.UmbracoLab` process.
2. Set a breakpoint in `ContentPublishedLoggingHandler.Handle`.
3. In the backoffice, **Save and publish** any plant.

**Expected:** execution stops in `Handle`; the call stack includes the scope disposal and event
aggregator frames. Continue, and the log line appears.

- [ ] Pass
- [ ] Fail

**Notes:** skipped by the owner's decision on 2026-11-15 (optional; time constraints). Not a failure.

---

# Milestone 5 — Visual identity

Milestone 4 had no manual tests (documentation and read-only investigation only).

Claude Code verified every page at 375, 768 and 1440 px through headless Edge (DevTools Protocol
device emulation: no horizontal overflow, no broken images, correct hero source per width), before
and after the owner's content steps. That is not visual approval; MT-31 and MT-32 are, and the owner
gave it on 2026-11-17.

**All six Milestone 5 checks passed.** The owner confirmed on 2026-11-17: "Everything is fantastic."
Claude's read-only follow-up verification is recorded in [verification-log.md](verification-log.md)
(M5-21 to M5-30).

## Summary

| ID | Test | Outcome | Date |
|---|---|---|---|
| MT-27 | Upload the three botanical illustrations to Media → Plants | Pass | 2026-11-16 |
| MT-28 | Assign them as each plant's Plant Image; Save and publish | Pass | 2026-11-16 |
| MT-29 | Add `storyHeading` / `storyText` to Home Page; fill and publish | Pass | 2026-11-17 |
| MT-30 | Run all four test scripts in your own terminal | Pass | 2026-11-17 |
| MT-31 | Visual review at 375, 768, 1440 px | Pass | 2026-11-17 |
| MT-32 | Keyboard and focus review | Pass | 2026-11-17 |

## MT-27 to MT-29 — Content steps

Follow the procedures in [05-assets.md §5](05-assets.md#5-owner-procedures-manual) (purpose,
navigation, exact values, expected results, troubleshooting).

- [x] MT-27 Pass   - [ ] Fail   **Notes:** three illustrations uploaded to Media → Plants.
- [x] MT-28 Pass   - [ ] Fail   **Notes:** assigned and published; the handler logged
  `Published plantPage` for Heirloom Tomato, Basil, and Zinnia at 12:15 local on 2026-11-16.
- [x] MT-29 Pass   - [ ] Fail   **Notes:** both properties added (generated model has `StoryHeading`
  and `StoryText`); Home published at 18:56 local on 2026-11-17; the story panel renders
  "Grown by hand, shared with joy".

Dates are taken from the publish log entries. The owner confirmed all three on 2026-11-17.

## MT-30 — Test scripts

With the app running, in a PowerShell window at `C:\dev\FunkyFreshFarm`:

```powershell
pwsh ./scripts/Test-BrandAssets.ps1
```

```powershell
pwsh ./scripts/Test-Site.ps1
```

```powershell
pwsh ./scripts/Test-DeliveryApi.ps1
```

```powershell
dotnet test FunkyFreshFarm.slnx --no-build
```

**Expected:** Brand 37/37 (the three "Botanical" checks pass after MT-28), Site 10/10, Delivery API
14/14, unit tests 3/3. The site test should then report "3 cards: 3 image(s), 0 placeholder(s)".

- [x] Pass
- [ ] Fail

**Notes:** confirmed by the owner on 2026-11-17. Claude's independent rerun the same day matched it:
Brand 37/37, Site 10/10 ("3 cards: 3 image(s), 0 placeholder(s)"), Delivery API 14/14, unit tests 3/3.

## MT-31 — Visual review at three widths

In Edge or Chrome: open the page, press **F12**, then **Ctrl+Shift+M** (device toolbar), and set the
width to 375, then 768, then 1440 (or use **Responsive** and type the width). Press **Ctrl+F5** once
first so the new CSS and fonts load.

| Page | Check |
|---|---|
| `/` | Header: emblem + "Funky Fresh Farm" in the serif font; Home pill highlighted. Hero: below 1024 px the artwork is fully visible and the text panel overlaps its bottom; at 1440 the panel sits over the cream sky on the left. Headline readable, "Explore Our Plants" button. Featured plants: three cards with botanical illustrations, square and uncropped, radish sticker beside the heading. Story panel (after MT-29). Footer: dark purple with stripe bands |
| `/plants/` | "Plant directory" label, "Our Plants", three square illustrated cards (1, 2, or 3 columns by width) |
| `/plants/heirloom-tomato/` | Two columns from 768 px: framed illustration left, "Plant profile", name, italic Latin name, description, Mint "Sun exposure" panel |
| `/plants/basil/` | Heading "Basil" (Name fallback); illustration |
| `/growing-guide/` | Centred title, life-cycle illustration, comfortable reading column, Coral bullet markers |
| `/any-missing-page/` | Lost-radish illustration, "This path leads nowhere", Marigold button home; status 404 |

At every width: no sideways scrolling, no distorted or stretched illustrations, no text over busy artwork.

- [x] Pass
- [ ] Fail

**Notes:** confirmed by the owner on 2026-11-17: "Everything is fantastic."

## MT-32 — Keyboard and focus

1. Reload `/` and press **Tab**: "Skip to content" appears first; **Enter** moves to the main content.
2. Keep pressing **Tab** through the header, hero button, cards, and footer: every focused element shows a
   clear dark outline (gold outline in the footer).
3. Open a plant card with **Enter**.

- [x] Pass
- [ ] Fail

**Notes:** confirmed by the owner on 2026-11-17.