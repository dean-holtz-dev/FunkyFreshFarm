# 05 — Design System: "Farmstand Funk"

The visual system for the Funky Fresh Farm site (a fictional demonstration site): plain CSS with
custom properties in `src/FunkyFreshFarm.UmbracoLab/wwwroot/css/site.css`, Razor templates, and
self-hosted fonts. There is no framework, no Node build, and no JavaScript. Assets are described in
[05-assets.md](05-assets.md).

## 1. Brand direction

1970s American farmstand signage, vintage seed packets, and festival posters, presented with the
calm layout of a contemporary editorial site. Personality comes from:

- **Expressive typography:** Fraunces, a soft, chunky old-style serif, for headings and the wordmark.
- **Distinctive illustration:** the owner's screen-print style artwork (hero, botanicals, story, guide, 404).
- **Restrained decoration:** four-colour "groovy stripe" bands under the header and above the
  footer, a Coral bar before small eyebrow labels, and one dancing-radish sticker. No animations
  beyond a small card lift on hover, which is disabled for users who prefer reduced motion.

## 2. Colour

### Palette tokens

| Token | Value | Role |
|---|---|---|
| `--color-basil` | `#285C47` Basil Green | Headings, links, primary buttons |
| `--color-coral` | `#E4583E` Tomato Coral | Decoration only: stripes, eyebrow bar, list markers |
| `--color-marigold` | `#F3BB48` Marigold Yellow | Call-to-action button background, focus ring on dark |
| `--color-cream` | `#FFF5DC` Warm Cream | Page background (matches the illustrations' paper) |
| `--color-eggplant` | `#3E2A47` Eggplant | Body text, hero headline, footer background, focus ring |
| `--color-mint` | `#A9D7C3` Pale Mint | Active navigation pill, sun badges, facts panel, story panel |

Derived tokens: `--color-surface: #fffbf0` (cards), `--color-border: #e9dcc0`.

### Contrast (WCAG 2.x, computed)

| Foreground on background | Ratio | Use |
|---|---|---|
| Eggplant on Cream | **11.89:1** (AAA) | Body text |
| Basil on Cream | **7.13:1** (AAA) | Headings, links |
| Cream on Basil | 7.13:1 (AAA) | Primary button |
| Eggplant on Marigold | **7.38:1** (AAA) | Call-to-action button |
| Eggplant on Mint | 8.11:1 (AAA) | Nav pill, sun badge, facts panel |
| Cream on Eggplant | 11.89:1 (AAA) | Footer text |
| Mint / Marigold on Eggplant | 8.11 / 7.38:1 | Footer links / hover, footer focus ring |
| Coral on Cream | 3.36:1 | **Large text or decoration only**; never body text |
| Marigold on Cream | 1.61:1 | **Never text**; decoration only |

## 3. Typography

| Role | Font | Size token | Notes |
|---|---|---|---|
| Wordmark, headings | Fraunces (variable 400–800), fallback Georgia | `--step-2` … `--step-4` | `h1` 800, `h2`/`h3` 700; `text-wrap: balance` |
| Body, UI | DM Sans (variable 400–700, normal and italic), fallback system UI | `--step-0` (16–17 px) | Line height 1.65; scientific names in true italic |
| Small labels | DM Sans 700, uppercase, 0.12em tracking | `--step--1` | "Eyebrow" labels with a Coral bar |

The scale is fluid (`clamp()`): `--step--1` 13.4–14.4 px up to `--step-4` 34–54 px. Prose is capped
at `--width-prose: 40rem` (about 70 characters) for reading comfort.

**Licensing (verified):** both families are under the SIL Open Font License 1.1 (Fraunces © 2018
The Fraunces Project Authors; DM Sans © 2014 The DM Sans Project Authors). OFL permits bundling and
self-hosting with the licence included (`wwwroot/fonts/OFL-*.txt`). Fonts are self-hosted rather than
loaded from Google's CDN, so visitors' browsers make no third-party requests. Two WOFF2 files are
preloaded; `font-display: swap` shows fallback text immediately.

## 4. Layout, spacing, and hierarchy

- **One content width** (`--width-content: 80rem`) for header, hero, sections, and footer; gutters
  `--gutter` scale from 16 to 32 px. Prose uses `--width-prose`.
- **Spacing scale:** `--space-2xs` … `--space-2xl` (4 px to 80 px, fluid at the upper end).
- **Shape:** radii `--radius-s/m/l/pill`; two shadows (`--shadow-card`, `--shadow-lift`) tinted with Eggplant.
- **Hierarchy per page:** eyebrow label → Fraunces `h1` → italic subtitle or lead paragraph → content →
  facts or actions. Exactly one `h1` per page; card titles are `h2` in the directory and `h3` under the
  homepage's "Featured plants" `h2`.

## 5. Components

| Component | Markup (Razor) | Notes |
|---|---|---|
| Header | `_Layout.cshtml`: `.site-header`, `.brand` (emblem + live-text name), `Partials/Navigation.cshtml` | Navigation built from the content tree; current page `aria-current="page"`, current section `.is-active` (Mint pill) |
| Footer | `_Layout.cshtml`: `.site-footer` | Eggplant background, stripe bands, emblem, fictional-site note |
| Buttons | `.button` (Basil), `.button--sun` (Marigold CTA) | Pill shape; hover swaps to Eggplant |
| Hero | `HomePage.cshtml`: `.hero`, `<picture>` art direction, `.hero__content` | Live HTML text (headline, intro, CTA labelled from the Plants page title) |
| Plant card | `Partials/PlantCard.cshtml` (shared by home and directory) | Square illustration or "No image yet" placeholder; name; italic Latin name; sun badge |
| Plant illustration | `Partials/PlantIllustration.cshtml` | Signed square WebP `srcset` from the Media Library |
| Plant profile | `PlantPage.cshtml`: `.plant-profile__layout` | Two columns from 48rem when an image exists (CSS `:has()`), otherwise one |
| Facts panel | `.facts` | Mint panel, `<dl>` |
| Rich text | `GuidePage.cshtml`: `.rich-text` | 40rem measure, Coral list markers, Basil `strong` |
| Story panel | `HomePage.cshtml`: `.story__panel` | Rendered only when the CMS `storyText` has content |
| Not found | `NotFound.cshtml`, `.not-found` | Branded 404 via `Umbraco:CMS:Global:NotFoundViewPath` |

## 6. Responsive strategy

| Breakpoint | Width | Changes |
|---|---|---|
| base | < 576 px | Single column; hero art shown in full with the text panel overlapping its bottom edge; nav wraps under the wordmark |
| `36rem` | ≥ 576 px | Plant grid: 2 columns |
| `48rem` | ≥ 768 px | Hero switches from portrait to wide art; rounded hero; plant profile becomes two columns |
| `64rem` | ≥ 1024 px | Plant grid: 3 columns; hero text panel overlays the art's cream sky; story panel two columns |

**Hero art direction:** `<source media="(max-width: 47.99rem)">` serves `hero-tall-*` (4:5) to phones
and `hero-wide-*` (2:1) to wider screens, each with `srcset` widths and explicit `width`/`height` so
the browser reserves space (no layout shift). The hero is not lazy-loaded and has
`fetchpriority="high"`; images below the fold use `loading="lazy"`.

Verified with headless Edge driven over the DevTools Protocol at 375, 768, and 1440 px (true
device emulation): no horizontal overflow on any page, no broken images, and the 375 px viewport
downloads `hero-tall-480.jpg` rather than a desktop file.

## 7. Accessibility

- Contrast as in §2; Coral and Marigold never carry text on Cream.
- Visible focus: 3 px Eggplant outline with offset; Marigold on the dark footer.
- "Skip to content" link; landmarks `header`, `nav[aria-label="Main"]`, `main`, `footer`; one `h1` per page.
- Alternative text: informational illustrations (guide, story, 404, plant profile) have descriptive
  `alt`; decorative images (hero art behind live text, emblem next to the wordmark, sticker, card
  thumbnails next to the plant name) have `alt=""`.
- Sun badge: decorative "☀" glyph is `aria-hidden`; a visually hidden "Sun exposure:" label is read instead.
- Motion: the only transition (card lift) is inside `@media (prefers-reduced-motion: no-preference)`.
- No text is baked into images; all words are live HTML.

## 8. Conventions for future work

- Use tokens, never raw hex values, in new CSS.
- New decorative art: `alt=""`, not focusable, lazy unless above the fold.
- New editorial images: an Image Media Picker property plus the `PlantIllustration` pattern (signed
  `GetCropUrl` widths), never a hard-coded `/media/` path.
- Keep components in partials when used on more than one page.
