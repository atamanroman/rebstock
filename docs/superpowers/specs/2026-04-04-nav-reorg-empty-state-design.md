# Nav Reorganization + Empty Home State

## Overview

Reorganize the site header navigation to clearly separate global vs. user-scoped links, add a username dropdown for tools (Import, Settings), and show a welcome/import CTA when the database is empty.

## Header Navigation

Reorganize into three right-aligned zones with visual separators:

```
Logo ——————— Wines  Wineries  │  Cellar  Wishlist  Ratings  │  ~username ▾
```

- **Logo** — grape emoji (`🍇`) + "Rebstock" text, left-aligned
- **Global links** — Wines, Wineries (browse all data)
- **Separator** — `│` character in muted color
- **User-scoped links** — Cellar, Wishlist, Ratings (link to `~username/...`)
- **Separator** — `│`
- **Username dropdown** — `~admin ▾` using a CSS-only `details`/`summary` element. No JS needed. Click opens, click again or outside closes.

### Dropdown contents

- Import (links to `~username/import`)
- Future items: Settings, Share, etc.

### Removed

- The `//` separator between global and user links
- The `~username:` label prefix
- The custom SVG logo (replaced by grape emoji)

## Empty Home Page State

When `db.count_wines(conn) == 0`, replace all normal home page content (stats, activity grids) with a centered welcome:

- Large grape emoji
- "Welcome to Rebstock" heading (`text-3xl font-light`)
- "Import your Vivino data to get started" subtitle
- Prominent "Import Vivino Data" button linking to `~username/import` (rose-800 bg)
- Small muted text: "You can also add wines manually later"

When wines exist, the normal home page renders unchanged.

The check is in `home.gleam`'s `home` function — wine count 0 triggers welcome view.

## Files Affected

- `src/rebstock/web/components.gleam` — update `site_header` to new layout (right-aligned nav, separators, details/summary dropdown, grape emoji logo)
- `src/rebstock/web/home.gleam` — add empty state check, render welcome when no wines
- `src/rebstock/web/cellar.gleam` — remove duplicate `logo_svg` function (also in components)
