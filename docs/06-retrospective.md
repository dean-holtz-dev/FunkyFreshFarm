# 06 — Retrospective: How Funky Fresh Farm Was Built

A look back at the whole lab: what was built, how the work was split between the owner and
Claude Code, what turned out to be easy, where the friction was, and the numbers behind it. The
detailed evidence lives in the other documents (links in §9). This one tells the story.

## 1. The short version

Starting from an empty folder, five milestones produced a branded, editor-managed website for a
fictional farm, with a public JSON API, on Umbraco CMS 17.8.1 LTS, .NET 10, and SQLite.

- **It was fast.** The code for all five milestones was committed on a single day, 2026-11-15:
  Milestone 1 at 14:42 and Milestone 5 at 21:38 local time. The owner's last steps (uploading the
  botanical prints and writing the farm story) followed on 2026-11-16 and 2026-11-17. They needed no
  code change, no build, and no restart.
- **It took very little code.** The site is about 1,200 hand-written lines: 369 lines of Razor
  across nine views, 792 lines of CSS, and 41 lines of C# for one notification handler.
  - The whole Content Delivery API took one line of C# (`.AddDeliveryApi()`) and three lines of JSON.
  - The branded 404 page took one line of JSON and a 19-line view.
  - Over five milestones, `Program.cs` changed by exactly one line.
- **Most of the work was configuration and backoffice clicks.** The content model (one Data Type,
  four Document Types, thirteen properties) and all six pages were built by the owner in the
  backoffice, without writing C#.
- **It was tested throughout.** Four test scripts (75 checks) and 3 unit tests ran after every
  milestone. Of 32 manual checks, 30 passed and the 2 optional ones were skipped by choice.
- **The friction was in setup, not in Umbraco's programming model.** It came from things like
  HTTPS for the backoffice, the installer writing a secret into tracked configuration, SQLite's WAL
  file, and the running app locking `bin/`. Every one is documented behaviour with a simple fix
  (§5). None needed a change to Umbraco or a workaround for a bug in it.

The owner's verdict at the end: *"Everything is fantastic."*

## 2. The finished site

| Page | URL | Editors control (backoffice) | Code controls (Git) |
|---|---|---|---|
| Home | `/` | Hero headline, intro, farm-story heading and text | Art-directed hero (portrait art on phones, wide on desktop), featured plants (the first three from the directory), story illustration |
| Plant directory | `/plants/` | Title, intro, which plants exist and their order | Card grid (1, 2, or 3 columns by width) |
| Plant profiles | `/plants/heirloom-tomato/`, `/plants/basil/`, `/plants/zinnia/` | Names, Latin name, description, sun exposure, botanical illustration | Two-column profile; signed, square WebP crops at four sizes |
| Growing guide | `/growing-guide/` | Rich-text body | Life-cycle illustration, reading-width layout |
| Not found | any unknown URL | — | Lost-radish page with a real 404 status |
| Content Delivery API | `/umbraco/delivery/api/v2/` | Everything that is published | Public and read-only; drafts can never be served |

Every page shares a branded header (emblem, Fraunces wordmark, navigation built from the content
tree) and footer. Self-hosted, OFL-licensed fonts and a social-sharing card complete the brand.
Every page was checked at 375, 768, and 1440 px: no sideways scrolling, no broken images, and
keyboard focus visible everywhere.

## 3. How it came together

| Milestone | Goal | The owner did | Claude Code did | Commit |
|---|---|---|---|---|
| 1. Foundation | Umbraco 17.8.1 on .NET 10 with SQLite | Trusted the dev certificate, ran the installer, created the administrator, tested HTTP versus HTTPS login, restarts, and Ctrl+C shutdown (MT-01 to MT-09) | Prerequisite checks, project from `Umbraco.Templates`, version pinning, moved the secret out of tracked config, Git hygiene, docs | `2a9f474` (14:42) |
| 2. Content and Razor | Model the content and render it | Built the Data Type, four Document Types, media, and content tree in the backoffice. Exercised Save versus Save and publish, unpublish, and persistence across a restart (MT-10 to MT-20) | Designed the model, wrote the step-by-step procedures, Razor views, layout, navigation, CSS, and the site smoke test | `afe3321` (20:13) |
| 3. API and extensibility | Headless delivery and a C# extension point | Restarted; traced save-only versus publish through the log, the API, and the page; ran the API test (MT-21 to MT-24) | Enabled the Delivery API; publish notification handler, composer, and unit tests; API test script | `f648a94` (20:48) |
| 4. Source and review | Understand how it really works | Nothing manual | Traced boot, routing, and publishing through Umbraco's source at `release-17.8.1`; operational review; hot-backup tool and runbook | `e4b329a` (21:11) |
| 5. Visual identity | Brand the site with the owner's artwork | Uploaded and assigned three prints, added two properties and the farm story, ran the tests, and did the visual and keyboard reviews (MT-27 to MT-32) | Design system, fonts, asset pipeline, templates, branded 404, brand test, docs | `4eb42bf` (21:38); originals `090cd26` |

### Milestone 1: installation and foundation

`dotnet new umbraco` followed by `dotnet run` gives a working CMS with an installer in minutes.
The rough edges were all about setup:

- **Version pinning.** The template's `--release LTS` option writes a floating `17.*` package
  version, so `--release Latest` was used to pin `17.8.1` exactly.
- **SQLite boot failure.** A preconfigured SQLite connection string with no database file boots as
  `BootFailed` unless an unattended install is configured. The source showed why, and the attended
  installer was used instead.
- **A secret in tracked config.** The installer wrote the image-signing `HMACSecretKey` into the
  tracked `appsettings.json`. It was moved to the untracked `appsettings.Local.json`, and the
  prerequisite script now fails if it ever comes back.
- **HTTPS-only login.** The first login over HTTP failed with OpenIddict error ID2083: the
  backoffice requires HTTPS by default.
- **The WAL file.** In WAL mode the `.db` file alone can look empty, so backups must include all
  three files.

### Milestone 2: content modelling and Razor

The big conceptual shift for a .NET developer is that **the schema lives in the database**. It is
defined by clicking in the backoffice, and Models Builder turns it into C# classes at runtime. Once
that is clear, templates are ordinary Razor with a strongly typed `Model`.

- **The owner built the whole model** from the written procedures. The only correction was at
  Checkpoint C, where Hero Headline was made mandatory.
- **The publishing lifecycle was demonstrated on the live site:**
  - **Save** leaves the public page unchanged ("Published (pending changes)").
  - **Save and publish** makes the change public immediately.
  - A new plant appears in the directory.
  - **Unpublish** removes it publicly while keeping it in the tree.
  - All of this survives a restart.
- **Catch:** views are not compiled at build time (InMemoryAuto with `RazorCompileOnBuild=false`),
  so an alias typo only shows up when a page is requested. `scripts/Test-Site.ps1` exists to catch that.

### Milestone 3: Delivery API and .NET extensibility

- **A full JSON API cost one line of code.** `.AddDeliveryApi()` plus `DeliveryApi:Enabled`
  produced a complete, public, read-only content API. With no API key configured, drafts can never
  leak.
- **The C# extension point was 41 lines.** A `ContentPublishedNotification` handler registered by a
  composer, with three unit tests. The owner watched the log line appear on publish but not on save.
- **Surprises, all documented:**
  - The query endpoint returns `total: 0` for about a minute after startup while its search index builds.
  - "-ed" notifications run after the database commit, on the editor's request thread.
  - A running app locks `bin/`, so builds need `--no-build` or a scratch output folder.

### Milestone 4: source exploration and engineering review

Boot, routing, and the publish pipeline were traced through the real source at tag
`release-17.8.1` (commit `89c87c2`, the same build that runs locally), all the way to the cache
refresh. The milestone also produced an operational review and a tested hot-backup tool.

It paid off in Milestone 5. When a question came up (does `format=webp` work, and does the 404
setting reload live?), the answer came from the source in minutes instead of guesswork.

### Milestone 5: visual identity ("Farmstand Funk")

The code was written in one evening session, and the owner did the content steps over the next two days.

- **Two homes for images.** Brand artwork is static files in Git; the plant prints are editorial
  content in the Media Library, chosen with the existing Image Media Picker.
- **No framework.** One CSS file holds colour, type, and spacing tokens, with contrast checked
  against WCAG. The fonts are self-hosted with their OFL licences.
- **The owner's part was pure editor work:**
  - upload three images and pick them on three pages;
  - add two properties to the Home Page Document Type and fill them in.

  Nothing else was needed: no code, build, or restart. The templates had already been written to
  cope with a property that does not exist yet.
- **Bumps:**
  - Referencing ImageSharp directly triggers a licence warning, so the asset-build script uses
    System.Drawing.
  - Headless screenshots below about 500 px were distorted, so the visual checks switched to
    DevTools device emulation.
  - The first screenshot review found four layout issues, all fixed in the same session.

## 4. Why it was relatively easy

1. **Umbraco is an ASP.NET Core application.** `Program.cs`, dependency injection, options,
   middleware, Razor, logging, and xUnit all work as usual. Nothing in the hosting model was new.
2. **The CMS does the heavy lifting.** We wrote none of the following; it all came built in:
   - the editing UI
   - versions and publishing workflow
   - caching and URL routing
   - media storage and image processing
   - the search index and the JSON API
3. **Content modelling is configuration, not code.** Four page types were modelled without writing
   a line of C#, and Models Builder generated the typed classes the views use.
4. **SQLite and Kestrel keep the footprint tiny.** There is no database server, no IIS, and no
   Docker. One folder plus `dotnet run` is the whole environment.
5. **Images are a solved problem.** ImageSharp resizes, crops, converts to WebP, caches, and signs
   URLs (a tampered URL gets a 400). One 21-line partial view turns any picked image into a
   responsive `srcset`.
6. **Cross-cutting features are configuration.** The Delivery API and the branded 404 page were
   switched on in `appsettings.json` rather than built.
7. **Small, verified steps.** Every milestone ended with automated tests and owner checks, so
   problems were found while they were small. Nothing had to be redone.

## 5. Where the friction was

| Issue | Milestone | How it showed up | Resolution |
|---|---|---|---|
| Backoffice requires HTTPS | 1 | Login over HTTP failed with OpenIddict ID2083 | Use https://localhost:44370/umbraco |
| Installer writes a secret into tracked config | 1 | `HMACSecretKey` in `appsettings.json` | Moved to `appsettings.Local.json`; the prerequisite script guards it |
| Preconfigured SQLite connection string | 1 | `BootFailed / InstallMissingDatabase` | No preconfigured string; attended installer |
| SQLite WAL mode | 1 | The `.db` file alone can be nearly empty | Back up all three files, or use the hot-backup tool (Milestone 4) |
| Stopping an instance already running | 1 | The owner needed extra help before testing Ctrl+C (MT-08) | Procedure expanded with a check-and-stop step |
| Schema lives in the database, not Git | 2 | A fresh clone renders nothing | Recreation procedures and backups; uSync and `SourceCodeAuto` documented as options |
| Views compile at runtime | 2 | Alias typos only show up on request | `Test-Site.ps1` |
| No heading button in the default rich-text toolbar | 2 | Headings are awkward to add | `##` + space, or the source view |
| The running app locks `bin/` | 3 | `MSB3027` on build or test | `--no-build`, or build to a scratch folder |
| Delivery API index builds after startup | 3 | `total: 0` for about a minute | Wait; the test script says so explicitly |
| ImageSharp licence notice | 5 | Warning when referenced directly | System.Drawing for the asset-build script |
| Headless screenshots at phone width | 5 | Distorted layout below about 500 px | DevTools Protocol device emulation |

None of these is hard. Each cost minutes, and each is now written down in `CLAUDE.md` so it never
costs anything again.

## 6. By the numbers

| Measure | Value |
|---|---|
| Calendar span | 2026-11-15 to 2026-11-17 |
| Commits | 10 (5 milestones, 3 test-result records, the originals, and this completion record) |
| Hand-written Razor | 369 lines in 9 views (6 page and layout views, 3 partials) |
| CSS | 792 lines, one file, no framework or build step |
| C# in the web app | 41 lines (handler and composer) plus 1 line in `Program.cs` |
| Packages added to the web app after Milestone 1 | 0 |
| Content model | 1 Data Type, 4 Document Types, 13 properties, 6 published pages |
| Automated checks | 78: prerequisites 14 (with `-SkipNetwork`), site 10, Delivery API 14, brand assets 37, unit tests 3 |
| Manual checks | 32: 30 passed, 2 optional skipped |
| Artwork | 12 originals (32.6 MB) → 19 web derivatives (3.6 MB) + 3 Media Library prints; 3 font files (206 KB) |
| Documentation | About 4,000 lines across 11 Markdown files, more than the code, because this was a learning lab |

## 7. How we worked

- **Protocol: INSPECT → PLAN → IMPLEMENT → VERIFY → EXPLAIN → STOP.** One milestone at a time,
  stopping for approval before the next.
- **The owner did the backoffice work personally.** Every manual task came with a complete
  procedure: purpose, navigation, exact values, how to save, expected result, verification, and
  troubleshooting. Doing the clicks is how Umbraco's concepts stick.
- **Checkpoint discipline.** No manual step was assumed done. After each confirmation, Claude Code
  verified independently and read-only: HTTP responses, logs, generated models, and database
  snapshots taken with SQLite's backup API. The live database was never written to directly.
- **Safety rules held throughout.** No secrets, databases, logs, or uploaded media ever entered Git;
  the prerequisite script checked this before every commit.
- **Source over guesswork.** When behaviour surprised us, the answer came from Umbraco's source at
  the exact tag in use.

## 8. Lessons to carry into a production Umbraco codebase

- **Ask where the schema lives.** Document Types are database state. Find out how the team
  versions and deploys them (for example uSync, Umbraco Deploy, or code-first migrations) and which
  Models Builder mode it uses.
- **Know the two homes for images.** Design assets ship with the code. Editorial media ships with
  the database and the media folder, and the two must be backed up together.
- **Never hard-code `/media/` paths.** Use `GetCropUrl()` so URLs stay signed, sized, and cached.
- **Write templates that tolerate missing content.** Fallbacks to the node's Name, and
  `Value<T>("alias")` for properties that may not exist yet, let code ship before content.
- **"-ed" notifications run after the commit.** Keep handlers quick and safe; an exception reaches
  the editor even though the content is already published.
- **The Delivery API serves stored values.** Presentation fallbacks that live in Razor do not apply
  to API clients.
- **Check environment configuration first.** `UseHttps`, `ApplicationUrl`, the HMAC key, and the
  connection string differ per environment, and secrets belong outside tracked files.

## 9. Where to find the details

| Topic | Document |
|---|---|
| Installation, configuration, startup, troubleshooting | [01-installation.md](01-installation.md) |
| Content model, backoffice recreation, Razor, publishing | [02-content-model.md](02-content-model.md) |
| Delivery API, security, notification handler | [03-api-and-extensions.md](03-api-and-extensions.md) |
| Source-backed architecture, operations, backup runbook | [04-architecture.md](04-architecture.md) |
| Design system | [05-design-system.md](05-design-system.md) |
| Brand assets and their provenance | [05-assets.md](05-assets.md) |
| Every manual check and its outcome | [manual-test-checklist.md](manual-test-checklist.md) |
| Every command run and its evidence | [verification-log.md](verification-log.md) |
