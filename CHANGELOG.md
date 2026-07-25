# Rebstock Changelog

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
