# Vivino Import Upload

Upload UI for importing Vivino export zip files into Rebstock.

## Overview

Users can upload a Vivino data export (zip file) via a drag-and-drop upload page. The server extracts CSVs from the zip in memory, parses them, and upserts wines, wineries, cellar entries, and wishlist items. Imports are repeatable — vivino IDs identify existing rows, and all fields are overwritten assuming the import is newer.

## Route

`~username/import` — GET renders the upload form, POST handles the upload.

Only the logged-in user can access their own import page.

## Upload UI

- Page at `~username/import` with standard page layout (back link, title "Import Vivino Data")
- Drag-and-drop zone with dashed border, drop hint text, and visual feedback on dragover
- Fallback file input for clicking to select
- Accepts `.zip` files only
- Standard `multipart/form-data` POST (full page submit, no htmx — import may be slow)
- Minimal JS for drag-and-drop events and form submission
- Follows existing stone/amber color palette

## Zip Processing

### Validation

1. Receive multipart upload, extract file bytes
2. Use Erlang `:zip.unzip/2` with `memory` option to extract in-memory (returns `[{filename, binary}]`)
3. Must be a valid zip
4. Must contain `full_wine_list.csv` (required)
5. `cellar.csv` and `wishlisted.csv` are optional
6. Validation errors re-render the upload page with an error message above the drop zone

### Import Order

1. Wines and wineries from `full_wine_list.csv`
2. Cellar entries from `cellar.csv` (if present)
3. Wishlist items from `wishlisted.csv` (if present)

### Upsert Strategy

- Identify existing records by vivino ID
- All fields overwritten (import assumed newer)
- Global data (wines, wineries) updated by any user — friendly coexistence assumed

## Refactor of vivino.gleam

Current import functions read CSVs from disk via `simplifile`. Refactor to:

- Accept CSV content as strings instead of reading from disk
- Return a result type with counts (created/updated per entity)
- The existing disk-based seed import calls the same functions after reading files itself

### Import Result Type

```
ImportResult {
  wineries_created: Int
  wineries_updated: Int
  wines_created: Int
  wines_updated: Int
  cellar_created: Int
  wishlist_created: Int
}
```

## Results Summary

After successful import, the same page renders with a results card showing:

- Wineries: X created, Y updated
- Wines: X created, Y updated
- Cellar entries: X created (if cellar.csv present)
- Wishlist items: X created (if wishlisted.csv present)
- Link to "View your cellar" or back to profile

## Error Handling

All errors re-render the upload page with a message above the drop zone:

- No file uploaded
- Not a valid zip
- Missing required `full_wine_list.csv`
- CSV parse failure

## Multipart Handling

Use `wisp.require_multipart_body` to parse the upload. Extract file bytes from the multipart body, pass raw bytes to Erlang `:zip.unzip/2` with memory option.

## Files Affected

- `src/rebstock/vivino.gleam` — refactor to accept strings, return counts
- `src/rebstock/router.gleam` — add `~username/import` route
- `src/rebstock/web/import.gleam` — new handler for upload page
- `src/rebstock/web/components.gleam` — possibly add error message component if needed
- Seed/dev startup code — update to pass strings to refactored vivino functions
