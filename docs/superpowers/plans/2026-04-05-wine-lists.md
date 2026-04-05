# Wine Lists Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add wine lists as a presentation and sharing layer with custom lists, wishlist migration, and public wine-menu-style shared views.

**Architecture:** New `lists` + `lists_wines` tables replace the `wishlist` table. System lists (cellar, rated, wishlist) are auto-created per user; cellar/rated are virtual (dynamic queries), wishlist stores data in `lists_wines`. A public `/shared/:id/:slug` route renders a standalone wine-menu page with Cormorant Garamond font and plain CSS. Shared CSS variables extracted to `colors.css` for reuse across Tailwind and plain CSS contexts.

**Tech Stack:** Gleam, nakai (HTML), SQLite (sqlight), wisp (HTTP), Tailwind CSS v4, plain CSS for shared view, Google Fonts (Cormorant Garamond)

---

### Task 1: Extract CSS color variables

**Files:**
- Create: `priv/static/css/colors.css`
- Modify: `src/css/app.css`

- [ ] **Step 1: Create `priv/static/css/colors.css`**

```css
:root {
  /* Wine type colors — section headers in shared view, badges in app */
  --wine-red: #78180e;
  --wine-white: #92400e;
  --wine-rose: #be185d;
  --wine-orange: #c2410c;
  --wine-sparkling: #57534e;
  --wine-dessert: #92400e;
  --wine-sake: #57534e;
  --wine-other: #57534e;

  /* Core palette */
  --stone-50: #fafaf9;
  --stone-100: #f5f5f4;
  --stone-200: #e7e5e4;
  --stone-300: #d6d3d1;
  --stone-400: #a8a29e;
  --stone-500: #78716c;
  --stone-600: #57534e;
  --stone-700: #44403c;
  --stone-800: #292524;
  --stone-900: #1c1917;
  --rose-800: #9f1239;
  --rose-900: #881337;
}
```

- [ ] **Step 2: Import colors.css in app.css**

At the top of `src/css/app.css`, add the import before `@import "tailwindcss"`:

```css
@import url("/static/css/colors.css");
@import "tailwindcss";
```

- [ ] **Step 3: Build and test**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: All 30 tests pass. CSS variables are available but not yet consumed — no visual changes.

- [ ] **Step 4: Commit**

```bash
git add priv/static/css/colors.css src/css/app.css
git commit -m "Extract CSS color variables to shared colors.css"
```

---

### Task 2: Update migration — add lists tables, remove wishlist table

**Files:**
- Modify: `priv/migrations/00001_create_wines.up.sql`
- Modify: `priv/migrations/00001_create_wines.down.sql`

- [ ] **Step 1: Update the up migration**

Replace the full content of `priv/migrations/00001_create_wines.up.sql` with:

```sql
CREATE TABLE users (
  username TEXT PRIMARY KEY
);

CREATE TABLE wineries (
  id TEXT PRIMARY KEY,
  created_by TEXT NOT NULL REFERENCES users(username),
  name TEXT NOT NULL,
  country TEXT,
  vivino_id TEXT,
  UNIQUE(created_by, name)
);

CREATE TABLE wines (
  id TEXT PRIMARY KEY,
  created_by TEXT NOT NULL REFERENCES users(username),
  winery_id TEXT NOT NULL REFERENCES wineries(id),
  name TEXT NOT NULL,
  region TEXT,
  country TEXT,
  style TEXT,
  personal_note TEXT,
  wine_type TEXT NOT NULL,
  vivino_id TEXT,
  UNIQUE(created_by, winery_id, name)
);

CREATE TABLE wines_vintages (
  wine_id TEXT NOT NULL REFERENCES wines(id),
  year TEXT NOT NULL,
  PRIMARY KEY (wine_id, year)
);

CREATE TABLE cellar (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL REFERENCES users(username),
  wine_id TEXT NOT NULL REFERENCES wines(id),
  vintage TEXT,
  quantity INTEGER NOT NULL,
  notes TEXT,
  date TEXT,
  parent_id TEXT REFERENCES cellar(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (wine_id, vintage) REFERENCES wines_vintages(wine_id, year)
);

CREATE TABLE ratings (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL REFERENCES users(username),
  wine_id TEXT NOT NULL REFERENCES wines(id),
  vintage TEXT,
  rating REAL,
  tasting_notes TEXT,
  rated_at TEXT,
  source TEXT NOT NULL DEFAULT 'user',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (wine_id, vintage) REFERENCES wines_vintages(wine_id, year)
);

CREATE TABLE lists (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL REFERENCES users(username),
  name TEXT NOT NULL,
  description TEXT,
  slug TEXT NOT NULL,
  list_type TEXT NOT NULL DEFAULT 'custom',
  public INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(username, slug)
);

CREATE TABLE lists_wines (
  list_id TEXT NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  wine_id TEXT NOT NULL REFERENCES wines(id),
  vintage TEXT NOT NULL DEFAULT '',
  sort_rank INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  added_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (list_id, wine_id, vintage)
);

CREATE TRIGGER lists_wines_type_check
BEFORE INSERT ON lists_wines
BEGIN
  SELECT RAISE(ABORT, 'Cannot add wines to virtual lists')
  WHERE (SELECT list_type FROM lists WHERE id = NEW.list_id) IN ('cellar', 'rated');
END;
```

- [ ] **Step 2: Update the down migration**

Replace the full content of `priv/migrations/00001_create_wines.down.sql` with:

```sql
DROP TRIGGER IF EXISTS lists_wines_type_check;
DROP TABLE IF EXISTS lists_wines;
DROP TABLE IF EXISTS lists;
DROP TABLE IF EXISTS ratings;
DROP TABLE IF EXISTS cellar;
DROP TABLE IF EXISTS wines_vintages;
DROP TABLE IF EXISTS wines;
DROP TABLE IF EXISTS wineries;
DROP TABLE IF EXISTS users;
```

- [ ] **Step 3: Delete the DB and rebuild**

```bash
rm -f rebstock.db rebstock.db-wal rebstock.db-shm
gleam format . && gleam build --warnings-as-errors && gleam test
```

Expected: Build succeeds. Some tests that used the old `wishlist` table will fail — that's expected, we'll fix them in later tasks.

- [ ] **Step 4: Commit**

```bash
git add priv/migrations/
git commit -m "Add lists and lists_wines tables, remove wishlist table"
```

---

### Task 3: Database layer — list types and CRUD functions

**Files:**
- Modify: `src/rebstock/db.gleam`

This task adds the List type, ListType enum, and all list CRUD functions. It also removes the old WishlistEntry type and wishlist functions, replacing them with list-based equivalents.

- [ ] **Step 1: Add ListType enum and List type**

After the existing `WineType` enum (around line 21), add:

```gleam
pub type ListType {
  CellarList
  RatedList
  WishlistList
  CustomList
}

pub type List {
  List(
    id: String,
    username: String,
    name: String,
    description: Option(String),
    slug: String,
    list_type: ListType,
    public: Bool,
    created_at: String,
  )
}
```

- [ ] **Step 2: Add list_type conversion functions**

```gleam
pub fn list_type_to_string(lt: ListType) -> String {
  case lt {
    CellarList -> "cellar"
    RatedList -> "rated"
    WishlistList -> "wishlist"
    CustomList -> "custom"
  }
}

pub fn list_type_from_string(s: String) -> ListType {
  case s {
    "cellar" -> CellarList
    "rated" -> RatedList
    "wishlist" -> WishlistList
    _ -> CustomList
  }
}
```

- [ ] **Step 3: Add `ensure_system_lists` function**

This auto-creates the three system lists for a user if they don't exist:

```gleam
pub fn ensure_system_lists(conn: Connection, username: String) -> Nil {
  let system = [
    #("Cellar", "cellar", "cellar"),
    #("Rated", "rated", "rated"),
    #("Wishlist", "wishlist", "wishlist"),
  ]
  list.each(system, fn(item) {
    let #(name, slug, list_type) = item
    sqlight.query(
      "INSERT OR IGNORE INTO lists (id, username, name, slug, list_type)
       VALUES (?, ?, ?, ?, ?)",
      conn,
      [
        sqlight.text(ulid.generate()),
        sqlight.text(username),
        sqlight.text(name),
        sqlight.text(slug),
        sqlight.text(list_type),
      ],
      fn(_) { Nil },
    )
    Nil
  })
}
```

- [ ] **Step 4: Add `slugify` helper function**

```gleam
pub fn slugify(name: String) -> String {
  name
  |> string.lowercase
  |> string.replace(each: " ", with: "-")
  |> string.to_graphemes
  |> list.filter(fn(c) {
    case c {
      "-" | "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
      _ ->
        case string.lowercase(c) == c && c >= "a" && c <= "z" {
          True -> True
          False -> False
        }
    }
  })
  |> string.concat
}
```

- [ ] **Step 5: Add list query functions**

```gleam
pub fn get_list(conn: Connection, id: String) -> Result(List, Nil) {
  let rows =
    sqlight.query(
      "SELECT id, username, name, description, slug, list_type, public, created_at
       FROM lists WHERE id = ?",
      conn,
      [sqlight.text(id)],
      decode_list_row,
    )
  case rows {
    [row] -> Ok(row)
    _ -> Error(Nil)
  }
}

pub fn get_list_by_slug(
  conn: Connection,
  username: String,
  slug: String,
) -> Result(List, Nil) {
  let rows =
    sqlight.query(
      "SELECT id, username, name, description, slug, list_type, public, created_at
       FROM lists WHERE username = ? AND slug = ?",
      conn,
      [sqlight.text(username), sqlight.text(slug)],
      decode_list_row,
    )
  case rows {
    [row] -> Ok(row)
    _ -> Error(Nil)
  }
}

pub fn lists_for_user(conn: Connection, username: String) -> List(List) {
  sqlight.query(
    "SELECT id, username, name, description, slug, list_type, public, created_at
     FROM lists WHERE username = ?
     ORDER BY CASE list_type
       WHEN 'cellar' THEN 1
       WHEN 'rated' THEN 2
       WHEN 'wishlist' THEN 3
       ELSE 4
     END, name",
    conn,
    [sqlight.text(username)],
    decode_list_row,
  )
}

fn decode_list_row(row: dynamic.Dynamic) -> List {
  let assert Ok(id) = dynamic.element(0, dynamic.string)(row)
  let assert Ok(username) = dynamic.element(1, dynamic.string)(row)
  let assert Ok(name) = dynamic.element(2, dynamic.string)(row)
  let assert Ok(description) = dynamic.element(3, dynamic.optional(dynamic.string))(row)
  let assert Ok(slug) = dynamic.element(4, dynamic.string)(row)
  let assert Ok(list_type_str) = dynamic.element(5, dynamic.string)(row)
  let assert Ok(public_int) = dynamic.element(6, dynamic.int)(row)
  let assert Ok(created_at) = dynamic.element(7, dynamic.string)(row)
  List(
    id: id,
    username: username,
    name: name,
    description: description,
    slug: slug,
    list_type: list_type_from_string(list_type_str),
    public: public_int == 1,
    created_at: created_at,
  )
}
```

- [ ] **Step 6: Add list mutation functions**

```gleam
pub fn create_list(
  conn: Connection,
  username: String,
  name: String,
  description: Option(String),
) -> String {
  let id = ulid.generate()
  let slug = slugify(name)
  sqlight.query(
    "INSERT INTO lists (id, username, name, description, slug, list_type)
     VALUES (?, ?, ?, ?, ?, 'custom')",
    conn,
    [
      sqlight.text(id),
      sqlight.text(username),
      sqlight.text(name),
      sqlight.nullable(sqlight.text, description),
      sqlight.text(slug),
    ],
    fn(_) { Nil },
  )
  id
}

pub fn update_list(
  conn: Connection,
  id: String,
  name: String,
  description: Option(String),
) -> Nil {
  sqlight.query(
    "UPDATE lists SET name = ?, description = ?, slug = ?
     WHERE id = ? AND list_type = 'custom'",
    conn,
    [
      sqlight.text(name),
      sqlight.nullable(sqlight.text, description),
      sqlight.text(slugify(name)),
      sqlight.text(id),
    ],
    fn(_) { Nil },
  )
  Nil
}

pub fn delete_list(conn: Connection, id: String) -> Nil {
  sqlight.query(
    "DELETE FROM lists WHERE id = ? AND list_type = 'custom'",
    conn,
    [sqlight.text(id)],
    fn(_) { Nil },
  )
  Nil
}

pub fn set_list_public(conn: Connection, id: String, public: Bool) -> Nil {
  sqlight.query(
    "UPDATE lists SET public = ? WHERE id = ?",
    conn,
    [sqlight.int(case public { True -> 1 False -> 0 }), sqlight.text(id)],
    fn(_) { Nil },
  )
  Nil
}
```

- [ ] **Step 7: Add list_wines query and mutation functions**

```gleam
pub type ListWine {
  ListWine(wine: Wine, vintage: Option(String), notes: Option(String))
}

pub fn list_wines_for_list(conn: Connection, list_id: String) -> List(ListWine) {
  sqlight.query(
    "SELECT " <> wine_cols <> ", lw.vintage, lw.notes
     " <> wine_join <> "
     JOIN lists_wines lw ON lw.wine_id = w.id
     WHERE lw.list_id = ?
     ORDER BY w.wine_type, w.region, wy.name, w.name",
    conn,
    [sqlight.text(list_id)],
    fn(row) {
      let wine = decode_wine_row(row)
      let assert Ok(vintage) = dynamic.element(12, dynamic.optional(dynamic.string))(row)
      let assert Ok(notes) = dynamic.element(13, dynamic.optional(dynamic.string))(row)
      ListWine(wine: wine, vintage: vintage, notes: notes)
    },
  )
}

pub fn add_wine_to_list(
  conn: Connection,
  list_id: String,
  wine_id: String,
  vintage: Option(String),
  notes: Option(String),
) -> Nil {
  let vintage_str = option.unwrap(vintage, "")
  sqlight.query(
    "INSERT OR IGNORE INTO lists_wines (list_id, wine_id, vintage, notes)
     VALUES (?, ?, ?, ?)",
    conn,
    [
      sqlight.text(list_id),
      sqlight.text(wine_id),
      sqlight.text(vintage_str),
      sqlight.nullable(sqlight.text, notes),
    ],
    fn(_) { Nil },
  )
  Nil
}

pub fn remove_wine_from_list(
  conn: Connection,
  list_id: String,
  wine_id: String,
) -> Nil {
  sqlight.query(
    "DELETE FROM lists_wines WHERE list_id = ? AND wine_id = ?",
    conn,
    [sqlight.text(list_id), sqlight.text(wine_id)],
    fn(_) { Nil },
  )
  Nil
}

pub fn count_list_wines(conn: Connection, list_id: String) -> Int {
  let rows =
    sqlight.query(
      "SELECT COUNT(*) FROM lists_wines WHERE list_id = ?",
      conn,
      [sqlight.text(list_id)],
      dynamic.element(0, dynamic.int),
    )
  case rows {
    [Ok(n)] -> n
    _ -> 0
  }
}

pub fn is_wine_in_list(
  conn: Connection,
  list_id: String,
  wine_id: String,
) -> Bool {
  let rows =
    sqlight.query(
      "SELECT 1 FROM lists_wines WHERE list_id = ? AND wine_id = ?",
      conn,
      [sqlight.text(list_id), sqlight.text(wine_id)],
      dynamic.element(0, dynamic.int),
    )
  list.length(rows) > 0
}
```

- [ ] **Step 8: Remove old wishlist types and functions**

Delete these from `db.gleam`:
- `WishlistEntry` type (lines 94-103)
- `WishlistWine` type (lines 338-340)
- `wishlist_wines` function (lines 342-390)
- `is_wishlisted` function (lines 392-409)
- `get_wishlist_entry_by_id` function (lines 411-442)
- `upsert_wishlist` function (lines 445-470)

- [ ] **Step 9: Add helper to get user's wishlist list**

```gleam
pub fn get_user_wishlist(conn: Connection, username: String) -> List {
  ensure_system_lists(conn, username)
  let assert Ok(wl) = get_list_by_slug(conn, username, "wishlist")
  wl
}
```

- [ ] **Step 10: Build**

Run: `gleam format . && gleam build --warnings-as-errors`

Expected: Build succeeds. Tests will still fail because wishlist.gleam, vivino.gleam, and tests reference removed functions — we'll fix those next.

- [ ] **Step 11: Commit**

```bash
git add src/rebstock/db.gleam
git commit -m "Add list types and CRUD functions, remove wishlist functions"
```

---

### Task 4: Rewrite wishlist.gleam to use lists

**Files:**
- Modify: `src/rebstock/web/wishlist.gleam`

- [ ] **Step 1: Rewrite wishlist.gleam**

Replace the entire file content. The wishlist now reads from `lists_wines` via the user's wishlist-type list:

```gleam
import gleam/list
import gleam/option.{None, Some}
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/auth.{type User}
import rebstock/db
import rebstock/web/components as c

pub fn wishlist(conn: Connection, user: User, username: String) -> Response {
  let wl = db.get_user_wishlist(conn, username)
  let wines = db.list_wines_for_list(conn, wl.id)
  let count = list.length(wines)
  let is_self = username == user.username
  let title = case is_self {
    True -> "Wishlist"
    False -> username <> "'s Wishlist"
  }

  c.page(title <> " \u{2014} Rebstock", user, conn, [
    c.page_header(title, case count {
      0 -> "empty"
      1 -> "1 wine"
      _ -> {
        let assert Ok(s) = gleam/int.to_string(count) |> Ok
        s <> " wines"
      }
    }),
    wishlist_table(wines),
  ])
}

fn wishlist_table(wines: List(db.ListWine)) -> Node {
  case wines {
    [] ->
      html.p([attr.class("text-stone-400 text-center py-8")], [
        html.Text("No wines wishlisted yet"),
      ])
    _ ->
      c.table(
        ["Winery", "Wine", "Vintage", "Country", "Type", "Notes"],
        list.index_map(wines, fn(lw, i) { wishlist_row(lw, i) }),
      )
  }
}

fn wishlist_row(lw: db.ListWine, index: Int) -> Node {
  let wine = lw.wine
  let bg = case index % 2 {
    0 -> ""
    _ -> "bg-stone-50/50"
  }
  html.tr([attr.class(bg)], [
    html.td([attr.class("px-4 py-3 text-sm")], [
      html.a(
        [
          attr.href("/wineries/" <> wine.winery_id),
          attr.class("text-stone-600 hover:text-rose-800"),
        ],
        [html.Text(wine.winery)],
      ),
    ]),
    html.td([attr.class("px-4 py-3 text-sm font-medium")], [
      html.a(
        [
          attr.href("/wines/" <> wine.id),
          attr.class("text-stone-800 hover:text-rose-800"),
        ],
        [html.Text(wine.name)],
      ),
    ]),
    html.td([attr.class("px-4 py-3 text-sm text-stone-500")], [
      html.Text(case lw.vintage {
        Some(v) -> v
        None -> ""
      }),
    ]),
    html.td([attr.class("px-4 py-3 text-sm text-stone-500")], [
      html.Text(case wine.country {
        Some(c) -> c
        None -> ""
      }),
    ]),
    html.td([attr.class("px-4 py-3 text-sm")], [
      c.wine_type_badge(wine.wine_type),
    ]),
    html.td([attr.class("px-4 py-3 text-sm text-stone-500")], [
      html.Text(case lw.notes {
        Some(n) -> n
        None -> ""
      }),
    ]),
  ])
}
```

Note: This removes the overlay functionality for wishlist entries (they were simple — just wine name, notes, date). We can add it back later if needed. The table now links directly to wine detail pages.

- [ ] **Step 2: Build**

Run: `gleam format . && gleam build --warnings-as-errors`

Expected: May have unused import warnings — fix them. The vivino.gleam and test file still need updating.

- [ ] **Step 3: Commit**

```bash
git add src/rebstock/web/wishlist.gleam
git commit -m "Rewrite wishlist to use lists_wines table"
```

---

### Task 5: Update vivino.gleam to write wishlist via lists

**Files:**
- Modify: `src/rebstock/vivino.gleam`

- [ ] **Step 1: Update import_wishlisted function**

Find the line that calls `db.upsert_wishlist` (around line 322). Replace it with:

```gleam
          let wl = db.get_user_wishlist(conn, created_by)
          db.add_wine_to_list(conn, wl.id, wine_id, vintage, option.None)
```

The `upsert_wishlist` call was:
```gleam
          db.upsert_wishlist(conn, created_by, wine_id, vintage, option.None)
```

- [ ] **Step 2: Build and test**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: Build succeeds. Some tests may still fail due to test code referencing old wishlist functions.

- [ ] **Step 3: Commit**

```bash
git add src/rebstock/vivino.gleam
git commit -m "Update vivino import to write wishlist via lists"
```

---

### Task 6: Update router and tests

**Files:**
- Modify: `src/rebstock/router.gleam`
- Modify: `test/rebstock_test.gleam`

- [ ] **Step 1: Remove wishlist overlay routes from router**

In `src/rebstock/router.gleam`, remove these two routes:
```gleam
      ["wishlist", id, "overlay"] -> wishlist.wishlist_entry_overlay(conn, id)
      ["wishlist", id] -> wishlist.wishlist_entry_detail(conn, id, user)
```

These were for the wishlist entry overlay/detail which we removed in the rewrite.

- [ ] **Step 2: Update tests**

In `test/rebstock_test.gleam`, update the `seed_two_users` function. Replace the wishlist section (the `db.upsert_wishlist` call) with:

```gleam
  let wl = db.get_user_wishlist(conn, "alice")
  db.add_wine_to_list(conn, wl.id, wine_b, option.Some("Want to try"))
```

Update the `wishlist_isolation_test` to use the new API:

```gleam
pub fn wishlist_isolation_test() {
  use conn <- with_empty_db
  let #(_wine_a, wine_b) = seed_two_users(conn)
  let alice_wl = db.get_user_wishlist(conn, "alice")
  let bob_wl = db.get_user_wishlist(conn, "bob")
  let alice_wines = db.list_wines_for_list(conn, alice_wl.id)
  let bob_wines = db.list_wines_for_list(conn, bob_wl.id)
  let assert 1 = list.length(alice_wines)
  let assert 0 = list.length(bob_wines)
  let assert True = db.is_wine_in_list(conn, alice_wl.id, wine_b)
  let assert False = db.is_wine_in_list(conn, bob_wl.id, wine_b)
  Nil
}
```

- [ ] **Step 3: Build and run all tests**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: All tests pass (some count may differ if old wishlist tests were removed — adjust accordingly).

- [ ] **Step 4: Commit**

```bash
git add src/rebstock/router.gleam test/rebstock_test.gleam
git commit -m "Update router and tests for lists-based wishlist"
```

---

### Task 7: Add nav link and ensure_system_lists in auth flow

**Files:**
- Modify: `src/rebstock/web/components.gleam`
- Modify: `src/rebstock/router.gleam`

- [ ] **Step 1: Add "Lists" nav link**

In `src/rebstock/web/components.gleam`, in the `site_header` function, add the Lists link after Ratings in the nav:

```gleam
            nav_link("Ratings", "/~" <> user.username <> "/ratings"),
            nav_link("Lists", "/~" <> user.username <> "/lists"),
```

- [ ] **Step 2: Call ensure_system_lists in the router**

In `src/rebstock/router.gleam`, after `db.ensure_user(conn, user.username)`, add:

```gleam
  db.ensure_system_lists(conn, user.username)
```

This ensures system lists exist for every authenticated request.

- [ ] **Step 3: Build and test**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: All tests pass. "Lists" link appears in nav but the route doesn't exist yet (404).

- [ ] **Step 4: Commit**

```bash
git add src/rebstock/web/components.gleam src/rebstock/router.gleam
git commit -m "Add Lists nav link and ensure system lists on auth"
```

---

### Task 8: Lists web handler — index, create, view, edit, delete

**Files:**
- Create: `src/rebstock/web/lists.gleam`
- Modify: `src/rebstock/router.gleam`

- [ ] **Step 1: Create `src/rebstock/web/lists.gleam`**

```gleam
import gleam/http
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type User}
import rebstock/db
import rebstock/web/components as c

pub fn lists_index(conn: Connection, user: User, username: String) -> Response {
  let lists = db.lists_for_user(conn, username)
  let is_self = username == user.username
  let title = case is_self {
    True -> "Your Lists"
    False -> username <> "'s Lists"
  }

  c.page(title <> " \u{2014} Rebstock", user, conn, [
    c.page_header(title, int.to_string(list.length(lists)) <> " lists"),
    case is_self {
      True ->
        html.div([attr.class("mb-6")], [
          html.a(
            [
              attr.href("/~" <> username <> "/lists/new"),
              attr.class(
                "inline-block px-4 py-2 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors text-sm font-medium",
              ),
            ],
            [html.Text("New List")],
          ),
        ])
      False -> html.Nothing
    },
    lists_grid(lists, username),
  ])
}

fn lists_grid(lists: List(db.List), username: String) -> Node {
  html.div(
    [attr.class("grid gap-4 sm:grid-cols-2 lg:grid-cols-3")],
    list.map(lists, fn(l) { list_card(l, username) }),
  )
}

fn list_card(l: db.List, username: String) -> Node {
  let href = case l.list_type {
    db.CellarList -> "/~" <> username <> "/cellar"
    db.RatedList -> "/~" <> username <> "/ratings"
    db.WishlistList -> "/~" <> username <> "/wishlist"
    db.CustomList -> "/~" <> username <> "/lists/" <> l.id
  }
  html.a(
    [
      attr.href(href),
      attr.class(
        "block p-4 bg-white border border-stone-200 rounded-lg hover:border-rose-300 transition-colors",
      ),
    ],
    [
      html.div([attr.class("flex items-center justify-between mb-1")], [
        html.span([attr.class("font-medium text-stone-800")], [
          html.Text(l.name),
        ]),
        case l.public {
          True ->
            html.span(
              [attr.class("text-xs text-stone-400 bg-stone-100 px-2 py-0.5 rounded")],
              [html.Text("shared")],
            )
          False -> html.Nothing
        },
      ]),
      case l.description {
        Some(d) ->
          html.p([attr.class("text-sm text-stone-500 mt-1")], [html.Text(d)])
        None -> html.Nothing
      },
      html.div([attr.class("text-xs text-stone-400 mt-2")], [
        html.Text(case l.list_type {
          db.CellarList -> "Cellar inventory"
          db.RatedList -> "All rated wines"
          db.WishlistList -> "Wishlist"
          db.CustomList -> "Custom list"
        }),
      ]),
    ],
  )
}

pub fn new_list_form(conn: Connection, user: User) -> Response {
  c.page("New List \u{2014} Rebstock", user, conn, [
    c.back_link("/~" <> user.username <> "/lists", "Lists"),
    html.h1(
      [attr.class("text-3xl font-light text-stone-800 tracking-tight mb-6")],
      [html.Text("New List")],
    ),
    list_form(user.username, None, None, None),
  ])
}

pub fn create_list(
  req: Request,
  conn: Connection,
  user: User,
) -> Response {
  use form <- wisp.require_form(req)
  let name = list.key_find(form.values, "name")
  let description = list.key_find(form.values, "description")

  case name {
    Ok(n) if n != "" -> {
      let desc = case description {
        Ok(d) if d != "" -> Some(d)
        _ -> None
      }
      let _id = db.create_list(conn, user.username, n, desc)
      wisp.redirect("/~" <> user.username <> "/lists")
    }
    _ -> wisp.redirect("/~" <> user.username <> "/lists/new")
  }
}

pub fn list_detail(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
  id: String,
) -> Response {
  case db.get_list(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(l) ->
      case l.username == username {
        False -> c.not_found(user, conn)
        True -> {
          let wines = db.list_wines_for_list(conn, l.id)
          let is_owner = user.username == l.username
          let title = l.name

          case req.method {
            http.Post if is_owner && l.list_type == db.CustomList ->
              update_list(req, conn, user, l)
            http.Delete if is_owner && l.list_type == db.CustomList -> {
              db.delete_list(conn, l.id)
              wisp.redirect("/~" <> username <> "/lists")
            }
            _ ->
              c.page(title <> " \u{2014} Rebstock", user, conn, [
                c.back_link("/~" <> username <> "/lists", "Lists"),
                html.div(
                  [attr.class("flex items-center justify-between mb-6")],
                  [
                    html.div([], [
                      html.h1(
                        [
                          attr.class(
                            "text-3xl font-light text-stone-800 tracking-tight",
                          ),
                        ],
                        [html.Text(title)],
                      ),
                      case l.description {
                        Some(d) ->
                          html.p([attr.class("text-stone-500 mt-1")], [
                            html.Text(d),
                          ])
                        None -> html.Nothing
                      },
                    ]),
                    case is_owner {
                      True ->
                        html.div([attr.class("flex gap-2")], [
                          share_toggle(l, username),
                        ])
                      False -> html.Nothing
                    },
                  ],
                ),
                list_wines_table(wines),
              ])
          }
        }
      }
  }
}

fn update_list(
  req: Request,
  conn: Connection,
  user: User,
  l: db.List,
) -> Response {
  use form <- wisp.require_form(req)
  let name = list.key_find(form.values, "name")
  let description = list.key_find(form.values, "description")
  case name {
    Ok(n) if n != "" -> {
      let desc = case description {
        Ok(d) if d != "" -> Some(d)
        _ -> None
      }
      db.update_list(conn, l.id, n, desc)
      wisp.redirect("/~" <> user.username <> "/lists/" <> l.id)
    }
    _ -> wisp.redirect("/~" <> user.username <> "/lists/" <> l.id)
  }
}

fn share_toggle(l: db.List, username: String) -> Node {
  let href =
    "/~" <> username <> "/lists/" <> l.id <> "/public"
  case l.public {
    True ->
      html.form([attr.method("PUT"), attr.action(href)], [
        html.Element("input", [attr.type_("hidden"), attr.name("public"), attr.value("0")], []),
        html.Element(
          "button",
          [
            attr.type_("submit"),
            attr.class(
              "text-sm px-3 py-1 border border-stone-200 rounded-lg text-stone-500 hover:text-stone-700 transition-colors",
            ),
          ],
          [html.Text("Unshare")],
        ),
      ])
    False ->
      html.form([attr.method("PUT"), attr.action(href)], [
        html.Element("input", [attr.type_("hidden"), attr.name("public"), attr.value("1")], []),
        html.Element(
          "button",
          [
            attr.type_("submit"),
            attr.class(
              "text-sm px-3 py-1 border border-rose-200 rounded-lg text-rose-800 hover:bg-rose-50 transition-colors",
            ),
          ],
          [html.Text("Share")],
        ),
      ])
  }
}

pub fn set_public(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
  id: String,
) -> Response {
  case username == user.username {
    False -> wisp.response(403)
    True ->
      case db.get_list(conn, id) {
        Error(_) -> c.not_found(user, conn)
        Ok(l) -> {
          use form <- wisp.require_form(req)
          let public = case list.key_find(form.values, "public") {
            Ok("1") -> True
            _ -> False
          }
          db.set_list_public(conn, l.id, public)
          wisp.redirect("/~" <> username <> "/lists/" <> l.id)
        }
      }
  }
}

pub fn add_wine(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
  id: String,
) -> Response {
  case username == user.username {
    False -> wisp.response(403)
    True ->
      case db.get_list(conn, id) {
        Error(_) -> c.not_found(user, conn)
        Ok(l) ->
          case l.list_type {
            db.CellarList | db.RatedList -> wisp.response(400)
            _ -> {
              use form <- wisp.require_form(req)
              let wine_id = list.key_find(form.values, "wine_id")
              case wine_id {
                Ok(wid) -> {
                  db.add_wine_to_list(conn, l.id, wid, None, None)
                  wisp.redirect("/~" <> username <> "/lists/" <> l.id)
                }
                _ -> wisp.response(400)
              }
            }
          }
      }
  }
}

pub fn remove_wine(
  conn: Connection,
  user: User,
  username: String,
  list_id: String,
  wine_id: String,
) -> Response {
  case username == user.username {
    False -> wisp.response(403)
    True ->
      case db.get_list(conn, list_id) {
        Error(_) -> c.not_found(user, conn)
        Ok(l) ->
          case l.list_type {
            db.CellarList | db.RatedList -> wisp.response(400)
            _ -> {
              db.remove_wine_from_list(conn, l.id, wine_id)
              wisp.redirect("/~" <> username <> "/lists/" <> l.id)
            }
          }
      }
  }
}

fn list_wines_table(wines: List(db.ListWine)) -> Node {
  case wines {
    [] ->
      html.p([attr.class("text-stone-400 text-center py-8")], [
        html.Text("No wines in this list yet"),
      ])
    _ ->
      c.table(
        ["Winery", "Wine", "Vintage", "Country", "Type"],
        list.index_map(wines, fn(lw, i) { list_wine_row(lw, i) }),
      )
  }
}

fn list_wine_row(lw: db.ListWine, index: Int) -> Node {
  let wine = lw.wine
  let bg = case index % 2 {
    0 -> ""
    _ -> "bg-stone-50/50"
  }
  html.tr([attr.class(bg)], [
    html.td([attr.class("px-4 py-3 text-sm")], [
      html.a(
        [
          attr.href("/wineries/" <> wine.winery_id),
          attr.class("text-stone-600 hover:text-rose-800"),
        ],
        [html.Text(wine.winery)],
      ),
    ]),
    html.td([attr.class("px-4 py-3 text-sm font-medium")], [
      html.a(
        [
          attr.href("/wines/" <> wine.id),
          attr.class("text-stone-800 hover:text-rose-800"),
        ],
        [html.Text(wine.name)],
      ),
    ]),
    html.td([attr.class("px-4 py-3 text-sm text-stone-500")], [
      html.Text(case lw.vintage {
        Some(v) -> v
        None -> ""
      }),
    ]),
    html.td([attr.class("px-4 py-3 text-sm text-stone-500")], [
      html.Text(case wine.country {
        Some(c) -> c
        None -> ""
      }),
    ]),
    html.td([attr.class("px-4 py-3 text-sm")], [
      c.wine_type_badge(wine.wine_type),
    ]),
  ])
}

fn list_form(
  username: String,
  name: Option(String),
  description: Option(String),
  id: Option(String),
) -> Node {
  let action = case id {
    Some(i) -> "/~" <> username <> "/lists/" <> i
    None -> "/~" <> username <> "/lists"
  }
  html.form([attr.method("POST"), attr.action(action), attr.class("space-y-4 max-w-lg")], [
    html.div([], [
      html.Element("label", [attr.class("block text-sm font-medium text-stone-700 mb-1")], [
        html.Text("Name"),
      ]),
      html.Element(
        "input",
        [
          attr.type_("text"),
          attr.name("name"),
          attr.value(option.unwrap(name, "")),
          attr.class(
            "w-full px-3 py-2 border border-stone-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-rose-800/20 focus:border-rose-800",
          ),
          attr.Attr("required", ""),
        ],
        [],
      ),
    ]),
    html.div([], [
      html.Element("label", [attr.class("block text-sm font-medium text-stone-700 mb-1")], [
        html.Text("Description (optional)"),
      ]),
      html.Element(
        "textarea",
        [
          attr.name("description"),
          attr.class(
            "w-full px-3 py-2 border border-stone-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-rose-800/20 focus:border-rose-800",
          ),
          attr.Attr("rows", "3"),
        ],
        [html.Text(option.unwrap(description, ""))],
      ),
    ]),
    html.Element(
      "button",
      [
        attr.type_("submit"),
        attr.class(
          "px-4 py-2 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors text-sm font-medium",
        ),
      ],
      [html.Text(case id {
        Some(_) -> "Update"
        None -> "Create List"
      })],
    ),
  ])
}
```

- [ ] **Step 2: Add list routes to router**

In `src/rebstock/router.gleam`, add the import:

```gleam
import rebstock/web/lists
```

Add these routes in the user-scoped section (with the `["~" <> username, ...]` patterns):

```gleam
      ["~" <> username, "lists"] -> lists.lists_index(conn, user, username)
      ["~" <> username, "lists", "new"] -> lists.new_list_form(conn, user)
      ["~" <> username, "lists", id, "public"] ->
        lists.set_public(req, conn, user, username, id)
      ["~" <> username, "lists", id, "wines"] ->
        lists.add_wine(req, conn, user, username, id)
      ["~" <> username, "lists", id, "wines", wine_id] ->
        lists.remove_wine(conn, user, username, id, wine_id)
      ["~" <> username, "lists", id] ->
        lists.list_detail(req, conn, user, username, id)
```

And a POST route for creating lists (matches the form action):

The POST to `/~username/lists` needs to be handled. Since the route `["~" <> username, "lists"]` already matches GET, we need to dispatch on method inside the handler. Update the route to:

```gleam
      ["~" <> username, "lists"] ->
        case req.method {
          http.Post -> lists.create_list(req, conn, user)
          _ -> lists.lists_index(conn, user, username)
        }
```

- [ ] **Step 3: Build and test**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: All tests pass. Lists page works at `/~username/lists`.

- [ ] **Step 4: Commit**

```bash
git add src/rebstock/web/lists.gleam src/rebstock/router.gleam
git commit -m "Add lists web handler with index, create, view, edit, delete"
```

---

### Task 9: Shared view — public wine-menu page

**Files:**
- Create: `src/rebstock/web/shared.gleam`
- Modify: `src/rebstock/router.gleam`

- [ ] **Step 1: Create `src/rebstock/web/shared.gleam`**

This is the standalone shared view — plain HTML/CSS, no Tailwind, no site header. Uses Cormorant Garamond from Google Fonts.

```gleam
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import nakai
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/db

pub fn shared_list(conn: Connection, id: String) -> Response {
  case db.get_list(conn, id) {
    Error(_) -> wisp.response(404)
    Ok(l) ->
      case l.public {
        False -> wisp.response(404)
        True -> render_shared(conn, l)
      }
  }
}

fn render_shared(conn: Connection, l: db.List) -> Response {
  let wines = wines_for_shared_list(conn, l)
  let grouped = group_by_type(wines)
  let wine_count = list.length(wines)

  let page =
    html.Html([attr.lang("en")], [
      html.Head([
        html.meta([attr.charset("utf-8")]),
        html.meta([
          attr.name("viewport"),
          attr.content("width=device-width, initial-scale=1"),
        ]),
        html.title(l.name),
        html.link([
          attr.rel("icon"),
          attr.href(
            "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🍇</text></svg>",
          ),
        ]),
        html.link([
          attr.rel("stylesheet"),
          attr.href("/static/css/colors.css"),
        ]),
        html.Element(
          "link",
          [
            attr.rel("preconnect"),
            attr.href("https://fonts.googleapis.com"),
          ],
          [],
        ),
        html.Element(
          "link",
          [
            attr.rel("preconnect"),
            attr.href("https://fonts.gstatic.com"),
            attr.Attr("crossorigin", ""),
          ],
          [],
        ),
        html.link([
          attr.rel("stylesheet"),
          attr.href(
            "https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,500;0,600;1,300&display=swap",
          ),
        ]),
        html.Element("style", [], [html.UnsafeInlineHtml(shared_css())]),
      ]),
      html.Body([], [
        html.div([attr.class("wine-menu")], [
          menu_header(l, wine_count),
          html.div(
            [],
            list.map(grouped, fn(group) {
              let #(type_label, type_color, group_wines) = group
              wine_type_section(type_label, type_color, group_wines, l.list_type)
            }),
          ),
          menu_footer(),
        ]),
      ]),
    ])

  page
  |> nakai.to_string
  |> wisp.html_response(200)
}

fn menu_header(l: db.List, wine_count: Int) -> Node {
  html.div([attr.class("menu-header")], [
    html.div([attr.class("menu-title")], [html.Text(l.name)]),
    case l.description {
      Some(d) ->
        html.div([attr.class("menu-description")], [html.Text(d)])
      None -> html.Nothing
    },
    html.div([attr.class("menu-meta")], [
      html.Text(
        "Curated by "
        <> l.username
        <> " \u{00b7} "
        <> int.to_string(wine_count)
        <> case wine_count {
          1 -> " wine"
          _ -> " wines"
        },
      ),
    ]),
  ])
}

fn menu_footer() -> Node {
  html.div([attr.class("menu-footer")], [
    html.Text("\u{1f347} Rebstock"),
  ])
}

type SharedWine {
  SharedWine(
    wine: db.Wine,
    vintage: option.Option(String),
    bottles: option.Option(Int),
  )
}

fn wines_for_shared_list(conn: Connection, l: db.List) -> List(SharedWine) {
  case l.list_type {
    db.CellarList -> {
      let cellar_wines = db.cellar_wines_by_type(conn, l.username)
      list.map(cellar_wines, fn(cw) {
        SharedWine(wine: cw.wine, vintage: cw.vintage, bottles: Some(cw.bottles))
      })
    }
    db.RatedList -> {
      let wines = db.rated_wines(conn, l.username)
      list.map(wines, fn(w) {
        SharedWine(wine: w, vintage: None, bottles: None)
      })
    }
    _ -> {
      let list_wines = db.list_wines_for_list(conn, l.id)
      list.map(list_wines, fn(lw) {
        SharedWine(wine: lw.wine, vintage: lw.vintage, bottles: None)
      })
    }
  }
}

fn group_by_type(
  wines: List(SharedWine),
) -> List(#(String, String, List(SharedWine))) {
  let type_order = ["Red", "White", "Rosé", "Orange", "Sparkling", "Dessert", "Sake", "Other"]
  let type_colors = [
    #("Red", "var(--wine-red)"),
    #("White", "var(--wine-white)"),
    #("Rosé", "var(--wine-rose)"),
    #("Orange", "var(--wine-orange)"),
    #("Sparkling", "var(--wine-sparkling)"),
    #("Dessert", "var(--wine-dessert)"),
    #("Sake", "var(--wine-sake)"),
    #("Other", "var(--wine-other)"),
  ]

  type_order
  |> list.filter_map(fn(type_name) {
    let matching =
      list.filter(wines, fn(sw) {
        db.wine_type_label(sw.wine.wine_type) == type_name
      })
    case matching {
      [] -> Error(Nil)
      _ -> {
        let color = case list.key_find(type_colors, type_name) {
          Ok(c) -> c
          Error(_) -> "var(--wine-other)"
        }
        Ok(#(type_name, color, matching))
      }
    }
  })
}

fn wine_type_section(
  type_label: String,
  type_color: String,
  wines: List(SharedWine),
  list_type: db.ListType,
) -> Node {
  html.div([attr.class("wine-section")], [
    html.div(
      [
        attr.class("section-header"),
        attr.Attr("style", "color: " <> type_color <> "; border-bottom-color: " <> type_color),
      ],
      [html.Text(type_label)],
    ),
    html.div([], list.map(wines, fn(sw) { wine_entry(sw, list_type) })),
  ])
}

fn wine_entry(sw: SharedWine, list_type: db.ListType) -> Node {
  html.div([attr.class("wine-entry")], [
    html.div([attr.class("wine-row")], [
      html.div([attr.class("wine-name-col")], [
        html.span([attr.class("wine-name")], [html.Text(sw.wine.name)]),
        case sw.vintage {
          Some(v) ->
            html.span([attr.class("wine-vintage")], [html.Text(v)])
          None -> html.Nothing
        },
      ]),
      html.span([attr.class("wine-region")], [
        html.Text(case sw.wine.region, sw.wine.country {
          Some(r), Some(c) -> r <> ", " <> c
          Some(r), None -> r
          None, Some(c) -> c
          None, None -> ""
        }),
      ]),
      case list_type, sw.bottles {
        db.CellarList, Some(b) ->
          html.span([attr.class("wine-bottles")], [
            html.Text("(" <> int.to_string(b) <> ")"),
          ])
        _, _ -> html.Nothing
      },
    ]),
    html.div([attr.class("wine-winery")], [html.Text(sw.wine.winery)]),
  ])
}

fn shared_css() -> String {
  "
    * { margin: 0; padding: 0; box-sizing: border-box; }

    body {
      background: #fff;
      color: var(--stone-900);
    }

    .wine-menu {
      font-family: 'Cormorant Garamond', Georgia, serif;
      max-width: 680px;
      margin: 0 auto;
      padding: 48px 40px;
      line-height: 1.5;
    }

    .menu-header {
      text-align: center;
      margin-bottom: 36px;
      padding-bottom: 20px;
      border-bottom: 1px solid var(--stone-400);
    }

    .menu-title {
      font-size: 30px;
      font-weight: 300;
      letter-spacing: 0.04em;
      color: var(--stone-800);
    }

    .menu-description {
      font-size: 15px;
      color: var(--stone-500);
      font-style: italic;
      font-weight: 300;
      margin-top: 6px;
    }

    .menu-meta {
      font-size: 11px;
      font-family: system-ui, sans-serif;
      color: var(--stone-400);
      margin-top: 8px;
      letter-spacing: 0.06em;
      text-transform: uppercase;
    }

    .wine-section {
      margin-bottom: 32px;
    }

    .section-header {
      font-size: 10px;
      font-family: system-ui, sans-serif;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.12em;
      margin-bottom: 16px;
      padding-bottom: 4px;
      border-bottom: 2px solid;
    }

    .wine-entry {
      margin-bottom: 14px;
    }

    .wine-row {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
    }

    .wine-name-col {
      flex: 1;
    }

    .wine-name {
      font-size: 18px;
      font-weight: 500;
      color: var(--stone-900);
    }

    .wine-vintage {
      font-size: 14px;
      color: var(--stone-500);
      margin-left: 4px;
    }

    .wine-region {
      font-size: 13px;
      color: var(--stone-400);
      font-style: italic;
      font-weight: 300;
    }

    .wine-bottles {
      font-size: 12px;
      font-family: system-ui, sans-serif;
      color: var(--stone-400);
      margin-left: 16px;
      min-width: 24px;
      text-align: right;
    }

    .wine-winery {
      font-size: 13px;
      color: var(--stone-600);
      font-weight: 300;
      margin-top: 1px;
    }

    .menu-footer {
      text-align: center;
      padding-top: 20px;
      border-top: 1px solid var(--stone-300);
      font-size: 11px;
      font-family: system-ui, sans-serif;
      color: var(--stone-400);
      letter-spacing: 0.04em;
    }

    @media print {
      .wine-menu { padding: 0; }
      body { font-size: 11pt; }
    }
  "
}
```

- [ ] **Step 2: Add `rated_wines` function to db.gleam**

The shared view needs a `rated_wines` function that returns wines the user has rated. Add to `src/rebstock/db.gleam`:

```gleam
pub fn rated_wines(conn: Connection, username: String) -> List(Wine) {
  sqlight.query(
    "SELECT DISTINCT " <> wine_cols <> "
     " <> wine_join <> "
     JOIN ratings r ON r.wine_id = w.id AND r.username = ?
     ORDER BY w.wine_type, w.region, wy.name, w.name",
    conn,
    [sqlight.text(username)],
    decode_wine_row,
  )
}
```

- [ ] **Step 3: Add shared route to router**

In `src/rebstock/router.gleam`, add the import:

```gleam
import rebstock/web/shared
```

Add the route BEFORE the auth check (since shared routes bypass auth):

```gleam
      ["shared", id, _slug] -> shared.shared_list(conn, id)
```

This should go before the `let user = ...` line since the shared route doesn't need authentication.

- [ ] **Step 4: Build and test**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: All tests pass. Shared view accessible at `/shared/:id/:slug`.

- [ ] **Step 5: Commit**

```bash
git add src/rebstock/web/shared.gleam src/rebstock/db.gleam src/rebstock/router.gleam
git commit -m "Add shared wine-menu view with Cormorant Garamond and plain CSS"
```

---

### Task 10: Add "Add to list" action on wine detail page

**Files:**
- Modify: `src/rebstock/web/wines.gleam`

- [ ] **Step 1: Add "Add to list" dropdown on wine detail page**

In the wine detail function, after fetching wine data, also fetch the user's lists that accept wines (wishlist + custom):

```gleam
let user_lists =
  db.lists_for_user(conn, user.username)
  |> list.filter(fn(l) {
    l.list_type == db.WishlistList || l.list_type == db.CustomList
  })
```

Then add an "Add to list" section in the wine detail view. This should be a `<details>`/`<summary>` dropdown with a form per list:

```gleam
fn add_to_list_section(wine: db.Wine, lists: List(db.List), username: String) -> Node {
  case lists {
    [] -> html.Nothing
    _ ->
      html.Element("details", [attr.class("relative mt-4")], [
        html.Element(
          "summary",
          [
            attr.class(
              "cursor-pointer text-sm text-stone-500 hover:text-rose-800 transition-colors list-none",
            ),
          ],
          [html.Text("Add to list...")],
        ),
        html.div(
          [
            attr.class(
              "absolute left-0 top-8 bg-white border border-stone-200 rounded-lg shadow-lg py-1 min-w-[180px] z-20",
            ),
          ],
          list.map(lists, fn(l) {
            html.form(
              [
                attr.method("POST"),
                attr.action("/~" <> username <> "/lists/" <> l.id <> "/wines"),
              ],
              [
                html.Element(
                  "input",
                  [attr.type_("hidden"), attr.name("wine_id"), attr.value(wine.id)],
                  [],
                ),
                html.Element(
                  "button",
                  [
                    attr.type_("submit"),
                    attr.class(
                      "block w-full text-left px-4 py-2 text-sm text-stone-600 hover:bg-amber-50 hover:text-stone-800 transition-colors",
                    ),
                  ],
                  [html.Text(l.name)],
                ),
              ],
            )
          }),
        ),
      ])
  }
}
```

The exact integration point depends on the wine detail page layout. Add `add_to_list_section(wine, user_lists, user.username)` to the wine detail content.

- [ ] **Step 2: Build and test**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/rebstock/web/wines.gleam
git commit -m "Add 'Add to list' dropdown on wine detail page"
```

---

### Task 11: Add tests for lists feature

**Files:**
- Modify: `test/rebstock_test.gleam`

- [ ] **Step 1: Add list creation and CRUD tests**

```gleam
pub fn create_list_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let id = db.create_list(conn, "test", "Dinner Picks", option.Some("For Friday"))
  let assert Ok(l) = db.get_list(conn, id)
  let assert "Dinner Picks" = l.name
  let assert Some("For Friday") = l.description
  let assert "dinner-picks" = l.slug
  let assert db.CustomList = l.list_type
  let assert False = l.public
  Nil
}

pub fn system_lists_auto_created_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let lists = db.lists_for_user(conn, "test")
  let assert 3 = list.length(lists)
  let assert Ok(_) = db.get_list_by_slug(conn, "test", "cellar")
  let assert Ok(_) = db.get_list_by_slug(conn, "test", "rated")
  let assert Ok(_) = db.get_list_by_slug(conn, "test", "wishlist")
  Nil
}

pub fn add_wine_to_list_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let list_id = db.create_list(conn, "test", "Favorites", None)
  let wine_id =
    db.upsert_wine(conn,
      created_by: "test", winery: "Test Winery", name: "Test Wine",
      vintage: None, region: None, country: None, style: None,
      personal_note: None, wine_type: db.Red, vivino_id: None,
    )
  db.add_wine_to_list(conn, list_id, wine_id, None, None)
  let wines = db.list_wines_for_list(conn, list_id)
  let assert 1 = list.length(wines)
  let assert True = db.is_wine_in_list(conn, list_id, wine_id)
  Nil
}

pub fn virtual_list_rejects_wines_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let assert Ok(cellar) = db.get_list_by_slug(conn, "test", "cellar")
  let wine_id =
    db.upsert_wine(conn,
      created_by: "test", winery: "Test Winery", name: "Test Wine",
      vintage: None, region: None, country: None, style: None,
      personal_note: None, wine_type: db.Red, vivino_id: None,
    )
  // This should fail due to the trigger
  let result =
    sqlight.query(
      "INSERT INTO lists_wines (list_id, wine_id, vintage) VALUES (?, ?, '')",
      conn,
      [sqlight.text(cellar.id), sqlight.text(wine_id)],
      fn(_) { Nil },
    )
  // The trigger should cause an error — we expect this to fail
  // In Gleam/sqlight, the query will crash with an assert error
  // We verify by checking no wines were added
  let wines = db.list_wines_for_list(conn, cellar.id)
  let assert 0 = list.length(wines)
  Nil
}

pub fn set_list_public_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let id = db.create_list(conn, "test", "Shared List", None)
  let assert Ok(l) = db.get_list(conn, id)
  let assert False = l.public
  db.set_list_public(conn, id, True)
  let assert Ok(l2) = db.get_list(conn, id)
  let assert True = l2.public
  Nil
}

pub fn shared_view_returns_200_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let id = db.create_list(conn, "test", "Public List", None)
  db.set_list_public(conn, id, True)
  let response =
    simulate.request(http.Get, "/shared/" <> id <> "/public-list")
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  Nil
}

pub fn shared_view_private_returns_404_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let id = db.create_list(conn, "test", "Private List", None)
  let response =
    simulate.request(http.Get, "/shared/" <> id <> "/private-list")
    |> router.handle_request(conn, test_auth)
  let assert 404 = response.status
  Nil
}
```

Note: The `virtual_list_rejects_wines_test` may need adjustment based on how sqlight handles SQLite trigger errors. If the trigger error crashes, wrap in a different approach or test at the route level instead.

- [ ] **Step 2: Run all tests**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add test/rebstock_test.gleam
git commit -m "Add tests for lists CRUD, sharing, and virtual list constraint"
```

---

**Self-review notes:**

1. **Spec coverage check:**
   - Data model (lists + lists_wines + trigger): Task 2 ✓
   - CSS variables: Task 1 ✓
   - List CRUD in DB: Task 3 ✓
   - Wishlist rewrite: Tasks 4, 5, 6 ✓
   - Nav link + system list creation: Task 7 ✓
   - Lists web handler: Task 8 ✓
   - Shared view: Task 9 ✓
   - Wine detail "add to list": Task 10 ✓
   - Tests: Tasks 6, 11 ✓
   - Protection rules: Enforced in Task 3 (trigger), Task 8 (handler checks) ✓

2. **Type consistency:** `db.List`, `db.ListType`, `db.ListWine`, `db.SharedWine` (internal to shared.gleam) used consistently across tasks.

3. **Missing from plan:** The `decode_wine_row` function is referenced but assumed to exist (it does — it's the existing wine row decoder in db.gleam). The `wine_type_label` function is also assumed to exist (it does in components.gleam — may need to be moved or re-exported from db.gleam for use in shared.gleam).
