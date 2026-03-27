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
    vintage: Some(2020),
    region: Some("Burgundy"),
    country: Some("France"),
    style: None,
    avg_rating: Some(4.2),
    rating_count: None,
    personal_note: None,
    wine_type: "Red Wine",
    vivino_link: None,
  )
  let wine_b = db.upsert_wine(
    conn,
    created_by: "bob",
    winery: "Bodega Bob",
    name: "Tempranillo Gran Reserva",
    vintage: Some(2018),
    region: Some("Rioja"),
    country: Some("Spain"),
    style: None,
    avg_rating: Some(4.5),
    rating_count: None,
    personal_note: None,
    wine_type: "Red Wine",
    vivino_link: None,
  )
  db.insert_cellar_entry(conn, username: "alice", wine_id: wine_a, quantity: 6, notes: None, dated_at: None)
  db.insert_cellar_entry(conn, username: "bob", wine_id: wine_b, quantity: 3, notes: None, dated_at: None)
  db.insert_rating(conn, username: "alice", wine_id: wine_a, rating: Some(4.5), tasting_notes: Some("Excellent"), rated_at: None)
  db.insert_rating(conn, username: "bob", wine_id: wine_b, rating: Some(3.8), tasting_notes: None, rated_at: None)
  db.upsert_wishlist(conn, username: "alice", wine_id: wine_b, notes: Some("Want to try"), dated_at: None)
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

pub fn wine_detail_not_found_test() {
  use conn <- with_empty_db
  let response =
    simulate.request(http.Get, "/wines/99999")
    |> router.handle_request(conn, test_auth)
  let assert 404 = response.status
  Nil
}
