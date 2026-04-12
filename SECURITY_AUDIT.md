# Security & Code Quality Audit

**Date:** 2026-04-11
**Scope:** Full codebase review (pre-0.1.0 release)

## Security

### High

**S1: No CSRF protection on any forms**
Wisp has no built-in CSRF tokens. All POST forms (create/edit wines, ratings, cellar entries, list toggles, imports) are vulnerable to cross-site request forgery. An attacker-controlled page could submit state-changing requests on behalf of a logged-in user.

**S2: `remove_wine` route accepts any HTTP method**
`router.gleam:104` routes `/~user/lists/:id/wines/:wine_id` to `lists.remove_wine` without checking `req.method`. A GET request (browser prefetch, crawler) can delete wines from lists.

**S3: `cellar_csv` has no authorization check**
`cellar.gleam:87` ignores the `_user` parameter. Any authenticated user can export any other user's cellar by visiting `/~victim/cellar/export.csv`.

### Medium

**S4: Open redirect via `redirect` form field**
`lists.gleam` `redirect_or_default` passes a user-controlled form value directly to `wisp.redirect()` with no validation. Combined with the CSRF issue, this enables phishing via `redirect=https://evil.com`.

**S5: Forward auth headers spoofable without reverse proxy**
`auth.gleam` trusts `x-webauth-user` unconditionally. If the app is exposed directly (not behind a proxy that sets/strips this header), any client can impersonate any user. This is inherent to forward auth but should be documented.

**S6: No upload size limit on zip import**
`imports.gleam` reads the entire uploaded zip into memory with no size check. A zip bomb could exhaust server memory. Wisp may enforce a default body limit, but there is no explicit application-level guard.

**S7: No server-side rating range validation**
`ratings.gleam` stores rating values from the form without validating they are within 0.0-5.0. Crafted POST requests can store arbitrary values, breaking the color scale display.

## Data Integrity

### Medium

**D1: `upsert_winery` / `upsert_wine` race conditions**
`db.gleam` upsert functions do a SELECT then INSERT/UPDATE as two separate queries. Under concurrent requests, two processes can both see no existing row and both INSERT, causing a UNIQUE constraint crash. Should use `INSERT ... ON CONFLICT`.

**D2: `delete_cellar_entry` is non-atomic**
`db.gleam` deletes children then parent in two separate queries. A crash between the two could leave orphan rows. Should be wrapped in a transaction.

## Code Quality

### High

**Q1: Duplicate `wine_type_label` function**
`components.gleam` defines `wine_type_label` which is identical to and shadows `db.wine_type_label`. The components version is dead code.

### Medium

**Q2: Inconsistent authorization patterns**
Some routes check `user.username == username` up front, others check after fetching the entity, and `cellar_csv` skips the check entirely. No consistent middleware or helper for authorization.

**Q3: Winery edit has no ownership check**
`wineries.gleam` `handle_edit_winery` allows any authenticated user to edit any winery. Wineries are global by design, but unrestricted editing could cause problems in multi-user setups.

### Low

**Q4: `count_wines` called twice in `site_header`**
`components.gleam` calls `db.count_wines(conn)` once to check for zero, then again to format. Should store the result.

**Q5: `ensure_user` + `ensure_system_lists` runs on every request**
`router.gleam` runs 4 INSERT queries per page load for already-existing users. Safe (`INSERT OR IGNORE`) but wasteful.

**Q6: Inline JS onclick handlers interpolate DB-derived values**
Wine/winery URLs are injected into `onclick="window.location='...'"` attributes. Currently safe due to `uri.percent_encode` in `slugify`, but the pattern is fragile. A safer approach would avoid inline JS entirely.

**Q7: Duplicated helpers across modules**
`is_htmx`, `form_value`, `form_field`, `req_field` are duplicated between cellar.gleam and ratings.gleam. Should be consolidated into components.

**Q8: `update_wine` takes 10 positional parameters**
Easy to mix up argument order. Should use labeled arguments like `upsert_wine` does.

**Q9: `parse_optional_int` is unused**
`db.gleam` exports `parse_optional_int` which is never called.
