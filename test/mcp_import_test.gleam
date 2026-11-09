import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import simplifile
import sqlight

import rebstock/db
import rebstock/mcp/imports
import rebstock/ulid

fn with_import_db(f: fn(String, sqlight.Connection) -> Nil) -> Nil {
  let path = "/tmp/rebstock-import-" <> ulid.generate() <> ".sqlite3"
  let uri = "file:" <> path
  let assert Ok(conn) = sqlight.open(uri)
  db.migrate(conn)
  f(uri, conn)
  let assert Ok(_) = sqlight.close(conn)
  let _ = simplifile.delete(path)
  let _ = simplifile.delete(path <> "-wal")
  let _ = simplifile.delete(path <> "-shm")
  Nil
}

fn run(uri: String, input: String) -> Result(json.Json, String) {
  let assert Ok(arguments) = json.parse(input, decode.dynamic)
  imports.run(uri, "alice", arguments)
}

fn count(conn: sqlight.Connection, table: String) -> Int {
  let decoder = {
    use n <- decode.field(0, decode.int)
    decode.success(n)
  }
  let assert Ok([n]) =
    sqlight.query("SELECT COUNT(*) FROM " <> table, conn, [], decoder)
  n
}

fn first_id(output: json.Json) -> String {
  let assert Ok(id) =
    json.parse(
      json.to_string(output),
      decode.at(["records"], {
        use records <- decode.then(
          decode.list({
            use id <- decode.field("id", decode.string)
            decode.success(id)
          }),
        )
        case records {
          [id, ..] -> decode.success(id)
          [] -> decode.failure("id", "empty records")
        }
      }),
    )
  id
}

pub fn preview_plans_without_creating_user_test() {
  use uri, conn <- with_import_db
  let assert Ok(output) =
    run(
      uri,
      "{\"source\":\"invoice\",\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\",\"vintages\":[{\"year\":\"2020\"}]}],\"cellar\":[{\"ref\":\"p1\",\"wine_ref\":\"w1\",\"vintage\":\"2020\",\"quantity\":3,\"date\":\"2024-02-29\",\"price_cents\":1250}]}",
    )
  let body = json.to_string(output)
  let assert True = string.contains(body, "\"bottles\":3")
  let assert True = string.contains(body, "\"outcome\":\"created\"")
  let assert 0 = count(conn, "users")
  let assert 0 = count(conn, "wines")
  let assert 0 = count(conn, "mcp_import_records")
  Nil
}

pub fn apply_preserves_purchase_rating_wishlist_and_snapshots_test() {
  use uri, conn <- with_import_db
  let assert Ok(_) =
    run(
      uri,
      "{\"source\":\"invoice\",\"apply\":true,\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\",\"country\":\"DE\",\"wine_type\":\"WHITE\",\"vivino_id\":\"123\",\"vivino_rating\":4.1,\"vivino_rating_count\":200,\"vintages\":[{\"year\":\"2020\",\"vivino_rating\":4.2,\"vivino_rating_count\":20}]}],\"cellar\":[{\"ref\":\"p1\",\"wine_ref\":\"w1\",\"vintage\":\"2020\",\"quantity\":3,\"date\":\"2024-02-29\",\"price_cents\":1250,\"notes\":\"Invoice notes\"}],\"ratings\":[{\"ref\":\"r1\",\"wine_ref\":\"w1\",\"vintage\":\"2020\",\"rating\":4.5,\"rated_at\":\"2025-01-01\",\"tasting_notes\":\"Citrus\"}],\"wishlist\":[{\"ref\":\"l1\",\"wine_ref\":\"w1\",\"vintage\":\"2020\",\"notes\":\"More please\"}]}",
    )
  let assert [wine] = db.list_wines(conn, "alice")
  let assert Some(4.1) = wine.vivino_rating
  let assert Some(200) = wine.vivino_rating_count
  let assert [entry] = db.cellar_entries_for_wine(conn, wine.id)
  let assert 3 = entry.quantity
  let assert Some("2024-02-29") = entry.date
  let assert Some(1250) = entry.price_cents
  let assert Some("Invoice notes") = entry.notes
  let assert [rating] = db.ratings_for_wine(conn, wine.id)
  let assert Some(4.5) = rating.rating
  let assert Some("Citrus") = rating.tasting_notes
  let wishlist = db.get_user_wishlist(conn, "alice")
  let assert [item] = db.list_wines_for_list(conn, wishlist.id)
  let assert Some("2020") = item.vintage
  let assert 4 = count(conn, "mcp_import_records")
  Nil
}

pub fn replay_after_reopen_is_unchanged_test() {
  use uri, conn <- with_import_db
  let input =
    "{\"source\":\"invoice\",\"apply\":true,\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\",\"vintages\":[{\"year\":\"NV\"}]}],\"cellar\":[{\"ref\":\"p1\",\"wine_ref\":\"w1\",\"vintage\":\"NV\",\"quantity\":2}]}"
  let assert Ok(first) = run(uri, input)
  let assert Ok(second) = run(uri, input)
  let assert True = first_id(first) == first_id(second)
  let assert True =
    string.contains(json.to_string(second), "\"outcome\":\"unchanged\"")
  let assert 1 = count(conn, "wines")
  let assert 1 = count(conn, "cellar")
  Nil
}

pub fn changed_reference_content_conflicts_test() {
  use uri, conn <- with_import_db
  let assert Ok(_) =
    run(
      uri,
      "{\"source\":\"invoice\",\"apply\":true,\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\"}]}",
    )
  let assert Error(error) =
    run(
      uri,
      "{\"source\":\"invoice\",\"apply\":true,\"wines\":[{\"ref\":\"w1\",\"name\":\"Changed\",\"winery\":\"Winery\"}]}",
    )
  let assert True = string.contains(error, "changed content")
  let assert 1 = count(conn, "wines")
  Nil
}

pub fn child_reference_can_use_prior_batch_wine_test() {
  use uri, conn <- with_import_db
  let assert Ok(_) =
    run(
      uri,
      "{\"source\":\"invoice\",\"apply\":true,\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\",\"vintages\":[{\"year\":\"2020\"}]}]}",
    )
  let assert Ok(_) =
    run(
      uri,
      "{\"source\":\"invoice\",\"apply\":true,\"cellar\":[{\"ref\":\"p1\",\"wine_ref\":\"w1\",\"vintage\":\"2020\",\"quantity\":2}]}",
    )
  let assert 1 = count(conn, "cellar")
  Nil
}

pub fn invalid_rows_leave_entire_batch_unwritten_test() {
  use uri, conn <- with_import_db
  let assert Error(_) =
    run(
      uri,
      "{\"source\":\"invoice\",\"apply\":true,\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\"}],\"cellar\":[{\"ref\":\"p1\",\"wine_ref\":\"w1\",\"quantity\":2},{\"ref\":\"p2\",\"wine_ref\":\"w1\",\"quantity\":-1}]}",
    )
  let assert 0 = count(conn, "users")
  let assert 0 = count(conn, "wines")
  let assert 0 = count(conn, "mcp_import_records")
  Nil
}

pub fn rejects_calendar_vintage_price_rating_and_duplicates_test() {
  use uri, conn <- with_import_db
  let wine =
    "\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\"}]"
  let invalid = [
    "\"cellar\":[{\"ref\":\"p1\",\"wine_ref\":\"w1\",\"quantity\":1,\"date\":\"2023-02-29\"}]",
    "\"cellar\":[{\"ref\":\"p1\",\"wine_ref\":\"w1\",\"quantity\":1,\"price_cents\":1.5}]",
    "\"cellar\":[{\"ref\":\"p1\",\"wine_ref\":\"w1\",\"quantity\":1,\"vintage\":\"2020-ish\"}]",
    "\"ratings\":[{\"ref\":\"r1\",\"wine_ref\":\"w1\",\"rating\":5.1}]",
    "\"wishlist\":[{\"ref\":\"l1\",\"wine_ref\":\"missing\"}]",
    "\"wishlist\":[{\"ref\":\"l1\",\"wine_ref\":\"w1\"},{\"ref\":\"l1\",\"wine_ref\":\"w1\"}]",
  ]
  list.each(invalid, fn(fields) {
    let assert Error(_) =
      run(
        uri,
        "{\"source\":\"invoice\",\"apply\":true,"
          <> wine
          <> ","
          <> fields
          <> "}",
      )
  })
  let assert 0 = count(conn, "wines")
  Nil
}

pub fn unexpected_sql_failure_rolls_back_entities_and_ledger_test() {
  use uri, conn <- with_import_db
  let assert Ok(_) =
    sqlight.exec(
      "CREATE TRIGGER import_test_failure BEFORE INSERT ON cellar BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      conn,
    )
  let assert Error(_) =
    run(
      uri,
      "{\"source\":\"invoice\",\"apply\":true,\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\"}],\"cellar\":[{\"ref\":\"p1\",\"wine_ref\":\"w1\",\"quantity\":2}]}",
    )
  let assert 0 = count(conn, "users")
  let assert 0 = count(conn, "wineries")
  let assert 0 = count(conn, "wines")
  let assert 0 = count(conn, "mcp_import_records")
  let assert Ok(_) = sqlight.exec("DROP TRIGGER import_test_failure", conn)
  let assert Ok(_) =
    run(
      uri,
      "{\"source\":\"invoice\",\"apply\":true,\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\"}]}",
    )
  Nil
}

pub fn owned_match_preserves_omitted_fields_and_shared_winery_test() {
  use uri, conn <- with_import_db
  db.ensure_user(conn, "alice")
  let id =
    db.upsert_wine(
      conn,
      "alice",
      "Winery",
      "Riesling",
      Some("2020"),
      Some("Mosel"),
      Some("DE"),
      Some("Dry"),
      Some("Mine"),
      db.White,
      Some("123"),
    )
  let assert Ok(output) =
    run(
      uri,
      "{\"source\":\"invoice\",\"apply\":true,\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\",\"region\":null}]}",
    )
  let assert True = first_id(output) == id
  let assert Ok(wine) = db.get_wine(conn, "alice", id)
  let assert Some("Mosel") = wine.region
  let assert Some("Mine") = wine.personal_note
  let assert db.White = wine.wine_type
  let assert Error(error) =
    run(
      uri,
      "{\"source\":\"other\",\"apply\":true,\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\",\"country\":\"FR\"}]}",
    )
  let assert True = string.contains(error, "winery")
  let assert Ok(unchanged) = db.get_wine(conn, "alice", id)
  let assert Some("DE") = unchanged.country
  Nil
}

pub fn foreign_owned_explicit_ids_and_conflicting_links_are_rejected_test() {
  use uri, conn <- with_import_db
  db.ensure_user(conn, "bob")
  let id =
    db.upsert_wine(
      conn,
      "bob",
      "Winery",
      "Riesling",
      None,
      None,
      None,
      None,
      None,
      db.White,
      Some("123"),
    )
  let assert Error(_) =
    run(
      uri,
      "{\"source\":\"invoice\",\"wines\":[{\"ref\":\"w1\",\"wine_id\":\""
        <> id
        <> "\",\"name\":\"Riesling\",\"winery\":\"Winery\"}]}",
    )
  db.ensure_user(conn, "alice")
  let _ =
    db.upsert_wine(
      conn,
      "alice",
      "Winery",
      "Riesling",
      None,
      None,
      None,
      None,
      None,
      db.White,
      Some("123"),
    )
  let assert Error(error) =
    run(
      uri,
      "{\"source\":\"invoice\",\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\",\"vivino_id\":\"456\"}]}",
    )
  let assert True = string.contains(error, "identity")
  Nil
}

pub fn batch_record_limit_is_combined_across_collections_test() {
  use uri, conn <- with_import_db
  let records =
    int.range(1, 102, [], fn(acc, n) {
      [
        json.object([
          #("ref", json.string(int.to_string(n))),
          #("wine_id", json.string("missing")),
        ]),
        ..acc
      ]
    })
  let input =
    json.object([
      #("source", json.string("large")),
      #("wishlist", json.array(list.take(records, 51), fn(x) { x })),
      #("ratings", json.array(list.drop(records, 51), fn(x) { x })),
    ])
  let assert Error(error) = run(uri, json.to_string(input))
  let assert True = string.contains(error, "100")
  let assert 0 = count(conn, "users")
  Nil
}

pub fn import_schema_has_explicit_closed_record_shapes_test() {
  let body = json.to_string(imports.schema())
  let assert True = string.contains(body, "\"source\"")
  let assert True = string.contains(body, "\"price_cents\"")
  let assert True = string.contains(body, "\"additionalProperties\":false")
  Nil
}

pub fn preview_reports_new_identity_and_purchase_field_changes_test() {
  use uri, conn <- with_import_db
  let assert Ok(output) =
    run(
      uri,
      "{\"source\":\"details\",\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\"}],\"cellar\":[{\"ref\":\"p1\",\"wine_ref\":\"w1\",\"quantity\":3,\"date\":\"2024-02-29\",\"price_cents\":1250,\"notes\":\"Receipt\"}]}",
    )
  let body = json.to_string(output)
  list.each(
    ["name", "winery", "quantity", "date", "notes", "price_cents"],
    fn(field) {
      let assert True = string.contains(body, "\"field\":\"" <> field <> "\"")
    },
  )
  let assert 0 = count(conn, "users")
  Nil
}

pub fn normalized_null_metadata_and_vintage_order_replay_test() {
  use uri, conn <- with_import_db
  let assert Ok(first) =
    run(
      uri,
      "{\"source\":\"normalized\",\"apply\":true,\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\",\"vintages\":[{\"year\":\"2020\"},{\"year\":\"2021\",\"vivino_rating\":4}]}]}",
    )
  let assert Ok(second) =
    run(
      uri,
      "{\"source\":\"normalized\",\"apply\":true,\"wines\":[{\"ref\":\"w1\",\"name\":\"Riesling\",\"winery\":\"Winery\",\"region\":null,\"vintages\":[{\"year\":\"2021\",\"vivino_rating\":4.0},{\"year\":\"2020\"}]}]}",
    )
  let assert True = first_id(first) == first_id(second)
  let assert True =
    string.contains(json.to_string(second), "\"outcome\":\"unchanged\"")
  let assert 1 = count(conn, "mcp_import_records")
  Nil
}

pub fn ambiguous_owned_vivino_identity_is_rejected_test() {
  use uri, conn <- with_import_db
  db.ensure_user(conn, "alice")
  let _ =
    db.upsert_wine(
      conn,
      "alice",
      "Winery",
      "One",
      None,
      None,
      None,
      None,
      None,
      db.Red,
      Some("123"),
    )
  let _ =
    db.upsert_wine(
      conn,
      "alice",
      "Winery",
      "Two",
      None,
      None,
      None,
      None,
      None,
      db.Red,
      Some("123"),
    )
  let assert Error(error) =
    run(
      uri,
      "{\"source\":\"ambiguous\",\"wines\":[{\"ref\":\"w1\",\"name\":\"One\",\"winery\":\"Winery\",\"vivino_id\":\"123\"}]}",
    )
  let assert True = string.contains(error, "Ambiguous")
  let assert 0 = count(conn, "mcp_import_records")
  Nil
}

pub fn preview_uses_its_own_connection_snapshot_test() {
  use uri, conn <- with_import_db
  let assert Ok(_) = sqlight.exec("BEGIN", conn)
  db.ensure_user(conn, "alice")
  let _ =
    db.upsert_wine(
      conn,
      "alice",
      "Uncommitted",
      "Private",
      None,
      None,
      None,
      None,
      None,
      db.Red,
      None,
    )
  let assert Ok(output) =
    run(
      uri,
      "{\"source\":\"snapshot\",\"wines\":[{\"ref\":\"w1\",\"name\":\"Private\",\"winery\":\"Uncommitted\"}]}",
    )
  let assert True =
    string.contains(json.to_string(output), "\"matched_by\":\"new\"")
  let assert 1 = count(conn, "users")
  let assert Ok(_) = sqlight.exec("ROLLBACK", conn)
  let assert 0 = count(conn, "users")
  Nil
}

pub fn owned_id_without_name_or_winery_previews_applies_and_replays_test() {
  use uri, conn <- with_import_db
  db.ensure_user(conn, "alice")
  let id =
    db.upsert_wine(
      conn,
      "alice",
      "Owned Winery",
      "Owned Wine",
      Some("2020"),
      Some("Mosel"),
      Some("DE"),
      Some("Dry"),
      Some("Previous note"),
      db.White,
      Some("123"),
    )
  let wine =
    json.object([
      #("ref", json.string("wine1")),
      #("wine_id", json.string(id)),
      #("personal_note", json.string("Imported note")),
    ])
  let preview_input =
    json.object([
      #("source", json.string("invoice-id")),
      #("wines", json.array([wine], fn(x) { x })),
    ])
  let assert Ok(preview) = run(uri, json.to_string(preview_input))
  let assert True = first_id(preview) == id
  let assert True =
    string.contains(json.to_string(preview), "\"matched_by\":\"wine_id\"")
  let assert Ok(before) = db.get_wine(conn, "alice", id)
  let assert Some("Previous note") = before.personal_note
  let assert 0 = count(conn, "mcp_import_records")
  let apply_input =
    json.object([
      #("source", json.string("invoice-id")),
      #("apply", json.bool(True)),
      #("wines", json.array([wine], fn(x) { x })),
    ])
  let assert Ok(applied) = run(uri, json.to_string(apply_input))
  let assert True = first_id(applied) == id
  let assert Ok(after) = db.get_wine(conn, "alice", id)
  let assert Some("Imported note") = after.personal_note
  let assert "Owned Wine" = after.name
  let assert "Owned Winery" = after.winery_name
  let assert Some("Mosel") = after.region
  let assert Ok(replayed) = run(uri, json.to_string(apply_input))
  let assert True = first_id(replayed) == id
  let assert True =
    string.contains(json.to_string(replayed), "\"outcome\":\"unchanged\"")
  let assert 1 = count(conn, "wines")
  let assert 1 = count(conn, "mcp_import_records")
  Nil
}

pub fn owned_id_rejects_supplied_conflicting_partial_name_anchor_test() {
  use uri, conn <- with_import_db
  db.ensure_user(conn, "alice")
  let id =
    db.upsert_wine(
      conn,
      "alice",
      "Owned Winery",
      "Owned Wine",
      None,
      None,
      None,
      None,
      Some("Previous note"),
      db.White,
      Some("123"),
    )
  list.each(
    [#("name", "Different wine"), #("winery", "Different winery")],
    fn(anchor) {
      let #(field, value) = anchor
      let input =
        json.object([
          #("source", json.string("conflicting-id")),
          #("apply", json.bool(True)),
          #(
            "wines",
            json.array(
              [
                json.object([
                  #("ref", json.string("wine1")),
                  #("wine_id", json.string(id)),
                  #(field, json.string(value)),
                  #("personal_note", json.string("Changed")),
                ]),
              ],
              fn(x) { x },
            ),
          ),
        ])
      let assert Error(error) = run(uri, json.to_string(input))
      let assert True = string.contains(error, "identity")
    },
  )
  let assert Ok(after) = db.get_wine(conn, "alice", id)
  let assert Some("Previous note") = after.personal_note
  let assert 0 = count(conn, "mcp_import_records")
  Nil
}

pub fn invalid_second_purchase_identifies_reference_and_date_before_writes_test() {
  use uri, conn <- with_import_db
  let assert Error(error) =
    run(
      uri,
      "{\"source\":\"row-errors\",\"apply\":true,\"wines\":[{\"ref\":\"wine1\",\"name\":\"Riesling\",\"winery\":\"Winery\"}],\"cellar\":[{\"ref\":\"purchase1\",\"wine_ref\":\"wine1\",\"quantity\":2,\"date\":\"2024-02-29\"},{\"ref\":\"purchase2\",\"wine_ref\":\"wine1\",\"quantity\":1,\"date\":\"2023-02-29\"}]}",
    )
  list.each(["cellar", "purchase2", "date"], fn(context) {
    let assert True = string.contains(error, context)
  })
  let assert 0 = count(conn, "users")
  let assert 0 = count(conn, "wines")
  let assert 0 = count(conn, "cellar")
  let assert 0 = count(conn, "mcp_import_records")
  Nil
}

pub fn invalid_reference_identifies_collection_and_array_index_test() {
  use uri, conn <- with_import_db
  let assert Error(error) =
    run(
      uri,
      "{\"source\":\"row-errors\",\"wines\":[{\"ref\":\"wine1\",\"name\":\"Riesling\",\"winery\":\"Winery\"}],\"cellar\":[{\"ref\":\"purchase1\",\"wine_ref\":\"wine1\",\"quantity\":2},{\"ref\":42,\"wine_ref\":\"wine1\",\"quantity\":1}]}",
    )
  let assert True = string.contains(error, "cellar[1]")
  let assert True = string.contains(error, "ref")
  let assert 0 = count(conn, "users")
  Nil
}

pub fn planned_missing_vintage_identifies_second_purchase_before_writes_test() {
  use uri, conn <- with_import_db
  let assert Error(error) =
    run(
      uri,
      "{\"source\":\"row-errors\",\"apply\":true,\"wines\":[{\"ref\":\"wine1\",\"name\":\"Riesling\",\"winery\":\"Winery\",\"vintages\":[{\"year\":\"2020\"}]}],\"cellar\":[{\"ref\":\"purchase1\",\"wine_ref\":\"wine1\",\"quantity\":2,\"vintage\":\"2020\"},{\"ref\":\"purchase2\",\"wine_ref\":\"wine1\",\"quantity\":1,\"vintage\":\"2021\"}]}",
    )
  list.each(["cellar", "purchase2", "vintage"], fn(context) {
    let assert True = string.contains(error, context)
  })
  let assert 0 = count(conn, "users")
  let assert 0 = count(conn, "wines")
  let assert 0 = count(conn, "cellar")
  let assert 0 = count(conn, "mcp_import_records")
  Nil
}
