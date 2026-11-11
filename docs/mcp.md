# MCP tools

Rebstock serves MCP at `/mcp` when its OAuth configuration is enabled.
Use [MCP OAuth setup](mcp-auth.md) to register the public Codex client with Authelia and configure the reverse proxy.
In production, web single-user and forward-auth credentials do not authenticate MCP requests.

## Local development

`just dev` / `gleam dev` enables OAuth-free `/mcp` when OAuth is unconfigured,
`auth.single` is selected, and `host` is `127.0.0.1` or `::1`. It uses that configured
user, ignores caller identity headers, and rejects foreign Host/Origin requests.
Production stays OAuth-only; explicit OAuth configuration is never bypassed.

## Protocol

The server supports the `2025-11-25`, `2025-06-18`, and `2025-03-26` protocol versions through stateless Streamable HTTP JSON responses.
It provides eight tools and does not allocate sessions or open an SSE stream.

| Tool | Arguments | Result |
| --- | --- | --- |
| `search_wines` | Optional `q`, `limit`, `offset` | Owned wines matching a name, winery, or stored Vivino ID. |
| `get_wine` | `wine_id` | An owned wine and exact vintage community ratings. |
| `get_cellar` | Optional `wine_id`, `limit`, `offset` | Your purchase and consumption entries. |
| `get_ratings` | Optional `wine_id`, `limit`, `offset` | Your personal ratings and tasting notes. |
| `get_wishlist` | Optional `limit`, `offset` | Your wishlist entries, vintages, and notes. |
| `import_batch` | `source`, optional `apply`, `wines`, `cellar`, `ratings`, `wishlist` | A preview or an atomic import with per-record outcomes. |
| `lookup_vivino_wine` | `vivino_id` | Upstream identity, metadata, label URL, and vintage ratings without database changes. |
| `sync_vivino_ratings` | `wine_ids` | Community-rating refresh outcomes for selected owned wines. |

Read tools default to 50 entries and accept a `limit` from 1 through 100.
Continue with `next_offset` until it is `null` when reconciling a complete collection.
All tool calls operate under the identity verified from the access token.

## Initial imports and invoices

The assistant reads the source document outside Rebstock, matches wines, and submits structured records.
The application no longer accepts Vivino ZIP exports or parses their CSV files.
An assistant can interpret an initial export using the same tools as an invoice.
Review existing purchases and personal ratings before importing historical data because old entries have no recorded import references.

Use a stable `source` namespace for each source document, such as `merchant:invoice-37140`.
Every record requires a stable `ref` within its collection and source.
Keep these values unchanged when retrying a request or splitting an import into different batches.
An identical replay returns the original destination IDs without adding bottles or reviews again.
Changing an already applied reference returns an error rather than creating another purchase.

Call `import_batch` without `apply` to preview this example:

```json
{
  "source": "merchant:invoice-37140",
  "wines": [
    {
      "ref": "riesling",
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
      "wine_ref": "riesling",
      "vintage": "2023",
      "quantity": 3,
      "date": "2026-11-08",
      "price_cents": 1250,
      "notes": "Invoice 37140"
    }
  ]
}
```

Inspect the preview's record matches, field changes, and requested bottle totals.
Then submit the same records with `"apply": true` when the import is authorized.
Each batch is revalidated before persistence and applies atomically on its own SQLite connection.
One invalid record prevents every write in that batch.
Batches may contain at most 100 records across all collections and requests may contain at most 1 MiB of JSON.
New destination IDs in a preview are provisional until apply returns the persisted IDs.

Wine records accept an existing owned `wine_id`, or an exact `winery` and `name`.
They may include `vivino_id`, `region`, `country`, `style`, `personal_note`, `wine_type`, community-rating snapshots, and vintages.
Matching considers an explicit owned ID, a unique owned Vivino link, then an exact winery and wine name.
Conflicting identity anchors are rejected.
Omitted or null optional metadata preserves an existing value.
An existing winery's supplied country must match its stored country, including when the stored country is unknown.
Resolve a shared winery's metadata through its explicit editing flow before retrying a conflicting import.

Children use either `wine_id` or `wine_ref`.
A `wine_ref` may refer to a wine in the same batch or an already applied wine reference under the same source.
The referenced vintage must already exist or be supplied in that wine's `vintages` array.
Use an exact four-digit year or `NV`; omit or null the vintage when the source does not identify one.
Use database wine types `RED`, `WHITE`, `ROSE`, `ORANGE`, `SPARKLING`, `DESSERT`, `SAKE`, or `OTHER`.

Purchases accept positive `quantity`, `date`, `notes`, and a nonnegative integer `price_cents` per bottle.
Dates use valid calendar dates in `YYYY-MM-DD` format.
Personal rating records accept `rating`, `tasting_notes`, and `rated_at`.
Wishlist records accept `vintage` and `notes`.
Ratings range from 0 through 5; missing ratings remain unknown.
Wine and vintage snapshots use `vivino_rating` and `vivino_rating_count`, separate from personal ratings.

The result includes `records` with source references and destination IDs, plus created, updated, and unchanged counts.
`counts.requested_bottles` is the source purchase total in that call.
`counts.bottles` counts newly added bottles and excludes replayed purchases.
Read the cellar and personal ratings again to verify the completed import against the source.

## Vivino lookup and refresh

`lookup_vivino_wine` accepts a positive wine ID, a public `https://www.vivino.com/.../w/ID` URL, or a vintage `/wines/ID` URL.
It also accepts legacy `v`-prefixed vintage IDs stored by older imports.
Review the fetched wine name, winery, and exact vintage before linking a wine during import.
The lookup returns a label URL; manual image uploads remain available through the web interface.

`sync_vivino_ratings` accepts 1 through 20 distinct owned wine IDs and uses their stored Vivino links.
It updates overall community ratings and ratings for exact, already-known vintages.
It does not add every upstream vintage or replace wine metadata, personal ratings, images, or bottles.
Missing or unrated upstream values preserve cached ratings, and unreported counts preserve cached counts.
Legacy vintage links become canonical wine IDs after a successful refresh.
Each wine's updates are atomic, and a rate limit stops remaining upstream requests in that batch.
Results distinguish refreshed, failed, and skipped wines; a partial failure sets the MCP result's `isError` flag.

Upstream requests have five-second timeouts.
Configure a longer Codex `tool_timeout_sec`, such as `240`, when refreshing batches of legacy vintage links that require an extra resolution request per wine.

## Verification

The official-client socket suite starts an isolated Rebstock server, a local OAuth issuer, and a disposable database.

```sh
npm run test:mcp
```

Browser regression checks use a separate disposable database.

```sh
npm run test:browser
```
