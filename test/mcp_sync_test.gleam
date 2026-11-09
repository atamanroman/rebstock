import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import simplifile
import sqlight

import rebstock/db
import rebstock/mcp/database
import rebstock/mcp/sync
import rebstock/ulid
import rebstock/vivino

fn with_database(run: fn(String, sqlight.Connection) -> Nil) {
  let path = "/tmp/rebstock-mcp-sync-" <> ulid.generate() <> ".db"
  sqlight.with_connection(path, fn(conn) {
    db.migrate(conn)
    run(path, conn)
  })
  let _ = simplifile.delete(path)
  Nil
}

fn wine(conn: sqlight.Connection, user: String, vivino_id: String) {
  db.ensure_user(conn, user)
  db.upsert_wine(
    conn,
    user,
    "Winery",
    "Wine",
    Some("2020"),
    None,
    None,
    None,
    Some("Keep this note"),
    db.Red,
    Some(vivino_id),
  )
}

fn detail() {
  vivino.VivinoWineDetail(
    123,
    "Upstream name",
    "Upstream winery",
    7,
    "Changed region",
    "FR",
    "White",
    4.2,
    150,
    "",
    [
      vivino.VivinoVintage("2020", 4.4, 60),
      vivino.VivinoVintage("2021", 4.5, 80),
    ],
  )
}

fn arguments(ids: List(String)) {
  let assert Ok(data) =
    json.object([#("wine_ids", json.array(ids, json.string))])
    |> json.to_string
    |> json.parse(decode.dynamic)
  data
}

pub fn mcp_ratings_sync_preserves_metadata_and_only_updates_known_vintages_test() {
  use path, conn <- with_database
  let id = wine(conn, "alice", "123")
  let assert Ok(outcome) =
    sync.run(path, "alice", arguments([id]), fn(_) { Ok(detail()) })
  let assert False = outcome.failed
  let assert Ok(after) = db.get_wine(conn, "alice", id)
  let assert "Wine" = after.name
  let assert "Winery" = after.winery_name
  let assert db.Red = after.wine_type
  let assert Some("Keep this note") = after.personal_note
  let assert Some(4.2) = after.vivino_rating
  let assert ["2020"] = db.vintages_for_wine(conn, id)
  let assert [rating] = db.vintage_ratings_for_wine(conn, id)
  let assert Some(4.4) = rating.rating
  Nil
}

pub fn mcp_sync_rejects_foreign_wines_before_any_upstream_request_test() {
  use path, conn <- with_database
  let id = wine(conn, "bob", "123")
  let assert Error(_) =
    sync.run(path, "alice", arguments([id]), fn(_) {
      panic as "Must validate ownership before network requests"
    })
  Nil
}

pub fn mcp_sync_keeps_cached_values_on_unrated_and_failed_upstream_test() {
  use path, conn <- with_database
  let id = wine(conn, "alice", "123")
  db.set_wine_vivino_rating(conn, id, 4.7, Some(9))
  let mock =
    vivino.VivinoWineDetail(
      ..detail(),
      rating: 0.0,
      rating_count: 0,
      vintages: [],
    )
  let assert Ok(_) =
    sync.run(path, "alice", arguments([id]), fn(_) { Ok(mock) })
  let assert Ok(failed) =
    sync.run(path, "alice", arguments([id]), fn(_) {
      Error("Upstream unavailable")
    })
  let assert True = failed.failed
  let assert Ok(after) = db.get_wine(conn, "alice", id)
  let assert Some(4.7) = after.vivino_rating
  let assert Some(9) = after.vivino_rating_count
  Nil
}

pub fn mcp_sync_rejects_mismatched_identity_and_invalid_ratings_test() {
  use path, conn <- with_database
  let id = wine(conn, "alice", "123")
  let other = vivino.VivinoWineDetail(..detail(), wine_id: 456)
  let invalid = vivino.VivinoWineDetail(..detail(), rating: 8.0)
  let assert Ok(mismatch) =
    sync.run(path, "alice", arguments([id]), fn(_) { Ok(other) })
  let assert True = mismatch.failed
  let assert Ok(bad) =
    sync.run(path, "alice", arguments([id]), fn(_) { Ok(invalid) })
  let assert True = bad.failed
  let assert Ok(after) = db.get_wine(conn, "alice", id)
  let assert None = after.vivino_rating
  Nil
}

pub fn mcp_sync_stops_fetching_after_rate_limiting_test() {
  use path, conn <- with_database
  let first = wine(conn, "alice", "123")
  let second =
    db.upsert_wine(
      conn,
      "alice",
      "Winery",
      "Second",
      None,
      None,
      None,
      None,
      None,
      db.Red,
      Some("456"),
    )
  let assert Ok(outcome) =
    sync.run(path, "alice", arguments([first, second]), fn(id) {
      case id {
        "123" -> Error("Vivino API returned status 429")
        _ -> panic as "A rate-limited batch must stop fetching"
      }
    })
  let assert True = outcome.failed
  let assert True = string.contains(json.to_string(outcome.data), "skipped")
  Nil
}

pub fn mcp_sync_resolves_legacy_ids_and_retains_unreported_counts_test() {
  use path, conn <- with_database
  let id = wine(conn, "alice", "v999")
  db.set_wine_vivino_rating(conn, id, 4.0, Some(200))
  let mock = vivino.VivinoWineDetail(..detail(), rating_count: 0)
  let assert Ok(_) =
    sync.run(path, "alice", arguments([id]), fn(_) { Ok(mock) })
  let assert Ok(after) = db.get_wine(conn, "alice", id)
  let assert Some("123") = after.vivino_id
  let assert Some(200) = after.vivino_rating_count
  Nil
}

pub fn mcp_mutation_transaction_rolls_back_failures_test() {
  use path, conn <- with_database
  let assert Error(_) =
    database.with_connection(path, fn(other) {
      database.transaction(other, fn() {
        db.ensure_user(other, "rolled-back")
        Error("Reject complete mutation")
      })
    })
  let assert Ok(rows) =
    sqlight.query(
      "SELECT username FROM users WHERE username='rolled-back'",
      conn,
      [],
      {
        use user <- decode.field(0, decode.string)
        decode.success(user)
      },
    )
  let assert [] = rows
  let assert Ok(_) =
    database.with_connection(path, fn(other) {
      database.transaction(other, fn() {
        db.ensure_user(other, "committed")
        Ok(Nil)
      })
    })
  let assert Ok(committed) =
    sqlight.query(
      "SELECT username FROM users WHERE username='committed'",
      conn,
      [],
      {
        use user <- decode.field(0, decode.string)
        decode.success(user)
      },
    )
  let assert ["committed"] = committed
  Nil
}
