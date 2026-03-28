import gleam/http
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import sqlight
import wisp/simulate

import rebstock/auth
import rebstock/config
import rebstock/db
import rebstock/router
import rebstock/vivino

const test_auth = auth.Single("test")

pub fn main() -> Nil {
  gleeunit.main()
}

fn with_seeded_db(f: fn(sqlight.Connection) -> Nil) -> Nil {
  use conn <- sqlight.with_connection(":memory:")
  db.migrate(conn)
  vivino.import_data(conn, "vivino_data", "test")
  f(conn)
}

fn with_empty_db(f: fn(sqlight.Connection) -> Nil) -> Nil {
  use conn <- sqlight.with_connection(":memory:")
  db.migrate(conn)
  f(conn)
}

pub fn home_returns_200_test() {
  use conn <- with_empty_db
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  Nil
}

pub fn home_contains_rebstock_test() {
  use conn <- with_empty_db
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_auth)
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Rebstock")
  Nil
}

pub fn not_found_test() {
  use conn <- with_empty_db
  let response =
    simulate.request(http.Get, "/nope")
    |> router.handle_request(conn, test_auth)
  let assert 404 = response.status
  Nil
}

pub fn import_and_count_test() {
  use conn <- with_seeded_db
  let count = db.count_wines(conn)
  let assert True = count > 0
  Nil
}

pub fn wines_page_test() {
  use conn <- with_seeded_db
  let response =
    simulate.request(http.Get, "/wines")
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Wines")
  Nil
}

pub fn wineries_page_test() {
  use conn <- with_seeded_db
  let response =
    simulate.request(http.Get, "/wineries")
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Wineries")
  Nil
}

pub fn cellar_page_test() {
  use conn <- with_seeded_db
  let response =
    simulate.request(http.Get, "/~test/cellar")
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Cellar")
  Nil
}

pub fn wine_detail_test() {
  use conn <- with_seeded_db
  let response =
    simulate.request(http.Get, "/wines/1")
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  Nil
}

pub fn config_single_mode_test() {
  let cfg = config.parse("{\"auth\": {\"single\": {\"user\": \"bob\"}}}")
  let assert auth.Single("bob") = cfg.auth
  let assert 3000 = cfg.port
  let assert "file:rebstock.db" = cfg.database_uri
  Nil
}

pub fn config_forward_mode_test() {
  let cfg = config.parse("{\"port\": 8080, \"auth\": {\"forward\": {\"header_user\": \"x-user\"}}}")
  let assert auth.Forward(header_user: "x-user", header_name: "x-webauth-name", ..) = cfg.auth
  let assert 8080 = cfg.port
  Nil
}

pub fn config_defaults_test() {
  let cfg = config.parse("{\"auth\": {\"single\": {}}}")
  let assert auth.Single("admin") = cfg.auth
  let assert 3000 = cfg.port
  let assert "file:rebstock.db" = cfg.database_uri
  Nil
}

pub fn config_missing_file_test() {
  let cfg = config.load("/nonexistent/config.json")
  let assert auth.Single("admin") = cfg.auth
  Nil
}

fn seed_two_users(conn: sqlight.Connection) -> #(Int, Int) {
  let wine_a = db.upsert_wine(
    conn,
    created_by: "alice",
    winery: "Domaine Alice",
    name: "Pinot Noir Reserve",
    vintages: Some("2020"),
    region: Some("Burgundy"),
    country: Some("France"),
    style: None,
    avg_rating: Some(4.2),
    rating_count: None,
    personal_note: None,
    wine_type: "Red Wine",
    vivino_id: None,
  )
  let wine_b = db.upsert_wine(
    conn,
    created_by: "bob",
    winery: "Bodega Bob",
    name: "Tempranillo Gran Reserva",
    vintages: Some("2018"),
    region: Some("Rioja"),
    country: Some("Spain"),
    style: None,
    avg_rating: Some(4.5),
    rating_count: None,
    personal_note: None,
    wine_type: "Red Wine",
    vivino_id: None,
  )
  db.insert_cellar_entry(conn, username: "alice", wine_id: wine_a, vintage: 2020, quantity: 6, notes: None, dated_at: None)
  db.insert_cellar_entry(conn, username: "bob", wine_id: wine_b, vintage: 2018, quantity: 3, notes: None, dated_at: None)
  db.insert_rating(conn, username: "alice", wine_id: wine_a, vintage: Some(2020), rating: Some(4.5), tasting_notes: Some("Excellent"), rated_at: None)
  db.insert_rating(conn, username: "bob", wine_id: wine_b, vintage: Some(2018), rating: Some(3.8), tasting_notes: None, rated_at: None)
  db.upsert_wishlist(conn, username: "alice", wine_id: wine_b, vintage: Some(2018), notes: Some("Want to try"), dated_at: None)
  #(wine_a, wine_b)
}

pub fn cellar_isolation_test() {
  use conn <- with_empty_db
  let #(wine_a, _wine_b) = seed_two_users(conn)
  let alice_cellar = db.cellar_wines(conn, "alice")
  let bob_cellar = db.cellar_wines(conn, "bob")
  let assert 1 = list.length(alice_cellar)
  let assert 1 = list.length(bob_cellar)
  let assert 6 = db.cellar_bottle_count(conn, "alice", wine_a)
  let assert 0 = db.cellar_bottle_count(conn, "bob", wine_a)
  Nil
}

pub fn ratings_isolation_test() {
  use conn <- with_empty_db
  let #(_wine_a, _wine_b) = seed_two_users(conn)
  let alice_ratings = db.ratings_by_user(conn, "alice")
  let bob_ratings = db.ratings_by_user(conn, "bob")
  let assert 1 = list.length(alice_ratings)
  let assert 1 = list.length(bob_ratings)
  let assert [r] = alice_ratings
  let assert Some(4.5) = r.rating
  Nil
}

pub fn wishlist_isolation_test() {
  use conn <- with_empty_db
  let #(_wine_a, wine_b) = seed_two_users(conn)
  let alice_wishlist = db.wishlist_wines(conn, "alice")
  let bob_wishlist = db.wishlist_wines(conn, "bob")
  let assert 1 = list.length(alice_wishlist)
  let assert 0 = list.length(bob_wishlist)
  let assert True = db.is_wishlisted(conn, "alice", wine_b)
  let assert False = db.is_wishlisted(conn, "bob", wine_b)
  Nil
}

pub fn wines_global_but_scoped_by_creator_test() {
  use conn <- with_empty_db
  let #(_wine_a, _wine_b) = seed_two_users(conn)
  let alice_wines = db.list_wines(conn, "alice")
  let bob_wines = db.list_wines(conn, "bob")
  let assert 1 = list.length(alice_wines)
  let assert 1 = list.length(bob_wines)
  let assert 2 = db.count_wines(conn)
  Nil
}

pub fn upsert_wine_deduplicates_by_name_test() {
  use conn <- with_empty_db
  let id1 = db.upsert_wine(
    conn,
    created_by: "alice",
    winery: "Domaine Test",
    name: "Chardonnay",
    vintages: Some("2020"),
    region: Some("Burgundy"),
    country: Some("France"),
    style: None,
    avg_rating: Some(4.0),
    rating_count: None,
    personal_note: None,
    wine_type: "White Wine",
    vivino_id: Some("111"),
  )
  let id2 = db.upsert_wine(
    conn,
    created_by: "alice",
    winery: "Domaine Test",
    name: "Chardonnay",
    vintages: Some("2022"),
    region: None,
    country: None,
    style: None,
    avg_rating: Some(4.3),
    rating_count: None,
    personal_note: None,
    wine_type: "White Wine",
    vivino_id: Some("222"),
  )
  // Same wine, same id
  let assert True = id1 == id2
  // Only one wine exists
  let assert 1 = db.count_wines(conn)
  // Vintages merged
  let assert Ok(wine) = db.get_wine_by_id(conn, id1)
  let assert Some(vintages) = wine.vintages
  let assert True = string.contains(vintages, "2020")
  let assert True = string.contains(vintages, "2022")
  Nil
}

pub fn upsert_wine_no_duplicate_vintage_test() {
  use conn <- with_empty_db
  let _id1 = db.upsert_wine(
    conn,
    created_by: "alice",
    winery: "Domaine Test",
    name: "Merlot",
    vintages: Some("2020"),
    region: None,
    country: None,
    style: None,
    avg_rating: None,
    rating_count: None,
    personal_note: None,
    wine_type: "Red Wine",
    vivino_id: None,
  )
  let id2 = db.upsert_wine(
    conn,
    created_by: "alice",
    winery: "Domaine Test",
    name: "Merlot",
    vintages: Some("2020"),
    region: None,
    country: None,
    style: None,
    avg_rating: None,
    rating_count: None,
    personal_note: None,
    wine_type: "Red Wine",
    vivino_id: None,
  )
  let assert Ok(wine) = db.get_wine_by_id(conn, id2)
  // Same vintage twice should not duplicate
  let assert Some("2020") = wine.vintages
  Nil
}

pub fn upsert_wine_different_vivino_ids_merge_test() {
  use conn <- with_empty_db
  let id1 = db.upsert_wine(
    conn,
    created_by: "alice",
    winery: "Domaine Test",
    name: "Syrah",
    vintages: Some("2019"),
    region: None,
    country: None,
    style: None,
    avg_rating: None,
    rating_count: None,
    personal_note: None,
    wine_type: "Red Wine",
    vivino_id: Some("aaa"),
  )
  let id2 = db.upsert_wine(
    conn,
    created_by: "alice",
    winery: "Domaine Test",
    name: "Syrah",
    vintages: Some("2021"),
    region: None,
    country: None,
    style: None,
    avg_rating: None,
    rating_count: None,
    personal_note: None,
    wine_type: "Red Wine",
    vivino_id: Some("bbb"),
  )
  // Same wine despite different vivino ids
  let assert True = id1 == id2
  let assert 1 = db.count_wines(conn)
  Nil
}

pub fn vivino_import_no_duplicate_wines_test() {
  use conn <- with_seeded_db
  let wines = db.list_wines(conn, "test")
  let wine_names = list.map(wines, fn(w) { w.winery_name <> " " <> w.name })
  // Check no duplicate names
  let unique = list.unique(wine_names)
  let assert True = list.length(wine_names) == list.length(unique)
  Nil
}

pub fn wine_detail_not_found_test() {
  use conn <- with_empty_db
  let response =
    simulate.request(http.Get, "/wines/99999")
    |> router.handle_request(conn, test_auth)
  let assert 404 = response.status
  Nil
}
