# Rebstock

Wine cellar management app. Gleam on BEAM/Erlang.

## Stack

- **Language:** Gleam (target: erlang)
- **Web:** wisp (HTTP) + nakai (HTML templating) + htmx (interactivity)
- **CSS:** Tailwind CSS v4 (standalone binary or npm)
- **Database:** SQLite via sqlight (WAL mode), migrations via migrant
- **Auth:** Simple username-based auth (see `auth.gleam`)

## Project Structure

```
src/rebstock/          Core modules (db, auth, config, router, seed, ulid, vivino)
src/rebstock/mcp/      OAuth, protocol, import, read, and rating-sync tools
src/rebstock/web/      Page handlers (home, wines, wineries, cellar, ratings, wishlist, components)
src/css/app.css        Tailwind source
priv/static/           Built assets (CSS)
priv/migrations/       SQL migrations (00001_, 00002_, ...)
```

## Commands

```sh
just dev               # Dev server with file watching (port 3000)
just build             # Build CSS + Gleam
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

- Stone/amber/rose color palette throughout
- Wine type badges: red (`bg-red-900`), white (`bg-amber-50`), rose (`bg-pink-50`), sparkling, dessert, fortified
- Rating colors: HSL scale red (3.0) to green (5.0) via `red_green_scale`
- "Your X" for logged-in user, "$username's X" for other profiles
