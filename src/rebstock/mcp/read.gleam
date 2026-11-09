import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/result
import sqlight.{type Connection}

import rebstock/db
import rebstock/mcp/encode

pub fn search(
  conn: Connection,
  username: String,
  arguments: Dynamic,
) -> Result(Json, String) {
  use _ <- result.try(only(arguments, ["q", "limit", "offset"]))
  use page <- result.try(pagination(arguments))
  use query <- result.try(
    decode.run(
      arguments,
      decode.optional_field("q", "", decode.string, decode.success),
    )
    |> result.map_error(fn(_) { "q must be a string" }),
  )
  use ids <- result.try(
    sqlight.query(
      "SELECT w.id FROM wines w JOIN wineries wy ON wy.id=w.winery_id
     WHERE w.created_by=? AND (instr(lower(w.name),lower(?))>0 OR instr(lower(wy.name),lower(?))>0 OR w.vivino_id=?)
     ORDER BY wy.name,w.name,w.id LIMIT ? OFFSET ?",
      on: conn,
      with: [
        sqlight.text(username),
        sqlight.text(query),
        sqlight.text(query),
        sqlight.text(query),
        sqlight.int(page.limit + 1),
        sqlight.int(page.offset),
      ],
      expecting: decode.field(0, decode.string, decode.success),
    )
    |> result.map_error(fn(_) { "Database read failed" }),
  )
  use wines <- result.try(
    list.try_map(list.take(ids, page.limit), fn(id) {
      db.get_wine(conn, username, id)
      |> result.map_error(fn(_) { "Wine unavailable" })
    }),
  )
  Ok(page_json(
    "wines",
    list.map(wines, encode.wine),
    page,
    list.length(ids) > page.limit,
  ))
}

pub fn wine(
  conn: Connection,
  username: String,
  arguments: Dynamic,
) -> Result(Json, String) {
  use _ <- result.try(only(arguments, ["wine_id"]))
  use id <- result.try(
    decode.run(
      arguments,
      decode.field("wine_id", decode.string, decode.success),
    )
    |> result.map_error(fn(_) { "wine_id is required" }),
  )
  use wine <- result.try(
    db.get_wine(conn, username, id)
    |> result.map_error(fn(_) { "Wine not found" }),
  )
  Ok(
    json.object([
      #("wine", encode.wine(wine)),
      #(
        "vintages",
        json.array(db.vintage_ratings_for_wine(conn, id), encode.vintage),
      ),
    ]),
  )
}

pub fn cellar(
  conn: Connection,
  username: String,
  arguments: Dynamic,
) -> Result(Json, String) {
  use page <- result.try(event_page(arguments))
  use ids <- result.try(event_ids(conn, "cellar", username, page))
  use entries <- result.try(
    list.try_map(list.take(ids, page.limit), fn(id) {
      db.get_cellar_entry_by_id(conn, id)
      |> result.map_error(fn(_) { "Cellar entry unavailable" })
    }),
  )
  Ok(page_json(
    "entries",
    list.map(entries, encode.cellar),
    page,
    list.length(ids) > page.limit,
  ))
}

pub fn ratings(
  conn: Connection,
  username: String,
  arguments: Dynamic,
) -> Result(Json, String) {
  use page <- result.try(event_page(arguments))
  use ids <- result.try(event_ids(conn, "ratings", username, page))
  use entries <- result.try(
    list.try_map(list.take(ids, page.limit), fn(id) {
      db.get_rating_by_id(conn, id)
      |> result.map_error(fn(_) { "Rating unavailable" })
    }),
  )
  Ok(page_json(
    "ratings",
    list.map(entries, encode.rating),
    page,
    list.length(ids) > page.limit,
  ))
}

pub fn wishlist(
  conn: Connection,
  username: String,
  arguments: Dynamic,
) -> Result(Json, String) {
  use _ <- result.try(only(arguments, ["limit", "offset"]))
  use page <- result.try(pagination(arguments))
  use rows <- result.try(
    sqlight.query(
      "SELECT w.id,wy.name,w.name,NULLIF(lw.vintage,''),lw.notes
     FROM lists l JOIN lists_wines lw ON lw.list_id=l.id JOIN wines w ON w.id=lw.wine_id JOIN wineries wy ON wy.id=w.winery_id
     WHERE l.username=? AND l.list_type='wishlist' ORDER BY lw.added_at,w.id,lw.vintage LIMIT ? OFFSET ?",
      on: conn,
      with: [
        sqlight.text(username),
        sqlight.int(page.limit + 1),
        sqlight.int(page.offset),
      ],
      expecting: {
        use id <- decode.field(0, decode.string)
        use winery <- decode.field(1, decode.string)
        use name <- decode.field(2, decode.string)
        use vintage <- decode.field(3, decode.optional(decode.string))
        use notes <- decode.field(4, decode.optional(decode.string))
        decode.success(
          json.object([
            #("wine_id", json.string(id)),
            #("winery", json.string(winery)),
            #("name", json.string(name)),
            #("vintage", json.nullable(vintage, json.string)),
            #("notes", json.nullable(notes, json.string)),
          ]),
        )
      },
    )
    |> result.map_error(fn(_) { "Database read failed" }),
  )
  Ok(page_json(
    "wishlist",
    list.take(rows, page.limit),
    page,
    list.length(rows) > page.limit,
  ))
}

type Page {
  Page(limit: Int, offset: Int, wine_id: String)
}

fn pagination(arguments: Dynamic) -> Result(Page, String) {
  let decoder = {
    use limit <- decode.optional_field("limit", 50, decode.int)
    use offset <- decode.optional_field("offset", 0, decode.int)
    use wine_id <- decode.optional_field("wine_id", "", decode.string)
    decode.success(Page(limit:, offset:, wine_id:))
  }
  use page <- result.try(
    decode.run(arguments, decoder)
    |> result.map_error(fn(_) { "Invalid pagination" }),
  )
  case
    page.limit >= 1
    && page.limit <= 100
    && page.offset >= 0
    && page.offset <= 1_000_000
  {
    True -> Ok(page)
    False -> Error("limit must be 1..100 and offset 0..1000000")
  }
}

fn event_page(arguments: Dynamic) -> Result(Page, String) {
  use _ <- result.try(only(arguments, ["wine_id", "limit", "offset"]))
  pagination(arguments)
}

fn event_ids(
  conn: Connection,
  table: String,
  username: String,
  page: Page,
) -> Result(List(String), String) {
  sqlight.query(
    "SELECT id FROM "
      <> table
      <> " WHERE username=? AND (?='' OR wine_id=?) ORDER BY created_at,id LIMIT ? OFFSET ?",
    on: conn,
    with: [
      sqlight.text(username),
      sqlight.text(page.wine_id),
      sqlight.text(page.wine_id),
      sqlight.int(page.limit + 1),
      sqlight.int(page.offset),
    ],
    expecting: decode.field(0, decode.string, decode.success),
  )
  |> result.map_error(fn(_) { "Database read failed" })
}

fn page_json(key: String, rows: List(Json), page: Page, more: Bool) -> Json {
  json.object([
    #(key, json.preprocessed_array(rows)),
    #("next_offset", case more {
      True -> json.int(page.offset + page.limit)
      False -> json.null()
    }),
  ])
}

pub fn only(arguments: Dynamic, keys: List(String)) -> Result(Nil, String) {
  use fields <- result.try(
    decode.run(arguments, decode.dict(decode.string, decode.dynamic))
    |> result.map_error(fn(_) { "Expected object arguments" }),
  )
  case list.all(dict.keys(fields), fn(key) { list.contains(keys, key) }) {
    True -> Ok(Nil)
    False -> Error("Unknown argument")
  }
}
