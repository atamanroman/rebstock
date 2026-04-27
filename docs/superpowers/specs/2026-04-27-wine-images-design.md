# Wine Images

Store wine images on disk, serve via `serve_static`, download from Vivino during import/sync, allow manual upload later.

## Data directory

Move all mutable data under `./data/` in dev:

- Default `database_uri` changes from `file:rebstock.db` to `file:./data/rebstock.db`
- Images stored at `{image_dir}/{wine_id}.jpg`
- `image_dir` config field, default `"./data/images"`
- `data/` added to `.gitignore`
- Config example and schema updated
- NixOS module: `dataDir` already defaults to `/var/lib/rebstock`, images go to `{dataDir}/images`

No DB migration. Image existence is convention-based: file on disk = has image.

## Config changes

Add `image_dir: String` to `Config`:

```json
{
  "image_dir": "./data/images",
  "database_uri": "file:./data/rebstock.db"
}
```

Default: `"./data/images"`. Prod deployments override via config (e.g. `/var/lib/rebstock/images`).

Adjust the json schema and the examples as well.

## Serving

Second `serve_static` in router:

```gleam
use <- wisp.serve_static(req, under: "/images/bottles", from: config.image_dir)
```

Images served at `/images/bottles/{wine_id}.jpg`. 404 for missing images handled in HTML.

## HTML fallback

Wine image component wraps `<img>` + placeholder. On `onerror`, hide `<img>`, show placeholder SVG (existing bottle SVG from wine detail). Works everywhere: wine detail, search results, cards.

```html
<img src="/images/bottles/{wine_id}.jpg"
     onerror="this.style.display='none';this.nextElementSibling.style.display='flex'"
     class="w-28 h-28 object-contain" />
<div style="display:none" class="placeholder...">
  <!-- existing bottle SVG -->
</div>
```

Extract as `c.wine_image(wine_id)` component in `web/components.gleam`.

## Vivino image download

During import and sync, after creating/updating the wine:

1. `VivinoWineDetail` already has `thumb_url` (from API)
2. HTTP GET the image URL
3. Save to `{image_dir}/{wine_id}.jpg`
4. If download fails, log warning, continue (image is optional)

New function in `vivino.gleam`:

```
pub fn download_image(url: String, dest: String) -> Result(Nil, String)
```

Uses `gleam_httpc` (already a dependency). Writes binary response body to disk via `simplifile.write_bits`.

Called from `vivino_import` and `vivino_sync_apply` after wine creation/update.

## Image selection

Per wine (not per vintage). During Vivino import, use `thumb_url` from the `VivinoWineDetail` (which is the wine-level image from the mobile API). This is already decoded and available.

During CSV import: no image (Vivino export CSVs don't include image URLs).

## Directory creation

`simplifile.create_directory_all(image_dir)` at startup, right after DB migration. Ensures the directory exists before any handler tries to write.

## Passing config to router

`handle_request` currently takes `(req, conn, auth)`. Add `image_dir: String` parameter so the router can pass it to `serve_static` and to import/sync handlers that need to save images.

Alternative: pass full `Config` instead of individual fields. Cleaner if more config fields get added later. Router signature becomes `handle_request(req, conn, config)` and extracts `config.auth`, `config.image_dir` internally.

Go with passing full `Config` — simpler, future-proof.

## Manual upload

Allow to upload (click of drag&drop) on the edit/create form.

## Summary of changes

1. **config.gleam**: add `image_dir` field, change `database_uri` default
2. **config.example.json + config.schema.json**: add `image_dir`, update `database_uri`
3. **.gitignore**: add `data/`
4. **rebstock.gleam (main)**: create image directory at startup, pass `Config` to router
5. **router.gleam**: accept `Config`, add `serve_static` for images, pass `image_dir` to wine handlers
6. **web/components.gleam**: `wine_image(wine_id)` component with onerror fallback
7. **web/wines.gleam**: replace placeholder SVG with `wine_image`, call `download_image` in import/sync
8. **vivino.gleam**: `download_image(url, dest)` function
9. **flake.nix**: update NixOS module image path config
