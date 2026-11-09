# Rebstock Changelog

## Unreleased

Migration 00006 creates an import-reference ledger while preserving existing wines, cellar entries, ratings, and lists.
MCP is disabled by default and requires OAuth configuration, an Authelia client registration, and reverse-proxy routing; see [OAuth setup](docs/mcp-auth.md).

- Redesign the application with the Journal visual style: serif headings, warm paper backgrounds, ruled sections, compact statistics, and consistent text actions across the dashboard, collections, detail pages, and forms.
- Improve mobile layouts with wrapping navigation, labeled table rows, readable form controls, larger touch targets, and dialogs that scroll within short viewports.
- Rework dialogs with keyboard focus trapping, Escape dismissal, browser history support, inline validation, and protection against duplicate submissions while preserving native forms without JavaScript.
- Upgrade vendored htmx to 4.0.0 and update navigation, form submissions, overlays, and the drink-to-rating flow to its request and history contracts.
- Add Chromium and WebKit browser regression tests for responsive layouts, accessibility, keyboard navigation, validation, error recovery, and forms without JavaScript.
- Add eight MCP tools for wine search and details, cellar entries, personal ratings, wishlist entries, batch imports, Vivino lookup, and community-rating refreshes.
- Import initial exports and invoices through structured batches with previews, atomic writes, and stable source references that prevent duplicate bottles and reviews on retries.
- Support Authelia browser authorization through a pre-registered public Codex client with PKCE and access-token validation independent of web authentication.
- Refresh Vivino community ratings for selected wines and exact known vintages without replacing wine metadata, personal ratings, images, or bottles.
- Remove the Vivino ZIP upload, single-wine import and metadata-sync screens, CSV/ZIP import code, and obsolete upload scripts.
- Seed an empty development collection directly with six demo wines, vintages, bottles, prices, ratings, wishlist entries, and demo activity for Alice instead of reading a Vivino export.
- Remove the `just dev --skip-import` option.
- Add an official MCP client socket suite covering imports, authorization, ownership, and a simulated OAuth browser callback with PKCE.
- Update the [MCP guide](docs/mcp.md) and invoice-importing skill for the new workflow.

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
