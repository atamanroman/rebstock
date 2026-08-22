---
name: importing-wine-invoices
description: Use when adding a wine purchase to rebstock from a merchant document — invoice, order confirmation or receipt as .eml, PDF or photo — including matching each line to Vivino, resolving Vivino wine and vintage ids, and creating cellar entries. Triggers on "import my invoice", "add these wines to rebstock", "find these wines on Vivino", "which Vivino id is this wine".
---

# Importing wine invoices into rebstock

## Overview

An invoice is a list of wine names and quantities.
Getting it into rebstock means resolving each line on Vivino, then creating the wine and its bottles over rebstock's own HTTP endpoints.

Pipeline: **parse invoice → resolve each line on Vivino → POST the wine → POST the bottles → verify.**

Use the endpoints, not the Vivino-export zip importer. The zip path loses the purchase date, the notes and the label image, and stores an unresolved vintage id where the endpoint stores a real wine id. It is only worth it for a bulk backfill of many wines at once — see the bottom of this file.

## Non-negotiable rules

1. **Every cellar POST creates a new entry.** Wine POSTs are upserts and safe to repeat; bottle POSTs are not. When a run fails halfway, drop the lines that already landed before re-running.
2. **Ask before writing to a deployed instance.** Default to a local server (see below). Only POST to a remote instance when the user names it and approves in that turn.
3. **Never invent a Vivino id.** Every id goes through `api.vivino.com/wines/{id}` and the returned winery and name must match the invoice line. A wrong id attaches someone else's ratings to the bottle.
4. **Skip non-wine lines** — sauces, glassware, shipping. Report what was dropped.
5. **There is no price field.** The `cellar` table stores vintage, quantity, notes and date only. Put the unit price in `notes` (`invoice #37140, EUR 11.30/bottle`) and say that is where it went.

**Defaults when running unattended** (no one to ask): a wine with no Vivino match is created from the invoice line alone; a wine whose invoice year is missing from Vivino keeps the invoice year and is created without the Vivino link. Never substitute a different vintage or a similar-sounding wine — a missing link is recoverable, a wrong link is not. Report every line that took a default.

## Vivino API map

`api.vivino.com` wants the mobile user agent `Vivino/8.18.11 (Android; SDK 30)` (`vivino.gleam`, `vivino_mobile_user_agent`); `www.vivino.com` wants a browser one.

| Endpoint | Verdict |
| --- | --- |
| `api.vivino.com/wines/{wine_id}` | **Works, unauthenticated.** name, `winery.id`, `winery.name`, `type_id`, `region`, `statistics`, and `vintages[]` with `id` + `year`. |
| `www.vivino.com/api/wineries/{winery_id}/wines` | **Works, returns the producer's entire catalog** in one response — 38 wines for Binekhi. The way to find a bottle web search misses. |
| `api.vivino.com/wineries/{id}/wines` | Different endpoint, same shape, **truncated to 10** with `page`/`per_page`/`offset` all ignored. Looks complete. Don't use it. |
| `www.vivino.com/api/explore/explore?search_term=X` | Scoped to what is **purchasable in `country_code`** — niche bottles return 0 while existing on Vivino. Not a catalog search. |
| any `q=`/`search`/`suggestions` path on either host | 404 or `{}`. **No text search exists on any Vivino API.** Don't go looking. |

**So name → id runs through web search:** `WebSearch` with `allowed_domains: ["vivino.com"]`, query `"<winery> <wine> vivino"`, take `/w/{wine_id}` from a result URL, verify against `api.vivino.com/wines/{id}`.

**When search comes up empty, enumerate the producer's catalog.** Get the winery id from any already-resolved wine of theirs (`winery.id`), or from `winery_id=NNN` in the HTML of `www.vivino.com/en/wineries/{slug}`. Then list every wine and match by name. Bottles often sit under a different name than the invoice uses (`Terra Kisi Khikhvi Qvevri` → `Terra Qisi — Khikhvi Amber`, `Binekhi Tsitska semi dry` → `Binekhi — Tsitska Semi Dry`).

**Fetch vivino.com with urllib, not curl.** `curl` on a winery page returns a 108-byte redirect stub where urllib with the same user agent returns the full page.

**`www` responses are localized.** The catalog endpoint returns `region.country.name` as `Georgien` from a German IP, which `country_to_iso` does not know — the wine would import with no country. Take `region.country.code` instead; it is locale-stable and `country_to_iso` accepts it.

Some wines are genuinely absent — `/en/wineries/{slug}` 404s and search finds nothing. Create those from the invoice line.

## Workflow

1. **Parse the invoice.** `scripts/parse_eml.py <file.eml>` for mail; the Read tool for PDF or photo. Merchant mail often has **no `text/plain` part**, and the line items are an HTML table — de-tag it with `</td>` → separator first, or product, quantity and price run together.
2. **Resolve each line** per the map above. Record wine id, winery, name, `wine_type`, region, country code.
3. **Pick the vintage** from `vintages[]`.
4. **Snapshot the cellar** — `GET /~<user>/cellar/export.csv` before writing anything. Without a baseline there is no way to say what the run added.
5. **Write it** with `scripts/import_via_api.py items.json <base-url> <user> --date <invoice date>`.
6. **Diff.** Fetch the export again and compare bottle totals. It is sorted, so a line diff also shows unrelated rows shifting position — compare sums, not just lines.

## Writing to rebstock

Two POSTs per wine. Both take ordinary form encoding.

**Vivino-matched wine** — `POST /wines/import/vivino`, fields `name`, `winery`, `vivino_id`, `wine_type`, `region`, `country`. rebstock then fetches every vintage, per-vintage ratings and the label image itself. Answers `303` with `location: /wines/{id}/{slug}`.

`name`, `winery` and `vivino_id` must all be non-empty, or the handler redirects back to the form without explaining why (`wines.gleam`, `vivino_import`). `vivino_id` is the **wine** id, not a vintage id.

**Wine with no Vivino match** — `POST /wines`, fields `name`, `winery`, `wine_type`, `region`, `country`, `vintage`. Note the path: **`POST /wines/new` renders the form and creates nothing**, answering `200` as if it worked (`router.gleam:88`).

**Bottles** — `POST /wines/{id}/x/cellar/new`, fields `vintage`, `quantity`, `date`, `notes`. The slug segment is ignored by the router, so any placeholder works. Success is `200` with an `hx-redirect` header, not a `303`.

## Running rebstock locally

```
cp data/rebstock.db /tmp/import-test.db          # never import into the working db
gleam run -- --config /tmp/test-config.json      # shape per config.example.json
```

Point `database_uri` at the copy and pick a port other than 3000.

**`auth.single.user` in that config is the `<username>` in the URL.** `import_page` returns a bare 403 when they differ (`imports.gleam:21`), which reads like an auth failure and isn't.

POSTs succeed without an `Origin` header because `require_same_origin` (`router.gleam:36`) only compares `Origin` against `Host` when `Origin` is present. Adding a mismatched one produces a silent 403 with no body.

## Quick reference

```
python3 .Codex/skills/importing-wine-invoices/scripts/parse_eml.py invoice.eml
python3 .Codex/skills/importing-wine-invoices/scripts/vivino.py wine 2701446
python3 .Codex/skills/importing-wine-invoices/scripts/vivino.py winery 26104
python3 .Codex/skills/importing-wine-invoices/scripts/import_via_api.py items.json http://127.0.0.1:3000 admin --date 2026-07-19
```

`items.json` is a list of `{"wine_id": 12067613, "name": "Tsitska Semi Dry", "winery": "Binekhi", "wine_type": "White Wine", "region": "Imereti", "country": "ge", "year": "2022", "bottles": 2, "notes": "invoice #37140, EUR 11.30/bottle"}`; a line with no Vivino match omits `wine_id`.

## Bulk alternative: the Vivino export importer

`POST /~<user>/import` takes a zip of Vivino CSVs and is the right tool for restoring a whole cellar at once. For an invoice it is worse: it writes `date` and `notes` as NULL, fetches no image, and stores `vivino_id` as the unresolved `v{vintage_id}` form rather than a wine id.

Build it with `scripts/build_import_zip.py items.json out.zip`, then `curl -F "zipfile=@out.zip" <base>/~<user>/import`.

- The zip must contain **`full_wine_list.csv`** or it errors `Zip must contain full_wine_list.csv`. Header-only satisfies it. `cellar.csv` carries the purchase.
- `cellar.csv` has exactly 11 columns in this order (`vivino.gleam`, `parse_cellar_row`): `Winery,Wine name,Vintage,Region,Country,Regional wine style,Average rating,Wine ratings count,Wine type,Link to wine,User cellar count`.
- **Link to wine** must be `https://www.vivino.com/wines/{vintage_id}` — the **vintage** id. `extract_vivino_id` only splits on `/wines/`; a `/w/{wine_id}` link is dropped and the wine imports unlinked.
- **Wine type** is matched by `wine_type_from_string`: `Red Wine`, `White Wine`, `Rosé`, `Orange`, `Sparkling`, `Dessert`, `Sake`. Anything else silently becomes `Other`. Vivino `type_id` maps 1 Red, 2 White, 3 Sparkling, 4 Rosé, 7 Dessert, 24 Fortified.
- **Average rating** blank, not `0`, when Vivino has none — `0` is stored as a real 0.0 rating.
- The summary page counts CSV rows, not bottles: 15 rows can be 20 bottles.
