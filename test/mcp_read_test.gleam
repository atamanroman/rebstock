import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/string

import rebstock/db
import rebstock/mcp/read
import test_helpers.{seed_two_users, with_empty_db}

fn arguments(source: String) {
  let assert Ok(data) = json.parse(source, decode.dynamic)
  data
}

pub fn mcp_reads_are_scoped_and_search_matches_winery_test() {
  use conn <- with_empty_db
  let #(alice, bob) = seed_two_users(conn)
  let assert Ok(found) =
    read.search(conn, "alice", arguments("{\"q\":\"domaine\"}"))
  let body = json.to_string(found)
  let assert True = string.contains(body, alice)
  let assert False = string.contains(body, bob)
  let assert Error(_) =
    read.wine(conn, "alice", arguments("{\"wine_id\":\"" <> bob <> "\"}"))
  let assert Error(_) = read.search(conn, "alice", arguments("{\"limit\":101}"))
  let assert Error(_) =
    read.search(conn, "alice", arguments("{\"username\":\"bob\"}"))
  Nil
}

pub fn mcp_event_reads_do_not_expose_other_users_test() {
  use conn <- with_empty_db
  let _ = seed_two_users(conn)
  let assert Ok(cellar) = read.cellar(conn, "alice", arguments("{}"))
  let assert Ok(ratings) = read.ratings(conn, "alice", arguments("{}"))
  let assert False = string.contains(json.to_string(cellar), "\"bob\"")
  let assert True = string.contains(json.to_string(ratings), "Excellent")
  let assert False = string.contains(json.to_string(ratings), "Tempranillo")
  Nil
}

pub fn mcp_wishlist_does_not_expose_another_creators_personal_note_test() {
  use conn <- with_empty_db
  let #(_alice, bob) = seed_two_users(conn)
  let assert Ok(wine) = db.get_wine(conn, "bob", bob)
  db.update_wine(
    conn,
    bob,
    wine.name,
    wine.winery_name,
    "bob",
    None,
    None,
    None,
    Some("Private producer note"),
    wine.wine_type,
    None,
  )
  let assert Ok(wishlist) = read.wishlist(conn, "alice", arguments("{}"))
  let body = json.to_string(wishlist)
  let assert True = string.contains(body, "Tempranillo")
  let assert False = string.contains(body, "Private producer note")
  Nil
}

pub fn mcp_reads_on_a_new_identity_are_empty_without_creating_users_test() {
  use conn <- with_empty_db
  let before = db.count_users(conn)
  let assert Ok(_) = read.search(conn, "new-user", arguments("{}"))
  let assert Ok(_) = read.wishlist(conn, "new-user", arguments("{}"))
  let assert True = before == db.count_users(conn)
  Nil
}

pub fn mcp_wine_detail_returns_the_legacy_external_link_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "alice")
  let id =
    db.upsert_wine(
      conn,
      "alice",
      "Winery",
      "Legacy Wine",
      None,
      None,
      None,
      None,
      None,
      db.Red,
      Some("v123"),
    )
  let assert Ok(data) =
    read.wine(conn, "alice", arguments("{\"wine_id\":\"" <> id <> "\"}"))
  let assert Ok("https://www.vivino.com/wines/123") =
    json.parse(
      json.to_string(data),
      decode.at(["wine", "vivino_url"], decode.string),
    )
  Nil
}
