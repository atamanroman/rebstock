# MCP import and Vivino ratings implementation plan

**Goal:** Replace the Vivino import and metadata-sync screens with authenticated MCP tools while preserving existing cellar data and a small Vivino fetcher.

**Architecture:** Serve stateless MCP JSON-RPC through Wisp and authenticate Authelia JWT access tokens independently of web forward auth.
Keep batch import, token verification, tool serialization, and Vivino rating persistence in separate modules.
Use a dedicated SQLite connection for each atomic mutation so web requests cannot join MCP transactions.

**Stack:** Gleam, BEAM, Wisp, gleam_json, gleam_httpc, sqlight, and OTP cryptography.

## Task 1: OAuth resource-server authentication

**Files:** `src/rebstock/mcp/oauth.gleam`, `src/rebstock/mcp_oauth_ffi.erl`, `src/rebstock/config.gleam`, `config.schema.json`, `config.example.json`, `flake.nix`, and OAuth tests.

- [x] Add failing tests for missing credentials, forged JWTs, wrong issuer/audience/client/scope, expired tokens, invalid origins, and unavailable signing keys.
- [x] Add optional MCP configuration with resource URL, issuer, JWKS URI, allowed client ID, required scope, and username claim.
- [x] Implement protected-resource metadata and bearer challenges.
- [x] Verify signed JWT access tokens using pinned issuer/JWKS configuration and PKCE client registration documented for Authelia.
- [x] Test token verification using real locally generated signing keys and mocked upstream key responses.
- [x] Keep secrets out of generated Nix configuration and keep MCP disabled by default.

```gleam
pub fn authenticate(req: Request, config: Config) -> Result(User, Failure)
pub fn challenge(config: Config, failure: Failure) -> Response
pub fn metadata(config: Config) -> Response
pub fn valid_origin(req: Request, config: Config) -> Bool
pub fn decoder() -> decode.Decoder(Config)
```

## Task 2: Atomic and repeatable batch import

**Files:** `src/rebstock/mcp/imports.gleam`, optional focused import helpers, `priv/migrations/00006_mcp_import_records.up.sql`, its down migration, and import tests.

- [x] Add failing tests for preview, apply, exact matching, ownership, invalid source records, cross-batch references, repeated imports, and transaction rollback.
- [x] Decode source namespaces and stable references for wine, purchase, rating, and wishlist records.
- [x] Reject ambiguous wine matches, invalid dates/vintages/prices/ratings, and shared-winery metadata conflicts before writes.
- [x] Build a full preview including exact matches, field changes, per-record outcomes, and bottle totals.
- [x] Persist imported entities and record fingerprints in one dedicated-connection transaction.
- [x] Test same-reference replay and changed-content conflicts after closing and reopening a file-backed database.
- [x] Test a failed batch leaves no partial entities or recorded references.

```gleam
pub fn run(database_uri: String, username: String, arguments: Dynamic) -> Result(Json, String)
pub fn schema() -> Json
```

## Task 3: Remove the old import surface and replace fixtures

**Files:** `src/rebstock/vivino.gleam`, `src/rebstock/web/wines.gleam`, `src/rebstock/web/imports.gleam`, home/navigation components, dev startup, seed helpers, dependency files, importer tests, and browser tests.

- [x] Add regression assertions that old import and metadata-sync navigation is absent.
- [x] Replace CSV-dependent dev/test seeds with deterministic DB fixtures.
- [x] Remove ZIP/CSV handling, ZIP FFI, upload handlers, and wine import/sync UI.
- [x] Preserve wine editing, image upload, external links, community rating displays, filters, and CSV export.
- [x] Remove dependencies that have no remaining callers and update coverage module registration.
- [x] Run affected Gleam and browser tests without accessing Vivino.

## Task 4: MCP protocol, read tools, and ratings-only sync

**Files:** `src/rebstock/mcp.gleam`, `src/rebstock/mcp/tools.gleam`, serialization helpers, ratings-sync module, `src/rebstock/router.gleam`, and MCP tests.

- [x] Test initialization, tools/list, tools/call, ping, notifications, parse errors, unknown methods, unsupported transport requests, and request-size limits.
- [x] Intercept MCP routes before web authentication and publish protected-resource metadata publicly.
- [x] Enforce exact external Origin checks and bearer verification before executing MCP operations.
- [x] Expose owned wine search/details, cellar, personal ratings, and wishlist with bounded pagination.
- [x] Connect `import_batch` to the isolated importer and expose its schema.
- [x] Add deterministic Vivino lookup and exact-vintage ratings refresh with bounded batches and upstream timeouts.
- [x] Test identity mismatch, cached-rating preservation, metadata preservation, missing values, timeouts, rate limiting, and owned-wine restrictions.

## Task 5: Connection instructions and final verification

**Files:** `docs/mcp.md`, `README.md`, project guidance, invoice-import skill/scripts, and an official-client smoke test.

- [x] Document the Authelia public Codex client, audience, custom scope, signing algorithm, username claims, callback registration, and reverse-proxy routing.
- [x] Document preview/apply and stable source references with complete MCP examples.
- [x] Update invoice imports to call MCP tools without the removed form routes.
- [x] Run `gleam format .`, `gleam build --warnings-as-errors`, and the full Gleam tests.
- [x] Run Chromium/WebKit browser tests against a disposable database.
- [x] Use a mock OAuth issuer and an official MCP client to verify discovery, authentication, preview, apply, replay, and readback through a real socket.
- [x] Review spec coverage and code quality, fix findings, and rerun only the affected checks.
- [x] Prepare the real Authelia/Caddy/Codex configuration for review and report deployment and live browser login separately from local verification.
