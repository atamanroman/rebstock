# Replace Vivino import screens with MCP

## Goal

Rebstock provides MCP tools for an assistant to import a cellar from an export or invoice and refresh Vivino community ratings.
The assistant interprets source documents and chooses operations, while Rebstock validates ownership, matches records, and persists changes.
A small Vivino adapter continues fetching wine details and ratings deterministically.

## Agreed direction

- Rebstock provides the MCP server.
- Keep a small Vivino fetcher inside Rebstock.
- Let the assistant select wines and initiate rating refreshes.
- Keep personal ratings separate from Vivino community ratings.

## Proposed first release

Add a Streamable HTTP endpoint at `/mcp` inside the existing Wisp application.
Keep the implementation on Gleam and BEAM with the existing HTTP, JSON, and SQLite dependencies.
Isolate protocol handling from import operations and the Vivino adapter.
Support the `2025-11-25` protocol with initialization, tool discovery, tool calls, and JSON responses.
Do not allocate server sessions or advertise streaming, resources, prompts, or server-initiated requests.
Return `405` for unsupported streaming GET and session DELETE requests.
Verify protocol negotiation and newer-client fallback with an official MCP client before claiming compatibility.

The proposed authentication is browser-based OAuth through Authelia using a pre-registered public client for Codex.
Use the client ID `rebstock-codex`, authorization-code flow with PKCE S256, and no client secret.
The client ID identifies the integration; the user still logs in through Authelia and consents to access under their own identity.
Codex opens the browser for login and consent, then receives an access token for subsequent MCP requests.
The existing web forward-auth login redirect alone does not implement this flow.
Rebstock advertises OAuth protected-resource metadata and validates Authelia-issued access tokens, their intended resource, granted scopes, and user mapping.
Authelia handles browser login and token issuance rather than Rebstock implementing its own authorization server.
Authelia documents authorization-code flow, PKCE, and resource indicators, but lists dynamic client registration as unsupported.
Pre-registration avoids requiring dynamic registration support.
The locally installed Codex CLI `0.166.0` supports `--oauth-client-id`, and the official documentation describes this flow.
Register the exact callback URI printed by Codex rather than assuming a fixed callback path.
Pin the callback listener port if required by the deployed Authelia redirect-URI policy and keep its configured URL and listener port consistent.
Configure the client to request the Rebstock MCP resource and the scopes published by Rebstock.
Do not accept a username supplied in tool arguments as authority.
Require an authenticated MCP access token even when the web application runs in single-user mode.
Leave MCP disabled until its OAuth resource-server configuration is complete.
Do not add a separate manually managed API-token mechanism in this release.
End-to-end authentication against the deployed Authelia instance remains part of implementation validation.

Once the MCP endpoint and its authorization metadata are available, configure Codex with the registered client ID.

```sh
codex mcp add rebstock --url https://rebstock.neonforest.org/mcp --oauth-client-id rebstock-codex
```

After registering the displayed callback URI in Authelia, start browser login if the initial connection did not complete it.

```sh
codex mcp login rebstock
```

These commands describe the planned connection rather than an already registered client or deployed endpoint.

## Tool boundary

| Tool | Purpose |
| --- | --- |
| `search_wines` | Find the caller's wines by name, winery, or stored Vivino ID with bounded pagination. |
| `get_wine` | Read an owned wine, its vintages, cached community ratings, and external link. |
| `get_cellar` | Read the caller's purchase and consumption entries for reconciliation. |
| `get_ratings` | Read the caller's personal ratings and tasting notes. |
| `get_wishlist` | Read the caller's wishlist entries and vintage selections. |
| `import_batch` | Validate or apply a bounded batch of wine, purchase, personal-rating, and wishlist records. |
| `lookup_vivino_wine` | Resolve an explicit Vivino URL or ID and return metadata, vintage ratings, and the label URL without creating records. |
| `sync_vivino_ratings` | Refresh cached community ratings for explicitly selected, owned wines using their stored Vivino links. |

Expose structured results with entity IDs, validation errors, and created, updated, and unchanged counts.
Use tool error results for validation, ownership, and upstream failures rather than making an HTTP success look like a completed mutation.
Keep arbitrary SQL, caller-selected remote URLs, destructive operations, and background scheduling outside this release.

## Initial import

The assistant reads and interprets the source outside Rebstock and submits structured batches.
The server does not receive ZIP files or implement Vivino CSV parsing.
The same import tool supports an initial Vivino export, an invoice, or a manually assembled source.

Each request carries a stable source namespace and stable references for the individual source records.
Wine records can refer to an existing owned ID or provide an exact winery and wine name with an optional Vivino link.
Purchase, personal-rating, and wishlist records refer to an existing owned wine ID or a wine reference in the same batch.
Vintage values remain explicit and are never substituted with a nearby year.
Preserve purchase dates, quantities, notes, unit prices in integer cents, tasting notes, personal ratings, and supplied community-rating snapshots.
Keep missing source dates and ratings unknown rather than inventing defaults.

Resolve an explicit owned wine ID first, then a unique stored Vivino link, then an exact winery and wine name.
Report conflicting matches instead of merging wines by a guessed similarity.
Treat omitted metadata as unchanged and make proposed changes visible in the validation result.
Do not silently update a shared winery's metadata as a side effect of importing a wine.

Limit a batch to 100 records across its collections and a request body to 1 MiB.
Default `import_batch` to validation only, with an explicit `apply` argument for persistence.
Return source references, proposed matches, field changes, duplicate records, validation failures, and bottle totals.
Revalidate on apply because a previous preview does not lock the cellar.
Reject the complete batch before mutation if any record is invalid or ambiguous.

Persist applied source references in a new `mcp_import_records` table keyed by username, source namespace, record kind, and source reference.
Store the destination ID and a fingerprint of the normalized record beside that key.
An identical replay returns the previous destination ID without repeating the write.
Reusing a reference with different content returns a conflict requiring an explicit edit rather than another purchase or review.
This protects retries across restarts and across different batch groupings.

Write imported entities and their source references in one transaction on a dedicated SQLite connection.
Enable foreign keys and a bounded busy timeout on that connection.
Never open a transaction on the application's shared connection, where unrelated web requests could otherwise join the transaction.
Roll back every write if persistence fails.
Use a temporary file-backed database to test transaction behavior with multiple connections.

## Vivino fetcher and rating refresh

Retain ID and URL parsing, legacy vintage-ID resolution, upstream HTTP fetching, and response decoding in the small adapter.
Keep its fetch operations independent of database writes.
The assistant remains responsible for finding a candidate Vivino link when a wine has none.
Return fetched identity and vintage details so the assistant can inspect a candidate before explicitly linking it during import.

`sync_vivino_ratings` accepts at most 20 owned wine IDs per call and has no implicit all-wines mode.
Resolve each stored link and verify that the returned wine ID matches the resolved request before persisting ratings.
Retain support for existing `v`-prefixed vintage IDs and update a resolved link to its canonical wine ID.
Update the overall community rating and ratings for exact, already-known vintages.
Do not add every upstream vintage during a rating refresh.
Do not change wine names, wineries, types, regions, personal notes, personal ratings, bottles, or label images.
Do not erase cached values when upstream data is absent or unrated.
Reject out-of-range ratings and negative rating counts.
Bound upstream requests with timeouts, stop a batch on rate limiting, and return per-wine outcomes without reporting skipped wines as refreshed.
A failed fetch leaves the existing cached values intact.
Apply a successful wine's rating updates atomically after fetching, without holding a database transaction during network requests.

## Removal and migration

Keep existing wines, purchases, personal ratings, wishlist entries, external IDs, and cached community ratings.
Add an import-reference migration without changing historical migrations.
Existing untracked records require preview and reconciliation before a source is imported again.
Do not promise automatic deduplication of historical purchases whose original source references were never recorded.

Remove the ZIP upload handler, its route, navigation links, upload JavaScript, and import-result UI.
Remove the single-wine Vivino import and metadata-sync pages, their form handlers, and their routes.
Remove CSV parsing, disk import, ZIP FFI, and import-only dependencies once no callers remain.
Replace development and test seeding that currently depends on the importer with small deterministic fixtures created through the database API.
Update browser tests to exercise the remaining native forms and verify that removed import entry points are absent.
Keep manual wine creation, manual editing, image uploads, stored Vivino links, community-rating displays, filters, and CSV export.

Document the MCP connection, Authelia client registration, OAuth setup, source-reference rules, initial-import workflow, and ratings-refresh workflow.
Update the invoice-importing skill and scripts so they use the MCP tools rather than the removed HTML import endpoints.
Do not add a second maintained Vivino CSV importer as a replacement helper.

## Validation

- Verify initialization, protocol negotiation, tool discovery, tool schemas, malformed requests, unsupported methods, and structured tool errors.
- Verify that missing, expired, or invalid MCP access tokens cannot inherit web single-user or forwarded-header authority.
- Verify OAuth discovery, resource and scope restrictions, user mapping, and browser login using Codex with the pre-registered Authelia client.
- Verify ownership checks on every tool and on references inside mixed batches.
- Verify exact wine matching, unknown vintages, invalid dates, rating bounds, positive purchase quantities, and integer-cent prices.
- Verify preview has no writes, apply revalidates, partial failure rolls back, and concurrent web writes cannot join an import transaction.
- Verify replayed source references do not duplicate purchases, ratings, or wishlist items after reopening the database.
- Verify an initial multi-batch import preserves source totals and personal data when read through MCP and the existing UI.
- Verify mocked Vivino responses cover legacy links, overall and vintage ratings, mismatched identity, missing values, timeouts, and rate limiting.
- Verify rating sync preserves metadata, images, personal ratings, and bottle counts.
- Run `gleam format .`, `gleam build --warnings-as-errors`, the Gleam tests, the affected browser tests, and an HTTP smoke test on a disposable database.
- Connect an official MCP client to the disposable HTTP server and run discovery, a preview, an apply, a replay, and a readback.

## Protocol references

- [MCP Streamable HTTP, 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [MCP lifecycle, 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
- [Current Streamable HTTP and compatibility requirements](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)
- [Official MCP SDKs](https://modelcontextprotocol.io/docs/2026-07-28/sdk)
- [MCP authorization](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization)
- [Authelia OAuth and OpenID Connect support](https://www.authelia.com/integration/openid-connect/introduction/)
- [Authelia client configuration and PKCE](https://www.authelia.com/configuration/identity-providers/openid-connect/clients/)
- [Codex MCP OAuth client registration and callbacks](https://learn.chatgpt.com/docs/extend/mcp#oauth-client-registration-and-callbacks)
- [Codex OAuth configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
