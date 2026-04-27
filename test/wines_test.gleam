import gleam/http
import gleam/option.{None}
import gleam/string
import wisp/simulate

import rebstock/auth
import rebstock/config
import rebstock/db
import rebstock/router
import test_helpers.{
  create_test_wine, seed_two_users, test_config, wine_path, with_empty_db,
  with_seeded_db,
}

pub fn wines_page_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/wines")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Wines")
  Nil
}

pub fn wine_detail_not_found_test() {
  use conn <- with_empty_db
  let response =
    simulate.request(http.Get, "/wines/nonexistent")
    |> router.handle_request(conn, test_config)
  let assert 404 = response.status
  Nil
}

pub fn wine_detail_with_data_test() {
  use conn <- with_seeded_db
  let wines = db.list_wines(conn, "test")
  let assert [wine, ..] = wines
  let response =
    simulate.request(http.Get, wine_path(wine.id, wine.name))
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, wine.name)
  Nil
}

pub fn new_wine_form_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/wines/new")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Add Wine")
  Nil
}

pub fn create_wine_via_form_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Post, "/wines")
    |> simulate.form_body([
      #("name", "Test Shiraz"),
      #("winery", "Test Estate"),
      #("wine_type", "RED"),
      #("region", "Barossa Valley"),
      #("country", "Australia"),
    ])
    |> router.handle_request(conn, test_config)
  let assert True = response.status == 303 || response.status == 200
  let assert 1 = db.count_wines(conn)
  Nil
}

pub fn edit_wine_form_test() {
  use conn <- with_seeded_db
  let wines = db.list_wines(conn, "test")
  let assert [wine, ..] = wines
  let response =
    simulate.request(http.Get, wine_path(wine.id, wine.name) <> "/edit")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Edit")
  Nil
}

pub fn edit_wine_post_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Original Wine", db.Red)
  db.update_wine(
    conn,
    wine_id,
    "Updated Name",
    "Test Winery",
    "test",
    None,
    None,
    None,
    None,
    db.White,
    None,
  )
  let assert Ok(updated) = db.get_wine_by_id(conn, wine_id)
  let assert "Updated Name" = updated.name
  let assert db.White = updated.wine_type
  let response =
    simulate.request(http.Post, wine_path(wine_id, "Updated Name") <> "/edit")
    |> simulate.form_body([
      #("name", "Final Name"),
      #("winery", "Test Winery"),
      #("wine_type", "RED"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  Nil
}

pub fn wine_detail_with_ratings_and_cellar_test() {
  use conn <- with_empty_db
  let #(wine_a, _wb) = seed_two_users(conn)
  let response =
    simulate.request(http.Get, wine_path(wine_a, "Pinot Noir Reserve"))
    |> router.handle_request(
      conn,
      config.Config(..test_config, auth: auth.Single("alice")),
    )
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Pinot Noir Reserve")
  Nil
}

pub fn wine_detail_with_vintage_filter_test() {
  use conn <- with_seeded_db
  let wines = db.list_wines(conn, "test")
  let assert [wine, ..] = wines
  let response =
    simulate.request(http.Get, wine_path(wine.id, wine.name) <> "?vintage=2020")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn wineries_page_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/wineries")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Wineries")
  Nil
}

pub fn winery_detail_test() {
  use conn <- with_seeded_db
  let wineries = db.list_wineries(conn)
  let assert [winery, ..] = wineries
  let response =
    simulate.request(http.Get, "/wineries/" <> winery.id)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn winery_detail_not_found_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/wineries/nonexistent")
    |> router.handle_request(conn, test_config)
  let assert 404 = response.status
  Nil
}

pub fn new_winery_form_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/wineries/new")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Add Winery")
  Nil
}

pub fn create_winery_via_form_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Post, "/wineries")
    |> simulate.form_body([#("name", "New Estate"), #("country", "France")])
    |> router.handle_request(conn, test_config)
  let assert True = response.status == 303 || response.status == 200
  let assert 1 = db.count_wineries(conn)
  Nil
}

pub fn edit_winery_form_test() {
  use conn <- with_seeded_db
  let wineries = db.list_wineries(conn)
  let assert [winery, ..] = wineries
  let url = "/wineries/" <> winery.id <> "/edit"
  let response =
    simulate.request(http.Get, url)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn edit_winery_post_test() {
  use conn <- with_seeded_db
  let wineries = db.list_wineries(conn)
  let assert [winery, ..] = wineries
  let url = "/wineries/" <> winery.id <> "/edit"
  let response =
    simulate.request(http.Post, url)
    |> simulate.form_body([#("name", "Renamed Estate"), #("country", "IT")])
    |> router.handle_request(conn, test_config)
  let assert True = response.status == 303 || response.status == 200
  let assert Ok(updated) = db.get_winery(conn, winery.id)
  let assert "Renamed Estate" = updated.name
  Nil
}
