# Vivino Import Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a drag-and-drop upload page at `~username/import` that accepts Vivino export zip files, extracts CSVs in memory, and upserts wines/wineries/cellar/wishlist data.

**Architecture:** Refactor `vivino.gleam` to accept CSV strings and return import counts. Add a new `web/import.gleam` handler with multipart upload support. Use Erlang's `:zip` module to extract zip contents in memory. The upload page uses a standard `multipart/form-data` POST with drag-and-drop JS enhancement.

**Tech Stack:** Gleam/Erlang, wisp (multipart), nakai (HTML), Erlang `:zip` module, htmx (minimal), Tailwind CSS

---

### Task 1: Refactor vivino.gleam to accept CSV strings and return counts

**Files:**
- Modify: `src/rebstock/vivino.gleam`

- [ ] **Step 1: Define ImportResult type**

Add at the top of `src/rebstock/vivino.gleam`:

```gleam
pub type ImportResult {
  ImportResult(
    wineries_created: Int,
    wineries_updated: Int,
    wines_created: Int,
    wines_updated: Int,
    cellar_created: Int,
    wishlist_created: Int,
  )
}

pub fn empty_result() -> ImportResult {
  ImportResult(
    wineries_created: 0,
    wineries_updated: 0,
    wines_created: 0,
    wines_updated: 0,
    cellar_created: 0,
    wishlist_created: 0,
  )
}

pub fn merge_results(a: ImportResult, b: ImportResult) -> ImportResult {
  ImportResult(
    wineries_created: a.wineries_created + b.wineries_created,
    wineries_updated: a.wineries_updated + b.wineries_updated,
    wines_created: a.wines_created + b.wines_created,
    wines_updated: a.wines_updated + b.wines_updated,
    cellar_created: a.cellar_created + b.cellar_created,
    wishlist_created: a.wishlist_created + b.wishlist_created,
  )
}
```

- [ ] **Step 2: Refactor import_cellar to accept string content**

Change the signature from `fn import_cellar(conn, path, created_by)` to `pub fn import_cellar(conn, content, created_by)` and remove the `simplifile.read(path)` call, accepting the CSV content as a `String` parameter directly. Return `ImportResult` instead of `Nil`.

The function should track counts: each successful `db.upsert_wine` call increments `wines_created` (we don't distinguish created vs updated from `upsert_wine` yet — count all as created for now). Each `db.insert_cellar_entry` call increments `cellar_created`.

```gleam
pub fn import_cellar(
  conn: Connection,
  content: String,
  created_by: String,
) -> ImportResult {
  let assert Ok(rows) = gsv.to_lists(content, ",")
  case rows {
    [_header, ..data] ->
      list.fold(data, empty_result(), fn(acc, row) {
        case row {
          [
            winery,
            name,
            vintage_str,
            region,
            country,
            style,
            avg_rating,
            _rating_count,
            wine_type,
            vivino_link,
            cellar_count,
          ] ->
            case is_blank(name) {
              True -> acc
              False -> {
                let vintage = db.parse_vintage(vintage_str)
                let wine_id =
                  db.upsert_wine(
                    conn,
                    created_by:,
                    winery:,
                    name:,
                    vintage:,
                    region: db.optional_non_empty(region),
                    country: db.country_to_iso(country),
                    style: db.optional_non_empty(style),
                    personal_note: None,
                    wine_type: db.wine_type_from_string(wine_type),
                    vivino_id: extract_vivino_id(vivino_link),
                  )
                case db.parse_optional_float(avg_rating) {
                  Some(r) ->
                    db.insert_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating: Some(r),
                      tasting_notes: None,
                      rated_at: None,
                      source: "vivino",
                    )
                  None -> Nil
                }
                let bottles = db.parse_int_or_zero(cellar_count)
                let cellar_add = case bottles > 0 {
                  True -> {
                    case vintage {
                      Some(v) -> db.upsert_vintage(conn, wine_id, v)
                      None -> Nil
                    }
                    db.insert_cellar_entry(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      quantity: bottles,
                      notes: None,
                      date: None,
                    )
                    1
                  }
                  False -> 0
                }
                ImportResult(
                  ..acc,
                  wines_created: acc.wines_created + 1,
                  cellar_created: acc.cellar_created + cellar_add,
                )
              }
            }
          _ -> acc
        }
      })
    _ -> empty_result()
  }
}
```

- [ ] **Step 3: Refactor import_full_wine_list to accept string content**

Same pattern — change signature to `pub fn import_full_wine_list(conn, content, created_by) -> ImportResult`, remove `simplifile.read`, return counts.

```gleam
pub fn import_full_wine_list(
  conn: Connection,
  content: String,
  created_by: String,
) -> ImportResult {
  let assert Ok(rows) = gsv.to_lists(content, ",")
  case rows {
    [_header, ..data] ->
      list.fold(data, empty_result(), fn(acc, row) {
        case row {
          [
            winery,
            name,
            vintage_str,
            region,
            country,
            style,
            avg_rating,
            _scan_date,
            _scan_location,
            user_rating,
            user_review,
            personal_note,
            wine_type,
            _drinking_window,
            vivino_link,
            ..
          ] ->
            case is_blank(name) {
              True -> acc
              False -> {
                let vintage = db.parse_vintage(vintage_str)
                let wine_id =
                  db.upsert_wine(
                    conn,
                    created_by:,
                    winery:,
                    name:,
                    vintage:,
                    region: db.optional_non_empty(region),
                    country: db.country_to_iso(country),
                    style: db.optional_non_empty(style),
                    personal_note: db.optional_non_empty(personal_note),
                    wine_type: db.wine_type_from_string(wine_type),
                    vivino_id: extract_vivino_id(vivino_link),
                  )
                case db.parse_optional_float(avg_rating) {
                  Some(r) ->
                    db.insert_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating: Some(r),
                      tasting_notes: None,
                      rated_at: None,
                      source: "vivino",
                    )
                  None -> Nil
                }
                let rating = db.parse_optional_float(user_rating)
                let tasting_notes = db.optional_non_empty(user_review)
                case rating, tasting_notes {
                  None, None -> Nil
                  _, _ ->
                    db.insert_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating:,
                      tasting_notes:,
                      rated_at: None,
                      source: "user",
                    )
                }
                ImportResult(..acc, wines_created: acc.wines_created + 1)
              }
            }
          _ -> acc
        }
      })
    _ -> empty_result()
  }
}
```

- [ ] **Step 4: Refactor import_wishlisted to accept string content**

Same pattern — `pub fn import_wishlisted(conn, content, created_by) -> ImportResult`.

```gleam
pub fn import_wishlisted(
  conn: Connection,
  content: String,
  created_by: String,
) -> ImportResult {
  let assert Ok(rows) = gsv.to_lists(content, ",")
  case rows {
    [_header, ..data] ->
      list.fold(data, empty_result(), fn(acc, row) {
        case row {
          [
            winery,
            name,
            vintage_str,
            region,
            country,
            style,
            avg_rating,
            _scan_date,
            _scan_location,
            user_rating,
            user_review,
            personal_note,
            wine_type,
            _wishlisted_date,
            _drinking_window,
            vivino_link,
            ..
          ] ->
            case is_blank(name) {
              True -> acc
              False -> {
                let vintage = db.parse_vintage(vintage_str)
                let wine_id =
                  db.upsert_wine(
                    conn,
                    created_by:,
                    winery:,
                    name:,
                    vintage:,
                    region: db.optional_non_empty(region),
                    country: db.country_to_iso(country),
                    style: db.optional_non_empty(style),
                    personal_note: db.optional_non_empty(personal_note),
                    wine_type: db.wine_type_from_string(wine_type),
                    vivino_id: extract_vivino_id(vivino_link),
                  )
                case db.parse_optional_float(avg_rating) {
                  Some(r) ->
                    db.insert_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating: Some(r),
                      tasting_notes: None,
                      rated_at: None,
                      source: "vivino",
                    )
                  None -> Nil
                }
                db.upsert_wishlist(
                  conn,
                  username: created_by,
                  wine_id:,
                  vintage:,
                  notes: None,
                )
                let rating = db.parse_optional_float(user_rating)
                let tasting_notes = db.optional_non_empty(user_review)
                case rating, tasting_notes {
                  None, None -> Nil
                  _, _ ->
                    db.insert_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating:,
                      tasting_notes:,
                      rated_at: None,
                      source: "user",
                    )
                }
                ImportResult(..acc, wishlist_created: acc.wishlist_created + 1)
              }
            }
          _ -> acc
        }
      })
    _ -> empty_result()
  }
}
```

- [ ] **Step 5: Update import_data to use refactored functions**

Update `import_data` to read files from disk and pass content strings to the refactored functions:

```gleam
pub fn import_data(
  conn: Connection,
  data_dir: String,
  created_by: String,
) -> Nil {
  db.ensure_user(conn, created_by)
  let assert Ok(cellar_csv) = simplifile.read(data_dir <> "/cellar.csv")
  let assert Ok(wine_list_csv) =
    simplifile.read(data_dir <> "/full_wine_list.csv")
  let assert Ok(wishlist_csv) = simplifile.read(data_dir <> "/wishlisted.csv")
  import_cellar(conn, cellar_csv, created_by)
  import_full_wine_list(conn, wine_list_csv, created_by)
  import_wishlisted(conn, wishlist_csv, created_by)
  let count = db.count_wines(conn)
  wisp.log_info(
    "Imported " <> int.to_string(count) <> " wines for " <> created_by,
  )
}
```

- [ ] **Step 6: Build and run tests**

Run: `gleam build --warnings-as-errors && gleam test`

Expected: All existing tests pass. No warnings.

- [ ] **Step 7: Commit**

```bash
git add src/rebstock/vivino.gleam
git commit -m "Refactor vivino imports to accept CSV strings and return counts"
```

### Task 2: Add zip extraction and import_from_zip function

**Files:**
- Modify: `src/rebstock/vivino.gleam`

- [ ] **Step 1: Add Erlang zip FFI**

Add an external function to call Erlang's `:zip.unzip/2` with the `memory` option. Create the FFI binding. In Gleam, use `@external` to call Erlang directly.

Add to `src/rebstock/vivino.gleam`:

```gleam
@external(erlang, "zip", "unzip")
fn erlang_unzip(
  archive: BitArray,
  options: List(dynamic.Dynamic),
) -> Result(dynamic.Dynamic, dynamic.Dynamic)
```

Also add the needed import for `gleam/dynamic`.

- [ ] **Step 2: Add import_from_zip function**

This is the main entry point for the upload handler. It takes zip bytes, extracts CSVs, validates, and runs imports:

```gleam
pub fn import_from_zip(
  conn: Connection,
  zip_bytes: BitArray,
  created_by: String,
) -> Result(ImportResult, String) {
  db.ensure_user(conn, created_by)
  case extract_zip(zip_bytes) {
    Error(e) -> Error(e)
    Ok(files) -> {
      case find_file(files, "full_wine_list.csv") {
        Error(_) -> Error("Zip must contain full_wine_list.csv")
        Ok(wine_list_csv) -> {
          let result = import_full_wine_list(conn, wine_list_csv, created_by)
          let result = case find_file(files, "cellar.csv") {
            Ok(cellar_csv) ->
              merge_results(
                result,
                import_cellar(conn, cellar_csv, created_by),
              )
            Error(_) -> result
          }
          let result = case find_file(files, "wishlisted.csv") {
            Ok(wishlist_csv) ->
              merge_results(
                result,
                import_wishlisted(conn, wishlist_csv, created_by),
              )
            Error(_) -> result
          }
          Ok(result)
        }
      }
    }
  }
}

fn extract_zip(
  zip_bytes: BitArray,
) -> Result(List(#(String, String)), String) {
  let memory_opt = dynamic.from(atom.create_from_string("memory"))
  case erlang_unzip(zip_bytes, [memory_opt]) {
    Error(_) -> Error("Invalid zip file")
    Ok(result) -> {
      // Result is {ok, [{filename, binary}]}
      // We need to decode the list of tuples
      case
        dynamic.element(1, dynamic.list(dynamic.tuple2(
          fn(d) {
            // Filename can be a charlist in Erlang
            case dynamic.string(d) {
              Ok(s) -> Ok(s)
              Error(_) ->
                case dynamic.dynamic(d) {
                  Ok(d2) -> {
                    case charlist_to_string(d2) {
                      Ok(s) -> Ok(s)
                      Error(e) -> Error(e)
                    }
                  }
                  Error(e) -> Error(e)
                }
            }
          },
          dynamic.bit_array,
        )))(result)
      {
        Error(_) -> Error("Failed to read zip contents")
        Ok(entries) ->
          Ok(
            list.filter_map(entries, fn(entry) {
              let #(name, data) = entry
              // Extract just the filename (strip directory paths)
              let filename = case string.split(name, "/") |> list.last {
                Ok(f) -> f
                Error(_) -> name
              }
              case bit_array.to_string(data) {
                Ok(content) -> Ok(#(filename, content))
                Error(_) -> Error(Nil)
              }
            }),
          )
      }
    }
  }
}

fn find_file(
  files: List(#(String, String)),
  name: String,
) -> Result(String, Nil) {
  list.find_map(files, fn(entry) {
    case entry.0 == name {
      True -> Ok(entry.1)
      False -> Error(Nil)
    }
  })
}
```

Note: We need `gleam/dynamic`, and `gleam/erlang/atom` imports. The Erlang `:zip.unzip/2` with `[memory]` option returns `{ok, [{Filename, Binary}]}` where `Filename` is a charlist. We need a charlist-to-string helper:

```gleam
@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(
  charlist: dynamic.Dynamic,
) -> Result(String, List(dynamic.DecodeError))
```

Actually, the simpler approach is to use `erlang:list_to_binary` for charlist conversion. Let me simplify — Erlang's zip module returns charlists for filenames. The cleanest way is to write a small Erlang FFI helper. But since we want to minimize files, let's use a different approach:

The Erlang `:zip.unzip/2` call with `[memory]` returns `{ok, FileList}` where `FileList` is `[{FileName, FileContent}]`. FileName is a charlist (Erlang string). We can handle this by using a custom decoder or by wrapping the call.

Let me simplify. Create a small Erlang helper file:

**Create file:** `src/rebstock/zip_ffi.erl`

```erlang
-module(zip_ffi).
-export([unzip_memory/1]).

unzip_memory(ZipBinary) ->
    case zip:unzip(ZipBinary, [memory]) of
        {ok, FileList} ->
            Converted = [{unicode:characters_to_binary(Name), Content}
                         || {Name, Content} <- FileList],
            {ok, Converted};
        {error, Reason} ->
            {error, Reason}
    end.
```

Then in Gleam:

```gleam
@external(erlang, "zip_ffi", "unzip_memory")
fn unzip_memory(
  archive: BitArray,
) -> Result(List(#(String, BitArray)), dynamic.Dynamic)
```

This is much cleaner. The full `import_from_zip` and `extract_zip` simplify to:

```gleam
pub fn import_from_zip(
  conn: Connection,
  zip_bytes: BitArray,
  created_by: String,
) -> Result(ImportResult, String) {
  db.ensure_user(conn, created_by)
  case unzip_memory(zip_bytes) {
    Error(_) -> Error("Invalid zip file")
    Ok(entries) -> {
      let files =
        list.filter_map(entries, fn(entry) {
          let #(name, data) = entry
          let filename = case string.split(name, "/") |> list.last {
            Ok(f) -> f
            Error(_) -> name
          }
          case bit_array.to_string(data) {
            Ok(content) -> Ok(#(filename, content))
            Error(_) -> Error(Nil)
          }
        })
      case find_file(files, "full_wine_list.csv") {
        Error(_) -> Error("Zip must contain full_wine_list.csv")
        Ok(wine_list_csv) -> {
          let result = import_full_wine_list(conn, wine_list_csv, created_by)
          let result = case find_file(files, "cellar.csv") {
            Ok(cellar_csv) ->
              merge_results(
                result,
                import_cellar(conn, cellar_csv, created_by),
              )
            Error(_) -> result
          }
          let result = case find_file(files, "wishlisted.csv") {
            Ok(wishlist_csv) ->
              merge_results(
                result,
                import_wishlisted(conn, wishlist_csv, created_by),
              )
            Error(_) -> result
          }
          Ok(result)
        }
      }
    }
  }
}
```

- [ ] **Step 3: Add needed imports**

Add to the top of `vivino.gleam`:

```gleam
import gleam/bit_array
import gleam/dynamic
```

Remove `simplifile` import if no longer needed (it's still used by `import_data`), so keep it.

- [ ] **Step 4: Build and run tests**

Run: `gleam build --warnings-as-errors && gleam test`

Expected: All tests pass. No warnings.

- [ ] **Step 5: Commit**

```bash
git add src/rebstock/vivino.gleam src/rebstock/zip_ffi.erl
git commit -m "Add zip extraction and import_from_zip entry point"
```

### Task 3: Add import route and handler

**Files:**
- Create: `src/rebstock/web/import.gleam`
- Modify: `src/rebstock/router.gleam`

- [ ] **Step 1: Create the import handler module**

Create `src/rebstock/web/import.gleam`:

```gleam
import gleam/http
import gleam/int
import gleam/list
import nakai/attr
import nakai/html
import simplifile
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type User}
import rebstock/vivino
import rebstock/web/components as c

pub fn import_page(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
) -> Response {
  case username == user.username {
    False -> wisp.response(403)
    True ->
      case req.method {
        http.Get -> render_upload_page(user, None, None)
        http.Post -> handle_upload(req, conn, user)
        _ -> wisp.method_not_allowed([http.Get, http.Post])
      }
  }
}

fn handle_upload(
  req: Request,
  conn: Connection,
  user: User,
) -> Response {
  use form <- wisp.require_form(req)
  case list.key_find(form.files, "zipfile") {
    Error(_) -> render_upload_page(user, Some("No file uploaded"), None)
    Ok(uploaded) -> {
      case simplifile.read_bits(uploaded.path) {
        Error(_) ->
          render_upload_page(user, Some("Failed to read uploaded file"), None)
        Ok(zip_bytes) ->
          case vivino.import_from_zip(conn, zip_bytes, user.username) {
            Error(msg) -> render_upload_page(user, Some(msg), None)
            Ok(result) -> render_upload_page(user, None, Some(result))
          }
      }
    }
  }
}

fn render_upload_page(
  user: User,
  error: option.Option(String),
  result: option.Option(vivino.ImportResult),
) -> Response {
  c.page("Import \u{2014} Rebstock", user, [
    c.back_link("/~" <> user.username, user.username),
    html.h1(
      [attr.class("text-3xl font-light text-stone-800 tracking-tight mb-6")],
      [html.Text("Import Vivino Data")],
    ),
    case error {
      option.Some(msg) ->
        html.div(
          [
            attr.class(
              "mb-4 p-3 bg-red-50 border border-red-200 rounded-md text-sm text-red-700",
            ),
          ],
          [html.Text(msg)],
        )
      option.None -> html.Nothing
    },
    case result {
      option.Some(r) -> result_card(r, user.username)
      option.None -> upload_form()
    },
  ])
}

fn upload_form() -> html.Node {
  html.Element(
    "form",
    [
      attr.Attr("method", "POST"),
      attr.Attr("enctype", "multipart/form-data"),
      attr.id("upload-form"),
    ],
    [
      html.div(
        [
          attr.id("drop-zone"),
          attr.class(
            "border-2 border-dashed border-stone-300 rounded-lg p-12 text-center cursor-pointer hover:border-amber-400 hover:bg-amber-50/30 transition-colors",
          ),
        ],
        [
          html.div([attr.class("text-stone-400 mb-3")], [
            html.UnsafeInlineHtml(upload_icon_svg()),
          ]),
          html.p([attr.class("text-stone-600 mb-1")], [
            html.Text("Drop your Vivino export zip here"),
          ]),
          html.p([attr.class("text-sm text-stone-400 mb-4")], [
            html.Text("or click to select a file"),
          ]),
          html.Element(
            "input",
            [
              attr.type_("file"),
              attr.name("zipfile"),
              attr.id("file-input"),
              attr.Attr("accept", ".zip"),
              attr.class("hidden"),
            ],
            [],
          ),
          html.p([attr.id("file-name"), attr.class("text-sm text-stone-500 hidden")], []),
        ],
      ),
      html.Element(
        "button",
        [
          attr.type_("submit"),
          attr.id("submit-btn"),
          attr.class(
            "mt-4 w-full px-4 py-2 bg-rose-800 text-white rounded-md text-sm font-medium hover:bg-rose-900 transition-colors disabled:opacity-50 disabled:cursor-not-allowed",
          ),
          attr.Attr("disabled", "disabled"),
        ],
        [html.Text("Import")],
      ),
      html.Element("script", [], [
        html.Text(drop_zone_js()),
      ]),
    ],
  )
}

fn result_card(result: vivino.ImportResult, username: String) -> html.Node {
  c.card([
    html.h2([attr.class("text-xl font-light text-stone-800 mb-4")], [
      html.Text("Import Complete"),
    ]),
    html.div([attr.class("space-y-2 text-sm")], [
      result_row("Wines", result.wines_created),
      result_row("Cellar entries", result.cellar_created),
      result_row("Wishlist items", result.wishlist_created),
    ]),
    html.div([attr.class("mt-6 flex gap-3")], [
      html.a(
        [
          attr.href("/~" <> username <> "/cellar"),
          attr.class(
            "px-4 py-2 bg-rose-800 text-white rounded-md text-sm font-medium hover:bg-rose-900 transition-colors",
          ),
        ],
        [html.Text("View Cellar")],
      ),
      html.a(
        [
          attr.href("/~" <> username <> "/import"),
          attr.class(
            "px-4 py-2 border border-stone-300 rounded-md text-sm text-stone-600 hover:bg-stone-50 transition-colors",
          ),
        ],
        [html.Text("Import Again")],
      ),
    ]),
  ])
}

fn result_row(label: String, count: Int) -> html.Node {
  html.div([attr.class("flex justify-between py-1 border-b border-stone-100")], [
    html.span([attr.class("text-stone-600")], [html.Text(label)]),
    html.span([attr.class("font-medium text-stone-800 tabular-nums")], [
      html.Text(int.to_string(count)),
    ]),
  ])
}

fn upload_icon_svg() -> String {
  "<svg class=\"mx-auto\" width=\"48\" height=\"48\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4\"/><polyline points=\"17 8 12 3 7 8\"/><line x1=\"12\" y1=\"3\" x2=\"12\" y2=\"15\"/></svg>"
}

fn drop_zone_js() -> String {
  "
  (function() {
    var dz = document.getElementById('drop-zone');
    var fi = document.getElementById('file-input');
    var fn_ = document.getElementById('file-name');
    var btn = document.getElementById('submit-btn');

    dz.addEventListener('click', function() { fi.click(); });

    fi.addEventListener('change', function() {
      if (fi.files.length > 0) {
        fn_.textContent = fi.files[0].name;
        fn_.classList.remove('hidden');
        btn.removeAttribute('disabled');
      }
    });

    dz.addEventListener('dragover', function(e) {
      e.preventDefault();
      dz.classList.add('border-amber-400', 'bg-amber-50/30');
    });

    dz.addEventListener('dragleave', function(e) {
      e.preventDefault();
      dz.classList.remove('border-amber-400', 'bg-amber-50/30');
    });

    dz.addEventListener('drop', function(e) {
      e.preventDefault();
      dz.classList.remove('border-amber-400', 'bg-amber-50/30');
      if (e.dataTransfer.files.length > 0) {
        fi.files = e.dataTransfer.files;
        fn_.textContent = e.dataTransfer.files[0].name;
        fn_.classList.remove('hidden');
        btn.removeAttribute('disabled');
      }
    });
  })();
  "
}
```

- [ ] **Step 2: Add the Option import**

Make sure `import gleam/option` is in the imports at the top:

```gleam
import gleam/option
```

- [ ] **Step 3: Add route to router**

In `src/rebstock/router.gleam`, add the import and route:

Add import:
```gleam
import rebstock/web/import as import_
```

Add route case before the `_ -> c.not_found(user)` catch-all:

```gleam
    ["~" <> username, "import"] ->
      import_.import_page(req, conn, user, username)
```

- [ ] **Step 4: Build and run tests**

Run: `gleam build --warnings-as-errors && gleam test`

Expected: All tests pass. No warnings.

- [ ] **Step 5: Commit**

```bash
git add src/rebstock/web/import.gleam src/rebstock/router.gleam
git commit -m "Add import page with drag-and-drop upload at ~username/import"
```

### Task 4: Add tests for the import upload flow

**Files:**
- Modify: `test/rebstock_test.gleam`

- [ ] **Step 1: Add import page GET test**

```gleam
pub fn import_page_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/~test/import")
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Import Vivino Data")
  Nil
}
```

- [ ] **Step 2: Add import page forbidden for other users test**

```gleam
pub fn import_page_forbidden_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/~other/import")
    |> router.handle_request(conn, test_auth)
  let assert 403 = response.status
  Nil
}
```

- [ ] **Step 3: Add vivino import_from_zip unit test**

Create a test zip in memory using Erlang's `:zip.create/3`:

```gleam
pub fn import_from_zip_test() {
  use conn <- with_empty_db
  let wine_list_csv =
    "Winery,Wine,Vintage,Region,Country,Style,Average Rating,Scan Date,Scan Location,User Rating,User Review,Personal Note,Wine Type,Drinking Window,Vivino Link\nTest Winery,Test Riesling,2021,Mosel,Germany,,4.2,,,3.5,,Great wine,White,,https://www.vivino.com/wines/12345\n"
  let cellar_csv =
    "Winery,Wine,Vintage,Region,Country,Style,Average Rating,Rating Count,Wine Type,Vivino Link,Cellar Count\nTest Winery,Test Riesling,2021,Mosel,Germany,,4.2,100,White,https://www.vivino.com/wines/12345,3\n"
  let zip_bytes = create_test_zip([
    #("full_wine_list.csv", wine_list_csv),
    #("cellar.csv", cellar_csv),
  ])
  let assert Ok(result) = vivino.import_from_zip(conn, zip_bytes, "test")
  let assert True = result.wines_created > 0
  let assert True = result.cellar_created > 0
  let assert 1 = db.count_wines(conn)
  Nil
}
```

Add the helper to create test zips using Erlang FFI. Add at the bottom of the test file:

```gleam
@external(erlang, "rebstock_test_ffi", "create_zip")
fn create_test_zip(files: List(#(String, String))) -> BitArray
```

Create `test/rebstock_test_ffi.erl`:

```erlang
-module(rebstock_test_ffi).
-export([create_zip/1]).

create_zip(Files) ->
    ErlFiles = [{binary_to_list(Name), unicode:characters_to_binary(Content)}
                || {Name, Content} <- Files],
    {ok, {_, ZipBin}} = zip:create("test.zip", ErlFiles, [memory]),
    ZipBin.
```

- [ ] **Step 4: Add missing required csv test**

```gleam
pub fn import_from_zip_missing_wine_list_test() {
  use conn <- with_empty_db
  let cellar_csv =
    "Winery,Wine,Vintage,Region,Country,Style,Average Rating,Rating Count,Wine Type,Vivino Link,Cellar Count\n"
  let zip_bytes = create_test_zip([#("cellar.csv", cellar_csv)])
  let assert Error("Zip must contain full_wine_list.csv") =
    vivino.import_from_zip(conn, zip_bytes, "test")
  Nil
}
```

- [ ] **Step 5: Run tests**

Run: `gleam test`

Expected: All tests pass including the new import tests.

- [ ] **Step 6: Commit**

```bash
git add test/rebstock_test.gleam test/rebstock_test_ffi.erl
git commit -m "Add tests for Vivino zip import and upload page"
```

### Task 5: Manual testing and polish

- [ ] **Step 1: Start dev server and test**

Run: `just dev`

Navigate to `http://localhost:3000/~admin/import` (or whatever your user is). Verify:
- Page renders with drag-and-drop zone
- Dragging a file shows visual feedback
- Clicking the zone opens file picker
- Uploading a Vivino export zip shows results
- Uploading an invalid file shows error
- Uploading a zip without `full_wine_list.csv` shows error

- [ ] **Step 2: Format and final build check**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: All pass, no warnings.

- [ ] **Step 3: Commit any polish**

```bash
git add -A
git commit -m "Polish import upload page"
```
