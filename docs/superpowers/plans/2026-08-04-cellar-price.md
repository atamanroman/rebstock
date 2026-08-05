# Cellar Entry Price Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record an optional per-bottle price on cellar purchases so the cellar can be read in money as well as in bottles.

**Architecture:** A nullable `price_cents` column on `cellar`, set only on purchase rows; drink rows inherit their parent's price through a join at query time. Held value per wine+vintage comes from one correlated subquery that returns a `bottles x price` breakdown string, parsed into pairs in Gleam so the value shown and the prices behind it cannot disagree. Everything degrades to showing nothing when no price is set.

**Tech Stack:** Gleam (erlang target), sqlight + SQLite, migrant migrations, wisp + nakai + htmx, Tailwind v4.

Spec: `docs/superpowers/specs/2026-08-04-cellar-price-design.md`.

## Global Constraints

- Prices are stored as integer cents, never floats. `price_cents` means one bottle, not the whole entry.
- Only purchase rows (positive quantity, no `parent_id`) carry a price. `insert_cellar_drink` never sets one.
- Money renders en-US: decimal point, leading `€`, no thousands separator. `1370` → `€13.70`, `123456` → `€1234.56`.
- CSV holds a bare number with no euro sign, e.g. `27.40`.
- Every surface omits price entirely when unset — never `€0.00`, never `0`.
- Never modify an existing migration file. Migration 00005 is new.
- `gleam format .` before every commit; `gleam build --warnings-as-errors` must stay clean.
- Commit messages: plain capitalized imperative, no conventional-commit prefixes.
- No `CHANGELOG.md` edits — this repo writes the changelog at release time.

## Deviation from the spec

The spec's "Held value" section calls for a separate `cellar_total_value` SQL query for the page subtitle. This plan drops it and folds the value out of the rows already on the page instead.

Reason: the cellar page subtitle's bottle count is already a fold over the rating-filtered rows (`cellar.gleam:26`). An unfiltered `cellar_total_value` query would print a value that does not match the bottles beside it whenever a rating filter is active. Folding keeps the two numbers describing the same set and removes a query.

## File Structure

- `priv/migrations/00005_cellar_price.up.sql` (create) — adds the column.
- `priv/migrations/00005_cellar_price.down.sql` (create) — drops it.
- `src/rebstock/db.gleam` (modify) — `CellarEntry.price_cents`, `CellarWine.price_breakdown`, money helpers, breakdown subquery, insert/update signatures.
- `src/rebstock/web/cellar.gleam` (modify) — form field, handlers, entry card row, table Value column, page subtitle, CSV column.
- `src/rebstock/seed.gleam`, `src/rebstock/vivino.gleam` (modify) — pass `price_cents: None`.
- `test/db_test.gleam` (modify) — money helper, held value and breakdown tests.
- `test/test_helpers.gleam`, `test/rating_filter_test.gleam`, `test/rebstock_test.gleam` (modify) — pass `price_cents: None`.
- `test/cellar_test.gleam` (modify) — form round-trip test.

---

### Task 1: Money helpers

Pure functions, no database. Everything later formats through them.

**Files:**
- Modify: `src/rebstock/db.gleam` (add beside `parse_optional_float`, around line 1971)
- Test: `test/db_test.gleam`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `pub fn parse_price_cents(s: String) -> Option(Int)`
  - `pub fn format_price(cents: Int) -> String` — `€13.70`
  - `pub fn format_price_plain(cents: Int) -> String` — `13.70`, for CSV and form values

- [ ] **Step 1: Write the failing tests**

Append to `test/db_test.gleam`:

```gleam
pub fn parse_price_cents_test() {
  let assert None = db.parse_price_cents("")
  let assert None = db.parse_price_cents("  ")
  let assert None = db.parse_price_cents("free")
  let assert Some(1370) = db.parse_price_cents("13.70")
  let assert Some(1370) = db.parse_price_cents("13.7")
  let assert Some(1371) = db.parse_price_cents("13.705")
  let assert Some(1300) = db.parse_price_cents("13")
  Nil
}

pub fn format_price_test() {
  let assert "\u{20ac}13.70" = db.format_price(1370)
  let assert "\u{20ac}0.05" = db.format_price(5)
  let assert "\u{20ac}1234.56" = db.format_price(123_456)
  let assert "13.70" = db.format_price_plain(1370)
  let assert "1234.56" = db.format_price_plain(123_456)
  Nil
}
```

`test/db_test.gleam` already imports `gleam/option.{None, Some}` and `rebstock/db` — no import changes needed.

- [ ] **Step 2: Run the tests and watch them fail**

Run: `gleam test`

Expected: compile error, `Unknown module field parse_price_cents` (and `format_price`, `format_price_plain`) on module `rebstock/db`.

- [ ] **Step 3: Implement the helpers**

In `src/rebstock/db.gleam`, directly after `parse_optional_float` (ends line 1971):

```gleam
pub fn parse_price_cents(s: String) -> Option(Int) {
  case parse_optional_float(s) {
    None -> None
    Some(euros) -> Some(float.round(euros *. 100.0))
  }
}

/// Euro amount without a sign, for the CSV export and number inputs
pub fn format_price_plain(cents: Int) -> String {
  int.to_string(cents / 100)
  <> "."
  <> string.pad_start(int.to_string(cents % 100), to: 2, with: "0")
}

pub fn format_price(cents: Int) -> String {
  "\u{20ac}" <> format_price_plain(cents)
}
```

`gleam/float`, `gleam/int` and `gleam/string` are already imported in `db.gleam`.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `gleam test`

Expected: all tests pass, including `parse_price_cents_test` and `format_price_test`.

- [ ] **Step 5: Format, lint, commit**

```
gleam format .
```

```
just lint
```

```
git add src/rebstock/db.gleam test/db_test.gleam
git commit -m "Add euro parsing and formatting helpers"
```

---

### Task 2: Store the price on cellar entries

Migration, model field, and the write path. No interface yet.

**Files:**
- Create: `priv/migrations/00005_cellar_price.up.sql`
- Create: `priv/migrations/00005_cellar_price.down.sql`
- Modify: `src/rebstock/db.gleam` — `CellarEntry` (line 147), `cellar_entry_decoder` (line 260), the three `SELECT`s at lines 965, 1000, 1200, `insert_cellar_entry` (line 1012), `update_cellar_entry` (line 1070)
- Modify: `src/rebstock/seed.gleam:66,75`, `src/rebstock/vivino.gleam:562`
- Modify: `test/test_helpers.gleam:60,118,127`, `test/rating_filter_test.gleam:105`, `test/rebstock_test.gleam:69`
- Test: `test/db_test.gleam`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `CellarEntry` gains `price_cents: Option(Int)` as its last field, after `created_at`.
  - `insert_cellar_entry(conn, username:, wine_id:, vintage:, quantity:, notes:, date:, price_cents:)` — `price_cents: Option(Int)` is the last labelled argument.
  - `update_cellar_entry(conn, id:, vintage:, quantity:, notes:, date:, price_cents:)` — same, last.

- [ ] **Step 1: Write the failing test**

Append to `test/db_test.gleam`:

```gleam
pub fn cellar_entry_stores_price_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Priced Cab", db.Red)
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2020"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: Some(1370),
  )
  let assert [entry] = db.cellar_entries_for_wine(conn, wine_id)
  let assert Some(1370) = entry.price_cents
  db.update_cellar_entry(
    conn,
    id: entry.id,
    vintage: Some("2020"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: None,
  )
  let assert [cleared] = db.cellar_entries_for_wine(conn, wine_id)
  let assert None = cleared.price_cents
  Nil
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `gleam test`

Expected: compile error, `insert_cellar_entry` given an unexpected labelled argument `price_cents`.

- [ ] **Step 3: Write the migration**

`priv/migrations/00005_cellar_price.up.sql`:

```sql
-- What a bottle cost, in integer cents, on purchase rows only. Drink rows
-- read the price of the purchase they draw from.
ALTER TABLE cellar ADD COLUMN price_cents INTEGER;
```

`priv/migrations/00005_cellar_price.down.sql`:

```sql
ALTER TABLE cellar DROP COLUMN price_cents;
```

- [ ] **Step 4: Add the field, decoder and column to every cellar SELECT**

In `src/rebstock/db.gleam`, `CellarEntry` (line 147) gains a last field:

```gleam
pub type CellarEntry {
  CellarEntry(
    id: String,
    username: String,
    wine_id: String,
    vintage: Option(String),
    quantity: Int,
    notes: Option(String),
    date: Option(String),
    parent_id: Option(String),
    created_at: String,
    price_cents: Option(Int),
  )
}
```

`cellar_entry_decoder` (line 260) reads it at index 9:

```gleam
fn cellar_entry_decoder() -> decode.Decoder(CellarEntry) {
  use id <- decode.field(0, decode.string)
  use username <- decode.field(1, decode.string)
  use wine_id <- decode.field(2, decode.string)
  use vintage <- decode.field(3, decode.optional(decode.string))
  use quantity <- decode.field(4, decode.int)
  use notes <- decode.field(5, decode.optional(decode.string))
  use date <- decode.field(6, decode.optional(decode.string))
  use parent_id <- decode.field(7, decode.optional(decode.string))
  use created_at <- decode.field(8, decode.string)
  use price_cents <- decode.field(9, decode.optional(decode.int))
  decode.success(CellarEntry(
    id:,
    username:,
    wine_id:,
    vintage:,
    quantity:,
    notes:,
    date:,
    parent_id:,
    created_at:,
    price_cents:,
  ))
}
```

All three queries that feed `cellar_entry_decoder` append `c.price_cents` after `c.created_at`:

`cellar_entries_for_wine` (line 965):

```gleam
      "SELECT c.id, c.username, c.wine_id, c.vintage, c.quantity, c.notes, c.date, c.parent_id, c.created_at, c.price_cents
       FROM cellar c WHERE c.wine_id = ? ORDER BY c.created_at DESC",
```

`get_cellar_entry_by_id` (line 1000):

```gleam
      "SELECT c.id, c.username, c.wine_id, c.vintage, c.quantity, c.notes, c.date, c.parent_id, c.created_at, c.price_cents
       FROM cellar c WHERE c.id = ?",
```

`latest_cellar_entries` (line 1200):

```gleam
      "SELECT c.id, c.username, c.wine_id, c.vintage, c.quantity, c.notes, c.date, c.parent_id, c.created_at, c.price_cents
       FROM cellar c WHERE c.username = ?
       ORDER BY c.created_at DESC LIMIT ?",
```

- [ ] **Step 5: Take the price on insert and update**

`insert_cellar_entry` (line 1012):

```gleam
pub fn insert_cellar_entry(
  conn: Connection,
  username username: String,
  wine_id wine_id: String,
  vintage vintage: Option(String),
  quantity quantity: Int,
  notes notes: Option(String),
  date date: Option(String),
  price_cents price_cents: Option(Int),
) -> Nil {
  let id = ulid.generate()
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO cellar (id, username, wine_id, vintage, quantity, notes, date, price_cents)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      on: conn,
      with: [
        sqlight.text(id),
        sqlight.text(username),
        sqlight.text(wine_id),
        nullable_text(vintage),
        sqlight.int(quantity),
        nullable_text(notes),
        nullable_text(date),
        nullable_int(price_cents),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}
```

`update_cellar_entry` (line 1070):

```gleam
pub fn update_cellar_entry(
  conn: Connection,
  id id: String,
  vintage vintage: Option(String),
  quantity quantity: Int,
  notes notes: Option(String),
  date date: Option(String),
  price_cents price_cents: Option(Int),
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "UPDATE cellar SET vintage = ?, quantity = ?, notes = ?, date = ?, price_cents = ?
       WHERE id = ?",
      on: conn,
      with: [
        nullable_text(vintage),
        sqlight.int(quantity),
        nullable_text(notes),
        nullable_text(date),
        nullable_int(price_cents),
        sqlight.text(id),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}
```

`insert_cellar_drink` is left exactly as it is.

- [ ] **Step 6: Update every caller to pass `price_cents: None`**

Add `price_cents: None,` as the last argument at each of these call sites — the surrounding code is unchanged:

- `src/rebstock/seed.gleam:66` and `:75`
- `src/rebstock/vivino.gleam:562` (CSV import has no price column)
- `src/rebstock/web/cellar.gleam:216` (`db.insert_cellar_entry` in `handle_new`) — placeholder, Task 4 replaces it
- `src/rebstock/web/cellar.gleam:274` (`db.update_cellar_entry` in `handle_edit`) — placeholder, Task 4 replaces it
- `test/test_helpers.gleam:60`, `:118`, `:127`
- `test/rating_filter_test.gleam:105`
- `test/rebstock_test.gleam:69`

Example, `test/test_helpers.gleam:60`:

```gleam
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some(vintage),
    quantity: quantity,
    notes: None,
    date: None,
    price_cents: None,
  )
```

Check none were missed:

```
grep -rn "insert_cellar_entry\|update_cellar_entry" src test
```

- [ ] **Step 7: Run the tests and watch them pass**

Run: `gleam test`

Expected: all tests pass, including `cellar_entry_stores_price_test`.

- [ ] **Step 8: Format, lint, commit**

```
gleam format .
```

```
just lint
```

```
git add priv/migrations src/rebstock test
git commit -m "Store an optional per-bottle price on cellar purchases"
```

---

### Task 3: Held value per wine and vintage

The read side: how many bottles are still held at each price.

**Files:**
- Modify: `src/rebstock/db.gleam` — `CellarWine` (line 864), `cellar_wine_cols` (line 868), `cellar_wine_decoder` (line 879), new `held_value` beside them
- Test: `test/db_test.gleam`

**Interfaces:**
- Consumes: `insert_cellar_entry(… price_cents:)` from Task 2.
- Produces:
  - `CellarWine(wine:, vintage:, bottles:, price_breakdown:)` where `price_breakdown: List(#(Int, Int))` is `#(bottles, unit price in cents)`, sorted ascending by price.
  - `pub fn held_value(breakdown: List(#(Int, Int))) -> Option(Int)` — `None` for an empty breakdown, otherwise the summed cents.

- [ ] **Step 1: Write the failing tests**

Append to `test/db_test.gleam`:

```gleam
pub fn cellar_value_survives_drinking_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Tenner", db.Red)
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2021"),
    quantity: 3,
    notes: None,
    date: None,
    price_cents: Some(1000),
  )
  let assert [entry] = db.cellar_entries_for_wine(conn, wine_id)
  db.insert_cellar_drink(
    conn,
    parent_id: entry.id,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2021"),
    notes: None,
    date: None,
  )
  let assert [cw] = db.cellar_wines(conn, "test", db.unfiltered)
  let assert 2 = cw.bottles
  let assert Some(2000) = db.held_value(cw.price_breakdown)
  Nil
}

pub fn cellar_price_breakdown_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Two Prices", db.White)
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2022"),
    quantity: 1,
    notes: None,
    date: None,
    price_cents: Some(1420),
  )
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2022"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: Some(1370),
  )
  let assert [cw] = db.cellar_wines(conn, "test", db.unfiltered)
  let assert [#(2, 1370), #(1, 1420)] = cw.price_breakdown
  let assert Some(4160) = db.held_value(cw.price_breakdown)
  Nil
}

pub fn cellar_without_price_has_no_value_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Unpriced", db.Red)
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2019"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: None,
  )
  let assert [cw] = db.cellar_wines(conn, "test", db.unfiltered)
  let assert [] = cw.price_breakdown
  let assert None = db.held_value(cw.price_breakdown)
  Nil
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `gleam test`

Expected: compile error, `CellarWine` has no field `price_breakdown` and `held_value` is unknown on `rebstock/db`.

- [ ] **Step 3: Add the breakdown column, field and decoder**

In `src/rebstock/db.gleam`, replace the `CellarWine` type and `cellar_wine_cols` (lines 863-873) with:

```gleam
/// Wine + vintage + bottle count for cellar views
pub type CellarWine {
  CellarWine(
    wine: Wine,
    vintage: Option(String),
    bottles: Int,
    price_breakdown: List(#(Int, Int)),
  )
}

const cellar_wine_cols = "w.id, w.created_by, w.winery_id, wy.name, w.name,
        (SELECT GROUP_CONCAT(v.year) FROM wines_vintages v WHERE v.wine_id = w.id ORDER BY v.year) AS vintages,
        w.region, wy.country, w.style,
        w.personal_note, w.wine_type,
        w.vivino_id, w.vivino_rating, w.vivino_rating_count,
        c.vintage, COALESCE(SUM(c.quantity), 0) AS bottles,
        (SELECT GROUP_CONCAT(pb.bottles || 'x' || pb.price)
         FROM (SELECT COALESCE(c2.price_cents, p2.price_cents) AS price,
                      SUM(c2.quantity) AS bottles
               FROM cellar c2 LEFT JOIN cellar p2 ON c2.parent_id = p2.id
               WHERE c2.username = c.username AND c2.wine_id = w.id
                 AND c2.vintage IS c.vintage
                 AND COALESCE(c2.price_cents, p2.price_cents) IS NOT NULL
               GROUP BY price HAVING bottles > 0) pb) AS price_breakdown"
```

The vintage comparison is `IS`, not `=`, because entries without a vintage hold `NULL`.

Add the parser and the fold beside the decoder, above `cellar_wine_decoder` (line 879):

```gleam
/// `"2x1370,1x1420"` from GROUP_CONCAT, whose order is not guaranteed,
/// into pairs of held bottles and unit price sorted by price
fn parse_price_breakdown(raw: Option(String)) -> List(#(Int, Int)) {
  case raw {
    None -> []
    Some(concatenated) ->
      concatenated
      |> string.split(",")
      |> list.filter_map(fn(pair) {
        case string.split(pair, "x") {
          [bottles, price] ->
            case int.parse(bottles), int.parse(price) {
              Ok(b), Ok(p) -> Ok(#(b, p))
              _, _ -> Error(Nil)
            }
          _ -> Error(Nil)
        }
      })
      |> list.sort(fn(a, b) { int.compare(a.1, b.1) })
  }
}

/// What the bottles still in the rack cost, `None` when none of them are priced
pub fn held_value(breakdown: List(#(Int, Int))) -> Option(Int) {
  case breakdown {
    [] -> None
    _ -> Some(list.fold(breakdown, 0, fn(acc, pair) { acc + pair.0 * pair.1 }))
  }
}
```

`cellar_wine_decoder` reads the new column at index 16:

```gleam
  use vintage <- decode.field(14, decode.optional(decode.string))
  use bottles <- decode.field(15, decode.int)
  use price_breakdown <- decode.field(16, decode.optional(decode.string))
  decode.success(CellarWine(
    wine: Wine(
      id:,
      created_by:,
      winery_id:,
      winery_name:,
      name:,
      vintages:,
      region:,
      country:,
      style:,
      personal_note:,
      wine_type: wine_type_from_string(wine_type_str),
      vivino_id:,
      vivino_rating:,
      vivino_rating_count:,
    ),
    vintage:,
    bottles:,
    price_breakdown: parse_price_breakdown(price_breakdown),
  ))
```

`gleam/list`, `gleam/int` and `gleam/string` are already imported in `db.gleam`.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `gleam test`

Expected: all tests pass, including the three new ones. `cellar_value_survives_drinking_test` is the one that proves a drink row inherits its parent's price instead of counting as free.

- [ ] **Step 5: Format, lint, commit**

```
gleam format .
```

```
just lint
```

```
git add src/rebstock/db.gleam test/db_test.gleam
git commit -m "Derive held cellar value from the prices bottles were bought at"
```

---

### Task 4: Price on the cellar form and entry card

**Files:**
- Modify: `src/rebstock/web/cellar.gleam` — `handle_new` (line 203), `handle_edit` (line 264), `cellar_form` (line 569, field goes between Quantity and Date), `cellar_entry_card` (line 828), new `form_price` helper beside `form_int` (line 817)
- Test: `test/cellar_test.gleam`

**Interfaces:**
- Consumes: `db.parse_price_cents`, `db.format_price`, `db.format_price_plain` (Task 1); `CellarEntry.price_cents`, `insert_cellar_entry`/`update_cellar_entry` `price_cents:` (Task 2).
- Produces: form field named `price`; nothing other modules call.

- [ ] **Step 1: Write the failing test**

Append to `test/cellar_test.gleam`:

```gleam
pub fn cellar_entry_price_round_trip_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let #(wine_id, entry_id) = create_test_cellar_wine(conn, "Priced Syrah", "2020", 2)
  let edit_url =
    wine_path(wine_id, "Priced Syrah") <> "/cellar/" <> entry_id <> "/edit"
  let response =
    simulate.request(http.Post, edit_url)
    |> simulate.form_body([
      #("vintage", "2020"),
      #("quantity", "2"),
      #("notes", ""),
      #("date", "2026-02-01"),
      #("price", "13.70"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let assert Ok(entry) = db.get_cellar_entry_by_id(conn, entry_id)
  let assert Some(1370) = entry.price_cents

  let response =
    simulate.request(http.Get, "/cellar/" <> entry_id)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "\u{20ac}13.70")
  let assert True = string.contains(body, "\u{20ac}27.40 for 2 bottles")

  let response =
    simulate.request(http.Get, edit_url)
    |> router.handle_request(conn, test_config)
  let assert True = string.contains(simulate.read_body(response), "value=\"13.70\"")
  Nil
}
```

Add `gleam/option.{Some}` to the imports at the top of `test/cellar_test.gleam`:

```gleam
import gleam/http
import gleam/option.{Some}
import gleam/string
import wisp/simulate
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `gleam test`

Expected: FAIL in `cellar_entry_price_round_trip_test` — the assert `Some(1370) = entry.price_cents` does not match, because the handler still passes `price_cents: None`.

- [ ] **Step 3: Read the price out of the form**

In `src/rebstock/web/cellar.gleam`, add beside `form_int` (after line 826):

```gleam
fn form_price(form: wisp.FormData) -> Option(Int) {
  case form_value(form, "price") {
    None -> None
    Some(s) -> db.parse_price_cents(s)
  }
}
```

In `handle_new` (line 203), read it and pass it on:

```gleam
        http.Post -> {
          use form <- wisp.require_form(req)
          let vintage = form_value(form, "vintage")
          let quantity = form_int(form, "quantity")
          let notes = form_value(form, "notes")
          let date = form_value(form, "date")
          let price_cents = form_price(form)
          case quantity < 1 {
            True ->
              form_error(
                cellar_form(wine, vintages, None),
                "Quantity must be at least 1",
              )
            False -> {
              db.insert_cellar_entry(
                conn,
                username: user.username,
                wine_id: wine.id,
                vintage: vintage,
                quantity: quantity,
                notes: notes,
                date: date,
                price_cents: price_cents,
              )
              wisp.response(200)
              |> wisp.set_header("HX-Redirect", c.wine_url(wine))
            }
          }
        }
```

In `handle_edit` (line 264), the same:

```gleam
                http.Post -> {
                  use form <- wisp.require_form(req)
                  let vintage = form_value(form, "vintage")
                  let quantity = form_int(form, "quantity")
                  let notes = form_value(form, "notes")
                  let date = form_value(form, "date")
                  let price_cents = form_price(form)
                  case quantity_error(conn, entry, quantity) {
                    Some(msg) ->
                      form_error(cellar_form(wine, vintages, Some(entry)), msg)
                    None -> {
                      db.update_cellar_entry(
                        conn,
                        id: entry.id,
                        vintage: vintage,
                        quantity: quantity,
                        notes: notes,
                        date: date,
                        price_cents: price_cents,
                      )
                      wisp.response(200)
                      |> wisp.set_header("HX-Redirect", c.wine_url(wine))
                    }
                  }
                }
```

- [ ] **Step 4: Add the field to the form**

In `cellar_form`, between the Quantity field (ends line 680 with `]),`) and the `// Date` comment (line 681), insert:

```gleam
        // Price per bottle
        form_field("Price per bottle (\u{20ac})", [
          html.Element(
            "input",
            [
              attr.type_("number"),
              attr.name("price"),
              attr.Attr("step", "0.01"),
              attr.Attr("min", "0"),
              attr.Attr("placeholder", "13.70"),
              attr.class(
                "w-full border border-stone-300 rounded-md px-3 py-2 text-sm",
              ),
              ..case existing {
                Some(e) ->
                  case e.price_cents {
                    Some(cents) -> [attr.value(db.format_price_plain(cents))]
                    None -> []
                  }
                None -> []
              }
            ],
            [],
          ),
        ]),
```

`cellar.gleam` already imports `rebstock/db`, so `db.format_price_plain` needs no import change.

The drink form gets no price field.

- [ ] **Step 5: Show the price on the entry card**

In `cellar_entry_card`, after the date paragraph (ends line 858) and before the notes block (line 859), insert:

```gleam
    case entry.price_cents {
      None -> html.Nothing
      Some(cents) ->
        html.p([attr.class("text-sm text-stone-500 mb-4")], [
          html.Text(case entry.quantity {
            1 -> db.format_price(cents)
            n ->
              db.format_price(cents)
              <> " \u{00b7} "
              <> db.format_price(cents * n)
              <> " for "
              <> int.to_string(n)
              <> " bottles"
          }),
        ])
    },
```

- [ ] **Step 6: Run the tests and watch them pass**

Run: `gleam test`

Expected: all tests pass, including `cellar_entry_price_round_trip_test`.

- [ ] **Step 7: Format, lint, commit**

```
gleam format .
```

```
just lint
```

```
git add src/rebstock/web/cellar.gleam test/cellar_test.gleam
git commit -m "Set and show a bottle price on cellar entries"
```

---

### Task 5: Value on the cellar page

**Files:**
- Modify: `src/rebstock/web/cellar.gleam` — `cellar` (line 18, subtitle), `cellar_wine_table` (line 871), `cellar_wine_row` (line 878)
- Test: `test/cellar_test.gleam`

**Interfaces:**
- Consumes: `CellarWine.price_breakdown`, `db.held_value` (Task 3); `db.format_price` (Task 1).
- Produces: nothing other modules call.

- [ ] **Step 1: Write the failing test**

Append to `test/cellar_test.gleam`:

```gleam
pub fn cellar_page_shows_value_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Valued Malbec", db.Red)
  db.upsert_vintage(conn, wine_id, "2021")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2021"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: Some(1370),
  )
  let response =
    simulate.request(http.Get, "/~test/cellar")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "2 bottles \u{b7} \u{20ac}27.40")
  let assert True = string.contains(body, "2\u{d7}\u{20ac}13.70")
  Nil
}
```

Extend the import list at the top of `test/cellar_test.gleam` with `create_test_wine`:

```gleam
import test_helpers.{
  create_test_cellar_wine, create_test_wine, seed_two_users, test_config,
  wine_path, with_empty_db, with_seeded_db,
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `gleam test`

Expected: FAIL in `cellar_page_shows_value_test` — the subtitle reads `2 bottles` with no value and the table has no breakdown title.

- [ ] **Step 3: Fold the value into the subtitle**

In `cellar` (line 18), after `total_bottles`:

```gleam
  let filter = c.rating_filter(req)
  let wines = db.cellar_wines(conn, username, filter)
  let total_bottles = list.fold(wines, 0, fn(acc, cw) { acc + cw.bottles })
  let total_value =
    list.fold(wines, 0, fn(acc, cw) {
      case db.held_value(cw.price_breakdown) {
        Some(cents) -> acc + cents
        None -> acc
      }
    })
  let subtitle =
    int.to_string(total_bottles)
    <> " bottles"
    <> case total_value {
      0 -> ""
      cents -> " \u{00b7} " <> db.format_price(cents)
    }
```

and the paragraph at line 37 uses it:

```gleam
        html.p([attr.class("text-stone-500 mt-1")], [html.Text(subtitle)]),
```

- [ ] **Step 4: Add the Value column**

In `cellar_wine_table` (line 871):

```gleam
fn cellar_wine_table(wines: List(CellarWine)) -> html.Node {
  c.table(
    ["Winery", "Wine", "Vintage", "Country", "Type", "Cellar", "Value"],
    list.index_map(wines, cellar_wine_row),
  )
}
```

In `cellar_wine_row`, after the bottles cell (ends line 904), add `value_cell(cw)` as the last child:

```gleam
      html.td([attr.class("px-4 py-3 text-center tabular-nums")], [
        html.Text(int.to_string(cw.bottles)),
      ]),
      value_cell(cw),
    ],
  )
}

/// Held value, with the prices behind it on hover so the answer costs no request
fn value_cell(cw: CellarWine) -> html.Node {
  case db.held_value(cw.price_breakdown) {
    None -> html.td([attr.class("px-4 py-3")], [])
    Some(cents) ->
      html.td(
        [
          attr.class("px-4 py-3 text-right tabular-nums text-stone-600"),
          attr.Attr("title", breakdown_title(cw.price_breakdown)),
        ],
        [html.Text(db.format_price(cents))],
      )
  }
}

fn breakdown_title(breakdown: List(#(Int, Int))) -> String {
  breakdown
  |> list.map(fn(pair) {
    int.to_string(pair.0) <> "\u{00d7}" <> db.format_price(pair.1)
  })
  |> string.join(", ")
}
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `gleam test`

Expected: all tests pass, including `cellar_page_shows_value_test`.

- [ ] **Step 6: Look at the page**

```
just dev
```

Open `http://localhost:3000/~<username>/cellar`, confirm the subtitle reads `N bottles · €X` and that hovering a Value cell shows `2×€13.70, 1×€14.20`. Stop the server.

- [ ] **Step 7: Format, lint, commit**

```
gleam format .
```

```
just lint
```

```
git add src/rebstock/web/cellar.gleam test/cellar_test.gleam
git commit -m "Show what the cellar holds in money beside the bottle count"
```

---

### Task 6: Value in the CSV export

**Files:**
- Modify: `src/rebstock/web/cellar.gleam` — `cellar_csv_body` (line 129)
- Test: `test/cellar_test.gleam`

**Interfaces:**
- Consumes: `db.held_value` (Task 3), `db.format_price_plain` (Task 1).
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

Append to `test/cellar_test.gleam`:

```gleam
pub fn cellar_csv_has_value_column_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Exported Riesling", db.White)
  db.upsert_vintage(conn, wine_id, "2021")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2021"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: Some(1370),
  )
  let response =
    simulate.request(http.Get, "/~test/cellar/export.csv")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True =
    string.contains(body, "Winery,Wine,Vintage,Country,Type,Bottles,Value")
  let assert True = string.contains(body, ",2,27.40")
  Nil
}
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `gleam test`

Expected: FAIL in `cellar_csv_has_value_column_test` — the header still ends at `Bottles`.

- [ ] **Step 3: Add the column**

In `cellar_csv_body` (line 129):

```gleam
fn cellar_csv_body(conn: Connection, username: String) -> Response {
  let wines = db.cellar_wines(conn, username, db.unfiltered)
  let header = "Winery,Wine,Vintage,Country,Type,Bottles,Value"
  let rows =
    list.map(wines, fn(cw) {
      [
        csv_field(cw.wine.winery_name),
        csv_field(cw.wine.name),
        c.display_vintage(cw.vintage),
        csv_field(c.display_country(cw.wine.country)),
        db.wine_type_to_string(cw.wine.wine_type),
        int.to_string(cw.bottles),
        case db.held_value(cw.price_breakdown) {
          Some(cents) -> db.format_price_plain(cents)
          None -> ""
        },
      ]
      |> string.join(",")
    })
  let csv = [header, ..rows] |> string.join("\n")
  wisp.response(200)
  |> wisp.file_download_from_memory(
    named: "cellar.csv",
    containing: bytes_tree.from_string(csv),
  )
}
```

The field is a bare number so a spreadsheet reads it as one, and it needs no `csv_field` quoting because it never holds a comma.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `gleam test`

Expected: all tests pass, including `cellar_csv_has_value_column_test` and the existing `cellar_csv_test`.

- [ ] **Step 5: Format, lint, commit**

```
gleam format .
```

```
just lint
```

```
git add src/rebstock/web/cellar.gleam test/cellar_test.gleam
git commit -m "Export held cellar value as a CSV column"
```

---

## After the plan

The spec's backfill of invoice #37140 is a one-off script written to the scratchpad and run against the live database after deploy. It is not committed and is not part of any task here. It matches on `wines.vivino_id` first and falls back to winery, wine name and vintage, because a Vivino sync rewrites the unresolved `v<vintage-id>` form into the resolved wine id.
