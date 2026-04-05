# Wine Lists

## Overview

Add wine lists as a presentation and sharing layer. Users can create custom lists of wines, share them as read-only wine-menu-style pages, and print/export them. Three system lists (Cellar, Rated, Wishlist) provide shared views of existing data. The Wishlist replaces the old dedicated wishlist table — it's now a regular list backed by the generic `lists_wines` table.

## Data Model

### `lists` table

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT (ULID) | Primary key |
| `username` | TEXT | FK → users, owner |
| `name` | TEXT | Display name |
| `description` | TEXT | Optional, shown in shared view header |
| `slug` | TEXT | URL-friendly name (for shared URLs) |
| `list_type` | TEXT | `cellar`, `rated`, `wishlist`, or `custom` |
| `public` | INTEGER | 0 or 1, default 0 |
| `created_at` | TEXT | ISO datetime |

Constraints: `UNIQUE(username, slug)`. Slug is auto-generated from name on create (lowercase, hyphens, strip non-alphanumeric). System lists use fixed slugs: `cellar`, `rated`, `wishlist`.

### `lists_wines` table

| Column | Type | Notes |
|--------|------|-------|
| `list_id` | TEXT | FK → lists |
| `wine_id` | TEXT | FK → wines |
| `vintage` | TEXT | Optional |
| `sort_rank` | INTEGER | For future manual ordering |
| `notes` | TEXT | Optional (used by wishlist entries) |
| `added_at` | TEXT | ISO datetime |

Constraints: `PRIMARY KEY(list_id, wine_id, vintage)` where vintage uses empty string for NULL to make the constraint work.

Trigger: `lists_wines_type_check` — `BEFORE INSERT` rejects inserts where the list's `list_type` is `cellar` or `rated` (virtual lists).

### Removed

The `wishlist` table is removed. Wishlist data lives in `lists_wines` linked to the user's wishlist-type list.

### System lists

Each user gets three auto-created lists on first access:

| list_type | Name | Data source |
|-----------|------|-------------|
| `cellar` | Cellar | Dynamic query against `cellar` table (virtual — no `lists_wines` rows) |
| `rated` | Rated | Dynamic query against `ratings` table (virtual — no `lists_wines` rows) |
| `wishlist` | Wishlist | Stored in `lists_wines` (real data) |

System lists (`list_type != "custom"`) cannot be renamed or deleted.

## Routes

### User-scoped (behind auth)

| Method | Path | Action |
|--------|------|--------|
| GET | `/~username/lists` | Lists index — system lists + custom lists |
| GET | `/~username/lists/new` | Create list form |
| POST | `/~username/lists` | Create list |
| GET | `/~username/lists/:id` | View list (with edit controls if owner) |
| POST | `/~username/lists/:id` | Update list name/description |
| DELETE | `/~username/lists/:id` | Delete list (custom only) |
| POST | `/~username/lists/:id/wines` | Add wine to list |
| DELETE | `/~username/lists/:id/wines/:wine_id` | Remove wine from list |
| PUT | `/~username/lists/:id/public` | Set public flag (boolean body) |

### Existing routes (updated)

Wishlist routes (`/~username/wishlist`, overlay, etc.) rewritten to read/write from the user's wishlist-type list via `lists_wines`.

### Public (Authelia bypass)

| Method | Path | Action |
|--------|------|--------|
| GET | `/shared/:id/:slug` | Read-only wine-menu view. Only renders if `public = true`. Slug is cosmetic, lookup by id. |

## Shared View

The shared view at `/shared/:id/:slug` renders a standalone wine-menu page. No Tailwind — plain CSS served inline or from a dedicated stylesheet.

### Template

- **Font:** Cormorant Garamond (Google Fonts), fallback to Georgia/serif
- **Layout:** Centered, max-width ~680px
- **Header:** List name (large, light weight), description (italic), "Curated by username · N wines"
- **Sections:** Grouped by wine type, then region, then alphabetical. Section headers are uppercase, small, system-ui font, colored by type (red = #78180e, white/amber = #92400e, others = #57534e), with a 2px bottom border in matching color.
- **Wine entry:** Wine name (medium weight) + vintage on left, region (italic, muted) right of center, bottle count in parentheses far right (only for cellar-type lists)
- **Winery:** Below wine name, smaller, muted
- **Footer:** Centered, "🍇 Rebstock", thin top border

### Data by list type

| list_type | Wine source | Bottle count |
|-----------|-------------|--------------|
| `cellar` | Dynamic query: `cellar` table, wines with bottles > 0 | Yes — aggregated quantity |
| `rated` | Dynamic query: `ratings` table, all rated wines | No |
| `wishlist` | `lists_wines` rows for this list | No |
| `custom` | `lists_wines` rows for this list | No |

### Sorting

All lists sorted: wine type → region → wine name (alphabetical at every level). Wine type order: Red, White, Rosé, Sparkling, Dessert, Fortified.

## Navigation

Add "Lists" to the nav bar in the user-scoped section:

```
Wines  Wineries  │  Cellar  Wishlist  Ratings  Lists  │  ~username ▾
```

## Adding Wines to Lists

From the wine detail page (`/wines/:id`): an "Add to list..." action that shows available custom lists + wishlist. Not shown for cellar/rated (those have their own dedicated add flows).

## Protection Rules

- System lists (`list_type != "custom"`): cannot rename, cannot delete
- Only the owner (`list.username == user.username`) can modify a list
- Only `wishlist` and `custom` lists accept wine additions/removals via `lists_wines`. Cellar and rated lists are virtual (dynamic queries) — attempts to add/remove wines return an error.
- Shared view: only renders if `list.public = true`, returns 404 otherwise

## CSS Variables

Extract wine type colors and core palette into `priv/static/css/colors.css` as CSS custom properties on `:root`. This file is imported by both `app.css` (main app) and the shared view template.

Variables include:
- `--color-red`, `--color-white`, `--color-rose`, `--color-sparkling`, `--color-dessert`, `--color-fortified` — wine type colors, used for badges in the app and section headers in the shared view
- `--color-stone-*`, `--color-rose-800` — core palette values reused across both contexts

The shared view references these variables in its plain CSS instead of hardcoding hex values.

## Files Affected

- `priv/static/css/colors.css` — new: CSS custom properties for wine type colors and core palette
- `src/css/app.css` — import `colors.css`, replace hardcoded color values with variables where applicable
- `priv/migrations/00001_create_wines.up.sql` — add `lists` + `lists_wines` tables, remove `wishlist` table
- `src/rebstock/db.gleam` — list CRUD functions, list query functions, remove wishlist functions
- `src/rebstock/router.gleam` — add list routes, shared route
- `src/rebstock/web/lists.gleam` — new: lists index, create/edit/delete, add/remove wines
- `src/rebstock/web/shared.gleam` — new: public shared wine-menu view (plain CSS, no Tailwind)
- `src/rebstock/web/wishlist.gleam` — rewrite to use lists_wines instead of wishlist table
- `src/rebstock/web/wines.gleam` — add "Add to list..." action on wine detail
- `src/rebstock/web/components.gleam` — add "Lists" nav link
- `src/rebstock/vivino.gleam` — update import to write wishlist entries to lists_wines
- `test/rebstock_test.gleam` — update wishlist tests, add list tests

## Deferred

- Custom CSS per list
- Predefined themes
- Manual reordering (sort_rank column is there, UI later)
- Expiring share links
- CSV/PDF export from lists
- Additional data columns in shared view (rating, tasting notes)
