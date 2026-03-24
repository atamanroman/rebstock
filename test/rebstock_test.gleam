import gleam/http
import gleam/string
import gleeunit
import sqlight
import wisp/simulate

import rebstock/db
import rebstock/router
import rebstock/vivino

pub fn main() -> Nil {
  gleeunit.main()
}

fn with_test_db(f: fn(sqlight.Connection) -> Nil) -> Nil {
  use conn <- sqlight.with_connection(":memory:")
  db.migrate(conn)
  f(conn)
}

pub fn home_returns_200_test() {
  use conn <- with_test_db
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn)
  let assert 200 = response.status
  Nil
}

pub fn home_returns_html_test() {
  use conn <- with_test_db
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn)
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Rebstock")
  Nil
}

pub fn not_found_test() {
  use conn <- with_test_db
  let response =
    simulate.request(http.Get, "/nope")
    |> router.handle_request(conn)
  let assert 404 = response.status
  Nil
}

pub fn import_and_count_test() {
  use conn <- with_test_db
  vivino.import_data(conn, "vivino_data")
  let count = db.count_wines(conn)
  let assert True = count > 0
  Nil
}
