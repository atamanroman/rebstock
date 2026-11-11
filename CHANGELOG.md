# Rebstock Changelog

## 0.4.0

Migrations 00006–00007 add import references and optional user profiles without
removing existing data. Back up SQLite and the configured image directory before
upgrading. MCP is disabled by default; see [OAuth setup](docs/mcp-auth.md).

- Replace the UI with Ledger: white backgrounds, system typography, compact
  summaries and tables, and a grapevine logo. Remove Tailwind and its build step.
- Improve mobile layouts, semantic HTML, keyboard-accessible dialogs, validation,
  and browser history. Upgrade htmx to 4.0.0; native forms still work without JavaScript.
- Add optional display names and round profile pictures, including account-menu
  avatars and a logo fallback. Usernames remain controlled by authentication.
- Add eight [MCP tools](docs/mcp.md) for collection reads, invoice/export imports,
  Vivino lookup, and community-rating refreshes that preserve personal data.
- Preview imports before applying atomic batches; stable source references prevent
  duplicate bottles and personal ratings on retries. Update the invoice-importing skill.
- Authenticate production MCP separately through OAuth, with Authelia browser login
  and PKCE. Allow OAuth-free MCP in loopback-only, single-user development.
- Remove the old ZIP/CSV importer, single-wine import and metadata-sync screens,
  and `just dev --skip-import`. Development now seeds a demo collection directly.
- Add the project site, Chromium/WebKit accessibility and regression coverage,
  and official MCP client tests.

## 0.3.0

Migration 00005 applies on first start and only adds a nullable column, so
existing cellar entries stay valid without a price.

- Optional price per bottle on cellar entries, shown on the entry, on the wine
  page beside each purchase, and as held value on the cellar page and in the
  CSV export
- Drunk bottles are charged to the purchase they came from, so a corrected
  price corrects every bottle drawn from it
- Dashboard rating charts redrawn: OKLCH colour ramp, half-step buckets, and
  your ratings set against Vivino's as a butterfly on one shared scale
- Dashboard rating bars link to the matching filtered list

## 0.2.2

- Fix dashboard "Recently Added to Cellar" and wishlist table showing all of a
  wine's vintages instead of the specific vintage on the cellar entry or
  wishlist item

## 0.2.1

- Fix migration 00002 failing on databases with duplicate Vivino ratings:
  keep the newest rating per wine+vintage before creating the unique index

## 0.2.0

Migrations 00002–00004 apply on first start and drop columns — back up
the database before upgrading.

- Vivino import by URL or ID and re-sync with diff preview, wine label images
- Vivino community ratings stored on wines and vintages with real rating counts
- Instant zip import: vintage IDs resolve lazily on first sync instead of per row
- Vintage-aware add-to-list on wine detail
- Filter input on wines, cellar, and wineries tables
- Cellar quantity edits validated against the drink ledger
- Hardening: CSRF protection, owner checks on winery edit and CSV export, configurable signing secret

## 0.1.0

First release of Rebstock, a self-hosted wine cellar management app.

- Wine and winery catalog with cellar tracking, ratings, and wishlist
- Shareable and printable wine lists with bottle counts
- Vivino export import (drag-and-drop zip upload)
- Simple auth (single user or forward auth via reverse proxy)
- Server-rendered UI with htmx, Tailwind CSS, SQLite
