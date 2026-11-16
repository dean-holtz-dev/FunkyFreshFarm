# 03 — Content Delivery API and .NET Extensibility

Milestone 3 exposes the farm's published content as JSON through Umbraco's built-in **Content
Delivery API**, adds one **notification handler** written in C#, and adds repeatable verification:
a PowerShell API test and a small xUnit project. Everything here was verified against Umbraco
**17.8.1** on 2026-11-15 (see [verification-log.md](verification-log.md)).

Contents:

1. [Configuration changes](#1-configuration-changes)
2. [Razor rendering versus headless delivery](#2-razor-rendering-versus-headless-delivery)
3. [Verified endpoints](#3-verified-endpoints)
4. [Example requests and responses](#4-example-requests-and-responses)
5. [Published-content availability and the Delivery API index](#5-published-content-availability-and-the-delivery-api-index)
6. [Security boundaries](#6-security-boundaries)
7. [Running the verification](#7-running-the-verification)
8. [Inspecting requests in a browser, Swagger UI, Postman, or curl](#8-inspecting-requests-in-a-browser-swagger-ui-postman-or-curl)
9. [Notification handler architecture](#9-notification-handler-architecture)
10. [End-to-end trace: edit, save, publish, log, API, Razor](#10-end-to-end-trace-edit-save-publish-log-api-razor)
11. [Troubleshooting](#11-troubleshooting)
12. [Files changed](#12-files-changed)

---

## 1. Configuration changes

The Delivery API ships inside the `Umbraco.Cms` package but is off until **two** things are done,
exactly as the 17.8.1 template's `--use-delivery-api` option would generate them:

`Program.cs`, register the services (between `AddWebsite()` and `AddComposers()`):

```csharp
builder.CreateUmbracoBuilder()
    .AddBackOffice()
    .AddWebsite()
    .AddDeliveryApi()
    .AddComposers()
    .Build();
```

`appsettings.json`, turn it on:

```json
"Umbraco": {
  "CMS": {
    "DeliveryApi": {
      "Enabled": true
    }
  }
}
```

Both are needed, and the first requires a restart. Without `AddDeliveryApi()` the endpoints still
exist (the controllers are in the referenced assembly) but fail with **HTTP 500**, "Unable to
resolve service for type IRequestSegmentService". In Development that response includes a stack
trace.

### Settings and defaults (from `Umbraco.Core/Configuration/Models/DeliveryApiSettings.cs`)

| Key under `Umbraco:CMS:DeliveryApi` | Default | This project | Effect |
|---|---|---|---|
| `Enabled` | `false` | **`true`** | Master switch |
| `PublicAccess` | `true` | default | Anonymous read access to published content |
| `ApiKey` | none | **not set** | Required for preview and for non-public access. Unset means preview is impossible |
| `DisallowedContentTypeAliases` / `AllowedContentTypeAliases` | empty | not set | Hide or whitelist Document Types |
| `RichTextOutputAsJson` | `false` | default | Rich text delivered as an HTML string inside `{ "markup": ... }` |
| `Media:Enabled` | `false` | default | Media endpoints disabled (they answer 401) |
| `MemberAuthorization` | none | not set | Protected content stays hidden |
| `OutputCache:Enabled` | `false` | default | No response caching (duration default 1 minute when enabled) |

## 2. Razor rendering versus headless delivery

| | Razor (Milestone 2) | Delivery API (this milestone) |
|---|---|---|
| Output | HTML pages | JSON |
| Who renders | The Umbraco app, with templates in `Views/` | Any client: SPA, mobile app, static-site generator, another service |
| Routing | Content finders map a URL to a node, then a template renders it | `/umbraco/delivery/api/v2/content/item/{path}` maps the same route to the same node, then a JSON builder serialises it |
| Data source | Published cache | Published cache (items); Examine `DeliveryApiContentIndex` plus the published cache (queries) |
| Presentation logic | In the view: fallbacks, formatting, `<br />`, crop URLs | **None.** The client gets stored values: Basil's `commonName` is `null`, Textarea text keeps `\n`, images are original URLs |
| Models | Models Builder classes (`PlantPage`) | Property aliases as JSON keys; value types come from the property value converters' Delivery API output |
| Draft content | Never on the public site | Only with `Preview: true` **and** a valid `Api-Key` |
| Security surface | HTML pages | A second public surface, listing and querying every published node |

The same content, the same publish workflow, and the same published cache feed both paths. Only
the last step differs: a template or a JSON serializer.

## 3. Verified endpoints

From the running app's OpenAPI document (`/umbraco/swagger/delivery/swagger.json`, title
"Umbraco Delivery API"). Only **v2** is served; a `/v1/` request returns 400.

| Method | Path | Purpose |
|---|---|---|
| GET | `/umbraco/delivery/api/v2/content/item/{path}` | One item by route, e.g. `plants/zinnia` (empty path = root) |
| GET | `/umbraco/delivery/api/v2/content/item/{id}` | One item by GUID key |
| GET | `/umbraco/delivery/api/v2/content/items?id=...` | Several items by key |
| GET | `/umbraco/delivery/api/v2/content` | Query: `fetch`, `filter`, `sort`, `skip`, `take`, `expand`, `fields` |
| GET | `/umbraco/delivery/api/v2/media`, `/media/item/{path}`, `/media/item/{id}`, `/media/items` | Media; **disabled** here |

Request headers accepted: `Accept-Language`, `Accept-Segment`, `Api-Key`, `Preview`, `Start-Item`.

Queries used and verified in this lab:

| Query string | Result |
|---|---|
| `fetch=children:/plants/` | The 3 published plants, in tree order |
| `fetch=children:/plants/&sort=sortOrder:asc` | Same, explicit order |
| `filter=contentType:plantPage&sort=name:asc` | Basil, Heirloom Tomato, Zinnia |
| `fetch=children:/plants/&sort=sortOrder:asc&take=2` / `&skip=2&take=2` | Paging; `total` stays 3 |
| `fetch=children:/` | Plants, Growing Guide |
| `fetch=children:/plants/&fields=properties[commonName,sunExposure]` | Only those properties; payload 2,344 → 1,176 bytes |

## 4. Example requests and responses

Homepage, `GET /umbraco/delivery/api/v2/content/item/`:

```json
{
  "contentType": "homePage",
  "name": "Home",
  "createDate": "2026-11-16T01:12:05.5999876Z",
  "updateDate": "2026-11-16T01:55:52.6604194Z",
  "route": { "path": "/", "queryString": null, "startItem": { "id": "a9461394-f8ce-4ccc-ad3e-4f9c2b9233e6", "path": "home" } },
  "id": "a9461394-f8ce-4ccc-ad3e-4f9c2b9233e6",
  "properties": {
    "heroHeadline": "Funky flavors, fresh from our fields",
    "introText": "Funky Fresh Farm is a small, fictional family farm growing heirloom vegetables, fragrant herbs, and cheerful flowers.\nBrowse the plant directory or read our growing guide to get started."
  },
  "cultures": {}
}
```

Plant, `GET /umbraco/delivery/api/v2/content/item/plants/heirloom-tomato/` (`route` and dates trimmed):

```json
{
  "contentType": "plantPage",
  "name": "Heirloom Tomato",
  "id": "48e49a10-4a72-43af-85b3-b8ed8f6bd87d",
  "properties": {
    "commonName": "Heirloom Tomato",
    "scientificName": "Solanum lycopersicum",
    "description": "Grown from seed saved season after season, ...\nStake plants early and water at the base to keep the leaves dry.",
    "sunExposure": "Full Sun",
    "plantImage": [
      {
        "focalPoint": { "left": 0.5, "top": 0.5 },
        "crops": [],
        "id": "d3c6a34a-2625-487d-a858-3ce322fd3d3d",
        "name": "Heirloom Tomato",
        "mediaType": "Image",
        "url": "/media/yvujazkm/heirloom-tomato.png",
        "extension": "png",
        "width": 800,
        "height": 600,
        "bytes": 9682,
        "properties": {}
      }
    ]
  },
  "cultures": {}
}
```

Notable shapes:

- `id` is the node's **GUID key**, not the integer id shown in the backoffice.
- Empty values are `null`: Basil `"commonName": null`, Zinnia `"plantImage": null`.
- The Image Media Picker is always an **array**, even when it allows a single item.
- Rich text: `"bodyText": { "markup": "<h2>Start with healthy soil</h2>...", "blocks": { ... } }`.

Directory query, `GET /umbraco/delivery/api/v2/content?fetch=children:/plants/&sort=sortOrder:asc`:

```json
{
  "total": 3,
  "items": [
    { "contentType": "plantPage", "name": "Heirloom Tomato", "route": { "path": "/plants/heirloom-tomato/", ... }, "properties": { ... } },
    { "contentType": "plantPage", "name": "Basil", ... },
    { "contentType": "plantPage", "name": "Zinnia", ... }
  ]
}
```

Status codes observed:

| Request | Status |
|---|---|
| Unpublished node (`/content/item/plants/mint/`) | 404 |
| Unknown route | 404 |
| Any request with `Preview: true` and no or invalid `Api-Key` | 401 |
| Media endpoints (media delivery disabled) | 401 |
| `/umbraco/delivery/api/v1/...` | 400 |

## 5. Published-content availability and the Delivery API index

- **Item endpoints** (`content/item/...`) resolve the route and read the **published cache**,
  the same cache Razor uses (`ByRouteContentApiController` → `ApiPublishedContentCache.GetByRouteAsync`).
  They work the moment the API is enabled.
- **The query endpoint** (`/content?...`) asks the Examine **`DeliveryApiContentIndex`** for matching
  keys (`QueryContentApiController` → `ApiContentQueryService.ExecuteQuery`), then loads those keys
  from the published cache. It returns nothing until the index is built.
- The index **does not exist until the API is enabled**. After the restart in this lab it was
  created empty, and Umbraco's `RebuildOnStartupHandler` rebuilt it automatically: on the first
  request after a normal ("warm") startup it rebuilds **empty** indexes after a **one-minute** delay
  (`RebuildOnStartupHandler.cs:40-42`). The query went from `total: 0` to `total: 3` about a minute
  after the first request. Nothing is logged at Information level when this happens.
- **Manual rebuild** (the documented route, and the fix if the index is ever stale): **Settings →
  Examine Management → DeliveryApiContentIndex → Rebuild index**.
- **On publish/unpublish**, `DeliveryApiIndexingHandler.HandleContentChanges` queues a deferred
  `DeliveryApiContentIndexHandleContentChanges` that updates the index. Only published,
  non-protected content of allowed types is indexed, which is why unpublished Mint is never returned
  by queries.

## 6. Security boundaries

Access is decided by `ApiAccessService` (`Umbraco.Cms.Api.Delivery/Services/ApiAccessService.cs:11-17`):

```text
public access  = Enabled && (PublicAccess || valid Api-Key)
preview access = Enabled && valid Api-Key
media access   = Enabled && Media.Enabled && ((PublicAccess && Media.PublicAccess) || valid Api-Key)
valid Api-Key  = ApiKey is configured && request header Api-Key equals it
```

A failed check returns **401** (`UnauthorizedResult`), whether the feature is disabled or
the caller lacks the key.

What that means here:

- **Only published content is exposed.** Unpublished nodes return 404 and are absent from queries.
  Drafts, the current version of a node with pending changes, are only served in **preview**, which
  needs a valid `Api-Key`. **No `ApiKey` is configured, so preview is impossible**; a forged key gets 401.
- **Everything published is public.** The API lists and queries all published content
  anonymously, including pages not linked from navigation. Do not rely on "unlinked" as private. Use
  `DisallowedContentTypeAliases`, `PublicAccess: false` with an `ApiKey`, or member authorization
  (protected content is ignored unless member authorization is configured).
- **Media endpoints are off.** Image URLs inside content responses still work because `/media/...` is
  served as static files, as for the Razor site.
- **No HTTPS enforcement.** The API answers over `http://localhost:41388` too; `UseHttps` only governs
  backoffice authentication. Production should redirect or terminate HTTP.
- **Configuration is read live** (`OnChange`), so editing `DeliveryApi:Enabled` or `PublicAccess`
  in `appsettings.json` takes effect without a restart, even though `AddDeliveryApi()` itself
  requires one.
- **Swagger** (`/umbraco/swagger`) is available because the runtime mode is not Production; the
  documentation says it is not exposed in production mode by default.
- **Misconfiguration leaks detail in Development**: the pre-enable 500 response included a .NET stack
  trace (Developer Exception Page). Production shows a generic error.
- If an `ApiKey` is added later, it is a secret: put it in `appsettings.Local.json` (never the
  tracked `appsettings.json`) and pass it only in the `Api-Key` header.

## 7. Running the verification

With the app running and the Milestone 2 content published (plus Mint unpublished):

```powershell
pwsh ./scripts/Test-DeliveryApi.ps1                                     # 14 checks
pwsh ./scripts/Test-DeliveryApi.ps1 -BaseUrl http://localhost:41388      # over HTTP
pwsh ./scripts/Test-DeliveryApi.ps1 -UnpublishedRoute ''                 # skip the Mint check
pwsh ./scripts/Test-Site.ps1                                             # Razor smoke test, 10 checks
dotnet test FunkyFreshFarm.slnx                                          # unit tests, 3 tests
```

In Windows PowerShell 5.1, use `powershell -ExecutionPolicy Bypass -File scripts\Test-DeliveryApi.ps1`.

`Test-DeliveryApi.ps1` is GET-only, uses no credentials or API key, and exits `0` (all pass), `1`
(any failure, including unreachable site or disabled API) or `2` (script error). Its checks:

| Check | Asserts |
|---|---|
| Homepage item | `contentType` `homePage`, `route.path` `/`, non-empty `heroHeadline` and `introText` |
| Plant directory item | `plantIndexPage`, `pageTitle` `Our Plants` |
| Directory children query | `total` > 0 (else an index hint), first three names in tree order, all `plantPage`, routes under `/plants/` |
| Heirloom Tomato | names, `Full Sun`, two-line `description`, one `Image` at `/media/.../heirloom-tomato.png`, 800×600 |
| Basil | `commonName` **null** (raw value, no Razor fallback), one image |
| Zinnia | `plantImage` empty |
| Guide | `pageTitle`; `bodyText.markup` contains `<h2>`, `<ul>`, `<strong>` |
| Item by GUID id | Same node as the route lookup |
| Filter by content type | The three plants, all `plantPage` |
| Paging | `take=2` returns 2 items, `total` ≥ 3 |
| Unpublished content not delivered | `-UnpublishedRoute` (default `/plants/mint/`) returns 404 |
| Preview without API key | 401 |
| Unknown route | 404 |
| Media delivery disabled | 401 |

Failures report the URL, status, a body excerpt, and a hint for the common causes (500 →
`AddDeliveryApi()` missing; 401 on a public read → API disabled; `total: 0` → index not built yet).

## 8. Inspecting requests in a browser, Swagger UI, Postman, or curl

- **Browser:** paste a GET URL, for example
  `https://localhost:44370/umbraco/delivery/api/v2/content/item/plants/zinnia/`. Edge and Chrome offer
  a **Pretty-print** option for JSON.
- **Swagger UI:** open `https://localhost:44370/umbraco/swagger`, select the **Umbraco Delivery API**
  definition, expand an operation, **Try it out**, fill the parameters, **Execute**. It shows the
  exact request URL and the response.
- **Postman:** create a GET request with the same URL. Postman may not trust the Windows
  certificate store; disable SSL verification for localhost or use `http://localhost:41388`. Add the
  header `Preview: true` to see the 401 boundary.
- **curl** (PowerShell): `curl.exe -s https://localhost:44370/umbraco/delivery/api/v2/content?fetch=children:/plants/`.
  For `fields=properties[...]`, add `-g`: curl otherwise treats `[...]` as a URL glob and fails with
  exit code 3.

## 9. Notification handler architecture

### What it does

`src/FunkyFreshFarm.UmbracoLab/Notifications/ContentPublishedLoggingHandler.cs` handles
`ContentPublishedNotification` and writes one Information log entry per published document:

```text
[20:42:04 INF] Published plantPage Zinnia (id 1073, key 41af6409-1759-4c16-bffb-23078a1d57ea)
```

It logs the content type alias, name, integer id, and key, all as structured properties
(`ContentTypeAlias`, `ContentName`, `ContentId`, `ContentKey`), and never property values, which
could contain personal data. It has no side effects: no database writes, no external calls.

### Registration

`Notifications/NotificationsComposer.cs` is an `IComposer`:

```csharp
public void Compose(IUmbracoBuilder builder)
    => builder.AddNotificationHandler<ContentPublishedNotification, ContentPublishedLoggingHandler>();
```

`AddComposers()` in `Program.cs` discovers every `IComposer` in the application's assemblies, so no
change to `Program.cs` was needed. `AddNotificationHandler` registers the handler as a **Transient**
`INotificationHandler<ContentPublishedNotification>` (`UmbracoBuilder.Events.cs`). Registering
directly on the builder chain in `Program.cs` would also work; a composer keeps the feature in its
own folder.

### Dependency injection

The handler is created from the DI container for each dispatch, so it can take any registered
service. It takes `ILogger<ContentPublishedLoggingHandler>` (a primary-constructor parameter). Being
transient, it must not hold state between notifications.

### Notifications versus ordinary .NET events

| | .NET `event` | Umbraco notification |
|---|---|---|
| Subscription | `+=` on an object instance; subscriber must hold a reference | Registered in DI; publisher and handler never reference each other |
| Lifetime | Subscriber lives as long as the subscription (leak risk) | Handler resolved per dispatch (transient) |
| Dependencies | Whatever the subscriber captured | Constructor injection |
| Timing | Synchronous at the moment of raising | **Scoped**: "-ed" notifications wait until the database scope completes |
| Cancellation | Ad hoc | "-ing" notifications (`ContentPublishingNotification`) implement `ICancelableNotification` |
| Batching | One call per event | One notification can carry many entities (`PublishedEntities`) |

### Execution timing (verified in source and in this lab)

1. The editor's **Save and publish** sends
   `PUT /umbraco/management/api/v1/document/{key}/update-and-publish`
   (`UpdateAndPublishDocumentController.Update` → `IContentEditingService.UpdateAndPublishAsync`).
2. `ContentPublishingNotification` ("-ing", cancellable) is published **immediately**, inside the
   operation; a handler could cancel the publish here (`ScopedNotificationPublisher.PublishCancelable`).
3. The content service writes the new versions; `ContentService` logs "Document … has been published."
4. `ContentPublishedNotification` ("-ed") is **queued** (`ScopedNotificationPublisher.Publish`).
5. When the outermost scope is disposed, `Scope.DisposeLastScope` **commits the transaction first**
   (`_database.CompleteTransaction()`), then publishes queued notifications, but only if the scope
   completed (`ScopeExit(completed)`). A failed publish never notifies.
6. `EventAggregator` invokes handlers **sequentially** on the same thread. In the lab, Umbraco's own
   `UserNotificationsHandler` ran first, then ours: same request (`HttpRequestNumber=6`), same thread
   (`ThreadId=38`), 132 ms after the publish was logged.

### Error propagation

`EventAggregator` has no `try`/`catch` around handlers. If a "-ed" handler throws:

- The exception propagates to the request that published, so the **editor sees an error**.
- But the transaction was **already committed**: the content **is published**.
- Handlers registered after the failing one are skipped.

For "-ing" handlers, an exception aborts the operation before commit. Set `notification.Cancel = true`
(with a message) to refuse it deliberately.

### Appropriate uses

Good fits: audit or diagnostic logging, cache invalidation of something Umbraco does not manage,
enqueueing work for a background service, validation that cancels a "-ing" operation.

Poor fits: slow or unreliable work inline (HTTP calls, emails), because it delays every editor's
publish and can make a successful publish look failed. Queue it instead. Also avoid writing more
Umbraco content from a handler without care; that triggers further notifications.

### Tests

`tests/FunkyFreshFarm.UmbracoLab.Tests` (xUnit 2.9.3, NSubstitute 6.2.0,
Microsoft.Extensions.Diagnostics.Testing 10.11.0 for `FakeLogger`):

| Test | Proves |
|---|---|
| `Logs_one_information_entry_per_published_document` | One entry per entity, Information level, exact message, all four structured properties |
| `Logs_nothing_when_no_documents_were_published` | No noise on empty notifications |
| `Registers_the_logging_handler_as_a_transient_ContentPublished_handler` | The composer's registration: service type, implementation, Transient lifetime |

The test package is pinned to the **10.x** line because Umbraco 17 constrains `Microsoft.Extensions.*`
to `(,10.0.32767]`. The 11.x package targets the next .NET wave.

## 10. End-to-end trace: edit, save, publish, log, API, Razor

Performed by the owner on 2026-11-15 with Zinnia's Description (a third line,
"Sow seeds directly in warm soil after the last frost.", was added).

| Step | Observation | Evidence |
|---|---|---|
| 1. Edit Description | — | — |
| 2. **Save** only | No handler log entry; API and Razor still show 2 lines | Snapshot: draft v17 has 3 lines, published v14 has 2; `edited=1`; only the draft cache row changed |
| 3. **Save and publish** | Console: `[20:42:04 INF] Published plantPage Zinnia (id 1073, key 41af6409-…)` | `update-and-publish` request; v17 published, new current v23; published cache row rewritten |
| 4. Notification log | One entry, same request and thread as the publish | Structured properties in `umbraco/Logs/UmbracoTraceLog.*.json` |
| 5. Delivery API | Item and query show 3 lines; `updateDate` 02:42:04Z | `GET .../content/item/plants/zinnia/` |
| 6. Razor | `/plants/zinnia/` shows 3 lines | Two `<br />` in the description |

### Classes, logs, and breakpoints along the path

| Stage | Class / method | Log to watch |
|---|---|---|
| Save and publish request | `UpdateAndPublishDocumentController.Update` | — |
| Publish operation | `IContentEditingService.UpdateAndPublishAsync`, `ContentService` | `ContentService`: "Document … has been published." |
| Commit and dispatch | `Scope.DisposeLastScope`, `ScopedNotificationPublisher.ScopeExit` | — |
| Our handler | `ContentPublishedLoggingHandler.Handle` | `ContentPublishedLoggingHandler`: "Published …" |
| Cache refresh | `DocumentCacheService.RefreshContentAsync` | — |
| Index update | `DeliveryApiIndexingHandler.HandleContentChanges` | — (Debug only) |
| API item | `ByRouteContentApiController.ByRouteV20` → `ApiPublishedContentCache.GetByRouteAsync` | — |
| API query | `QueryContentApiController.QueryV20` → `ApiContentQueryService.ExecuteQuery` | — |
| Razor | `UmbracoRouteValueTransformer.TransformAsync` → `ContentFinderByUrlNew` → `RenderController.Index` | — |

**Debugging with breakpoints:** start the app as usual, then attach the C# debugger to the running
`FunkyFreshFarm.UmbracoLab` process (in VS Code with the C# Dev Kit, use the C# debugger's
"attach to process" option; the exact command name was not verified here). A breakpoint in
`ContentPublishedLoggingHandler.Handle` stops during **Save and publish**; the call stack shows the
scope disposal and event aggregator frames. For Umbraco's own classes, turn off "Just My Code".
(Breakpoints were not exercised in this milestone; the trace above used logs, snapshots, and HTTP.)

## 11. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Delivery API returns 500 "Unable to resolve service … IRequestSegmentService" | `AddDeliveryApi()` missing from `Program.cs`, or the app was not restarted after adding it |
| Every public request returns 401 | `DeliveryApi:Enabled` is false, or `PublicAccess` is false without an `Api-Key` |
| `/content?...` returns `{"total":0,"items":[]}` | The `DeliveryApiContentIndex` is empty: wait about a minute after the first request following startup, or rebuild it in Settings → Examine Management |
| An item returns 404 | Not published (or an ancestor isn't), wrong route, or the type is disallowed |
| `Preview: true` returns 401 | Expected: no `ApiKey` is configured |
| Media endpoints return 401 | Expected: `DeliveryApi:Media:Enabled` is false |
| `/v1/` returns 400 | Use `/v2/` |
| curl exits with code 3 on `fields=properties[...]` | Add `-g` (disable URL globbing) |
| No "Published …" log line on publish | Handler not registered: the composer must be public, in the web project, with `AddComposers()` in `Program.cs`; the app must have been rebuilt and restarted |
| An error after Save and publish, but the content is live | A notification handler threw after the commit (see §9) |
| Build error "file is being used by another process" | The app is running; C# changes need it stopped. `dotnet run` rebuilds before starting |
| `appsettings-schema*.json` appear in `tests/` | Expected: `Umbraco.Cms.Targets` copies them into every referencing project; they are gitignored |

## 12. Files changed

| File | Change |
|---|---|
| `src/FunkyFreshFarm.UmbracoLab/Program.cs` | `.AddDeliveryApi()` |
| `src/FunkyFreshFarm.UmbracoLab/appsettings.json` | `Umbraco:CMS:DeliveryApi:Enabled = true` |
| `src/FunkyFreshFarm.UmbracoLab/Notifications/ContentPublishedLoggingHandler.cs` | New handler |
| `src/FunkyFreshFarm.UmbracoLab/Notifications/NotificationsComposer.cs` | Registers the handler |
| `tests/FunkyFreshFarm.UmbracoLab.Tests/` | New xUnit project (3 tests) |
| `FunkyFreshFarm.slnx` | Adds the test project under `/tests/` |
| `scripts/Test-DeliveryApi.ps1` | New API verification script |
| `.gitignore` | Ignores Umbraco's generated JSON schema files repo-wide |
| `docs/03-api-and-extensions.md` | This document |
