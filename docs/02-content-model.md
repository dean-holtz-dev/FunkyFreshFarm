# 02 — Content Model and Razor Rendering

Milestone 2 turns the empty Umbraco installation into a small fictional farm website: a homepage,
a plant directory with plant detail pages, and a growing guide, all edited in the backoffice and
rendered with Razor.

Contents:

1. [Why Umbraco models content this way](#1-why-umbraco-models-content-this-way)
2. [Concepts](#2-concepts)
3. [Document Types and Data Types](#3-document-types-and-data-types)
4. [Content tree and URLs](#4-content-tree-and-urls)
5. [Backoffice recreation instructions](#5-backoffice-recreation-instructions)
6. [Demonstration content](#6-demonstration-content)
7. [Templates and the shared layout](#7-templates-and-the-shared-layout)
8. [Content versus code ownership](#8-content-versus-code-ownership)
9. [Razor implementation](#9-razor-implementation)
10. [Publishing lifecycle](#10-publishing-lifecycle)
11. [Relevant files and classes](#11-relevant-files-and-classes)
12. [Debugging suggestions](#12-debugging-suggestions)
13. [Testing the public site](#13-testing-the-public-site)

---

## 1. Why Umbraco models content this way

In a conventional ASP.NET Core application, the developer owns the schema. Entities are C#
classes, the database follows through EF Core migrations, routes are declared in code, and a
controller decides which view to render. Changing the shape of a page means a code change and a
deployment.

Umbraco is built for a different division of labour. **Editors** own the content, and the
**schema of the content** is data that the CMS can inspect at runtime:

- **Schema as data.** A Document Type is stored in the database, not compiled into the
  application. The backoffice reads it to generate editing forms and validation, and to decide what may
  be created where. A new property needs no EF migration: values live in a generic table
  (`umbracoPropertyData`: one row per property, per content version), so any Document Type can be
  stored without schema changes.
- **Versioned, workflow-aware content.** Content is stored as *versions*, and "published" and
  "draft" are separate states of the same node, so editors can prepare changes without affecting
  the live site, preview them, roll back, and schedule publishing. (Exactly when a new version is
  created is observed in §10.)
- **The tree is the information architecture.** A page's URL comes from its position in the
  content tree and its Name; navigation follows the tree, and permissions can be granted
  per branch. "Allowed child node types" make the tree enforce the site structure.
- **Reads are served from a published cache.** The public site does not query the database per
  request. Published content is held in Umbraco's cache (a HybridCache in 17.x), and Razor reads
  strongly typed or dynamic views of it.

The trade-off is that a significant part of the application now lives in the database, not in
Git. Section 8 covers what that means for this project.

| Concern | Conventional ASP.NET Core | Umbraco |
|---|---|---|
| Schema | C# entities + EF migrations | Document Types stored in the database; generic property storage |
| Who changes the schema | Developers, via deployment | Developers (or trusted admins) in the backoffice, at runtime |
| Routing | Route templates in code | URL derived from the content tree; resolved dynamically |
| Controllers | Required for every page | Optional; a default controller renders the node's template |
| View model | Built by the developer | `IPublishedContent`, or a Models Builder class generated from the Document Type |
| Validation | Data annotations / FluentValidation | Per-property settings on the Document Type (mandatory, regex) |
| Draft vs live | Usually not modelled | Built in: versions, draft/published states, scheduling |
| Deployable state | Build output | Build output **plus** database (schema + content) **plus** media files |

## 2. Concepts

| Concept | Meaning | Stored in |
|---|---|---|
| **Document Type** | The schema for one kind of page: properties, structure rules, allowed templates | Database (`cmsContentType`, `cmsPropertyType`, `cmsPropertyTypeGroup`, `cmsContentTypeAllowedContentType`) |
| **Property** | A field on a Document Type: name, **alias**, Data Type, validation | Database (`cmsPropertyType`) |
| **Data Type** | A *configured* property editor. The editor supplies the UI and value conversion; the Data Type supplies its settings (for example the list of radio options). One Data Type can back many properties | Database (`umbracoDataType`; settings as JSON in `config`) |
| **Property editor** | The underlying editor, identified by a schema alias (e.g. `Umbraco.RadioButtonList`) and a UI alias (e.g. `Umb.PropertyEditorUi.RadioButtonList`) | Code (Umbraco packages) |
| **Template** | A Razor file plus a database record. Document Types list *allowed* templates and a *default*; each content node uses one of them | Record: database (`cmsTemplate`, `cmsDocumentType`). Markup: `Views/{alias}.cshtml` |
| **Content node** | A page: an instance of a Document Type at a position in the tree, with a Name, property values, versions, and publish state | Database (`umbracoNode`, `umbracoContent*`, `umbracoDocument*`, `umbracoPropertyData`) |
| **Alias** | The stable identifier code uses (`plantPage`, `commonName`). Models Builder turns aliases into C# names (`PlantPage.CommonName`). Display names can change freely; **renaming an alias breaks code** | Database |
| **Allowed child node types** | Which Document Types may be created beneath a node of this type; drives the backoffice "Create" menu | Database |
| **Media item** | An uploaded file plus metadata, itself typed by a Media Type (`Image`, `File`, ...) | Metadata: database. File: `wwwroot/media/` |

## 3. Document Types and Data Types

All four Document Types are created **with a template**, have one property group named
`Content`, and do not vary by culture. Aliases are exact; Models Builder class names are shown in
parentheses.

### Data Type: Sun Exposure (new)

| Setting | Value |
|---|---|
| Name | `Sun Exposure` |
| Property editor | **Radio Button List** (`Umbraco.RadioButtonList`) |
| Options, in order | `Full Sun`, `Partial Sun`, `Shade` |

The stored value is the selected option's text. Renaming an option later does **not** rewrite
values already saved on content, which keep the old text, so treat option text like an alias.

All other properties use built-in Data Types created by the installer.

Property display names below are the ones configured in this lab. Names are cosmetic and can
change freely; **aliases** are what code depends on.

Note the casing difference: Document Type aliases are camelCase (`homePage`), but the template
that Umbraco 17.8.1 creates alongside a Document Type gets a **PascalCase** alias (`HomePage`), and
its file is named after that (`Views/HomePage.cshtml`). Windows hides the difference because its
filesystem is case-insensitive; Linux would not.

### Home Page: `homePage` (model `HomePage`, template `HomePage`)

| Property | Alias | Data Type | Mandatory |
|---|---|---|---|
| Hero Headline | `heroHeadline` | Textstring | **Yes** |
| Intro Text | `introText` | Textarea | No |

Structure: **Allow at root** on. Allowed child node types: Plant Index Page, Guide Page.

### Plant Index Page: `plantIndexPage` (model `PlantIndexPage`, template `PlantIndexPage`)

| Property | Alias | Data Type | Mandatory |
|---|---|---|---|
| Page Title | `pageTitle` | Textstring | No (falls back to the node Name) |
| Intro Text | `introText` | Textarea | No |

Structure: allowed child node types: Plant Page. The list of plants is **not** a property; it is
the node's published children.

### Plant Page: `plantPage` (model `PlantPage`, template `PlantPage`)

| Property | Alias | Data Type | Mandatory |
|---|---|---|---|
| Common Name | `commonName` | Textstring | No (falls back to the node Name) |
| Scientific Name | `scientificName` | Textstring | No |
| Description | `description` | Textarea | No |
| Sun Exposure | `sunExposure` | Sun Exposure | No |
| Plant Image | `plantImage` | Image Media Picker | No |

Structure: no children. `plantImage` is named generically so it can hold a photograph or an
illustration (Milestone 5), and avoids clashing with the generated `Image` media model class.
The built-in **Image Media Picker** Data Type allows a single item of media type `Image` only.

### Guide Page: `guidePage` (model `GuidePage`, template `GuidePage`)

| Property | Alias | Data Type | Mandatory |
|---|---|---|---|
| Page Title | `pageTitle` | Textstring | No (falls back to the node Name) |
| Body Text | `bodyText` | Richtext editor | No |

Structure: no children. `bodyText` is the only property rendered as HTML; every other value is
plain text and HTML-encoded on output.

### Deliberately not used

No compositions, element types, block editors, culture variants, or custom property editors.
`pageTitle` and `introText` are repeated on two Document Types; a shared composition would remove
the repetition, but is not worth the extra concept for four types.

## 4. Content tree and URLs

```text
Home                     homePage         /
├── Plants               plantIndexPage   /plants/
│   ├── Heirloom Tomato  plantPage        /plants/heirloom-tomato/
│   ├── Basil            plantPage        /plants/basil/
│   └── Zinnia           plantPage        /plants/zinnia/
└── Growing Guide        guidePage        /growing-guide/
```

- **Plants** and **Growing Guide** are both children of Home and siblings of each other (tree
  level 2). The three plants are children of Plants (level 3). Growing Guide is not inside Plants.
- The root node is served at `/` because `Umbraco:CMS:Global:HideTopLevelNodeFromPath` defaults
  to `true`.
- URL segments come from node Names (lower-cased, spaces to hyphens). Renaming a published node
  changes its URL; Umbraco records a redirect automatically.
- Navigation renders Home followed by Home's published children.

## 5. Backoffice recreation instructions

Use this section to build the content model the first time, or to recreate it on a fresh clone:
the model lives only in the database (see §8). Each part follows the lab's human-in-the-loop
standard (see `CLAUDE.md`): purpose, starting location, steps, input values, saving, expected
result, verification, troubleshooting, and stop point.

**Status in this lab:** Parts 0–E were completed by the owner on 2026-11-15. Claude Code verified
Checkpoint C (after one fix: `heroHeadline` was not mandatory) and Checkpoint E.

### Backoffice orientation

| Term | Where it is |
|---|---|
| **Section bar** | Across the top of the backoffice: **Content**, **Media**, **Settings**, **Packages**, **Members**, **Users**, **Translation** |
| **Tree** | The left-hand panel of the current section. In **Settings** it is grouped under headings such as **Structure** (Document Types, Data Types, …) and **Templating** (Templates, …) |
| **Actions menu** | Hover a tree item and select the **…** button that appears beside it. **Create** is in that menu |
| **Workspace** | The main editing area on the right, with its own tabs (for example **Design**, **Structure**, **Templates** on a Document Type) and action buttons at the bottom right (**Save**, **Save and publish**) |
| **Available configurations** vs **Create new** | When picking a property editor, *Available configurations* lists existing Data Types; *Create new* makes a new Data Type. In this guide, always pick from *Available configurations* unless told otherwise |

**UI-label confidence.** Labels in bold were checked against the 17.8.1 backoffice language file
(`src/Umbraco.Web.UI.Client/src/assets/lang/en.ts`). Where the exact control is uncertain, the step
says so.

### Part 0 — Start the application and sign in

| | |
|---|---|
| **Purpose** | The backoffice is part of the running web application; every configuration step below happens there |
| **Starting location** | A PowerShell window (Windows PowerShell 5.1 or PowerShell 7) |
| **Stop point** | Continue to Part A |

1. Go to the repository root:

   ```powershell
   Set-Location C:\dev\FunkyFreshFarm
   ```

2. Start the application and leave this window open:

   ```powershell
   dotnet run --project src/FunkyFreshFarm.UmbracoLab --launch-profile Umbraco.Web.UI
   ```

3. Wait for the line `Application started. Press Ctrl+C to shut down.`
4. In a browser, open `https://localhost:44370/umbraco` and log in with the administrator account.

**Expected result:** the backoffice opens with the section bar across the top.
**Verification:** in **Settings → Document Types**, no Funky Fresh Farm Document Types exist yet (on a fresh database).
**Troubleshooting:**

| Symptom | Cause / action |
|---|---|
| `Failed to bind to address ... address already in use` | Another instance is running. Run `Get-Process -Name FunkyFreshFarm.UmbracoLab` and stop it |
| Login fails with `ID2083` | You used `http://`. Use `https://localhost:44370/umbraco` |
| Certificate warning | Run `dotnet dev-certs https --trust` once (see `01-installation.md` §3) |
| The installer appears instead of the login | No database is configured: install first (`01-installation.md` §6) or restore a backup (§11) |

### Part A — Create the Sun Exposure Data Type

| | |
|---|---|
| **Purpose** | Give `sunExposure` a fixed vocabulary. A **Data Type** is a configured property editor: here, the built-in *Radio Button List* editor plus our three options. Any property that uses this Data Type shares its options |
| **Starting location** | Backoffice → **Settings** section |
| **Stop point** | Continue to Part B |

| Field | Value |
|---|---|
| Name | `Sun Exposure` |
| Property editor | **Radio Button List** |
| Options (**Add option**), in this order | `Full Sun`, `Partial Sun`, `Shade` |

1. Select **Settings** in the section bar.
2. In the tree, hover **Data Types** → select **…** → **Create** → **Data Type**.
3. In the name field at the top of the workspace, enter `Sun Exposure`.
4. Select **Select a property editor**. In the dialog, type `Radio` in the search box and choose **Radio Button List**.
5. In the **Add option** setting, enter `Full Sun`. Add a second option `Partial Sun` and a third
   option `Shade`. *(Uncertain: the control that adds another row may appear as an **Add** button or
   a **+**; use whichever is shown.)*
6. Select **Save** (bottom right).

**Expected result:** a "saved" notification; **Sun Exposure** appears under **Data Types**.
**Verification:** reopen **Sun Exposure**: the editor is *Radio Button List* and the options appear in the order above.
**Troubleshooting:**

| Symptom | Cause / action |
|---|---|
| You edited the built-in **Radiobox** Data Type instead | That is a shared built-in. Remove the options you added to it, then create **Sun Exposure** as a new Data Type |
| Options in the wrong order | Drag them into order (each row has a drag handle), then **Save** |

### Part B — Create the leaf Document Types: Plant Page and Guide Page

| | |
|---|---|
| **Purpose** | Define the schema for plant detail pages and the guide page. A **Document Type** is the schema for one kind of page; creating it *with a template* also creates a template record and a starter Razor file `Views/{TemplateAlias}.cshtml`. Leaf types are created first so they exist when the parent types' allowed children are chosen in Part C |
| **Starting location** | Backoffice → **Settings** section |
| **Stop point** | Continue to Part C |

**Plant Page** (Document Type alias `plantPage`; template alias `PlantPage`):

| Property name | Alias | Data Type (from *Available configurations*) | Mandatory |
|---|---|---|---|
| Common Name | `commonName` | Textstring | Off |
| Scientific Name | `scientificName` | Textstring | Off |
| Description | `description` | Textarea | Off |
| Sun Exposure | `sunExposure` | Sun Exposure | Off |
| Plant Image | `plantImage` | Image Media Picker | Off |

1. In the **Settings** tree, hover **Document Types** → **…** → **Create** → **Document Type with Template**.
2. In the name field at the top, enter `Plant Page`. The alias is generated beside it; confirm it
   reads `plantPage`. Select the lock icon only if you need to correct it.
3. *(Optional, cosmetic)* select the icon beside the name and pick one.
4. On the **Design** tab, select **Add group** and name the group `Content`.
5. For each row in the table, inside the **Content** group:
   1. Select **Add property**.
   2. Enter the property name; confirm the generated alias matches the table.
   3. Select **Select a property editor**, search for the Data Type name, and choose it under
      **Available configurations** (not **Create new**).
   4. Leave **Mandatory** (in the **Validation** section) off.
   5. Select **Submit**.
6. On the **Structure** tab, leave **Allow at root** off and **Allowed child node types** empty.
7. On the **Templates** tab, confirm **Plant Page** is listed under **Allowed Templates** and marked as the default.
8. Select **Save**.

**Guide Page** (Document Type alias `guidePage`; template alias `GuidePage`): repeat steps 1–8 with
name `Guide Page` and these properties:

| Property name | Alias | Data Type | Mandatory |
|---|---|---|---|
| Page Title | `pageTitle` | Textstring | Off |
| Body Text | `bodyText` | Richtext editor | Off |

**Expected result:** **Document Types** lists Plant Page and Guide Page; **Settings → Templates**
lists Plant Page and Guide Page.
**Verification:** each property shows the alias and Data Type from the tables. The template files exist:

```powershell
Get-ChildItem C:\dev\FunkyFreshFarm\src\FunkyFreshFarm.UmbracoLab\Views\*.cshtml
```

**Troubleshooting:**

| Symptom | Cause / action |
|---|---|
| Alias is not what the table shows (e.g. `plantPage1`) | A type with that alias already exists, or the name was typed differently. Correct it with the lock icon before saving content against it |
| No template was created | You chose **Document Type** instead of **Document Type with Template**. Delete the type and recreate it |
| A Data Type named like `Textstring (1)` appears | **Create new** was used. Point the property at the built-in Data Type and delete the duplicate |

### Part C — Create the parent Document Types: Plant Index Page and Home Page

| | |
|---|---|
| **Purpose** | Define the directory and home page, and the **structure rules** that shape the tree: only Home may be created at the root; only Plant Index Page and Guide Page may be created under Home; only Plant Page may be created under Plant Index Page |
| **Starting location** | Backoffice → **Settings** section |
| **Stop point** | **Wait.** Tell Claude Code `Checkpoint C done` and wait for its verification |

**Plant Index Page** (alias `plantIndexPage`; template `PlantIndexPage`):

| Property name | Alias | Data Type | Mandatory |
|---|---|---|---|
| Page Title | `pageTitle` | Textstring | Off |
| Intro Text | `introText` | Textarea | Off |

| Structure setting | Value |
|---|---|
| Allow at root | Off |
| Allowed child node types | Plant Page |

**Home Page** (alias `homePage`; template `HomePage`):

| Property name | Alias | Data Type | Mandatory |
|---|---|---|---|
| Hero Headline | `heroHeadline` | Textstring | **On** |
| Intro Text | `introText` | Textarea | Off |

| Structure setting | Value |
|---|---|
| Allow at root | **On** |
| Allowed child node types | Plant Index Page, Guide Page |

1. Create **Plant Index Page** with steps 1–5 of Part B and the property table above.
2. On its **Structure** tab, under **Allowed child node types**, select **Choose** and pick **Plant Page**. Leave **Allow at root** off.
3. Select **Save**.
4. Create **Home Page** with steps 1–5 of Part B. For **Hero Headline**, turn **Mandatory** on in the
   **Validation** section of the property dialog before selecting **Submit**. (This toggle is easy to
   miss; it was missed on the first pass in this lab and caught at Checkpoint C.)
5. On its **Structure** tab, turn **Allow at root** on. Under **Allowed child node types**, select
   **Choose** and pick **Plant Index Page** and **Guide Page**.
6. Select **Save**.

**Expected result:** four Document Types and four templates exist.
**Verification:** reopen each type's **Structure** tab and compare with the tables;
`Views\` now also contains `HomePage.cshtml` and `PlantIndexPage.cshtml`.
**Troubleshooting:**

| Symptom | Cause / action |
|---|---|
| Plant Page is not offered under **Choose** | It was not saved in Part B, or it was created as an *Element Type* |
| Later, **Create** under Content offers nothing | **Allow at root** is off on Home Page |

**Claude Code's verification (Checkpoint C):** template files and their `@inherits` model types;
then every Document Type alias, property alias, Data Type, mandatory flag, allowed child type, and
default template, read from a read-only database snapshot (§12).

### Part D — Upload the placeholder images to the Media library

| | |
|---|---|
| **Purpose** | Put the images in Umbraco's **Media** library so pages can reference them. Media items are typed (**Image**, **File**, **Folder**, …) and stored separately from content; a page stores a *reference* (the media item's key), not the file path, so a media item can be moved or replaced without editing pages |
| **Starting location** | Backoffice → **Media** section. Source files: `C:\dev\FunkyFreshFarm\assets\placeholder-images\` |
| **Stop point** | Continue to Part E (Claude Code verifies the media at Checkpoint E) |

| Media item name | Type | File to upload | Parent |
|---|---|---|---|
| `Plants` | Folder | — | Media root |
| `Heirloom Tomato` | Image | `heirloom-tomato.png` | Plants |
| `Basil` | Image | `basil.png` | Plants |
| `Zinnia` | Image | `zinnia.png` | Plants |

1. Select **Media** in the section bar.
2. Hover **Media** at the top of the tree → **…** → **Create** → **Folder**. Name it `Plants` → **Save**.
3. Hover **Plants** → **…** → **Create** → **Image**.
4. Enter the name `Heirloom Tomato`.
5. In the file area, select **Click to upload** and choose `heirloom-tomato.png`, or drag the file onto
   the area labelled **Drag and drop your file(s) into the area**.
6. Select **Save**.
7. Repeat steps 3–6 for `Basil` (`basil.png`) and `Zinnia` (`zinnia.png`).

**Expected result:** the **Plants** folder shows three images with thumbnails.
**Verification:** the uploaded files exist on disk (each in a randomly named folder):

```powershell
Get-ChildItem C:\dev\FunkyFreshFarm\src\FunkyFreshFarm.UmbracoLab\wwwroot\media -Recurse -File
```

**Troubleshooting:**

| Symptom | Cause / action |
|---|---|
| An image was created at the Media root | Hover it → **…** → move it into **Plants** |
| An SVG upload cannot be picked later | SVGs become the *Vector Graphics (SVG)* media type, which the Image Media Picker does not accept. Use PNG or JPG |

### Part E — Create and publish the content

| | |
|---|---|
| **Purpose** | Create the pages. A **content node** is an instance of a Document Type at a position in the tree; its Name becomes its URL segment. **Save and publish** makes the current version public; parents must be published before their children are reachable |
| **Starting location** | Backoffice → **Content** section |
| **Stop point** | **Wait.** Tell Claude Code `Checkpoint E done` and wait for its verification |

Target hierarchy: **Plants** and **Growing Guide** are both children of **Home**, and siblings of
each other. Growing Guide is **not** inside Plants.

```text
Home                         (Home Page, at the root)
├── Plants                   (Plant Index Page, child of Home)
│   ├── Heirloom Tomato      (Plant Page, child of Plants)
│   ├── Basil                (Plant Page, child of Plants)
│   └── Zinnia               (Plant Page, child of Plants)
└── Growing Guide            (Guide Page, child of Home, sibling of Plants)
```

Field values for every page are in §6.

1. **Home.** Select **Content** in the section bar. Hover **Content** at the top of the tree → **…** →
   **Create**. In the dialog (**Create an item under Content**), choose **Home Page**. Enter the name
   `Home` in the name field at the top, fill **Hero Headline** and **Intro Text** from §6, then select
   **Save and publish** (bottom right). *(If a confirmation dialog appears, confirm the publish.)*
2. **Plants.** Hover **Home** → **…** → **Create** → **Plant Index Page**. Name `Plants`; fill the fields
   → **Save and publish**.
3. **The three plants.** Hover **Plants** → **…** → **Create** → **Plant Page**. Name it, fill the fields
   from §6, and for **Plant Image** select **Choose** to open the **Choose media** dialog, open the
   **Plants** folder, select the matching image, and confirm the selection *(the confirm button's
   label was not verified; it is at the bottom of the dialog)*. **Save and publish**. Repeat for each plant:
   - Heirloom Tomato: image **Heirloom Tomato**.
   - Basil: image **Basil**; leave **Common Name empty** (tests the fallback to the node Name).
   - Zinnia: **no image** (tests the missing-image fallback).
4. **Growing Guide.** Hover **Home** (not Plants) → **…** → **Create** → **Guide Page**. Name
   `Growing Guide`; fill **Page Title**; enter the body as described in §6 → **Save and publish**.

**Expected result:** the tree matches the diagram; no node shows an unpublished or draft state.
**Verification:** open each node's **Info** tab: **Links** shows its URL (for example
`/plants/basil/`). Each URL in §4 returns HTTP 200:

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" https://localhost:44370/plants/basil/
```

**Troubleshooting:**

| Symptom | Cause / action |
|---|---|
| **Home Page** is not offered under Content | **Allow at root** is off on Home Page (Part C) |
| **Plant Page** is not offered under Plants | Plant Index Page's allowed child types (Part C) |
| **Save and publish** on Home is rejected | **Hero Headline** is mandatory and empty |
| A page URL returns 404 | The page or one of its ancestors is not published, or it was created under the wrong parent |
| The plant image is missing from **Choose media** | The item is not of media type **Image** |

**Claude Code's verification (Checkpoint E):** from a read-only database snapshot, the tree,
levels, publish/draft state, templates, every published property value, and that each
`plantImage` points at the right media key; the uploaded files match the placeholder sources
byte-for-byte; every public route's status code; and the classes and property types in the
generated `models.generated.cs`.

## 6. Demonstration content

All content is fictional demonstration text. Copy each value from its block.

### Home (Home Page)

Name: `Home`

Hero headline:

```text
Fresh from our fields to your garden
```

Introductory text (two lines; keep the line break):

```text
Funky Fresh Farm is a small, fictional family farm growing heirloom vegetables, fragrant herbs, and cheerful flowers.
Browse the plant directory or read our growing guide to get started.
```

### Plants (Plant Index Page)

Name: `Plants`

Page title:

```text
Our Plants
```

Introductory text:

```text
Everything we grow, with notes on the conditions each plant enjoys.
```

### Heirloom Tomato (Plant Page)

Name: `Heirloom Tomato` · Common name: `Heirloom Tomato` · Scientific name: `Solanum lycopersicum` ·
Sun exposure: **Full Sun** · Plant image: media item **Heirloom Tomato**

Description:

```text
Grown from seed saved season after season, our heirloom tomatoes ripen to a deep red with a sweet, old-fashioned flavor.
Stake plants early and water at the base to keep the leaves dry.
```

### Basil (Plant Page)

Name: `Basil` · Common name: *(leave empty; the page falls back to the Name)* · Scientific name:
`Ocimum basilicum` · Sun exposure: **Full Sun** · Plant image: media item **Basil**

Description:

```text
A fragrant, fast-growing herb for pesto, salads, and summer cooking.
Pinch off flower buds to keep the leaves coming.
```

### Zinnia (Plant Page)

Name: `Zinnia` · Common name: `Zinnia` · Scientific name: `Zinnia elegans` · Sun exposure:
**Full Sun** · Plant image: *(leave empty; tests the missing-image fallback)*

Description:

```text
Bright, long-lasting blooms in every color of the sunset. Zinnias love summer heat and attract butterflies.
Cut flowers often: the more you pick, the more they bloom.
```

*Milestone 3's tracing exercise added a third line, `Sow seeds directly in warm soil after the
last frost.` (see 03-api-and-extensions.md §10). Neither smoke test depends on Zinnia's description.*

### Growing Guide (Guide Page)

Name: `Growing Guide`

Page title:

```text
A Beginner's Growing Guide
```

Body Text. The default **Richtext editor** toolbar in 17.8.1 has **no heading button**. Its
buttons are: Source code, Bold, Italic, Underline, three alignment buttons, Bulleted list,
Numbered list, Blockquote, Horizontal rule, Link, Unlink, Media, Embed. Headings are still
supported by the editor, so use one of these two methods:

**Method 1: paste HTML (most reliable).** Select the **Source code** button (the first toolbar
button), replace the contents with the block below, and confirm the dialog.

```html
<h2>Start with healthy soil</h2>
<p>Mix compost into your beds before planting. Healthy soil holds moisture and feeds roots all season.</p>
<h2>Water wisely</h2>
<ul>
<li>Water deeply and less often.</li>
<li>Water in the morning, at the base of the plant.</li>
<li>Mulch to keep moisture in the soil.</li>
</ul>
<h2>Match plants to the light</h2>
<p>Check each plant's <strong>sun exposure</strong> in our plant directory before choosing a spot.</p>
```

**Method 2: type it.** Start a line with `##` followed by a space to turn it into a Heading 2 (an
editor shortcut; it was not checked against the 17.8.1 source). Use the **Bulleted list** button
for the list and **Bold** for *sun exposure*. The intended structure:

- Heading 2: `Start with healthy soil`
- Paragraph: `Mix compost into your beds before planting. Healthy soil holds moisture and feeds roots all season.`
- Heading 2: `Water wisely`
- Bulleted list, three items:
  - `Water deeply and less often.`
  - `Water in the morning, at the base of the plant.`
  - `Mulch to keep moisture in the soil.`
- Heading 2: `Match plants to the light`
- Paragraph, with the words *sun exposure* in **bold**:
  `Check each plant's sun exposure in our plant directory before choosing a spot.`

**As entered in this lab:** the published body matches this structure but contains the typo
"before **planing**" (instead of "planting"). It is left in place for now. Fixing it is a natural
first edit for the publishing exercise in §10.

## 7. Templates and the shared layout

This project uses a **code-owned layout**: `Views/_Layout.cshtml` is an ordinary Razor layout
file in Git, and each page template sets `Layout = "_Layout.cshtml";`. Umbraco's own convention
is a **backoffice master template**: a template created under Settings → Templates and chosen as
the *master* of each page template. Both render identically; they differ in where the
relationship is recorded.

| Aspect | Code-owned `_Layout.cshtml` (this project) | Backoffice master template |
|---|---|---|
| How it is created | Developer adds the file to `Views/` | Settings → Templates → Create; then each page template's master is set |
| Database | **Nothing**. The layout is invisible to Umbraco | A template record (`cmsTemplate` + `umbracoNode`); each child template's node is stored *under* the master's node |
| Filesystem | `Views/_Layout.cshtml` | `Views/{masterAlias}.cshtml` |
| Link from page template | `Layout = "_Layout.cshtml";` written by hand | The backoffice writes `Layout = "{masterAlias}.cshtml";` into the child file when the master is chosen |
| Visible/editable in backoffice | No | Yes, under Settings → Templates |
| Rename | Code change | Backoffice rename updates record and file |
| Why chosen | Editors never choose a layout, so it does not need a database record; one fewer artefact to recreate by hand on a fresh clone | Lets non-developers restructure layouts in the backoffice |

**What remains database-backed either way:** each page template's *record* (alias, name), the
Document Type's *allowed* and *default* templates (`cmsDocumentType`), and the template chosen by
each content node (stored on its version). Umbraco resolves a request to a node, reads that
template alias, and renders `Views/{alias}.cshtml`.

When a Document Type is created **with a template**, Umbraco writes a starter file
(`Umbraco.Core/IO/DefaultViewContentProvider.cs`):

```cshtml
@using Umbraco.Cms.Web.Common.PublishedModels;
@inherits Umbraco.Cms.Web.Common.Views.UmbracoViewPage<ContentModels.PlantPage>
@using ContentModels = Umbraco.Cms.Web.Common.PublishedModels;
@{
	Layout = null;
}
```

From Phase 3 onwards the template **files** are owned by Git. Do not edit them in the backoffice;
in `BackofficeDevelopment` mode the backoffice can write to them, and those edits would show up as
uncommitted changes.

## 8. Content versus code ownership

| Artefact | Owner | Location | In Git |
|---|---|---|---|
| Document Types, properties, aliases, structure rules | Backoffice | Database | **No** |
| Sun Exposure Data Type | Backoffice | Database | **No** |
| Template records and Document Type ↔ template links | Backoffice | Database | **No** |
| Template markup, layout, partials | Code | `Views/` | Yes |
| Stylesheet | Code | `wwwroot/css/site.css` | Yes |
| Pages, text, publish state, versions | Editors | Database | **No** |
| Uploaded media files | Editors | `wwwroot/media/` | **No** |
| Placeholder image sources | Code | `assets/placeholder-images/` | Yes |
| Generated models (InMemoryAuto) | Umbraco, at runtime | `umbraco/Data/TEMP/InMemoryAuto/` | **No** |

### Reproducibility limitations

- **A fresh clone does not reproduce the site.** It contains the Razor views, CSS, and placeholder
  images, but no Document Types, Data Types, template records, content, or media. Recreate them
  with §5 and §6, or restore a database backup (see `01-installation.md` §11).
- **Views depend on database-defined aliases.** Templates use Models Builder classes generated
  from Document Type aliases. With `InMemoryAuto`, those classes exist only at runtime, and the
  project sets `RazorCompileOnBuild=false`, so **`dotnet build` cannot catch an alias mismatch**.
  It surfaces at runtime as a compilation error page. `scripts/Test-Site.ps1` (Phase 5) catches
  it on the published routes.
- **No schema history.** Document Type changes are not versioned in Git. A typo fixed in the
  backoffice leaves no trace in the repository.
- **Possible future options** (not adopted in this milestone): open-source serialization of
  schema to files (for example uSync), code-first migrations using Umbraco's
  `IContentTypeService`, or switching Models Builder to `SourceCodeAuto` so generated models are
  committed and compiled. Umbraco Deploy is commercial and out of scope.

## 9. Razor implementation

### How a template gets its model

No custom controllers are involved. The request path in 17.8.1:

1. `UseWebsiteEndpoints()` (in `Program.cs`) registers a dynamic route handled by
   `UmbracoRouteValueTransformer`. Its `TransformAsync` skips non-document paths (static files,
   `/umbraco/…`) using `IRoutableDocumentFilter`.
2. `PublishedRouter.RouteRequestAsync` runs the **content finders** in order:
   `ContentFinderByPageIdQuery` → **`ContentFinderByUrlNew`** → `ContentFinderByKeyPath` →
   `ContentFinderByUrlAlias` → `ContentFinderByRedirectUrl`. `ContentFinderByUrlNew` asks
   `IDocumentUrlService.GetDocumentKeyByRoute` for the document key of `/plants/basil/`, then loads
   the published node from the published cache. If no finder succeeds, `IContentLastChanceFinder`
   produces the 404.
3. `PublishedRouter.FindTemplate` takes the template chosen on the node (by default, the
   Document Type's default template).
4. `UmbracoRouteValuesFactory` picks the controller. If a controller named after the **Document
   Type alias** exists (for example `PlantPageController : RenderController`), the request is
   "hijacked" to it; otherwise the default `RenderController.Index` is used.
5. `RenderController` renders the view named after the template alias, found at
   `Views/{TemplateAlias}.cshtml`, with the node as the model. The model's runtime type is the
   Models Builder class for the node's Document Type, so `Views/PlantPage.cshtml` can declare
   `UmbracoViewPage<ContentModels.PlantPage>`.

### `IPublishedContent` versus Models Builder models

Every published node is an `IPublishedContent`. Models Builder additionally generates one class
per Document Type (`HomePage`, `PlantPage`, …) that wraps it with typed properties.

| | `IPublishedContent` | Models Builder model |
|---|---|---|
| Reading a value | `Model.Value<string>("commonName")` | `Model.CommonName` |
| Typo in an alias | Silently returns `null` | Fails to compile (at runtime, see below) |
| Value types | You choose the type argument | Generated from the property editor: `string`, `MediaWithCrops`, `IHtmlEncodedString` |
| Works across Document Types | Yes | Only for its own type (use `is PlantPage p` to narrow) |
| Needs regeneration after schema changes | No | Yes (automatic in `InMemoryAuto`) |

**Choice in this project:**

- **Page templates use the generated models.** Each template renders exactly one Document Type,
  so typed properties are clearer and alias typos fail loudly instead of rendering blank.
- **The layout and navigation use `IPublishedContent`** (`UmbracoViewPage` with no type argument),
  because they render for every Document Type and only need `Name`, `Url()`, and tree navigation.
- **Typed child queries:** `Model.Children<PlantPage>()` returns only published children of that
  type, already typed.

**Caveat of `InMemoryAuto`:** the generated classes exist only inside the running application.
IDEs do not see them (expect red squiggles in `.cshtml` files), and the project sets
`RazorCompileOnBuild=false`, so `dotnet build` does not compile views. An alias mismatch appears only
when the page is requested. `scripts/Test-Site.ps1` exists to catch that. `SourceCodeAuto` mode
would write the models into the project so they compile with the build; that is a possible later
change, not part of this milestone.

### Output safety by property type

| Property | Value type | Rendered with | Encoding |
|---|---|---|---|
| Textstring (`heroHeadline`, `pageTitle`, `commonName`, `scientificName`, `sunExposure`) | `string` | `@value` | HTML-encoded by Razor (e.g. `'` becomes `&#x27;`) |
| Textarea (`introText`, `description`) | `string` | `@Html.ReplaceLineBreaks(value)` | HTML-encoded first, then line breaks become `<br />` |
| Richtext editor (`bodyText`) | `IHtmlEncodedString` | `@Model.BodyText` | **Not encoded**: `UmbracoViewPage` writes it as HTML |
| Image Media Picker (`plantImage`) | `MediaWithCrops` | `GetCropUrl(...)` in `src`, name in `alt` | URL attribute-encoded by Razor |

**Rich text is trusted input.** The rich-text editor calls `IHtmlSanitizer.Sanitize` on save, but
Umbraco registers a no-op implementation by default (`NoopHtmlSanitizer`). Anyone allowed to edit
the Growing Guide can therefore place arbitrary HTML, including scripts, on the public site.
That is acceptable for a single-administrator lab. The hardening path is to register a real
`IHtmlSanitizer` implementation.

### Images

`GetCropUrl(width: 480, height: 360, imageCropMode: ImageCropMode.Crop)` produces a URL such as
`/media/yvujazkm/heirloom-tomato.png?width=480&height=360&v=…&hmac=…`. ImageSharp resizes on the
first request and caches the result in `umbraco/Data/TEMP/MediaCache/` (local state, gitignored).
Because `Imaging:HMACSecretKey` is set,
every processing URL carries an `hmac` signature, and ImageSharp rejects a URL whose signature does
not match with HTTP 400. That stops outsiders from making the server generate arbitrary image sizes.
`v=` is a cache buster that changes when the media item changes.

### Graceful handling of missing content

| Situation | Behaviour |
|---|---|
| `commonName` / `pageTitle` empty | Falls back to the node's Name (Basil demonstrates this) |
| `heroHeadline` empty (should be impossible: it is mandatory) | Falls back to the node's Name |
| `plantImage` empty | Directory card shows a striped "No image yet" box; detail page omits the figure (Zinnia) |
| `scientificName`, `introText`, `description` empty | The element is omitted |
| `sunExposure` empty | Detail page shows "Not specified" |
| Plants has no published children | "No plants have been published yet." |
| `bodyText` empty | "This guide has no content yet." |
| Unknown URL | Umbraco's built-in 404 page |
| No published root node at all | Umbraco's built-in "No published content" page (templates are not used) |

### Code-owned text

The site name ("Funky Fresh Farm"), the footer note, and UI labels ("Sun exposure", "Back to …",
"No image yet", the empty-state messages) are part of the templates. They are interface text, not
content. Every heading, paragraph, name, image, and list item inside `<main>` comes from the
content tree. Umbraco's **Dictionary** (Translation section) is the built-in way to move interface
text into the CMS later, if editors need to change it.

## 10. Publishing lifecycle

Phase 4 exercised the lifecycle by hand on 2026-11-15. Each stage was checked with a read-only
database snapshot and public HTTP requests, and matched the 17.8.1 source
(`Umbraco.Infrastructure/Persistence/Repositories/Implement/DocumentRepository.cs:1355-1425`,
`Umbraco.PublishedCache.HybridCache/Services/DocumentCacheService.cs`).

### The model: one node, two states, several versions

| Term | Meaning | Stored in |
|---|---|---|
| **Current version** | The draft editors are working on. Exactly one per document | `umbracoContentVersion.current = 1` |
| **Published version** | The version visitors see. At most one | `umbracoDocumentVersion.published = 1` |
| **Document published flag** | Whether the node is live at all | `umbracoDocument.published` |
| **Edited flag** | Whether the draft differs from the published version ("pending changes") | `umbracoDocument.edited` |
| **Published cache rows** | Serialised draft and published copies used to build the in-memory caches | `cmsContentNu` (`published` = 0 or 1) |
| **Audit trail** | Every save, publish, and unpublish, shown as **History** in the Info view | `umbracoLog` |

**Rules observed in 17.8.1:**

- **Save** overwrites the current version **in place**. No version is created, and the published
  version, the published cache row, and the public site are untouched.
- **Publish** marks the current version published, un-marks the previously published one, and
  **inserts a new current version** for future edits. The published cache row is rewritten and the
  in-memory caches are refreshed, so the change is public immediately.
- **Unpublish** sets the document's published flag to 0 (and `edited` to 1), deletes the
  published cache row, and clears the in-memory published cache. No version is created; content,
  versions, and tree position are kept.
- **Restart** discards only the in-memory caches; they are rebuilt from `cmsContentNu` and the
  content tables. Nothing about publish state lives only in memory.
- Version IDs are global across all content, so they are not consecutive per page.
- **History ≠ versions.** History lists audit entries (every save and publish); versions are created
  only by publishing. Rollback works from versions.

### Evidence from Phase 4

| Stage | Action | Home or Mint state afterwards | Public site |
|---|---|---|---|
| Baseline | — | Home: v5 published, v6 current (same text); `edited=0`; cache rows draft `rv=1`, published `rv=0` | "Fresh from our fields to your garden" |
| A | Edit Hero Headline, **Save** | `edited=1`; **still 2 versions**; v6 updated in place to "Funky flavors, fresh from our fields"; v5 unchanged; only the draft cache row changed (`rv` 1→2) | Unchanged (old headline) |
| B | **Save and publish** | `edited=0`; v5 no longer published; **v6 published**; **new v20 current**; published cache row rewritten (`rv` 0→1); History shows 4 entries (Save, Publish, Save, Publish) | New headline, immediately |
| C | Create **Mint** under Plants, **Save and publish** | Mint: level 3, sort position 4; v21 published, v22 current; both cache rows | Directory lists 4 cards; `/plants/mint/` 200 |
| D | **Unpublish** Mint | `published=0`, `edited=1`, not trashed (grey in the tree); still 2 versions; **published cache row deleted** | Directory lists 3 cards; `/plants/mint/` 404 |
| E | Ctrl+C, then restart | Identical to D for both Home and Mint; the clean shutdown checkpointed SQLite's WAL into the main file | Same as D |

### Published-content caching

A public request for a page looks in three places, in order:

1. **L0**: an in-memory cache of converted `IPublishedContent` objects.
2. **HybridCache** (Microsoft.Extensions.Caching.Hybrid): L1 in memory, plus an optional distributed
   L2, which this lab does not use.
3. **The database**: the published row in `cmsContentNu`, with a guard that hides content whose
   ancestors are unpublished.

Saving and publishing call `DocumentCacheService.RefreshContentAsync`, which always rewrites the
draft row, rewrites the published row when publishing, and deletes it when unpublishing. That is
why publishing shows up without a restart, and why a saved draft never leaks to the public site.

### Things this milestone did not exercise

Scheduled publishing, rollback to an earlier version, preview links for others, culture variants,
and the Recycle Bin (trash and restore).

## 11. Relevant files and classes

### Files (all under `src/FunkyFreshFarm.UmbracoLab/` unless noted)

| File | Owner | Role |
|---|---|---|
| `Views/_Layout.cshtml` | Git | Shared HTML shell: `<head>`, header, navigation, footer; code-owned site name |
| `Views/Partials/Navigation.cshtml` | Git | Root node + its published children; marks current page and section |
| `Views/HomePage.cshtml` | Git (record: DB) | Hero headline and intro |
| `Views/PlantIndexPage.cshtml` | Git (record: DB) | Title, intro, and a card per published Plant Page child |
| `Views/PlantPage.cshtml` | Git (record: DB) | Plant detail: names, image, description, sun exposure |
| `Views/GuidePage.cshtml` | Git (record: DB) | Title and rich-text body |
| `wwwroot/css/site.css` | Git | All styling; no framework, no build step |
| `Views/_ViewImports.cshtml` | Git (template) | `@using Umbraco.Extensions` etc., which make the friendly extension methods available |
| `assets/placeholder-images/*.png` (repo root) | Git | Source files uploaded to the Media library |
| `umbraco/Data/TEMP/InMemoryAuto/models.generated.cs` | Runtime | The generated model classes; read it to check what Razor can use |

### Umbraco classes and APIs used (17.8.1)

| API | Where defined | Used for |
|---|---|---|
| `UmbracoViewPage<TModel>` | `Umbraco.Web.Common/Views/UmbracoViewPage.cs` | Base class of every template; writes `IHtmlEncodedString` values unencoded |
| `IPublishedContent`, `PublishedContentModel` | `Umbraco.Core` | Read-only view of a published node; generated models derive from `PublishedContentModel` |
| `Root()`, `Children()`, `Children<T>()`, `Parent()`, `AncestorsOrSelf()`, `Url()` | `Umbraco.Web.Common/Extensions/FriendlyPublishedContentExtensions.cs` | Tree navigation and URLs; children are published-only and in sort order |
| `MediaWithCrops`, `GetCropUrl(width:, height:, imageCropMode:)` | `Umbraco.Web.Common/Extensions/FriendlyImageCropperTemplateExtensions.cs` | Resized, HMAC-signed image URLs |
| `Html.ReplaceLineBreaks(string)` | `Umbraco.Web.Website/Extensions/HtmlHelperRenderExtensions.cs` → `HtmlStringUtilities` | HTML-encodes text, then turns line breaks into `<br />` |
| `IHtmlEncodedString` | `Umbraco.Core/Strings` | Type of rich-text values; treated as trusted HTML |
| `IHtmlSanitizer` / `NoopHtmlSanitizer` | `Umbraco.Core/Security`; registered in `UmbracoBuilder.cs` | Called on rich-text save; the default does nothing |
| `RenderRazorViewEngineOptionsSetup` | `Umbraco.Web.Website` | Adds view locations `/Views/{0}.cshtml`, `/Views/Shared/{0}.cshtml`, `/Views/Partials/{0}.cshtml` |
| `DefaultViewContentProvider` | `Umbraco.Core/IO` | Writes the starter content of templates created in the backoffice |
| `InMemoryModelFactory` | `Umbraco.Cms.DevelopmentMode.Backoffice/InMemoryAuto` | Generates and compiles models at runtime (`InMemoryAuto` mode) |

## 12. Debugging suggestions

| Symptom | Where to look |
|---|---|
| A page shows a compilation error | The message names the file and line. Most often a property name that does not exist on the generated model: compare with `umbraco/Data/TEMP/InMemoryAuto/models.generated.cs`. `dotnet build` cannot catch this (`RazorCompileOnBuild=false`, models generated at runtime) |
| A page returns 404 | Is the node **and every ancestor** published? Check the node's **Info** tab → **Links** for its URL. Is it in the Recycle Bin? |
| A page renders blank or with the wrong layout | The node's template (Info tab) and the template file's `Layout = "_Layout.cshtml";` line |
| An edited value does not appear | The public site shows the **published** version. **Save** alone changes only the draft; use **Save and publish** |
| A property is always empty | Alias mismatch, or the value is on a different Document Type. Read the generated model for the class's properties |
| An image is missing | `plantImage` empty (by design for Zinnia), or the media item was deleted or trashed. A **400** on an image URL means the HMAC signature did not verify, for example if `appsettings.Local.json` (which holds the key) changed |
| Navigation is missing a page | Only Home and Home's **published** children appear; check publish state and tree position |

**Diagnostics that need no debugger:**

- Request the page from PowerShell and look at the markup:
  `curl.exe -s https://localhost:44370/plants/`
- Turn on Umbraco's debug logging for one run: start the app with
  `$env:Serilog__MinimumLevel__Default = 'Debug'` set in the same window.
- Read the structured log: `umbraco/Logs/UmbracoTraceLog.<machine>.<yyyyMMdd>.json`, or
  **Settings → Log Viewer** in the backoffice.
- Inspect database state without touching it: copy the live database with SQLite's online backup
  API from a read-only connection (`SqliteConnection.BackupDatabase`), then query the copy. This is
  how Claude Code verified Checkpoints C and E. Never write to the live database.

**Breakpoints (VS Code + C# Dev Kit, or Visual Studio 2026):**

- Umbraco routing internals, with "Just My Code" off: `UmbracoRouteValueTransformer.TransformAsync`
  (entry point for every content URL), `PublishedRouter.FindPublishedContent` (runs the content
  finders), `ContentFinderByUrlNew.TryFindContent` (route → document key via
  `IDocumentUrlService.GetDocumentKeyByRoute`), `UmbracoRouteValuesFactory.CreateAsync` (chooses
  the controller and action), and `RenderController.Index` (the default controller that renders the
  node's template). In 17.8.1 the older `ContentFinderByUrl` is obsolete and not registered, so a
  breakpoint there never fires.
- Razor views are compiled at runtime in `BackofficeDevelopment` mode; breakpoints inside `.cshtml`
  files may not bind. Inspect values by rendering them temporarily, or move logic into a C# class.

## 13. Testing the public site

`scripts/Test-Site.ps1` is a smoke test for the rendered site. It sends GET requests only, uses no
credentials, and changes nothing. Its one side effect is that ImageSharp may cache a resized image
in `umbraco/Data/TEMP/MediaCache/`.

```powershell
pwsh ./scripts/Test-Site.ps1                                  # https://localhost:44370
pwsh ./scripts/Test-Site.ps1 -BaseUrl http://localhost:41388  # public site over HTTP
```

It also runs in Windows PowerShell 5.1:
`powershell -ExecutionPolicy Bypass -File scripts\Test-Site.ps1`.

| Exit code | Meaning |
|---|---|
| 0 | All checks passed |
| 1 | At least one check failed, including "site not reachable" |
| 2 | The script itself hit an unexpected error |

### What it checks (10 checks)

| Check | Proves |
|---|---|
| Home page | 200 HTML; site title; non-empty hero `<h1>`; navigation links to Plants and Growing Guide; Home marked as current page |
| Plant directory | Title "Our Plants"; Heirloom Tomato, Basil, Zinnia cards **in tree order**; signed 480×360 image URLs for Tomato and Basil; "No image yet" placeholder for Zinnia |
| Heirloom Tomato | Name, scientific name, image figure, "Full Sun", back link, description with a rendered line break |
| Basil | Heading falls back to the node Name (Common Name empty); image figure |
| Zinnia | Heading; scientific name; **no** `<figure>` (missing-image fallback) |
| Growing guide | Title (HTML-encoded apostrophe `&#x27;` in the raw markup); rich text with `<h2>`, `<ul>`, `<strong>` rendered as HTML |
| Stylesheet | `/css/site.css` served as `text/css` |
| Unknown URL | Returns 404 |
| Resized image | The first directory image URL returns `image/*` |
| Tampered image signature | Altering the `hmac` parameter returns 400 |

The checks are a data table at the top of the script. Update it when the baseline content changes.

### Prerequisites for a passing run

1. The application is running (`dotnet run --project src/FunkyFreshFarm.UmbracoLab --launch-profile Umbraco.Web.UI`).
2. For `https://`, the development certificate is trusted (`dotnet dev-certs https --check --trust`
   exits 0). Otherwise use `-BaseUrl http://localhost:41388`.
3. **This published content exists**, as created in §5–§6:

   | Page | Must be published with |
   |---|---|
   | Home (root) | Any non-empty Hero Headline |
   | Plants (child of Home) | Page Title `Our Plants` |
   | Heirloom Tomato (under Plants, first) | Common Name `Heirloom Tomato`, Scientific Name `Solanum lycopersicum`, a two-line Description, Sun Exposure `Full Sun`, a Plant Image |
   | Basil (under Plants, after Tomato) | **Empty** Common Name, Scientific Name `Ocimum basilicum`, a Plant Image |
   | Zinnia (under Plants, after Basil) | Scientific Name `Zinnia elegans`, **no** Plant Image |
   | Growing Guide (child of Home) | Page Title `A Beginner's Growing Guide`; Body Text containing a Heading 2, a bulleted list, and bold text |

   Additional plants, such as Mint, may exist in any state; the checks do not count cards.

### Why not a test framework

The public output is server-rendered HTML whose content lives in a database. A unit-test project
could not exercise it without a running site and a seeded database, and the brief rules out a large
framework for static Razor output. A smoke test against the running site checks the thing that
matters: the published content renders correctly through the real pipeline.
