import gleam/http
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

pub fn wine_detail_not_found_test() {
  use conn <- with_empty_db
  let response =
    simulate.request(http.Get, "/wines/99999")
    |> router.handle_request(conn, test_auth)
  let assert 404 = response.status
  Nil
}
