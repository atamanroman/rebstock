import gleam/http
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import wisp/simulate

import rebstock/db
import rebstock/router
import test_helpers.{
  create_test_wine, seed_two_users, test_config, with_empty_db, with_seeded_db,
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn home_contains_rebstock_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_config)
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Rebstock")
  Nil
}

pub fn not_found_test() {
  use conn <- with_empty_db
  let response =
    simulate.request(http.Get, "/nope")
    |> router.handle_request(conn, test_config)
  let assert 404 = response.status
  Nil
}

pub fn home_empty_shows_import_cta_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Import Vivino Data")
  let assert True = string.contains(body, "/~test/import")
  Nil
}

pub fn home_with_data_shows_stats_test() {
  use conn <- with_seeded_db
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Your Stats")
  let assert False = string.contains(body, "Welcome to Rebstock")
  Nil
}

pub fn home_recent_cellar_shows_entry_vintage_only_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Multi Vintage Riesling", db.White)
  db.upsert_vintage(conn, wine_id, "2018")
  db.upsert_vintage(conn, wine_id, "2019")
  db.upsert_vintage(conn, wine_id, "2020")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2020"),
    quantity: 1,
    notes: None,
    date: None,
    price_cents: None,
  )
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "2020")
  let assert False = string.contains(body, "2018")
  Nil
}

pub fn nav_contains_username_dropdown_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_config)
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "~test")
  let assert True = string.contains(body, "/~test/import")
  Nil
}

pub fn import_page_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/~test/import")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Import Vivino Data")
  Nil
}

pub fn import_page_forbidden_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/~other/import")
    |> router.handle_request(conn, test_config)
  let assert 403 = response.status
  Nil
}

pub fn profile_page_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/~test")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "test")
  Nil
}

pub fn profile_other_user_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let response =
    simulate.request(http.Get, "/~alice")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn head_request_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Head, "/")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}
