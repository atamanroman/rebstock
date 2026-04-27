# Wine Images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store wine images on disk (downloaded from Vivino or uploaded), serve via `serve_static`, display with HTML fallback for missing images.

**Architecture:** Images live on disk at `{image_dir}/{wine_id}.jpg`, served by wisp's static file handler under `/images/bottles/`. No DB column — presence of file on disk = has image. HTML `onerror` shows placeholder SVG when image is 404. Config gets `image_dir` field; dev default `./data/images`, DB moves to `./data/rebstock.db`.

**Tech Stack:** Gleam, wisp (`serve_static`), gleam_httpc (`send_bits`), simplifile (`write_bits`, `create_directory_all`), nakai (HTML)

---

## File Map

- **Modify:** `src/rebstock/config.gleam` — add `image_dir` field
- **Modify:** `config.example.json` — add `image_dir`, update `database_uri`
- **Modify:** `config.schema.json` — add `image_dir`, update `database_uri` default
- **Modify:** `.gitignore` — add `data/`
- **Modify:** `src/rebstock.gleam` — create image dir at startup, pass `Config` to router
- **Modify:** `src/rebstock/router.gleam` — accept `Config`, add `serve_static` for images
- **Modify:** `src/rebstock/web/components.gleam` — add `wine_image` component
- **Modify:** `src/rebstock/web/wines.gleam` — use `wine_image`, download image on import/sync
- **Modify:** `src/rebstock/vivino.gleam` — add `download_image` function
- **Modify:** `flake.nix` — add `image_dir` to generated NixOS config
- **Modify:** `test/auth_test.gleam` — update config assertions for new defaults
- **Modify:** `test/vivino_test.gleam` — add `download_image` test (optional, HTTP call)

---

### Task 1: Data directory setup

Move DB default to `./data/rebstock.db`, add `image_dir` config, update gitignore.

**Files:**
- Modify: `src/rebstock/config.gleam:11-21`
- Modify: `config.example.json`
- Modify: `config.schema.json:16-19`
- Modify: `.gitignore`
- Modify: `test/auth_test.gleam:57,79`

- [ ] **Step 1: Update `.gitignore`**

Add `data/` to `.gitignore`:

```
data/
```

Add after the existing `/.worktrees` line. Also remove the now-redundant `*.db`, `/rebstock.db-shm`, `/rebstock.db-wal` lines since they're covered by `data/` (the DB will live there now).

Wait — keep `*.db` since someone might still have a root-level DB from before. Just add `data/`.

- [ ] **Step 2: Update `config.gleam` — add `image_dir` and change DB default**

Change the `Config` type at line 11:

```gleam
pub type Config {
  Config(
    host: String,
    port: Int,
    database_uri: String,
    image_dir: String,
    auth: AuthMode,
  )
}
```

Change `default()` at line 15:

```gleam
pub fn default() -> Config {
  Config(
    host: "127.0.0.1",
    port: 3000,
    database_uri: "file:./data/rebstock.db",
    image_dir: "./data/images",
    auth: Single("admin"),
  )
}
```

Add `image_dir` to the decoder at line 75:

```gleam
fn config_decoder(d: Config) -> decode.Decoder(Config) {
  use host <- decode.optional_field("host", d.host, decode.string)
  use port <- decode.optional_field("port", d.port, decode.int)
  use database_uri <- decode.optional_field(
    "database_uri",
    d.database_uri,
    decode.string,
  )
  use image_dir <- decode.optional_field(
    "image_dir",
    d.image_dir,
    decode.string,
  )
  use auth <- decode.field("auth", auth_decoder())
  decode.success(Config(host:, port:, database_uri:, image_dir:, auth:))
}
```

Add `image_dir` to the log line in `load()` — after `db:` line:

```gleam
<> " | images: "
<> config.image_dir
```

- [ ] **Step 3: Update `config.example.json`**

```json
{
  "$schema": "./config.schema.json",
  "host": "127.0.0.1",
  "port": 3000,
  "database_uri": "file:./data/rebstock.db",
  "image_dir": "./data/images",
  "auth": {
    "single": {
      "user": "admin"
    }
  }
}
```

- [ ] **Step 4: Update `config.schema.json`**

Add `image_dir` property after `database_uri`:

```json
"image_dir": {
  "type": "string",
  "default": "./data/images",
  "description": "Directory for wine bottle images"
},
```

Change `database_uri` default to `"file:./data/rebstock.db"`.

- [ ] **Step 5: Update tests**

In `test/auth_test.gleam`, update the two assertions that check `database_uri`:

Line 57: change `"file:rebstock.db"` to `"file:./data/rebstock.db"`
Line 79: change `"file:rebstock.db"` to `"file:./data/rebstock.db"`

Also add an `image_dir` default assertion in `config_defaults_test`:

```gleam
let assert "./data/images" = cfg.image_dir
```

- [ ] **Step 6: Run tests**

Run: `gleam test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add src/rebstock/config.gleam config.example.json config.schema.json .gitignore test/auth_test.gleam
git commit -m "Add image_dir config, move DB default to ./data/"
```

---

### Task 2: Pass Config through to router

Change router to accept full `Config` instead of just `AuthMode`. Wire up at startup and add image directory creation.

**Files:**
- Modify: `src/rebstock.gleam:14-20`
- Modify: `src/rebstock/router.gleam:1-27`

- [ ] **Step 1: Update `rebstock.gleam` (main)**

Add `simplifile` import. After `db.migrate(conn)`, create the image directory. Pass `cfg` instead of `cfg.auth` to router:

```gleam
import gleam/erlang/process
import mist
import simplifile
import sqlight
import wisp
import wisp/wisp_mist

import rebstock/config
import rebstock/db
import rebstock/router

pub fn main() -> Nil {
  wisp.configure_logger()

  let cfg = config.load(config.parse_args())

  let assert Ok(conn) = sqlight.open(cfg.database_uri)
  db.migrate(conn)

  let assert Ok(_) = simplifile.create_directory_all(cfg.image_dir)

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, conn, cfg), "secret")
    |> mist.new
    |> mist.port(cfg.port)
    |> mist.bind(cfg.host)
    |> mist.start

  process.sleep_forever()
}
```

- [ ] **Step 2: Update `router.gleam`**

Change `handle_request` to accept `Config`. Add second `serve_static` for images. Extract `auth` from config internally:

```gleam
import gleam/erlang/application
import gleam/http
import gleam/string
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth
import rebstock/config.{type Config}
import rebstock/db
import rebstock/web/cellar
import rebstock/web/components as c
import rebstock/web/home
import rebstock/web/imports
import rebstock/web/lists
import rebstock/web/ratings
import rebstock/web/shared
import rebstock/web/wineries
import rebstock/web/wines
import rebstock/web/wishlist

pub fn handle_request(
  req: Request,
  conn: Connection,
  config: Config,
) -> Response {
  use req <- wisp.handle_head(req)
  let assert Ok(priv) = application.priv_directory("rebstock")
  use <- wisp.serve_static(req, under: "/static", from: priv <> "/static")
  use <- wisp.serve_static(
    req,
    under: "/images/bottles",
    from: config.image_dir,
  )

  // Public routes (no auth required)
  case wisp.path_segments(req) {
    ["shared", id, _slug] -> shared.shared_list(conn, id)
    _ -> {
      let user = auth.get_user(req, config.auth)
      db.ensure_user(conn, user.username)
      db.ensure_system_lists(conn, user.username)
```

The rest of the router body stays the same. The only changes are:
- Import `config.{type Config}` instead of `auth.{type AuthMode}`
- Parameter `auth: AuthMode` → `config: Config`
- `auth.get_user(req, auth)` → `auth.get_user(req, config.auth)`
- Remove `import rebstock/auth.{type AuthMode}` (keep `import rebstock/auth`)
- Add `serve_static` for images

For routes that need `image_dir` (vivino import/sync), pass `config.image_dir` — but those changes come in Task 5. For now just get the wiring compiling.

- [ ] **Step 3: Build and test**

Run: `gleam build --warnings-as-errors && gleam test`
Expected: Compiles clean, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/rebstock.gleam src/rebstock/router.gleam
git commit -m "Pass full Config to router, serve images via serve_static"
```

---

### Task 3: Wine image component

Create reusable `wine_image` component with onerror fallback to placeholder SVG.

**Files:**
- Modify: `src/rebstock/web/components.gleam`

- [ ] **Step 1: Add `wine_image` function to `components.gleam`**

Add a public function that renders an `<img>` with the bottle SVG fallback:

```gleam
pub fn wine_image(wine_id: String, class: String) -> Node {
  html.div([attr.class(class <> " relative overflow-hidden")], [
    html.img([
      attr.src("/images/bottles/" <> wine_id <> ".jpg"),
      attr.Attr("alt", ""),
      attr.class("w-full h-full object-contain"),
      attr.Attr(
        "onerror",
        "this.style.display='none';this.nextElementSibling.style.display='flex'",
      ),
    ]),
    html.div(
      [
        attr.class(
          "hidden items-center justify-center w-full h-full bg-stone-100 border border-stone-200 rounded-lg p-1",
        ),
      ],
      [
        html.UnsafeInlineHtml(
          "<svg class=\"w-full h-full\" viewBox=\"0 0 80 220\" fill=\"#2d5a27\" xmlns=\"http://www.w3.org/2000/svg\">"
          <> "<path d=\"M30,0 L30,4 L26,4 L26,8 L30,8 L30,38 C30,52 10,62 10,80 L10,206 C10,214 16,220 24,220 L56,220 C64,220 70,214 70,206 L70,80 C70,62 50,52 50,38 L50,8 L54,8 L54,4 L50,4 L50,0 Z\"/>"
          <> "</svg>",
        ),
      ],
    ),
  ])
}
```

The `class` parameter lets callers set sizing (`"w-28 h-28 shrink-0 hidden sm:flex"` on detail, `"w-10 h-14"` in tables, etc).

- [ ] **Step 2: Build**

Run: `gleam build --warnings-as-errors`
Expected: Compiles clean.

- [ ] **Step 3: Commit**

```bash
git add src/rebstock/web/components.gleam
git commit -m "Add wine_image component with onerror fallback"
```

---

### Task 4: Use wine_image in wine detail

Replace the inline placeholder SVG on the wine detail page with the new component.

**Files:**
- Modify: `src/rebstock/web/wines.gleam:118-134`

- [ ] **Step 1: Replace placeholder in `wine_header`**

In `wine_header` function (line 118), replace the entire `html.div` block containing the bottle SVG placeholder (lines 121-134):

```gleam
// Old (lines 121-134):
      html.div(
        [
          attr.class(
            "hidden sm:flex w-28 h-28 shrink-0 rounded-lg bg-stone-100 border border-stone-200 items-center justify-center p-1",
          ),
        ],
        [
          html.UnsafeInlineHtml(
            "<svg class=\"w-full h-full\" viewBox=\"0 0 80 220\" fill=\"#2d5a27\" xmlns=\"http://www.w3.org/2000/svg\">"
            <> "<path d=\"M30,0 L30,4 L26,4 L26,8 L30,8 L30,38 C30,52 10,62 10,80 L10,206 C10,214 16,220 24,220 L56,220 C64,220 70,214 70,206 L70,80 C70,62 50,52 50,38 L50,8 L54,8 L54,4 L50,4 L50,0 Z\"/>"
            <> "</svg>",
          ),
        ],
      ),
```

Replace with:

```gleam
      c.wine_image(wine.id, "hidden sm:flex w-28 h-28 shrink-0 rounded-lg"),
```

- [ ] **Step 2: Build and test**

Run: `gleam build --warnings-as-errors && gleam test`
Expected: Compiles clean, tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/rebstock/web/wines.gleam
git commit -m "Use wine_image component on wine detail page"
```

---

### Task 5: Download Vivino images on import/sync

Add `download_image` to `vivino.gleam`. Call it from import and sync flows.

**Files:**
- Modify: `src/rebstock/vivino.gleam`
- Modify: `src/rebstock/web/wines.gleam`
- Modify: `src/rebstock/router.gleam`

- [ ] **Step 1: Add `download_image` to `vivino.gleam`**

Add import for `simplifile` at the top. Add this function:

```gleam
pub fn download_image(
  url: String,
  image_dir: String,
  wine_id: String,
) -> Result(Nil, String) {
  case url {
    "" -> Error("No image URL")
    _ ->
      case request.to(url) {
        Error(_) -> Error("Invalid image URL")
        Ok(req) -> {
          let req = request.set_body(req, <<>>)
          case httpc.send_bits(req) {
            Error(e) -> {
              wisp.log_warning(
                "Image download failed: " <> string.inspect(e),
              )
              Error("Image download failed")
            }
            Ok(resp) ->
              case resp.status {
                200 ->
                  case simplifile.write_bits(
                    image_dir <> "/" <> wine_id <> ".jpg",
                    resp.body,
                  ) {
                    Ok(_) -> Ok(Nil)
                    Error(e) -> {
                      wisp.log_warning(
                        "Image write failed: " <> string.inspect(e),
                      )
                      Error("Failed to write image")
                    }
                  }
                status -> Error(
                  "Image download status " <> int.to_string(status),
                )
              }
          }
        }
      }
  }
}
```

Add `import simplifile` to imports. Also need `import gleam/httpc` — check if it's already imported. It is (used by `send`). Add `send_bits` — it's in the same module, no new import needed.

- [ ] **Step 2: Wire image_dir through router to wine handlers**

In `router.gleam`, pass `config.image_dir` to the wine handlers that need it. The vivino import and sync routes need `image_dir`:

For the import route (line 54-58):
```gleam
        ["wines", "import", "vivino"] ->
          case req.method {
            http.Post -> wines.vivino_import(req, conn, user, config.image_dir)
            _ -> wines.vivino_search(req, conn, user)
          }
```

For the sync route (line 65-69):
```gleam
        ["wines", id, _, "sync"] ->
          case req.method {
            http.Post ->
              wines.vivino_sync_apply(req, conn, id, user, config.image_dir)
            _ -> wines.vivino_sync_preview(conn, id, user)
          }
```

- [ ] **Step 3: Update `vivino_import` in `wines.gleam`**

Add `image_dir: String` parameter to `vivino_import`. After the wine is created and synced (around line 1331), download the image:

Find the `vivino_import` function. Add `image_dir` parameter. After `sync_vintages_and_ratings` call (line 1331), add:

```gleam
          // Download wine image
          let _ = vivino.download_image(
            detail.thumb_url,
            image_dir,
            wine_id,
          )
```

Also in the fallback path (when `fetch_wine_with_vintages` fails), skip image download — there's no URL.

The full import success path becomes:

```gleam
      case vivino.fetch_wine_with_vintages(vivino_id) {
        Ok(detail) -> {
          sync_vintages_and_ratings(conn, user.username, wine_id, detail)
          let _ = vivino.download_image(
            detail.thumb_url,
            image_dir,
            wine_id,
          )
        }
        Error(_) -> {
          // Fallback: use rating from form if vintage fetch fails
          case float.parse(form_val(form, "rating")) {
            Ok(rating) ->
              db.upsert_vivino_rating(
                conn,
                username: username,
                wine_id: wine_id,
                vintage: None,
                rating: rating,
              )
            _ -> Nil
          }
        }
      }
```

- [ ] **Step 4: Update `vivino_sync_apply` in `wines.gleam`**

Add `image_dir: String` parameter. After `sync_vintages_and_ratings` (line 1482), download image:

```gleam
          case vivino.fetch_wine_with_vintages(vid) {
            Ok(detail) -> {
              sync_vintages_and_ratings(conn, user.username, wine.id, detail)
              let _ = vivino.download_image(
                detail.thumb_url,
                image_dir,
                wine.id,
              )
            }
            Error(_) -> Nil
          }
```

- [ ] **Step 5: Build and test**

Run: `gleam build --warnings-as-errors && gleam test`
Expected: Compiles clean, tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/rebstock/vivino.gleam src/rebstock/web/wines.gleam src/rebstock/router.gleam
git commit -m "Download Vivino images to disk on import and sync"
```

---

### Task 6: Image upload on wine forms

Add file upload to the create/edit wine forms. The form becomes `multipart/form-data`. On submit, if a file is attached, copy it to `{image_dir}/{wine_id}.jpg`.

**Files:**
- Modify: `src/rebstock/web/wines.gleam` — `wine_form`, `handle_edit_wine`, `create_wine`
- Modify: `src/rebstock/router.gleam` — pass `image_dir` to create/edit handlers

- [ ] **Step 1: Add file input to `wine_form`**

In the `wine_form` function (around line 1063), add a file input after the existing form fields, before the submit button. Add `enctype="multipart/form-data"` to the form element.

Change the form element (line 1095-1099) to include enctype:

```gleam
  html.Element(
    "form",
    [
      attr.method("post"),
      attr.Attr("action", action),
      attr.Attr("enctype", "multipart/form-data"),
```

Add the file input field (add it near the end of the form fields, before the submit button). Use the existing form field styling pattern from the file:

```gleam
      // Image upload
      html.div([attr.class("space-y-1")], [
        html.label([attr.class("block text-sm text-stone-600")], [
          html.Text("Image"),
        ]),
        html.input([
          attr.type_("file"),
          attr.name("image"),
          attr.Attr("accept", "image/*"),
          attr.class("block w-full text-sm text-stone-500 file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border file:border-stone-300 file:text-sm file:text-stone-700 file:bg-white hover:file:bg-stone-50"),
        ]),
      ]),
```

- [ ] **Step 2: Update router to pass `image_dir` to create/edit wine handlers**

In `router.gleam`, update the wine create and edit routes:

```gleam
        ["wines"] ->
          case req.method {
            http.Post -> wines.create_wine(req, conn, user, config.image_dir)
            _ -> wines.wines(conn, user)
          }
```

```gleam
        ["wines", id, _, "edit"] ->
          case req.method {
            http.Post ->
              wines.handle_edit_wine(req, conn, id, user, config.image_dir)
            _ -> wines.edit_wine_form(req, conn, id, user)
          }
```

- [ ] **Step 3: Update `create_wine` to handle image upload**

Add `image_dir: String` parameter to `create_wine`. After the wine is created (after `db.upsert_wine` returns `wine_id`), check for uploaded file:

```gleam
      // Save uploaded image if present
      case list.key_find(form.files, "image") {
        Ok(file) ->
          case file.file_name {
            "" -> Nil
            _ -> {
              let _ = simplifile.copy(
                file.path,
                image_dir <> "/" <> wine_id <> ".jpg",
              )
              Nil
            }
          }
        Error(_) -> Nil
      }
```

Add `import simplifile` to the imports of `wines.gleam`.

- [ ] **Step 4: Update `handle_edit_wine` to handle image upload**

Add `image_dir: String` parameter. After `db.update_wine` (around line 1027), save the uploaded image:

```gleam
              // Save uploaded image if present
              case list.key_find(form.files, "image") {
                Ok(file) ->
                  case file.file_name {
                    "" -> Nil
                    _ -> {
                      let _ = simplifile.copy(
                        file.path,
                        image_dir <> "/" <> id <> ".jpg",
                      )
                      Nil
                    }
                  }
                Error(_) -> Nil
              }
```

- [ ] **Step 5: Build and test**

Run: `gleam build --warnings-as-errors && gleam test`
Expected: Compiles clean, tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/rebstock/web/wines.gleam src/rebstock/router.gleam
git commit -m "Add image upload on wine create and edit forms"
```

---

### Task 7: NixOS module update

Add `image_dir` to the generated NixOS config so prod deployments get images in the right place.

**Files:**
- Modify: `flake.nix:105-120`

- [ ] **Step 1: Update generated config in flake.nix**

In the `configJson` generation block (line 105), add `image_dir`:

```nix
else pkgs.writeText "rebstock-config.json" (builtins.toJSON ({
  host = cfg.host;
  port = cfg.port;
  database_uri = "file:${cfg.dataDir}/rebstock.db";
  image_dir = "${cfg.dataDir}/images";
  auth =
```

No new NixOS option needed — `image_dir` derives from existing `dataDir`. The systemd service already has `StateDirectory = "rebstock"` which ensures `/var/lib/rebstock` exists and is writable.

- [ ] **Step 2: Build and test**

Run: `gleam build --warnings-as-errors && gleam test`
Expected: Compiles clean (flake.nix is Nix, not Gleam, but verify Gleam still builds).

- [ ] **Step 3: Commit**

```bash
git add flake.nix
git commit -m "Add image_dir to NixOS module config"
```

---

### Task 8: Format, lint, manual test

- [ ] **Step 1: Format**

Run: `gleam format .`

- [ ] **Step 2: Lint**

Run: `gleam build --warnings-as-errors`
Expected: No warnings.

- [ ] **Step 3: Run full test suite**

Run: `gleam test`
Expected: All tests pass.

- [ ] **Step 4: Manual smoke test**

Run: `just dev`

1. Check `./data/` directory was created with `images/` subdirectory
2. Go to Vivino import, search for a wine, import it — verify image appears on wine detail
3. Go to wine detail → edit → upload a different image — verify it replaces the Vivino one
4. Create a wine manually without image — verify placeholder SVG shows
5. Sync a wine with Vivino — verify image downloads

- [ ] **Step 5: Final commit (if any formatting changes)**

```bash
git add -A
git commit -m "Format and lint pass"
```
