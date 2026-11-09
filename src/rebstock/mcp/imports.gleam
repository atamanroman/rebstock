import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sqlight.{type Connection, type Value}

import rebstock/ulid

type Object =
  Dict(String, Dynamic)

type Vintage {
  Vintage(year: String, rating: Option(Float), count: Option(Int))
}

type WineInput {
  WineInput(
    ref: String,
    wine_id: Option(String),
    winery: Option(String),
    name: Option(String),
    region: Option(String),
    country: Option(String),
    style: Option(String),
    personal_note: Option(String),
    wine_type: Option(String),
    vivino_id: Option(String),
    rating: Option(Float),
    count: Option(Int),
    vintages: List(Vintage),
  )
}

type Child {
  Child(
    kind: String,
    ref: String,
    wine_ref: Option(String),
    wine_id: Option(String),
    vintage: Option(String),
    quantity: Int,
    date: Option(String),
    notes: Option(String),
    price: Option(Int),
    rating: Option(Float),
    rated_at: Option(String),
    tasting_notes: Option(String),
  )
}

type Batch {
  Batch(
    source: String,
    apply: Bool,
    wines: List(WineInput),
    children: List(Child),
  )
}

type Wine {
  Wine(
    id: String,
    winery_id: String,
    winery: String,
    name: String,
    region: Option(String),
    style: Option(String),
    personal_note: Option(String),
    wine_type: String,
    vivino_id: Option(String),
    rating: Option(Float),
    count: Option(Int),
    vintages: List(Vintage),
  )
}

type Winery {
  Winery(id: String, name: String, country: Option(String))
}

type Ledger {
  Ledger(
    kind: String,
    ref: String,
    fingerprint: String,
    id: String,
    wine_id: String,
  )
}

type Statement {
  Statement(sql: String, arguments: List(Value))
}

type Plan {
  Plan(
    kind: String,
    ref: String,
    fingerprint: String,
    id: String,
    wine_id: String,
    outcome: String,
    matched_by: String,
    changes: List(json.Json),
    statements: List(Statement),
    bottles: Int,
  )
}

type State {
  State(
    username: String,
    wines: List(Wine),
    wineries: List(Winery),
    ledger: List(Ledger),
    plans: List(Plan),
  )
}

@external(erlang, "mcp_import_ffi", "with_connection")
fn with_connection(
  uri: String,
  apply: Bool,
  work: fn(Connection) -> Result(json.Json, String),
) -> Result(json.Json, String)

@external(erlang, "mcp_import_ffi", "valid_date")
fn calendar_date(year: Int, month: Int, day: Int) -> Bool

pub fn run(
  database_uri: String,
  username: String,
  arguments: Dynamic,
) -> Result(json.Json, String) {
  use batch <- result.try(parse_batch(arguments))
  use _ <- result.try(check(string.trim(username) != "", "Username is required"))
  with_connection(database_uri, batch.apply, fn(conn) {
    use initial <- result.try(load_state(conn, username, batch.source))
    use planned <- result.try(
      list.try_fold(batch.wines, initial, fn(state, input) {
        plan_wine(state, input) |> in_record("wines", input.ref)
      }),
    )
    use planned <- result.try(
      list.try_fold(batch.children, planned, fn(state, input) {
        plan_child(conn, state, input) |> in_record(input.kind, input.ref)
      }),
    )
    let plans = list.reverse(planned.plans)
    use _ <- result.try(case batch.apply {
      True -> apply_plans(conn, username, batch.source, plans)
      False -> Ok(Nil)
    })
    Ok(output(batch, plans))
  })
}

fn check(valid: Bool, error: String) -> Result(Nil, String) {
  case valid {
    True -> Ok(Nil)
    False -> Error(error)
  }
}

fn object(value: Dynamic) -> Result(Object, String) {
  decode.run(value, decode.dict(decode.string, decode.dynamic))
  |> result.map_error(fn(_) { "Expected an object" })
}

fn fields(value: Object, allowed: List(String)) -> Result(Nil, String) {
  case list.find(dict.keys(value), fn(key) { !list.contains(allowed, key) }) {
    Ok(key) -> Error("Unknown field: " <> key)
    Error(_) -> Ok(Nil)
  }
}

fn required(
  value: Object,
  key: String,
  decoder: decode.Decoder(a),
) -> Result(a, String) {
  use raw <- result.try(
    dict.get(value, key) |> result.map_error(fn(_) { "Missing field: " <> key }),
  )
  decode.run(raw, decoder)
  |> result.map_error(fn(_) { "Invalid field: " <> key })
}

fn optional(
  value: Object,
  key: String,
  decoder: decode.Decoder(a),
) -> Result(Option(a), String) {
  case dict.get(value, key) {
    Error(_) -> Ok(None)
    Ok(raw) ->
      decode.run(raw, decode.optional(decoder))
      |> result.map_error(fn(_) { "Invalid field: " <> key })
  }
}

fn text(value: Object, key: String) -> Result(String, String) {
  use value <- result.try(required(value, key, decode.string))
  let value = string.trim(value)
  use _ <- result.try(check(
    value != "" && string.length(value) <= 1000,
    "Invalid nonempty text: " <> key,
  ))
  Ok(value)
}

fn optional_text(value: Object, key: String) -> Result(Option(String), String) {
  use value <- result.try(optional(value, key, decode.string))
  case value {
    None -> Ok(None)
    Some(value) -> {
      use _ <- result.try(check(
        string.length(value) <= 100_000,
        "Text too long: " <> key,
      ))
      Ok(Some(value))
    }
  }
}

fn optional_anchor(
  value: Object,
  key: String,
) -> Result(Option(String), String) {
  use anchor <- result.try(optional_text(value, key))
  case anchor {
    None -> Ok(None)
    Some(anchor) -> {
      let anchor = string.trim(anchor)
      use _ <- result.try(check(
        anchor != "" && string.length(anchor) <= 1000,
        "Invalid nonempty text: " <> key,
      ))
      Ok(Some(anchor))
    }
  }
}

fn rows(value: Object, key: String) -> Result(List(Dynamic), String) {
  case dict.get(value, key) {
    Error(_) -> Ok([])
    Ok(raw) ->
      decode.run(raw, decode.list(decode.dynamic))
      |> result.map_error(fn(_) { "Expected an array: " <> key })
  }
}

fn record_label(kind: String, ref: String) -> String {
  kind <> "[ref=" <> json.to_string(json.string(ref)) <> "]"
}

fn in_record(
  value: Result(a, String),
  kind: String,
  ref: String,
) -> Result(a, String) {
  value
  |> result.map_error(fn(error) { record_label(kind, ref) <> ": " <> error })
}

fn parse_records(
  values: List(Dynamic),
  kind: String,
  parse: fn(Dynamic) -> Result(a, String),
) -> Result(List(a), String) {
  values
  |> list.index_map(fn(value, index) { #(value, index) })
  |> list.try_map(fn(item) {
    let #(value, index) = item
    let label = case decode.run(value, decode.at(["ref"], decode.string)) {
      Ok(ref) -> {
        let ref = string.trim(ref)
        case ref != "" && string.length(ref) <= 1000 {
          True -> record_label(kind, ref)
          False -> kind <> "[" <> int.to_string(index) <> "]"
        }
      }
      Error(_) -> kind <> "[" <> int.to_string(index) <> "]"
    }
    parse(value) |> result.map_error(fn(error) { label <> ": " <> error })
  })
}

fn unique_references(
  references: List(#(String, String)),
) -> Result(Nil, String) {
  use _ <- result.try(
    list.try_fold(references, [], fn(seen, reference) {
      let #(kind, ref) = reference
      use _ <- result.try(check(
        !list.contains(seen, reference),
        record_label(kind, ref) <> ": Duplicate source ref in batch",
      ))
      Ok([reference, ..seen])
    }),
  )
  Ok(Nil)
}

fn parse_batch(value: Dynamic) -> Result(Batch, String) {
  use value <- result.try(object(value))
  use _ <- result.try(
    fields(value, ["source", "apply", "wines", "cellar", "ratings", "wishlist"]),
  )
  use source <- result.try(text(value, "source"))
  use apply <- result.try(case dict.get(value, "apply") {
    Error(_) -> Ok(False)
    Ok(raw) ->
      decode.run(raw, decode.bool)
      |> result.map_error(fn(_) { "apply must be a boolean" })
  })
  use wines <- result.try(rows(value, "wines"))
  use cellar <- result.try(rows(value, "cellar"))
  use ratings <- result.try(rows(value, "ratings"))
  use wishlist <- result.try(rows(value, "wishlist"))
  let total =
    list.length(wines)
    + list.length(cellar)
    + list.length(ratings)
    + list.length(wishlist)
  use _ <- result.try(check(
    total > 0 && total <= 100,
    "Batch must contain between 1 and 100 records in total",
  ))
  use wines <- result.try(parse_records(wines, "wines", parse_wine))
  use cellar <- result.try(
    parse_records(cellar, "cellar", fn(x) { parse_child(x, "cellar") }),
  )
  use ratings <- result.try(
    parse_records(ratings, "ratings", fn(x) { parse_child(x, "ratings") }),
  )
  use wishlist <- result.try(
    parse_records(wishlist, "wishlist", fn(x) { parse_child(x, "wishlist") }),
  )
  let children = list.flatten([cellar, ratings, wishlist])
  let refs =
    list.append(
      list.map(wines, fn(w) { #("wines", w.ref) }),
      list.map(children, fn(c) { #(c.kind, c.ref) }),
    )
  use _ <- result.try(unique_references(refs))
  Ok(Batch(source, apply, wines, children))
}

fn number() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.map(decode.int, int.to_float)])
}

fn score(value: Object, key: String) -> Result(Option(Float), String) {
  use value <- result.try(optional(value, key, number()))
  use _ <- result.try(check(
    case value {
      None -> True
      Some(x) -> x >=. 0.0 && x <=. 5.0
    },
    key <> " must be between 0 and 5",
  ))
  Ok(value)
}

fn nonnegative(value: Object, key: String) -> Result(Option(Int), String) {
  use value <- result.try(optional(value, key, decode.int))
  use _ <- result.try(check(
    case value {
      None -> True
      Some(x) -> x >= 0
    },
    key <> " must be a nonnegative integer",
  ))
  Ok(value)
}

fn valid_vintage(value: String) -> Bool {
  case value {
    "NV" -> True
    _ ->
      case int.parse(value) {
        Ok(year) -> year >= 1000 && year <= 9999 && int.to_string(year) == value
        Error(_) -> False
      }
  }
}

fn parse_vintage(raw: Dynamic) -> Result(Vintage, String) {
  use value <- result.try(object(raw))
  use _ <- result.try(
    fields(value, ["year", "vivino_rating", "vivino_rating_count"]),
  )
  use year <- result.try(required(value, "year", decode.string))
  use _ <- result.try(check(
    valid_vintage(year),
    "year must be an exact four-digit year or NV",
  ))
  use rating <- result.try(score(value, "vivino_rating"))
  use count <- result.try(nonnegative(value, "vivino_rating_count"))
  Ok(Vintage(year, rating, count))
}

fn parse_wine(raw: Dynamic) -> Result(WineInput, String) {
  use value <- result.try(object(raw))
  use _ <- result.try(
    fields(value, [
      "ref",
      "wine_id",
      "winery",
      "name",
      "region",
      "country",
      "style",
      "personal_note",
      "wine_type",
      "vivino_id",
      "vivino_rating",
      "vivino_rating_count",
      "vintages",
    ]),
  )
  use ref <- result.try(text(value, "ref"))
  use name <- result.try(optional_anchor(value, "name"))
  use winery <- result.try(optional_anchor(value, "winery"))
  use wine_id <- result.try(optional_anchor(value, "wine_id"))
  use _ <- result.try(check(
    case wine_id, name, winery {
      Some(_), _, _ -> True
      None, Some(_), Some(_) -> True
      _, _, _ -> False
    },
    "Supply wine_id or both name and winery",
  ))
  use region <- result.try(optional_text(value, "region"))
  use country <- result.try(optional_text(value, "country"))
  use style <- result.try(optional_text(value, "style"))
  use personal_note <- result.try(optional_text(value, "personal_note"))
  use wine_type <- result.try(optional_text(value, "wine_type"))
  let wine_type = option.map(wine_type, string.uppercase)
  use _ <- result.try(check(
    case wine_type {
      None -> True
      Some(t) ->
        list.contains(
          [
            "RED",
            "WHITE",
            "ROSE",
            "ORANGE",
            "SPARKLING",
            "DESSERT",
            "SAKE",
            "OTHER",
          ],
          t,
        )
    },
    "Unknown wine_type",
  ))
  use vivino_id <- result.try(optional_text(value, "vivino_id"))
  use _ <- result.try(check(
    case vivino_id {
      None -> True
      Some(id) -> positive_id(id)
    },
    "vivino_id must be a positive decimal string",
  ))
  use rating <- result.try(score(value, "vivino_rating"))
  use count <- result.try(nonnegative(value, "vivino_rating_count"))
  use vintages <- result.try(rows(value, "vintages"))
  use vintages <- result.try(parse_records(vintages, "vintages", parse_vintage))
  use _ <- result.try(check(
    list.length(vintages)
      == list.length(list.unique(list.map(vintages, fn(v) { v.year }))),
    "Duplicate wine vintages",
  ))
  Ok(WineInput(
    ref,
    wine_id,
    winery,
    name,
    region,
    country,
    style,
    personal_note,
    wine_type,
    vivino_id,
    rating,
    count,
    list.sort(vintages, fn(a, b) { string.compare(a.year, b.year) }),
  ))
}

fn positive_id(value: String) -> Bool {
  case int.parse(value) {
    Ok(id) -> id > 0 && int.to_string(id) == value
    Error(_) -> False
  }
}

fn digits(value: String) -> Bool {
  list.all(string.to_graphemes(value), fn(char) {
    list.contains(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"], char)
  })
}

fn parse_date(value: Object, key: String) -> Result(Option(String), String) {
  use value <- result.try(optional_text(value, key))
  use _ <- result.try(check(
    case value {
      None -> True
      Some(date) ->
        case string.split(date, "-") {
          [y, m, d] ->
            case int.parse(y), int.parse(m), int.parse(d) {
              Ok(y1), Ok(m1), Ok(d1) ->
                string.length(y) == 4
                && string.length(m) == 2
                && string.length(d) == 2
                && y1 >= 1
                && digits(y)
                && digits(m)
                && digits(d)
                && calendar_date(y1, m1, d1)
              _, _, _ -> False
            }
          _ -> False
        }
    },
    "Invalid calendar date: " <> key,
  ))
  Ok(value)
}

fn parse_child(raw: Dynamic, kind: String) -> Result(Child, String) {
  use value <- result.try(object(raw))
  let specific = case kind {
    "cellar" -> ["quantity", "date", "notes", "price_cents"]
    "ratings" -> ["rating", "rated_at", "tasting_notes"]
    _ -> ["notes"]
  }
  use _ <- result.try(fields(
    value,
    list.append(["ref", "wine_ref", "wine_id", "vintage"], specific),
  ))
  use ref <- result.try(text(value, "ref"))
  use wine_ref <- result.try(optional_text(value, "wine_ref"))
  use wine_id <- result.try(optional_text(value, "wine_id"))
  use _ <- result.try(check(
    case wine_ref, wine_id {
      Some(r), None -> r != ""
      None, Some(id) -> id != ""
      _, _ -> False
    },
    "Supply exactly one of wine_ref or wine_id",
  ))
  use vintage <- result.try(optional_text(value, "vintage"))
  use _ <- result.try(check(
    case vintage {
      None -> True
      Some(v) -> valid_vintage(v)
    },
    "vintage must be an exact four-digit year or NV",
  ))
  use quantity <- result.try(case kind {
    "cellar" -> required(value, "quantity", decode.int)
    _ -> Ok(0)
  })
  use _ <- result.try(check(
    kind != "cellar" || quantity > 0,
    "Purchase quantity must be positive",
  ))
  use date <- result.try(parse_date(value, "date"))
  use notes <- result.try(optional_text(value, "notes"))
  use price <- result.try(nonnegative(value, "price_cents"))
  use rating <- result.try(score(value, "rating"))
  use rated_at <- result.try(parse_date(value, "rated_at"))
  use tasting_notes <- result.try(optional_text(value, "tasting_notes"))
  Ok(Child(
    kind,
    ref,
    wine_ref,
    wine_id,
    vintage,
    quantity,
    date,
    notes,
    price,
    rating,
    rated_at,
    tasting_notes,
  ))
}

fn query(
  conn: Connection,
  sql: String,
  arguments: List(Value),
  decoder: decode.Decoder(a),
) -> Result(List(a), String) {
  sqlight.query(sql, conn, arguments, decoder)
  |> result.map_error(fn(error) { "Import database error: " <> error.message })
}

fn execute(conn: Connection, statement: Statement) -> Result(Nil, String) {
  use _ <- result.try(query(
    conn,
    statement.sql,
    statement.arguments,
    decode.success(Nil),
  ))
  Ok(Nil)
}

fn load_state(
  conn: Connection,
  username: String,
  source: String,
) -> Result(State, String) {
  let wine_decoder = {
    use id <- decode.field(0, decode.string)
    use winery_id <- decode.field(1, decode.string)
    use winery <- decode.field(2, decode.string)
    use name <- decode.field(3, decode.string)
    use region <- decode.field(4, decode.optional(decode.string))
    use style <- decode.field(5, decode.optional(decode.string))
    use personal_note <- decode.field(6, decode.optional(decode.string))
    use wine_type <- decode.field(7, decode.string)
    use vivino_id <- decode.field(8, decode.optional(decode.string))
    use rating <- decode.field(9, decode.optional(number()))
    use count <- decode.field(10, decode.optional(decode.int))
    decode.success(
      Wine(
        id,
        winery_id,
        winery,
        name,
        region,
        style,
        personal_note,
        wine_type,
        vivino_id,
        rating,
        count,
        [],
      ),
    )
  }
  use wines <- result.try(query(
    conn,
    "SELECT w.id, w.winery_id, wy.name, w.name, w.region, w.style, w.personal_note, w.wine_type, w.vivino_id, w.vivino_rating, w.vivino_rating_count FROM wines w JOIN wineries wy ON wy.id = w.winery_id WHERE w.created_by = ?",
    [sqlight.text(username)],
    wine_decoder,
  ))
  use wines <- result.try(
    list.try_map(wines, fn(wine) {
      let decoder = {
        use year <- decode.field(0, decode.string)
        use rating <- decode.field(1, decode.optional(number()))
        use count <- decode.field(2, decode.optional(decode.int))
        decode.success(Vintage(year, rating, count))
      }
      use vintages <- result.try(query(
        conn,
        "SELECT year, vivino_rating, vivino_rating_count FROM wines_vintages WHERE wine_id = ? ORDER BY year",
        [sqlight.text(wine.id)],
        decoder,
      ))
      Ok(Wine(..wine, vintages: vintages))
    }),
  )
  let winery_decoder = {
    use id <- decode.field(0, decode.string)
    use name <- decode.field(1, decode.string)
    use country <- decode.field(2, decode.optional(decode.string))
    decode.success(Winery(id, name, country))
  }
  use wineries <- result.try(query(
    conn,
    "SELECT id, name, country FROM wineries",
    [],
    winery_decoder,
  ))
  let ledger_decoder = {
    use kind <- decode.field(0, decode.string)
    use ref <- decode.field(1, decode.string)
    use fingerprint <- decode.field(2, decode.string)
    use id <- decode.field(3, decode.string)
    use wine_id <- decode.field(4, decode.string)
    decode.success(Ledger(kind, ref, fingerprint, id, wine_id))
  }
  use ledger <- result.try(query(
    conn,
    "SELECT kind, source_ref, fingerprint, destination_id, wine_id FROM mcp_import_records WHERE username = ? AND source = ?",
    [sqlight.text(username), sqlight.text(source)],
    ledger_decoder,
  ))
  Ok(State(username, wines, wineries, ledger, []))
}

fn text_json(value: Option(String)) -> json.Json {
  case value {
    Some(x) -> json.string(x)
    None -> json.null()
  }
}

fn score_json(value: Option(Float)) -> json.Json {
  case value {
    Some(x) -> json.float(x)
    None -> json.null()
  }
}

fn int_json(value: Option(Int)) -> json.Json {
  case value {
    Some(x) -> json.int(x)
    None -> json.null()
  }
}

fn vintage_json(vintage: Vintage) -> json.Json {
  json.object([
    #("year", json.string(vintage.year)),
    #("vivino_rating", score_json(vintage.rating)),
    #("vivino_rating_count", int_json(vintage.count)),
  ])
}

fn fingerprint(value: json.Json) -> String {
  value
  |> json.to_string
  |> bit_array.from_string
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base64_encode(False)
}

fn wine_fingerprint(input: WineInput) -> String {
  json.object([
    #("wine_id", text_json(input.wine_id)),
    #("winery", text_json(input.winery)),
    #("name", text_json(input.name)),
    #("region", text_json(input.region)),
    #("country", text_json(input.country)),
    #("style", text_json(input.style)),
    #("personal_note", text_json(input.personal_note)),
    #("wine_type", text_json(input.wine_type)),
    #("vivino_id", text_json(input.vivino_id)),
    #("vivino_rating", score_json(input.rating)),
    #("vivino_rating_count", int_json(input.count)),
    #("vintages", json.array(input.vintages, vintage_json)),
  ])
  |> fingerprint
}

fn child_fingerprint(input: Child) -> String {
  json.object([
    #("wine_ref", text_json(input.wine_ref)),
    #("wine_id", text_json(input.wine_id)),
    #("vintage", text_json(input.vintage)),
    #("quantity", json.int(input.quantity)),
    #("date", text_json(input.date)),
    #("notes", text_json(input.notes)),
    #("price_cents", int_json(input.price)),
    #("rating", score_json(input.rating)),
    #("rated_at", text_json(input.rated_at)),
    #("tasting_notes", text_json(input.tasting_notes)),
  ])
  |> fingerprint
}

fn replay(
  state: State,
  kind: String,
  ref: String,
  fingerprint: String,
) -> Result(Option(Plan), String) {
  case
    list.find(state.ledger, fn(item) { item.kind == kind && item.ref == ref })
  {
    Error(_) -> Ok(None)
    Ok(item) -> {
      use _ <- result.try(check(
        item.fingerprint == fingerprint,
        "Source reference has changed content: " <> kind <> "/" <> ref,
      ))
      use _ <- result.try(check(
        list.any(state.wines, fn(w) { w.id == item.wine_id }),
        "Imported wine no longer exists or is not owned",
      ))
      Ok(
        Some(Plan(
          kind,
          ref,
          fingerprint,
          item.id,
          item.wine_id,
          "unchanged",
          "source_ref",
          [],
          [],
          0,
        )),
      )
    }
  }
}

fn single(
  wines: List(Wine),
  description: String,
) -> Result(Option(Wine), String) {
  case wines {
    [] -> Ok(None)
    [wine] -> Ok(Some(wine))
    _ -> Error("Ambiguous " <> description)
  }
}

fn match_wine(
  state: State,
  input: WineInput,
) -> Result(#(Option(Wine), String), String) {
  use by_id <- result.try(case input.wine_id {
    None -> Ok(None)
    Some(id) ->
      case list.find(state.wines, fn(w) { w.id == id }) {
        Ok(w) -> Ok(Some(w))
        Error(_) -> Error("wine_id does not identify an owned wine")
      }
  })
  use by_vivino <- result.try(case input.vivino_id {
    None -> Ok(None)
    Some(id) ->
      single(
        list.filter(state.wines, fn(w) { w.vivino_id == Some(id) }),
        "Vivino identity",
      )
  })
  use by_name <- result.try(single(
    list.filter(state.wines, fn(w) {
      input.winery == Some(w.winery) && input.name == Some(w.name)
    }),
    "winery and wine name",
  ))
  let selected = option.or(by_id, option.or(by_vivino, by_name))
  use _ <- result.try(
    list.try_each([by_id, by_vivino, by_name], fn(candidate) {
      check(
        case candidate, selected {
          Some(a), Some(b) -> a.id == b.id
          _, _ -> True
        },
        "wine_id/vivino_id/name/winery: Conflicting wine identity anchors",
      )
    }),
  )
  use _ <- result.try(check(
    case selected {
      None -> True
      Some(w) ->
        option.unwrap(input.winery, w.winery) == w.winery
        && option.unwrap(input.name, w.name) == w.name
        && case w.vivino_id, input.vivino_id {
          Some(a), Some(b) -> a == b
          _, _ -> True
        }
    },
    "name/winery/vivino_id: Conflicting wine identity or Vivino link",
  ))
  let matched_by = case by_id, by_vivino, by_name {
    Some(_), _, _ -> "wine_id"
    _, Some(_), _ -> "vivino_id"
    _, _, Some(_) -> "winery_name"
    _, _, _ -> "new"
  }
  Ok(#(selected, matched_by))
}

fn created_changes(values: List(#(String, json.Json))) -> List(json.Json) {
  list.filter_map(values, fn(item) {
    let #(field, after) = item
    case json.to_string(after) == "null" {
      True -> Error(Nil)
      False ->
        Ok(
          json.object([
            #("field", json.string(field)),
            #("before", json.null()),
            #("after", after),
          ]),
        )
    }
  })
}

fn child_changes(input: Child, wine_id: String) -> List(json.Json) {
  let common = [
    #("wine_id", json.string(wine_id)),
    #("vintage", text_json(input.vintage)),
  ]
  let fields = case input.kind {
    "cellar" -> [
      #("quantity", json.int(input.quantity)),
      #("date", text_json(input.date)),
      #("notes", text_json(input.notes)),
      #("price_cents", int_json(input.price)),
    ]
    "ratings" -> [
      #("rating", score_json(input.rating)),
      #("rated_at", text_json(input.rated_at)),
      #("tasting_notes", text_json(input.tasting_notes)),
    ]
    _ -> [#("notes", text_json(input.notes))]
  }
  created_changes(list.append(common, fields))
}

fn wine_changes(before: Wine, after: Wine) -> List(json.Json) {
  list.filter_map(
    [
      #("region", text_json(before.region), text_json(after.region)),
      #("style", text_json(before.style), text_json(after.style)),
      #(
        "personal_note",
        text_json(before.personal_note),
        text_json(after.personal_note),
      ),
      #(
        "wine_type",
        json.string(before.wine_type),
        json.string(after.wine_type),
      ),
      #("vivino_id", text_json(before.vivino_id), text_json(after.vivino_id)),
      #("vivino_rating", score_json(before.rating), score_json(after.rating)),
      #("vivino_rating_count", int_json(before.count), int_json(after.count)),
      #(
        "vintages",
        json.array(before.vintages, vintage_json),
        json.array(after.vintages, vintage_json),
      ),
    ],
    fn(item) {
      let #(field, old, new) = item
      case json.to_string(old) == json.to_string(new) {
        True -> Error(Nil)
        False ->
          Ok(
            json.object([
              #("field", json.string(field)),
              #("before", old),
              #("after", new),
            ]),
          )
      }
    },
  )
}

fn merge_vintages(
  existing: List(Vintage),
  incoming: List(Vintage),
) -> List(Vintage) {
  list.fold(incoming, existing, fn(acc, input) {
    let merged = case list.find(acc, fn(v) { v.year == input.year }) {
      Error(_) -> input
      Ok(v) ->
        Vintage(
          input.year,
          option.or(input.rating, v.rating),
          option.or(input.count, v.count),
        )
    }
    [merged, ..list.filter(acc, fn(v) { v.year != input.year })]
  })
  |> list.sort(fn(a, b) { string.compare(a.year, b.year) })
}

fn plan_wine(state: State, input: WineInput) -> Result(State, String) {
  let hash = wine_fingerprint(input)
  use replay <- result.try(replay(state, "wines", input.ref, hash))
  case replay {
    Some(plan) -> Ok(State(..state, plans: [plan, ..state.plans]))
    None -> {
      use matched <- result.try(match_wine(state, input))
      let #(existing, matched_by) = matched
      use name <- result.try(option.to_result(
        option.or(input.name, option.map(existing, fn(w) { w.name })),
        "Missing wine name",
      ))
      use winery_name <- result.try(option.to_result(
        option.or(input.winery, option.map(existing, fn(w) { w.winery })),
        "Missing winery name",
      ))
      let existing_winery =
        list.find(state.wineries, fn(wy) { wy.name == winery_name })
      use _ <- result.try(check(
        case existing_winery, input.country {
          Ok(wy), Some(country) -> wy.country == Some(country)
          _, _ -> True
        },
        "country: Shared winery metadata conflict: " <> winery_name,
      ))
      let #(winery, winery_statements) = case existing_winery {
        Ok(winery) -> #(winery, [])
        Error(_) -> {
          let winery = Winery(ulid.generate(), winery_name, input.country)
          #(winery, [
            Statement(
              "INSERT INTO wineries (id, created_by, name, country) VALUES (?, ?, ?, ?)",
              [
                sqlight.text(winery.id),
                sqlight.text(state.username),
                sqlight.text(winery.name),
                sqlight.nullable(sqlight.text, winery.country),
              ],
            ),
          ])
        }
      }
      let before = case existing {
        Some(w) -> w
        None ->
          Wine(
            ulid.generate(),
            winery.id,
            winery_name,
            name,
            None,
            None,
            None,
            "OTHER",
            None,
            None,
            None,
            [],
          )
      }
      let after =
        Wine(
          ..before,
          region: option.or(input.region, before.region),
          style: option.or(input.style, before.style),
          personal_note: option.or(input.personal_note, before.personal_note),
          wine_type: option.unwrap(input.wine_type, before.wine_type),
          vivino_id: option.or(input.vivino_id, before.vivino_id),
          rating: option.or(input.rating, before.rating),
          count: option.or(input.count, before.count),
          vintages: merge_vintages(before.vintages, input.vintages),
        )
      let changes = case existing {
        Some(_) -> wine_changes(before, after)
        None ->
          created_changes([
            #("name", json.string(after.name)),
            #("winery", json.string(after.winery)),
            #("country", text_json(winery.country)),
            #("region", text_json(after.region)),
            #("style", text_json(after.style)),
            #("personal_note", text_json(after.personal_note)),
            #("wine_type", json.string(after.wine_type)),
            #("vivino_id", text_json(after.vivino_id)),
            #("vivino_rating", score_json(after.rating)),
            #("vivino_rating_count", int_json(after.count)),
            #("vintages", json.array(after.vintages, vintage_json)),
          ])
      }
      let sql = case existing {
        None ->
          "INSERT INTO wines (region, style, personal_note, wine_type, vivino_id, vivino_rating, vivino_rating_count, id, created_by, winery_id, name) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        Some(_) ->
          "UPDATE wines SET region = ?, style = ?, personal_note = ?, wine_type = ?, vivino_id = ?, vivino_rating = ?, vivino_rating_count = ? WHERE id = ?"
      }
      let arguments = [
        sqlight.nullable(sqlight.text, after.region),
        sqlight.nullable(sqlight.text, after.style),
        sqlight.nullable(sqlight.text, after.personal_note),
        sqlight.text(after.wine_type),
        sqlight.nullable(sqlight.text, after.vivino_id),
        sqlight.nullable(sqlight.float, after.rating),
        sqlight.nullable(sqlight.int, after.count),
        sqlight.text(after.id),
      ]
      let arguments = case existing {
        None ->
          list.append(arguments, [
            sqlight.text(state.username),
            sqlight.text(after.winery_id),
            sqlight.text(after.name),
          ])
        Some(_) -> arguments
      }
      let vintage_statements =
        list.map(input.vintages, fn(v) {
          Statement(
            "INSERT INTO wines_vintages (wine_id, year, vivino_rating, vivino_rating_count) VALUES (?, ?, ?, ?) ON CONFLICT(wine_id, year) DO UPDATE SET vivino_rating = COALESCE(excluded.vivino_rating, wines_vintages.vivino_rating), vivino_rating_count = COALESCE(excluded.vivino_rating_count, wines_vintages.vivino_rating_count)",
            [
              sqlight.text(after.id),
              sqlight.text(v.year),
              sqlight.nullable(sqlight.float, v.rating),
              sqlight.nullable(sqlight.int, v.count),
            ],
          )
        })
      let outcome = case existing {
        None -> "created"
        Some(_) ->
          case changes {
            [] -> "unchanged"
            _ -> "updated"
          }
      }
      let statements =
        list.flatten([
          winery_statements,
          [Statement(sql, arguments)],
          vintage_statements,
        ])
      let plan =
        Plan(
          "wines",
          input.ref,
          hash,
          after.id,
          after.id,
          outcome,
          matched_by,
          changes,
          statements,
          0,
        )
      Ok(
        State(
          ..state,
          wines: [after, ..list.filter(state.wines, fn(w) { w.id != after.id })],
          wineries: [
            winery,
            ..list.filter(state.wineries, fn(w) { w.id != winery.id })
          ],
          plans: [plan, ..state.plans],
        ),
      )
    }
  }
}

fn referenced_wine(state: State, input: Child) -> Result(Wine, String) {
  use wine_id <- result.try(case input.wine_id, input.wine_ref {
    Some(id), _ -> Ok(id)
    _, Some(ref) ->
      case list.find(state.plans, fn(p) { p.kind == "wines" && p.ref == ref }) {
        Ok(plan) -> Ok(plan.wine_id)
        Error(_) ->
          case
            list.find(state.ledger, fn(l) { l.kind == "wines" && l.ref == ref })
          {
            Ok(ledger) -> Ok(ledger.wine_id)
            Error(_) -> Error("Unknown wine_ref in this source: " <> ref)
          }
      }
    _, _ -> Error("Missing wine reference")
  })
  list.find(state.wines, fn(w) { w.id == wine_id })
  |> result.map_error(fn(_) {
    "wine_id/wine_ref: Referenced wine does not exist or is not owned"
  })
}

fn plan_child(
  conn: Connection,
  state: State,
  input: Child,
) -> Result(State, String) {
  let hash = child_fingerprint(input)
  use replay <- result.try(replay(state, input.kind, input.ref, hash))
  case replay {
    Some(plan) -> {
      use _ <- result.try(child_exists(
        conn,
        state.username,
        plan,
        input.vintage,
      ))
      Ok(State(..state, plans: [plan, ..state.plans]))
    }
    None -> {
      use wine <- result.try(referenced_wine(state, input))
      use _ <- result.try(check(
        case input.vintage {
          None -> True
          Some(vintage) -> list.any(wine.vintages, fn(v) { v.year == vintage })
        },
        "Referenced vintage is absent; supply it in the wine vintages",
      ))
      use plan <- result.try(case input.kind {
        "wishlist" -> plan_wishlist(conn, state, input, wine, hash)
        _ -> {
          let id = ulid.generate()
          let #(sql, arguments) = case input.kind {
            "cellar" -> #(
              "INSERT INTO cellar (id, username, wine_id, vintage, quantity, notes, date, price_cents) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
              [
                sqlight.text(id),
                sqlight.text(state.username),
                sqlight.text(wine.id),
                sqlight.nullable(sqlight.text, input.vintage),
                sqlight.int(input.quantity),
                sqlight.nullable(sqlight.text, input.notes),
                sqlight.nullable(sqlight.text, input.date),
                sqlight.nullable(sqlight.int, input.price),
              ],
            )
            _ -> #(
              "INSERT INTO ratings (id, username, wine_id, vintage, rating, tasting_notes, rated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
              [
                sqlight.text(id),
                sqlight.text(state.username),
                sqlight.text(wine.id),
                sqlight.nullable(sqlight.text, input.vintage),
                sqlight.nullable(sqlight.float, input.rating),
                sqlight.nullable(sqlight.text, input.tasting_notes),
                sqlight.nullable(sqlight.text, input.rated_at),
              ],
            )
          }
          Ok(Plan(
            input.kind,
            input.ref,
            hash,
            id,
            wine.id,
            "created",
            "wine_reference",
            child_changes(input, wine.id),
            [Statement(sql, arguments)],
            input.quantity,
          ))
        }
      })
      Ok(State(..state, plans: [plan, ..state.plans]))
    }
  }
}

fn child_exists(
  conn: Connection,
  username: String,
  plan: Plan,
  vintage: Option(String),
) -> Result(Nil, String) {
  let #(sql, arguments) = case plan.kind {
    "cellar" -> #(
      "SELECT 1 FROM cellar WHERE id = ? AND username = ? AND wine_id = ?",
      [
        sqlight.text(plan.id),
        sqlight.text(username),
        sqlight.text(plan.wine_id),
      ],
    )
    "ratings" -> #(
      "SELECT 1 FROM ratings WHERE id = ? AND username = ? AND wine_id = ?",
      [
        sqlight.text(plan.id),
        sqlight.text(username),
        sqlight.text(plan.wine_id),
      ],
    )
    _ -> #(
      "SELECT 1 FROM lists_wines lw JOIN lists l ON l.id = lw.list_id WHERE l.username = ? AND l.list_type = 'wishlist' AND lw.wine_id = ? AND lw.vintage = ?",
      [
        sqlight.text(username),
        sqlight.text(plan.wine_id),
        sqlight.text(option.unwrap(vintage, "")),
      ],
    )
  }
  use rows <- result.try(query(conn, sql, arguments, decode.success(Nil)))
  check(
    !list.is_empty(rows),
    "Previously imported destination no longer exists",
  )
}

fn plan_wishlist(
  conn: Connection,
  state: State,
  input: Child,
  wine: Wine,
  hash: String,
) -> Result(Plan, String) {
  let vintage = option.unwrap(input.vintage, "")
  let id = wine.id <> "/" <> vintage
  use _ <- result.try(check(
    !list.any(state.plans, fn(p) { p.kind == "wishlist" && p.id == id }),
    "Duplicate wishlist destination in batch",
  ))
  let decoder = {
    use notes <- decode.field(0, decode.optional(decode.string))
    decode.success(notes)
  }
  use existing <- result.try(query(
    conn,
    "SELECT lw.notes FROM lists_wines lw JOIN lists l ON lw.list_id = l.id WHERE l.username = ? AND l.list_type = 'wishlist' AND lw.wine_id = ? AND lw.vintage = ?",
    [sqlight.text(state.username), sqlight.text(wine.id), sqlight.text(vintage)],
    decoder,
  ))
  let #(outcome, changes) = case existing {
    [] -> #("created", child_changes(input, wine.id))
    [notes] ->
      case input.notes {
        None -> #("unchanged", [])
        Some(new) ->
          case notes == Some(new) {
            True -> #("unchanged", [])
            False -> #("updated", [
              json.object([
                #("field", json.string("notes")),
                #("before", text_json(notes)),
                #("after", json.string(new)),
              ]),
            ])
          }
      }
    _ -> #("conflict", [])
  }
  use _ <- result.try(check(outcome != "conflict", "Ambiguous wishlist list"))
  Ok(Plan(
    "wishlist",
    input.ref,
    hash,
    id,
    wine.id,
    outcome,
    "wine_vintage",
    changes,
    [
      Statement(
        "INSERT INTO lists_wines (list_id, wine_id, vintage, notes) SELECT id, ?, ?, ? FROM lists WHERE username = ? AND list_type = 'wishlist' ON CONFLICT(list_id, wine_id, vintage) DO UPDATE SET notes = COALESCE(excluded.notes, lists_wines.notes)",
        [
          sqlight.text(wine.id),
          sqlight.text(vintage),
          sqlight.nullable(sqlight.text, input.notes),
          sqlight.text(state.username),
        ],
      ),
    ],
    0,
  ))
}

fn ensure_user_lists(
  conn: Connection,
  username: String,
) -> Result(Nil, String) {
  use _ <- result.try(execute(
    conn,
    Statement("INSERT OR IGNORE INTO users (username) VALUES (?)", [
      sqlight.text(username),
    ]),
  ))
  list.try_each(
    [
      #("Cellar", "cellar", True),
      #("Rated", "rated", False),
      #("Wishlist", "wishlist", False),
    ],
    fn(item) {
      let #(name, kind, bottles) = item
      execute(
        conn,
        Statement(
          "INSERT OR IGNORE INTO lists (id, username, name, slug, list_type, show_bottles) VALUES (?, ?, ?, ?, ?, ?)",
          [
            sqlight.text(ulid.generate()),
            sqlight.text(username),
            sqlight.text(name),
            sqlight.text(kind),
            sqlight.text(kind),
            sqlight.bool(bottles),
          ],
        ),
      )
    },
  )
}

fn apply_plans(
  conn: Connection,
  username: String,
  source: String,
  plans: List(Plan),
) -> Result(Nil, String) {
  use _ <- result.try(ensure_user_lists(conn, username))
  list.try_each(plans, fn(plan) {
    let applied = case plan.matched_by == "source_ref" {
      True -> Ok(Nil)
      False -> {
        use _ <- result.try(
          list.try_each(plan.statements, fn(statement) {
            execute(conn, statement)
          }),
        )
        execute(
          conn,
          Statement(
            "INSERT INTO mcp_import_records (username, source, kind, source_ref, fingerprint, destination_id, wine_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
            [
              sqlight.text(username),
              sqlight.text(source),
              sqlight.text(plan.kind),
              sqlight.text(plan.ref),
              sqlight.text(plan.fingerprint),
              sqlight.text(plan.id),
              sqlight.text(plan.wine_id),
            ],
          ),
        )
      }
    }
    applied |> in_record(plan.kind, plan.ref)
  })
}

fn output(batch: Batch, plans: List(Plan)) -> json.Json {
  let records =
    json.array(plans, fn(plan) {
      json.object([
        #("kind", json.string(plan.kind)),
        #("ref", json.string(plan.ref)),
        #("outcome", json.string(plan.outcome)),
        #("id", json.string(plan.id)),
        #("wine_id", json.string(plan.wine_id)),
        #("matched_by", json.string(plan.matched_by)),
        #("changes", json.array(plan.changes, fn(value) { value })),
      ])
    })
  let counts =
    list.map(["wines", "cellar", "ratings", "wishlist"], fn(kind) {
      #(kind, json.int(list.count(plans, fn(p) { p.kind == kind })))
    })
  let outcomes =
    list.map(["created", "updated", "unchanged"], fn(outcome) {
      #(outcome, json.int(list.count(plans, fn(p) { p.outcome == outcome })))
    })
  json.object([
    #("apply", json.bool(batch.apply)),
    #("source", json.string(batch.source)),
    #("records", records),
    #(
      "counts",
      json.object(
        list.flatten([
          counts,
          outcomes,
          [
            #(
              "bottles",
              json.int(
                list.fold(plans, 0, fn(acc, plan) { acc + plan.bottles }),
              ),
            ),
            #(
              "requested_bottles",
              json.int(
                list.fold(batch.children, 0, fn(acc, child) {
                  acc + child.quantity
                }),
              ),
            ),
          ],
        ]),
      ),
    ),
  ])
}

fn string_schema() -> json.Json {
  json.object([#("type", json.string("string"))])
}

fn nullable_schema(schema: json.Json) -> json.Json {
  json.object([
    #(
      "anyOf",
      json.array([schema, json.object([#("type", json.string("null"))])], fn(x) {
        x
      }),
    ),
  ])
}

fn object_schema(
  properties: List(#(String, json.Json)),
  required: List(String),
) -> json.Json {
  json.object([
    #("type", json.string("object")),
    #("additionalProperties", json.bool(False)),
    #("properties", json.object(properties)),
    #("required", json.array(required, json.string)),
  ])
}

fn wine_schema(properties: List(#(String, json.Json))) -> json.Json {
  json.object([
    #("type", json.string("object")),
    #("additionalProperties", json.bool(False)),
    #("properties", json.object(properties)),
    #("required", json.array(["ref"], json.string)),
    #(
      "anyOf",
      json.array(
        [
          json.object([
            #("required", json.array(["wine_id"], json.string)),
            #("properties", json.object([#("wine_id", string_schema())])),
          ]),
          json.object([
            #("required", json.array(["name", "winery"], json.string)),
            #(
              "properties",
              json.object([
                #("name", string_schema()),
                #("winery", string_schema()),
              ]),
            ),
          ]),
        ],
        fn(x) { x },
      ),
    ),
  ])
}

fn integer_schema() -> json.Json {
  json.object([#("type", json.string("integer")), #("minimum", json.int(0))])
}

fn rating_schema() -> json.Json {
  nullable_schema(
    json.object([
      #("type", json.string("number")),
      #("minimum", json.int(0)),
      #("maximum", json.int(5)),
    ]),
  )
}

fn vintage_schema() -> json.Json {
  json.object([
    #("type", json.string("string")),
    #("pattern", json.string("^([1-9][0-9]{3}|NV)$")),
  ])
}

fn array_schema(item: json.Json) -> json.Json {
  json.object([
    #("type", json.string("array")),
    #("maxItems", json.int(100)),
    #("items", item),
  ])
}

pub fn schema() -> json.Json {
  let nullable_text = nullable_schema(string_schema())
  let snapshot = [
    #("vivino_rating", rating_schema()),
    #("vivino_rating_count", nullable_schema(integer_schema())),
  ]
  let wine =
    wine_schema(list.append(
      [
        #("ref", string_schema()),
        #("name", nullable_text),
        #("winery", nullable_text),
        #("wine_id", nullable_text),
        #("vivino_id", nullable_text),
        #("region", nullable_text),
        #("country", nullable_text),
        #("style", nullable_text),
        #("personal_note", nullable_text),
        #(
          "wine_type",
          nullable_schema(
            json.object([
              #("type", json.string("string")),
              #(
                "enum",
                json.array(
                  [
                    "RED",
                    "WHITE",
                    "ROSE",
                    "ORANGE",
                    "SPARKLING",
                    "DESSERT",
                    "SAKE",
                    "OTHER",
                  ],
                  json.string,
                ),
              ),
            ]),
          ),
        ),
        #(
          "vintages",
          array_schema(
            object_schema(list.append([#("year", vintage_schema())], snapshot), [
              "year",
            ]),
          ),
        ),
      ],
      snapshot,
    ))
  let common = [
    #("ref", string_schema()),
    #("wine_ref", nullable_text),
    #("wine_id", nullable_text),
    #("vintage", nullable_schema(vintage_schema())),
  ]
  let date =
    nullable_schema(
      json.object([
        #("type", json.string("string")),
        #("pattern", json.string("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")),
      ]),
    )
  let cellar =
    object_schema(
      list.append(common, [
        #(
          "quantity",
          json.object([
            #("type", json.string("integer")),
            #("minimum", json.int(1)),
          ]),
        ),
        #("date", date),
        #("notes", nullable_text),
        #("price_cents", nullable_schema(integer_schema())),
      ]),
      ["ref", "quantity"],
    )
  let ratings =
    object_schema(
      list.append(common, [
        #("rating", rating_schema()),
        #("rated_at", date),
        #("tasting_notes", nullable_text),
      ]),
      ["ref"],
    )
  let wishlist =
    object_schema(list.append(common, [#("notes", nullable_text)]), ["ref"])
  object_schema(
    [
      #(
        "source",
        json.object([
          #("type", json.string("string")),
          #("minLength", json.int(1)),
          #(
            "description",
            json.string(
              "Stable namespace for source record references; changing content for an already imported reference conflicts.",
            ),
          ),
        ]),
      ),
      #(
        "apply",
        json.object([
          #("type", json.string("boolean")),
          #("default", json.bool(False)),
          #(
            "description",
            json.string(
              "False previews without writes; true revalidates and atomically applies at most 100 total records.",
            ),
          ),
        ]),
      ),
      #("wines", array_schema(wine)),
      #("cellar", array_schema(cellar)),
      #("ratings", array_schema(ratings)),
      #("wishlist", array_schema(wishlist)),
    ],
    ["source"],
  )
}
