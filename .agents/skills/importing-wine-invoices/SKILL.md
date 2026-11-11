---
name: importing-wine-invoices
description: Use when importing wine purchases from invoices, order confirmations, receipts, PDFs, photos, or email into Rebstock through MCP, including matching and verifying Vivino identities.
---

# Importing wine invoices into Rebstock

Use the connected Rebstock MCP server to preview and apply structured wine and purchase records.
The ZIP importer and Vivino HTML import endpoints have been removed.
For local `just dev`, see [OAuth-free local MCP](../../../docs/mcp.md#local-development); production requires [OAuth setup](../../../docs/mcp-auth.md). Never post to retired import endpoints.
The [tool guide](../../../docs/mcp.md) describes schemas, pagination, and import references.

## Preserve source data

- Preserve invoice dates, exact vintages, quantities, tasting notes, and purchase notes.
- Store unit prices in integer `price_cents` per bottle and the invoice number in `notes`.
- Skip non-wine charges such as shipping and glassware, and report them.
- Leave unavailable years, dates, and ratings unknown.
- Never substitute a neighboring vintage or similar-sounding wine to obtain a Vivino match.
- Confirm the destination server and account when the request does not already identify them.
  Authorization to import covers the approved records and their retries, not unrelated cellar changes.

## Parse and match

For `.eml`, use `scripts/parse_eml.py` from this skill folder.
The helper prints both plain-text and HTML alternatives when present; these are two renderings of the same invoice, not separate purchases.
Merchant email may contain its line items only in an HTML table, even when a plain-text part exists.
Inspect any listed invoice attachments separately. For a PDF or photo, extract each product, year, quantity, and unit price before matching.

Search existing wines with `search_wines`, following `next_offset` when needed, and inspect exact vintages with `get_wine`.
Use the existing owned `wine_id` when a match is clear.
For a new Vivino candidate, search the web restricted to `vivino.com`, then call `lookup_vivino_wine` with the candidate URL or wine ID.
Verify the returned winery and wine name against the invoice before linking it.
If the wine identity cannot be verified, create it from the invoice without an external link.
A verified wine ID can still be linked when Vivino lacks the invoice's exact year; preserve that year without inventing vintage IDs or ratings.
Supply missing invoice years in the wine record's `vintages` array before referencing them in purchases; use `NV` only for an explicitly non-vintage wine.

When web search misses a wine, `scripts/vivino.py winery <id-or-slug>` can enumerate the producer's catalog.
The `www.vivino.com/api/wineries/{id}/wines` endpoint has historically returned the complete catalog, while its `api.vivino.com` counterpart silently capped results.
Treat these observations as discovery hints and verify candidates through MCP before linking them.
Use locale-stable country codes and database wine types `RED`, `WHITE`, `ROSE`, `ORANGE`, `SPARKLING`, `DESSERT`, `SAKE`, or `OTHER`.
Map unsupported upstream types explicitly to `OTHER`.

## Preview and apply

Read the complete cellar through `get_cellar`, following `next_offset` until null, to establish a baseline.
Historical purchases have no MCP source references, so reconcile them before importing the same document again.
Choose a stable source such as `merchant:invoice-37140` and stable references for each source line.
Do not generate new source references when retrying.
Wine references can be reused by later batches under the same source.
Keep each batch within the 100-record combined limit and 1 MiB request limit.

Call `import_batch` with `apply` omitted or false to preview:

```json
{
  "source": "merchant:invoice-37140",
  "wines": [
    {
      "ref": "riesling-2023",
      "winery": "Example Estate",
      "name": "Riesling",
      "country": "DE",
      "wine_type": "WHITE",
      "vintages": [{ "year": "2023" }]
    }
  ],
  "cellar": [
    {
      "ref": "line-1",
      "wine_ref": "riesling-2023",
      "vintage": "2023",
      "quantity": 2,
      "date": "2026-11-08",
      "price_cents": 1450,
      "notes": "Invoice 37140"
    }
  ]
}
```

For an existing owned wine, a wine record can contain just `ref`, `wine_id`, and the explicitly supplied metadata or vintages.
Resolve conflicting identity anchors before apply.
A supplied country for an existing shared winery must match its stored value, including when that value is unknown.
Resolve that metadata explicitly or omit the country before previewing again.

Review the preview's matches, field changes, and bottle totals against the source.
Submit the same approved records with `apply: true`.
Identical retries return existing destination IDs without adding bottles or personal ratings again.
A reference reused with different content is a conflict; inspect the existing entry rather than inventing a new reference.
Check `isError` and each record outcome before reporting success.
If a batch fails validation, none of its records are applied.

## Verify

Read the cellar again and compare total quantities with the baseline and source.
`counts.requested_bottles` includes all source purchases in the call, while `counts.bottles` excludes replayed purchases.
Use `get_ratings` and `get_wishlist` when those collections were imported.
Report every unmatched wine, omitted external link, skipped charge, conflict, and missing source field.

Community-rating refresh is a separate operation through `sync_vivino_ratings` on 1–20 distinct owned wine IDs per call.
It preserves wine metadata, personal ratings, images, and bottle quantities.
