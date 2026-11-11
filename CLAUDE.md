# Rebstock

Wine cellar management app. Gleam on BEAM/Erlang.

## Stack

- **Language:** Gleam (target: erlang)
- **Web:** wisp (HTTP) + nakai (HTML templating) + htmx (interactivity)
- **CSS:** Plain CSS, served directly from `priv/static/css/` (no build step)
- **Database:** SQLite via sqlight (WAL mode), migrations via migrant
- **Auth:** Simple username-based auth (see `auth.gleam`)

## Project Structure

```
src/rebstock/          Core modules (db, auth, config, router, seed, ulid, vivino)
src/rebstock/mcp/      OAuth, protocol, import, read, and rating-sync tools
src/rebstock/web/      Page handlers (home, wines, wineries, cellar, ratings, wishlist, components)
priv/static/css/      Plain CSS source (app, ui, layout helpers, shared colors)
priv/static/js/       Vendored htmx and UI enhancements
priv/migrations/       SQL migrations (00001_, 00002_, ...)
```

## Commands

```sh
just dev               # Dev server with file watching (port 3000)
just build             # Build Gleam (CSS is served directly)
just test              # Run tests
just lint              # Format check + build with --warnings-as-errors
just format            # Format Gleam code
npm run test:mcp       # Official MCP client + OAuth on a disposable database
```

## Build Rules

- **Always** run `gleam format .` before commit
- **Always** run `gleam build --warnings-as-errors` — no warnings allowed
- Pre-commit hook (lefthook) runs `just lint` auto
- Fix unused variables/imports immediately, never leave them
- No conventional commits — use plain descriptive messages

## Architecture Notes

- **HTML rendering:** nakai nodes (`html.Element`, `html.Text`, `html.UnsafeInlineHtml`), no JSX
- **Overlays:** htmx requests (`HX-Request` header) return fragments; full page loads return complete pages
- **Overlay control:** `HX-Retarget`, `HX-Reswap`, `HX-Redirect` headers for flow control
- **Cellar event sourcing:** positive quantity = purchase, negative = consumption, linked via `parent_id`
- **Routing:** pattern matching in `router.gleam`, user-scoped routes under `~username/`
- **Components:** shared helpers in `web/components.gleam` (stat cards, tables, overlays, badges, rating display)
- **Date defaults:** inline `<script>` with `valueAsDate = new Date()` (no date library)
- **MCP:** `/mcp` uses OAuth access tokens independently of web auth; batch imports preview by default and use stable source references for retry safety.
- **MCP writes:** use dedicated SQLite connections and atomic transactions, never the web handler's shared connection.
- **Vivino:** the small adapter fetches explicit IDs; MCP rating sync preserves wine metadata and personal data.

## Style Guide

- Ledger is the sole UI: white, system typography, thin rules, muted burgundy accent.
- Shared component CSS lives in `priv/static/css/ui.css`; local helpers in `layout.css`.
- No CSS framework or compiler; see `docs/ui.md`.
- Wine types use colored dots with explicit labels, not pills.
- Rating colors: OKLCH scale red (3.0) to green (5.0) via `rating_fill` / `rating_ink`
- "Your X" for logged-in user, "$username's X" for other profiles
