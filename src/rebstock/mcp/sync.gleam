import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import sqlight.{type Connection}

import rebstock/db
import rebstock/mcp/database
import rebstock/mcp/read
import rebstock/vivino

pub type Outcome {
  Outcome(data: Json, failed: Bool)
}

type Item {
  Item(wine: db.Wine, link: String)
}

pub fn run(
  database_uri: String,
  username: String,
  arguments: Dynamic,
  fetch: fn(String) -> Result(vivino.VivinoWineDetail, String),
) -> Result(Outcome, String) {
  use _ <- result.try(read.only(arguments, ["wine_ids"]))
  let decoder = {
    use ids <- decode.field("wine_ids", decode.list(decode.string))
    decode.success(ids)
  }
  use ids <- result.try(
    decode.run(arguments, decoder)
    |> result.map_error(fn(_) { "wine_ids must be an array of owned wine IDs" }),
  )
  use _ <- result.try(
    case
      list.length(ids) >= 1
      && list.length(ids) <= 20
      && list.length(ids) == list.length(list.unique(ids))
    {
      True -> Ok(Nil)
      False -> Error("Select 1..20 distinct owned wine IDs")
    },
  )
  database.with_connection(database_uri, fn(conn) {
    use wines <- result.try(
      list.try_map(ids, fn(id) {
        db.get_wine(conn, username, id)
        |> result.map_error(fn(_) { "Wine not found" })
      }),
    )
    let items =
      list.map(wines, fn(wine) { Item(wine, option_link(wine.vivino_id)) })
    let outcomes = refresh(conn, username, items, fetch, False)
    let failed = list.any(outcomes, fn(outcome) { outcome.1 == "failed" })
    Ok(Outcome(
      json.object([
        #("results", json.array(outcomes, fn(outcome) { outcome.0 })),
        #(
          "refreshed",
          json.int(
            list.count(outcomes, fn(outcome) { outcome.1 == "refreshed" }),
          ),
        ),
        #(
          "failed",
          json.int(list.count(outcomes, fn(outcome) { outcome.1 == "failed" })),
        ),
        #(
          "skipped",
          json.int(list.count(outcomes, fn(outcome) { outcome.1 == "skipped" })),
        ),
      ]),
      failed,
    ))
  })
}

fn option_link(link: option.Option(String)) -> String {
  case link {
    Some(value) -> value
    None -> ""
  }
}

fn refresh(
  conn: Connection,
  username: String,
  items: List(Item),
  fetch: fn(String) -> Result(vivino.VivinoWineDetail, String),
  rate_limited: Bool,
) -> List(#(Json, String)) {
  case items {
    [] -> []
    [item, ..rest] -> {
      let #(outcome, limited) = case rate_limited, item.link {
        True, _ -> #(
          item_result(item, "skipped", "Earlier request was rate limited"),
          True,
        )
        _, "" -> #(
          item_result(item, "skipped", "Wine has no Vivino link"),
          False,
        )
        False, _ ->
          case fetch(item.link) {
            Error(message) -> #(
              item_result(item, "failed", message),
              string.contains(message, "429"),
            )
            Ok(detail) ->
              case persist(conn, username, item, detail) {
                Error(message) -> #(item_result(item, "failed", message), False)
                Ok(count) -> #(
                  #(
                    json.object([
                      #("wine_id", json.string(item.wine.id)),
                      #("status", json.string("refreshed")),
                      #("vivino_id", json.string(int.to_string(detail.wine_id))),
                      #("vintages_updated", json.int(count)),
                    ]),
                    "refreshed",
                  ),
                  False,
                )
              }
          }
      }
      [outcome, ..refresh(conn, username, rest, fetch, limited)]
    }
  }
}

fn item_result(item: Item, status: String, message: String) -> #(Json, String) {
  #(
    json.object([
      #("wine_id", json.string(item.wine.id)),
      #("status", json.string(status)),
      #("message", json.string(message)),
    ]),
    status,
  )
}

fn persist(
  conn: Connection,
  username: String,
  item: Item,
  detail: vivino.VivinoWineDetail,
) -> Result(Int, String) {
  use _ <- result.try(validate(item.link, detail))
  database.transaction(conn, fn() {
    use current <- result.try(
      db.get_wine(conn, username, item.wine.id)
      |> result.map_error(fn(_) { "Wine no longer available" }),
    )
    use _ <- result.try(case current.vivino_id == item.wine.vivino_id {
      True -> Ok(Nil)
      False ->
        Error("Vivino link changed while fetching ratings; retry the refresh")
    })
    let known = db.vintages_for_wine(conn, current.id)
    let vintages =
      list.filter(detail.vintages, fn(vintage) {
        list.contains(known, vintage.year) && vintage.rating >. 0.0
      })
    case detail.rating >. 0.0 {
      True ->
        db.set_wine_vivino_rating(
          conn,
          current.id,
          detail.rating,
          known_count(detail.rating_count),
        )
      False -> Nil
    }
    list.each(vintages, fn(vintage) {
      db.set_vintage_vivino_rating(
        conn,
        current.id,
        vintage.year,
        vintage.rating,
        known_count(vintage.rating_count),
      )
    })
    use _ <- result.try(
      sqlight.query(
        "UPDATE wines SET vivino_id=? WHERE id=? AND created_by=?",
        on: conn,
        with: [
          sqlight.text(int.to_string(detail.wine_id)),
          sqlight.text(current.id),
          sqlight.text(username),
        ],
        expecting: decode.success(Nil),
      )
      |> result.map_error(fn(_) { "Failed to update resolved Vivino link" }),
    )
    Ok(list.length(vintages))
  })
}

fn known_count(count: Int) -> option.Option(Int) {
  case count > 0 {
    True -> Some(count)
    False -> None
  }
}

fn validate(
  link: String,
  detail: vivino.VivinoWineDetail,
) -> Result(Nil, String) {
  let identity_matches = case int.parse(link) {
    Ok(expected) -> expected == detail.wine_id
    Error(_) -> string.starts_with(link, "v") && detail.wine_id > 0
  }
  let valid_rating = fn(rating: Float, count: Int) {
    rating >=. 0.0 && rating <=. 5.0 && count >= 0
  }
  case
    identity_matches,
    valid_rating(detail.rating, detail.rating_count)
    && list.all(detail.vintages, fn(vintage) {
      valid_rating(vintage.rating, vintage.rating_count)
    })
  {
    False, _ ->
      Error("Fetched Vivino wine identity does not match the stored link")
    _, False -> Error("Vivino returned invalid ratings or counts")
    True, True -> Ok(Nil)
  }
}
