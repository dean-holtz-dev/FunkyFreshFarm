# 04 — Architecture and Engineering Review

A development-lead briefing on how Umbraco CMS 17 is built, based on reading the framework source
and on the behaviour observed in this lab. The discussion is generic: it describes open-source
Umbraco and this fictional lab only.

**Inspected revision:** [`umbraco/Umbraco-CMS` tag `release-17.8.1`](https://github.com/umbraco/Umbraco-CMS/tree/release-17.8.1),
commit [`89c87c2f768418d877281d3dcaba9c0a7e806461`](https://github.com/umbraco/Umbraco-CMS/commit/89c87c2f768418d877281d3dcaba9c0a7e806461)
(2026-11-04). The running lab reports build `17.8.1+89c87c2`, so the source read is the code that
runs. The source was shallow-cloned read-only into a scratch folder; it was not built or modified.

Links below are permalinks to that commit. `S` = `https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src`.
Each claim is marked **Verified** (read in source and/or observed in the lab) or **Conceptual**
(a simplification for orientation).

Contents:

1. [Source-backed architecture overview](#1-source-backed-architecture-overview)
2. [Application and framework boundaries](#2-application-and-framework-boundaries)
3. [Narrated content lifecycle](#3-narrated-content-lifecycle)
4. [Assessment of our implementation choices](#4-assessment-of-our-implementation-choices)
5. [Operational risks and maintenance concerns](#5-operational-risks-and-maintenance-concerns)
6. [Testing recommendations](#6-testing-recommendations)
7. [Appropriate versus inappropriate customisations](#7-appropriate-versus-inappropriate-customisations)
8. [Upgrade and migration considerations](#8-upgrade-and-migration-considerations)
9. [Questions for engineers maintaining a large Umbraco installation](#9-questions-for-engineers-maintaining-a-large-umbraco-installation)
10. [Local backup and restore runbook](#10-local-backup-and-restore-runbook)

---

## 1. Source-backed architecture overview

Umbraco is an ordinary ASP.NET Core application with a layered domain inside it. The host is the
standard generic host; Umbraco contributes a builder for DI registration, a runtime that boots before
the HTTP pipeline, a fixed middleware order, and two families of endpoints: the website and the APIs.

### Startup path (Verified)

| Step | Code in `Program.cs` | Implementation |
|---|---|---|
| Host | `WebApplication.CreateBuilder(args)` | Plain ASP.NET Core |
| Umbraco builder | `builder.CreateUmbracoBuilder()` | [`Web.Common/Extensions/WebApplicationBuilderExtensions.cs#L21`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Common/Extensions/WebApplicationBuilderExtensions.cs#L21) → `AddUmbraco` [`Web.Common/DependencyInjection/UmbracoBuilderExtensions.cs#L129`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Common/DependencyInjection/UmbracoBuilderExtensions.cs#L129) (sets `DataDirectory` at [#L149](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Common/DependencyInjection/UmbracoBuilderExtensions.cs#L149)) |
| Backoffice services | `.AddBackOffice()` | [`Cms.Api.Management/DependencyInjection/UmbracoBuilder.BackOffice.cs#L37`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Cms.Api.Management/DependencyInjection/UmbracoBuilder.BackOffice.cs#L37) |
| Website services | `.AddWebsite()` | [`Web.Website/DependencyInjection/UmbracoBuilderExtensions.cs#L44`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Website/DependencyInjection/UmbracoBuilderExtensions.cs#L44) |
| Delivery API services | `.AddDeliveryApi()` | [`Cms.Api.Delivery/DependencyInjection/UmbracoBuilderExtensions.cs#L43`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Cms.Api.Delivery/DependencyInjection/UmbracoBuilderExtensions.cs#L43) |
| Composers | `.AddComposers()` | [`Core/DependencyInjection/UmbracoBuilder.Composers.cs#L14`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/DependencyInjection/UmbracoBuilder.Composers.cs#L14): type-loader scan, ordered by `ComposerGraph` |
| Flush collections | `.Build()` | [`Core/DependencyInjection/UmbracoBuilder.cs#L143`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/DependencyInjection/UmbracoBuilder.cs#L143): each collection builder registers into `IServiceCollection` |
| Container | `builder.Build()` | Plain ASP.NET Core |
| Boot | `await app.BootUmbracoAsync()` | [`Web.Common/Extensions/WebApplicationExtensions.cs#L20`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Common/Extensions/WebApplicationExtensions.cs#L20) → `CoreRuntime.StartAsync` [`Infrastructure/Runtime/CoreRuntime.cs#L105`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Infrastructure/Runtime/CoreRuntime.cs#L105): MainDom, unattended install, `RuntimeState.DetermineRuntimeLevel` [`RuntimeState.cs#L153`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Infrastructure/Runtime/RuntimeState.cs#L153), migrations |
| Middleware | `app.UseUmbraco().WithMiddleware(...)` | [`Web.Common/Extensions/ApplicationBuilderExtensions.cs#L38`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Common/Extensions/ApplicationBuilderExtensions.cs#L38) → [`UmbracoApplicationBuilder.cs#L50`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Common/ApplicationBuilder/UmbracoApplicationBuilder.cs#L50), fixed order in `RegisterDefaultRequiredMiddleware` [#L71](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Common/ApplicationBuilder/UmbracoApplicationBuilder.cs#L71); `UseBackOffice` [`Management/Extensions/UmbracoApplicationBuilder.BackOffice.cs#L19`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Cms.Api.Management/Extensions/UmbracoApplicationBuilder.BackOffice.cs#L19); `UseWebsite` [`Web.Website/Extensions/UmbracoApplicationBuilderExtensions.cs#L20`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Website/Extensions/UmbracoApplicationBuilderExtensions.cs#L20) |
| Endpoints | `.WithEndpoints(...)` | [`UmbracoApplicationBuilder.cs#L168`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Common/ApplicationBuilder/UmbracoApplicationBuilder.cs#L168); `UseBackOfficeEndpoints` [#L31](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Cms.Api.Management/Extensions/UmbracoApplicationBuilder.BackOffice.cs#L31); `UseWebsiteEndpoints` maps `MapDynamicControllerRoute<UmbracoRouteValueTransformer>` [`#L49`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Website/Extensions/UmbracoApplicationBuilderExtensions.cs#L49) |

The repository's own development host, [`Umbraco.Web.UI/Program.cs`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.UI/Program.cs),
has the same shape as ours, plus `#if` switches for a documented Content Security Policy and HTTPS
redirection (both off in this lab).

### Compared with ordinary ASP.NET Core (Conceptual, from the verified mechanics)

| Concern | Typical ASP.NET Core app | Umbraco |
|---|---|---|
| DI registration | Directly on `IServiceCollection` | `IUmbracoBuilder` + composers + **collection builders** (ordered extension lists flushed in `Build()`) |
| Pre-pipeline work | Rare; hosted services start with the host | `BootUmbracoAsync` decides a **runtime level** (Install, Upgrade, Run, BootFailed) *before* middleware is built, and middleware behaves according to it |
| Middleware order | Hand-written | Fixed by `UseUmbraco()`; customise through `IUmbracoPipelineFilter` hooks |
| Routing | Attribute or conventional routes | One dynamic route; a transformer resolves URLs to content via content finders |
| Data access | EF Core `DbContext` | NPoco repositories + units of work inside `ICoreScope`; EF Core only for some newer subsystems (OpenIddict stores) |
| Events | Ad hoc or MediatR-style | Notifications through `IEventAggregator`, scoped to transactions |
| Read model | Query the database | Published cache (HybridCache + `cmsContentNu`); the database is not queried per page view |

## 2. Application and framework boundaries

### Project dependency graph (Verified from the `.csproj` files)

```text
Umbraco.Core                         no project references; Microsoft.Extensions.* abstractions only
  └─ Umbraco.Infrastructure          NPoco, Examine.Core, MailKit, Markdig, ncrontab, MiniProfiler
       ├─ Umbraco.PublishedCache.HybridCache   Microsoft.Extensions.Caching.Hybrid, MessagePack, LZ4
       ├─ Umbraco.Examine.Lucene               Examine (Lucene.NET)
       ├─ Umbraco.Cms.Persistence.Sqlite / .SqlServer / .EFCore.*
       └─ Umbraco.Web.Common         ← first layer with the Microsoft.AspNetCore.App framework reference
            ├─ Umbraco.Web.Website             front-end routing and Razor rendering
            ├─ Umbraco.Cms.Api.Common          OpenIddict, Swashbuckle, Asp.Versioning
            │    ├─ Umbraco.Cms.Api.Management (+ Infrastructure, HybridCache)
            │    └─ Umbraco.Cms.Api.Delivery
            ├─ Umbraco.Cms.Imaging.ImageSharp  (ImageSharp 3.2.0 / ImageSharp.Web 3.3.0)
            └─ Umbraco.Cms.DevelopmentMode.Backoffice  Razor runtime compilation + Roslyn (InMemoryAuto)
Umbraco.Cms.StaticAssets   → Api.Management, Web.Website; carries the built backoffice client
Umbraco.Cms.Targets        → Api.Delivery, StaticAssets, Api.Management; MSBuild targets (schema files)
Umbraco.Cms (metapackage)  → Targets, ImageSharp, SQLite + SQL Server providers (NPoco and EF Core)
Umbraco.Web.UI             → Umbraco.Cms + DevelopmentMode.Backoffice  (HQ's dev host; same shape as ours)
```

### Responsibilities, dependencies, and extension points

| Project | Responsibility | Depends on | Typical extension points |
|---|---|---|---|
| **Umbraco.Core** (2,669 `.cs` files) | Domain model (`IContent`, `IContentType`), service interfaces and many implementations (`ContentService`, `ContentEditingService`), notifications, routing contracts, Delivery API contracts | Nothing Umbraco; no ASP.NET Core | `IComposer`, notification handlers, `IContentFinder`, `IUrlProvider`, property value converters, `IHtmlSanitizer` |
| **Umbraco.Infrastructure** (1,088) | Persistence (NPoco repositories, migrations), scopes and transactions, runtime and boot, Examine integration, background jobs, mail | Core | Package migrations, custom repositories, background jobs, index value sets |
| **PublishedCache.HybridCache** | Published-content cache: `cmsContentNu` rows serialised with MessagePack (+ LZ4) behind `HybridCache` | Core, Infrastructure | Cache settings (seeding, bounded cache via `.Bounded`) |
| **Examine.Lucene** | Lucene-backed search indexes (Internal, External, Members, DeliveryApiContent) | Infrastructure | Custom indexes and value sets |
| **Umbraco.Web.Common** (213) | ASP.NET Core integration: `CreateUmbracoBuilder`, `BootUmbracoAsync`, `UseUmbraco`, Razor base classes (`UmbracoViewPage`), model binding, Serilog setup, controllers base | Examine.Lucene, HybridCache, ASP.NET Core | `IUmbracoPipelineFilter`, `RenderController` hijacking, Razor helpers |
| **Umbraco.Web.Website** (62) | Front-end routing (`UmbracoRouteValueTransformer`, `PublishedRouter`), surface controllers | Web.Common | Content finders, route hijacking, `SurfaceController` |
| **Cms.Api.Common** (48) | Shared API infrastructure: OpenIddict auth, OpenAPI/Swagger, versioning | Core, Web.Common | OpenAPI customisation |
| **Cms.Api.Management** (1,428) | The backoffice's REST API, `/umbraco/management/api/v1`: every backoffice action (the `update-and-publish` call seen in Milestone 3) | Api.Common, Infrastructure, HybridCache | Custom Management API controllers (authorised by backoffice policies) |
| **Cms.Api.Delivery** (96) | Headless read API, `/umbraco/delivery/api/v2` | Api.Common, Web.Common | `IDeliveryApiPropertyValueConverter`, query handlers (selectors, filters, sorts) |
| **Umbraco.Web.UI** | HQ's development and test host | Umbraco.Cms | — (it plays the role of *our* project) |
| **Backoffice client** (`Umbraco.Web.UI.Client`, 8,358 `.ts` files) | The editor UI: npm package `@umbraco-cms/backoffice` 17.8.1, Lit 3 web components, `@umbraco-ui/uui` 2.1.1, RxJS, Tiptap, Monaco, DOMPurify, SignalR; 40 feature packages including `management-api` (generated API client) | Calls only the Management API | Backoffice extensions via `umbraco-package.json` manifests (`App_Plugins`): dashboards, property editor UIs, workspace views, actions |

**How the client reaches us (Verified):** `Umbraco.Cms.StaticAssets.csproj` runs `npm i` and
`npm run build:for:cms` during *Umbraco's* build
([#L59-L66](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Cms.StaticAssets/Umbraco.Cms.StaticAssets.csproj#L59-L66))
into `wwwroot/umbraco/backoffice`, which ships inside the NuGet package. Consumers like us never need
Node.

### Architectural trade-offs

- **Host-agnostic core.** Domain logic is testable without a web host, at the cost of many projects
  and an abstraction-heavy service layer.
- **Two API surfaces.** The Management API is large and private to the backoffice; the Delivery API is
  small, read-only, and public. Mixing them would couple editor tooling to public contracts.
- **The backoffice as a separate SPA.** A modern UI with its own release cadence, extended in
  TypeScript rather than C#. Teams need front-end skills to customise the editor experience.
- **NPoco plus EF Core.** Mature hand-tuned SQL for content; EF Core only where useful. Two data-access
  styles to understand.
- **Schema as data.** Flexibility for editors, at the cost of reproducibility and source control (§4).
- **Both database providers in the metapackage.** Simple to install; larger dependency surface.

## 3. Narrated content lifecycle

Traced through one real action from Milestone 3: an editor changes Zinnia's description and selects
**Save and publish**. Line numbers refer to the inspected commit.

1. **Backoffice edit (Verified).** The Lit client sends `PUT /umbraco/management/api/v1/document/{key}/update-and-publish`
   to `UpdateAndPublishDocumentController.Update`
   ([#L64](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Cms.Api.Management/Controllers/Document/UpdateAndPublishDocumentController.cs#L64)).
   The log entries showed `RequestPath`, `ActionName`, thread, and request number.
2. **Application service (Verified).** `IContentEditingService.UpdateAndPublishAsync`
   ([`ContentEditingService.cs#L343`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentEditingService.cs#L343))
   → `HandleUpdateAsync` ([#L351](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentEditingService.cs#L351))
   maps and validates the request against the Document Type, enforces field permissions, applies the
   template, then `SaveAndPublish` ([#L543](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentEditingService.cs#L543))
   calls `ContentService.SaveAndPublish` ([#L557](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentEditingService.cs#L557)).
   (A publish-only action goes through `ContentPublishingService.PublishAsync`, [#L80](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentPublishingService.cs#L80),
   to `ContentService.Publish`, [#L1373](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentService.cs#L1373).)
3. **Domain service, scope, and lock (Verified).** `ContentService.SaveAndPublish`
   ([#L1451](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentService.cs#L1451))
   opens a scope, which is the database transaction ([#L1492](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentService.cs#L1492)),
   takes a **write lock on the content tree** ([#L1493](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentService.cs#L1493);
   both providers implement it as `UPDATE umbracoLock SET value = … WHERE id = <lockId>` inside the
   transaction: SQL Server with `ROWLOCK, REPEATABLEREAD` and `SET LOCK_TIMEOUT`
   ([`SqlServerDistributedLockingMechanism.cs#L182`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Cms.Persistence.SqlServer/Services/SqlServerDistributedLockingMechanism.cs#L182)),
   SQLite by waiting on its single-writer lock
   ([`SqliteDistributedLockingMechanism.cs#L177`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Cms.Persistence.Sqlite/Services/SqliteDistributedLockingMechanism.cs#L177)),
   so concurrent content writes are serialised, even across servers sharing one database), gives
   cancellable "-ing" notification handlers the chance to veto ([#L1502](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentService.cs#L1502);
   `ContentPublishingNotification` is raised at [#L1845](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentService.cs#L1845)),
   runs `CommitDocumentChangesInternal` ([#L1515](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentService.cs#L1515);
   method at [#L1739](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentService.cs#L1739)),
   and marks the scope complete ([#L1516](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentService.cs#L1516)).
4. **Persistence (Verified).** `DocumentRepository.PersistUpdatedItem`
   ([#L1324](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Infrastructure/Persistence/Repositories/Implement/DocumentRepository.cs#L1324))
   writes the node, version rows, and property data with NPoco. When publishing, it marks the current
   version published and inserts a new draft version (observed in Milestone 2: v6 published, v20 current).
5. **Published-cache row, inside the transaction (Verified).** The repository raises
   `ContentRefreshNotification` ([#L1535](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Infrastructure/Persistence/Repositories/Implement/DocumentRepository.cs#L1535))
   through `OnUowRefreshedEntity`, which publishes **immediately** via the event aggregator
   ([`ContentRepositoryBase.cs#L1128`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Infrastructure/Persistence/Repositories/Implement/ContentRepositoryBase.cs#L1128)).
   `CacheRefreshingNotificationHandler` ([#L63](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.PublishedCache.HybridCache/NotificationHandlers/CacheRefreshingNotificationHandler.cs#L63))
   calls `DocumentCacheService.RefreshContentAsync`
   ([#L722](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.PublishedCache.HybridCache/Services/DocumentCacheService.cs#L722)),
   which rewrites the `cmsContentNu` draft and published rows through `DatabaseCacheRepository`
   ([#L59](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.PublishedCache.HybridCache/Persistence/DatabaseCacheRepository.cs#L59)).
   *Inference:* because this runs on the ambient scope's database, the cache row commits atomically with
   the content.
6. **Commit, then "-ed" notifications (Verified).** `ContentPublishedNotification`
   ([`ContentService.cs#L2041`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentService.cs#L2041))
   and `ContentTreeChangeNotification` ([#L1294](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/ContentService.cs#L1294))
   are **queued** by `ScopedNotificationPublisher.Publish`
   ([#L95](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Events/ScopedNotificationPublisher.cs#L95)).
   `Scope.DisposeLastScope` commits first ([`Scope.cs#L556`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Infrastructure/Scoping/Scope.cs#L556)),
   then `ScopeExit` dispatches the queue ([#L108](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Events/ScopedNotificationPublisher.cs#L108)).
   Our `ContentPublishedLoggingHandler` ran here, 132 ms after the publish, on the same request.
7. **Memory caches, URLs, index (Verified).** `ContentTreeChangeDistributedCacheNotificationHandler`
   ([link](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Cache/NotificationHandlers/Implement/ContentTreeChangeDistributedCacheNotificationHandler.cs#L9))
   calls `DistributedCache.RefreshContentCache`
   ([`DistributedCacheExtensions.cs#L245`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Cache/DistributedCacheExtensions.cs#L245)),
   and `ContentCacheRefresher.Refresh` ([#L194](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Cache/Refreshers/Implement/ContentCacheRefresher.cs#L194))
   refreshes the in-memory published cache ([#L271](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Cache/Refreshers/Implement/ContentCacheRefresher.cs#L271)),
   routing, navigation, and clears partial-view caches. URL segments are updated by
   `DocumentUrlServiceContentTreeChangeNotificationHandler`
   ([#L61](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/DocumentUrlServiceContentTreeChangeNotificationHandler.cs#L61)),
   and the Delivery API index by `DeliveryApiIndexingHandler.HandleContentChanges`
   ([#L82](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Infrastructure/Examine/DeliveryApiIndexingHandler.cs#L82)).
   *Conceptual:* in a load-balanced setup the same refreshers run on other servers through cache
   instructions (`InstructionProcessJob`, every 5 s in the lab log); with one server they run locally.
8. **Razor read (Verified).** `UmbracoRouteValueTransformer.TransformAsync`
   ([#L172](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Website/Routing/UmbracoRouteValueTransformer.cs#L172))
   → `PublishedRouter.RouteRequestAsync` ([#L101](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Routing/PublishedRouter.cs#L101))
   → `ContentFinderByUrlNew.TryFindContent` ([#L73](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Routing/ContentFinderByUrlNew.cs#L73))
   → `DocumentUrlService.GetDocumentKeyByRoute` ([#L998](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/Services/DocumentUrlService.cs#L998))
   → published cache → `RenderController.Index` ([#L52](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Common/Controllers/RenderController.cs#L52))
   → `ContentModelBinder` ([#L17](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Common/ModelBinders/ContentModelBinder.cs#L17))
   → the template, whose model was created by the Models Builder factory
   ([`InMemoryModelFactory.cs#L147`](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Cms.DevelopmentMode.Backoffice/InMemoryAuto/InMemoryModelFactory.cs#L147))
   → `UmbracoViewPage.Write` writes rich text raw ([#L102](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Web.Common/Views/UmbracoViewPage.cs#L102)).
9. **Delivery API read (Verified).** `ByRouteContentApiController.ByRouteV20`
   ([#L50](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Cms.Api.Delivery/Controllers/Content/ByRouteContentApiController.cs#L50))
   → `ApiPublishedContentCache.GetByRouteAsync` ([#L44](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/DeliveryApi/ApiPublishedContentCache.cs#L44))
   → the same published cache → `ApiContentResponseBuilder` ([#L10](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Core/DeliveryApi/ApiContentResponseBuilder.cs#L10))
   → JSON. Access is decided first by `ApiAccessService`
   ([#L11](https://github.com/umbraco/Umbraco-CMS/blob/89c87c2f768418d877281d3dcaba9c0a7e806461/src/Umbraco.Cms.Api.Delivery/Services/ApiAccessService.cs#L11)).

**The short version (Conceptual):** the editor's change is written as a new version and a refreshed
cache row in one transaction; after commit, notifications fan out to memory caches, URLs, indexes,
and our handler; both read paths then serve the new published state from memory, never from the
content tables.

## 4. Assessment of our implementation choices

| Choice | Assessment |
|---|---|
| Template defaults, `--release Latest` (exact `17.8.1` pin) | Good: reproducible restores. `--release LTS` would have floated to `17.*` |
| Attended install, secrets in `appsettings.Local.json` | Good for a lab: nothing secret in Git. Weakness: that file loads only in DEBUG builds, so a Release build has no connection string |
| SQLite | Right for a single-developer lab; see §5 for why enterprises differ |
| `BackofficeDevelopment` + `InMemoryAuto` models | Fast learning loop; views and aliases are only checked at request time. A team would move to `SourceCodeAuto`/`Nothing` with committed models |
| Code-owned layout, page templates in Git | Clean separation of markup (Git) from template records (database) |
| Typed models in pages, `IPublishedContent` in layout/navigation | Appropriate split |
| Content model created by hand in the backoffice | Fine for learning; **not reproducible** without the database (biggest gap, §5) |
| Delivery API: public, no key, media off | Least-privilege defaults; good |
| One notification handler via a composer, unit-tested | Idiomatic and minimal |
| PowerShell smoke tests + xUnit | Proportionate. No browser or visual tests, and the tests depend on specific content |
| Read-only verification through SQLite online-backup snapshots | Strong safety practice; also reused for hot backups (§10) |

## 5. Operational risks and maintenance concerns

| Area | Current state in the lab | Risk | Recommendation for a maintained application |
|---|---|---|---|
| **Configuration** | `appsettings*.json` tracked; secrets in untracked `appsettings.Local.json` (DEBUG only) | Release builds and other environments have no connection string or HMAC key; secrets live in a plain file | Per-environment configuration via environment variables or a secret store; keep `Global:Id`, `ApplicationUrl`, and `UseHttps` explicit per environment |
| **Database and media backup** | Manual cold copies; hot backup tool (§10); backups in an untracked folder on the same disk | Same-disk backups die with the disk; media and database can drift apart | Scheduled, off-machine backups taken together for database and media; tested restores |
| **Content-model reproducibility** | Document Types and Data Types exist only in SQLite | A new environment needs hand recreation; no review or history of schema changes | Source-control the schema (serialisation tooling such as open-source uSync, commercial Umbraco Deploy, or migrations/code-first). Treat schema changes like code changes |
| **Deployment and promotion** | None; `dotnet run` in Debug | No artefact, no promotion path; content and schema can't be promoted | Build once, publish an artefact, run in `Production` runtime mode with compiled models; promote schema via Git, content via a content-transfer process |
| **Testing** | Unit tests for one handler; HTTP smoke tests tied to demo content | Content edits break tests; no browser coverage | See §6 |
| **Diagnostics and logging** | Serilog JSON files plus console; Log Viewer; 3 harmless warnings per publish (no `ApplicationUrl`) | Warning noise hides signal; files grow on local disk | Set `WebRouting:UmbracoApplicationUrl`; ship logs to central storage; health checks and request tracing |
| **Security** | HTTPS dev certificate; backoffice HTTPS-only; rich text unsanitised; Delivery API public; HTTP still served | Editor-authored HTML can carry scripts; plain HTTP accepted | Register a real `IHtmlSanitizer`; HTTP→HTTPS redirect, HSTS, a CSP (the HQ host has a switch); strong admin passwords and 2FA; least-privilege user groups |
| **Caching and performance** | Unbounded in-memory published cache (log: "unbounded in-memory (L0) cache"); ImageSharp cache on local disk; no output cache | Memory grows with content size; disk cache grows unattended | Size the cache (the `HybridCache.Bounded` package exists); consider Delivery API output caching; CDN for media |
| **Dependency upgrades** | Exact pins; `UpgradeUnattended: true` runs migrations automatically | An upgrade migrates the database irreversibly on first start | Back up first; upgrade in a branch; read the version-specific upgrade notes; test with a production-like database copy; keep minor and patch versions current within the LTS line |
| **Technical debt** | `InMemoryAuto`; tests depend on demo content; DEBUG-only secrets; Growing Guide typo; unpublished Mint | Small now; would compound in a team | Track them as backlog items |
| **Commercial extension implications** | None used | Common needs (forms, schema/content deployment, workflow) are often met by commercial add-ons with licensing and upgrade cadence of their own; ImageSharp 3.x is under the Six Labors Split License (Umbraco ships an ImageSharp 2 alternative package) | Inventory every add-on's licence and version-compatibility policy before adopting; check the imaging licence for your organisation |

### Why SQLite here differs from a typical enterprise deployment

SQLite is an embedded, file-based database: one writer at a time, no server, no network access,
and a WAL file that must travel with the main file. That suits one developer on one machine with
zero setup. Enterprise installations typically use **SQL Server (or Azure SQL)** because they need
concurrent writers from several web servers (load balancing, separate backoffice and front-end
servers), point-in-time recovery and managed backups, high availability, monitoring, and
operational tooling. Umbraco supports both through the same NPoco layer; the provider is a package
choice (`Umbraco.Cms.Persistence.Sqlite` versus `.SqlServer`), but load-balanced setups add
requirements SQLite cannot meet: server roles, shared or replicated media, and per-server indexes and caches.

## 6. Testing recommendations

1. **Keep the HTTP smoke tests** (`Test-Site.ps1`, `Test-DeliveryApi.ps1`) as release gates, but run
   them against a **seeded, known database** (a restored backup) rather than a hand-edited one.
2. **Unit-test extensions** (handlers, composers, value converters, content finders) the way the
   notification handler is tested: fakes for `IContent` and loggers, assertions on registrations.
3. **Compile views at build time** in CI: switch to `SourceCodeAuto`/`Nothing` with committed models
   and Razor compilation on build, so alias mismatches fail the build, not the page.
4. **Integration tests** for service-level behaviour against a disposable SQLite database (Umbraco's
   own repository has integration-test infrastructure under `tests/`).
5. **Browser tests** (Playwright, which Umbraco itself uses for the backoffice) for critical editor
   journeys and visual regressions, kept few and stable.
6. **Upgrade rehearsal test**: restore a production-like backup, upgrade, run the smoke tests.
7. **Security tests**: preview and draft exposure (as `Test-DeliveryApi.ps1` does), HTTPS enforcement,
   header checks.

## 7. Appropriate versus inappropriate customisations

| Appropriate (supported extension points) | Inappropriate (fights the framework) |
|---|---|
| Composers and `IUmbracoBuilder` extensions for registration | Replacing core services wholesale when a notification or decorator would do |
| Notification handlers, kept fast and side-effect-light; queue slow work | Slow I/O (HTTP, email) inside "-ed" handlers on the editor's request |
| Route hijacking (`RenderController` per Document Type), content finders, URL providers | Hand-rolled routing that bypasses the published router |
| Property value converters, Delivery API converters, custom property editors with backoffice extensions | Writing directly to Umbraco's tables or `cmsContentNu` |
| `IUmbracoPipelineFilter` for middleware placement | Re-ordering Umbraco's middleware by hand |
| Backoffice extensions through `umbraco-package.json` manifests | Patching the shipped backoffice bundle |
| Configuration through documented `Umbraco:CMS:*` settings | Forking Umbraco source for local changes (blocks upgrades) |
| A real `IHtmlSanitizer`; custom `IContentLastChanceFinder` for 404s | Disabling security defaults (`UseHttps`) to avoid certificate set-up |

## 8. Upgrade and migration considerations

- **Version lines.** 17 is the LTS line in this lab; the template already offers 18.x. Plan major
  upgrades deliberately, and take patches within the LTS line regularly.
- **Migrations run at boot.** `RuntimeState` detects a schema older than the code and, with
  `UpgradeUnattended: true`, runs migrations on startup. That is irreversible: **back up first** (§10)
  and rehearse on a copy.
- **Breaking-change surface.** Expect changes at the C# extension points (composers, services,
  notifications), the backoffice extension API (TypeScript, which changed fundamentally at v14), Models
  Builder output, and the Delivery API version (`v1` is no longer served here).
- **Obsolete markers are the early warning.** Example: `ContentFinderByUrl` is `[Obsolete("Scheduled
  for removal in Umbraco 18.")]` and already unregistered. Build with warnings visible and fix them before upgrading.
- **Pinned transitive constraints.** Umbraco 17 constrains `Microsoft.Extensions.*` to `10.0.x`; your
  own packages must fit that range.
- **Content-model drift.** Without schema in source control, an upgrade cannot be rehearsed faithfully
  on a clean environment.

## 9. Questions for engineers maintaining a large Umbraco installation

1. How is the content model (Document Types, Data Types, templates) source-controlled and promoted
   between environments, and how are conflicts resolved?
2. Which Umbraco version and support line is in use, what is the upgrade cadence, and how is an
   upgrade rehearsed (database copy, migrations, smoke tests)?
3. What is the server topology (backoffice versus front-end servers, load balancing), and how are
   published caches, indexes, and media kept consistent across servers?
4. What is the backup and restore policy for the database **and** media together, and when was a
   restore last tested?
5. Which commercial add-ons are in use, what are their licences and compatibility windows, and which
   ones block upgrades?
6. Which custom extensions exist (composers, notification handlers, content finders, property editors,
   backoffice extensions), who owns them, and how are they tested?
7. How are models generated (`SourceCodeAuto`/`Nothing`), and do views compile in CI?
8. How is rich-text HTML sanitised, and how are editor permissions scoped?
9. Is the Delivery API (or another headless surface) enabled, what can it expose, and how are API keys
   managed?
10. What do the logs and monitoring show on a normal day, and what are the most common incidents?
11. How long does a cold start take (index rebuilds, cache seeding), and what happens to traffic meanwhile?
12. Where are the known performance hotspots (large trees, heavy queries in views, cache memory)?

## 10. Local backup and restore runbook

Tested on 2026-11-15 except where marked. Paths are relative to the repository root.

### What must be backed up together

| Item | Location | Why |
|---|---|---|
| Database | `src/FunkyFreshFarm.UmbracoLab/umbraco/Data/Umbraco.sqlite.db` (+ `-wal`, `-shm` while running) | Schema, content, versions, users |
| Local configuration | `src/FunkyFreshFarm.UmbracoLab/appsettings.Local.json` | Connection string and image HMAC key (signed image URLs break with a different key) |
| Media files | `src/FunkyFreshFarm.UmbracoLab/wwwroot/media/` | The files that media items in the database point to |

Not needed: `umbraco/Data/TEMP/` (indexes, models, image cache; rebuilt automatically) and `umbraco/Logs/`.

### Option A: hot backup while the app runs (tested)

```powershell
Set-Location C:\dev\FunkyFreshFarm
dotnet run scripts/backup-database.cs
```

`scripts/backup-database.cs` opens the live database **read-only**, copies it with SQLite's online
backup API into `backups/<yyyyMMdd-HHmmss>-hot/Umbraco.sqlite.db` (one self-contained file that
includes pages still in the WAL), runs `PRAGMA integrity_check`, and prints counts. It refuses to
overwrite an existing backup. Then copy the other two items into the same folder:

```powershell
$dest = (Get-ChildItem backups -Directory | Sort-Object Name | Select-Object -Last 1).FullName
Copy-Item src\FunkyFreshFarm.UmbracoLab\appsettings.Local.json $dest
Copy-Item src\FunkyFreshFarm.UmbracoLab\wwwroot\media "$dest\media" -Recurse
```

The lab's run: integrity `ok`, 79 tables, 7 documents (6 published), 4 media items, 1 user.

### Option B: cold backup with the app stopped (tested in Milestone 1)

Stop the app with Ctrl+C, then copy `Umbraco.sqlite.db*`, `appsettings.Local.json`, and `wwwroot/media`
into `backups/<stamp>/` (commands in [01-installation.md §11](01-installation.md#11-backup-restore-and-restart)).

### Verify a backup (tested)

```powershell
dotnet run scripts/backup-database.cs -- --verify-only backups/<stamp>/Umbraco.sqlite.db
```

Expect `Integrity check : ok` and plausible counts. A backup that has not been verified is not a backup.

### Restore (not executed: overwrites the live database, requires the owner's explicit approval)

1. Stop the app (Ctrl+C) and confirm `Get-Process -Name FunkyFreshFarm.UmbracoLab` returns nothing.
2. **Take a hot or cold backup of the current state first** (Option A or B), so the restore is reversible.
3. Move, don't delete, the current files into a dated `backups/<stamp>-pre-restore/` folder:
   `Umbraco.sqlite.db*`, `appsettings.Local.json`, `wwwroot/media`.
4. Copy the chosen backup's `Umbraco.sqlite.db` into `umbraco/Data/` (a hot backup has no `-wal`/`-shm`
   files, which is correct), `appsettings.Local.json` into the project folder, and `media` into `wwwroot/`.
5. Delete only `umbraco/Data/TEMP/` (rebuildable: indexes, models, image cache).
6. Start the app; check `serverStatus` is `Run`; run `Test-Site.ps1`, `Test-DeliveryApi.ps1` (wait about
   a minute for the index), and log in to the backoffice.

**Restore drill without risk:** verifying the backup file with `--verify-only` exercises everything
except the file swap. A full drill would run a second copy of the app against a restored copy on
other ports. That was not done in this milestone.
