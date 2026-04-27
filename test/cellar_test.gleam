import gleam/http
import gleam/string
import wisp/simulate

import rebstock/db
import rebstock/router
import test_helpers.{
  create_test_cellar_wine, seed_two_users, test_config, wine_path, with_empty_db,
  with_seeded_db,
}

pub fn cellar_page_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/~test/cellar")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Cellar")
  Nil
}

pub fn cellar_csv_test() {
  use conn <- with_seeded_db
  let response =
    simulate.request(http.Get, "/~test/cellar/export.csv")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Winery,Wine")
  Nil
}

pub fn cellar_entry_detail_test() {
  use conn <- with_empty_db
  let #(wine_a, _wb) = seed_two_users(conn)
  let entries = db.cellar_entries_for_wine(conn, wine_a)
  let assert [entry, ..] = entries
  let response =
    simulate.request(http.Get, "/cellar/" <> entry.id)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn cellar_entry_overlay_test() {
  use conn <- with_empty_db
  let #(wine_a, _wb) = seed_two_users(conn)
  let entries = db.cellar_entries_for_wine(conn, wine_a)
  let assert [entry, ..] = entries
  let response =
    simulate.request(http.Get, "/cellar/" <> entry.id <> "/overlay")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn cellar_entry_not_found_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/cellar/nonexistent")
    |> router.handle_request(conn, test_config)
  let assert 404 = response.status
  Nil
}

pub fn cellar_new_entry_test() {
  use conn <- with_seeded_db
  let wines = db.list_wines(conn, "test")
  let assert [wine, ..] = wines
  let url = wine_path(wine.id, wine.name) <> "/cellar/new"
  let response =
    simulate.request(http.Get, url)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let vintages = db.vintages_for_wine(conn, wine.id)
  let vintage_val = case vintages {
    [v, ..] -> v
    [] -> ""
  }
  let response =
    simulate.request(http.Post, url)
    |> simulate.form_body([
      #("vintage", vintage_val),
      #("quantity", "6"),
      #("notes", "Picked up at the winery"),
      #("date", "2026-01-01"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn cellar_edit_entry_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let #(wine_id, entry_id) =
    create_test_cellar_wine(conn, "Test Cab", "2020", 3)
  let edit_url =
    wine_path(wine_id, "Test Cab") <> "/cellar/" <> entry_id <> "/edit"
  let response =
    simulate.request(http.Get, edit_url)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let response =
    simulate.request(http.Post, edit_url)
    |> simulate.form_body([
      #("vintage", "2020"),
      #("quantity", "5"),
      #("notes", "Updated"),
      #("date", "2026-02-01"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn cellar_drink_and_delete_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let #(wine_id, entry_id) =
    create_test_cellar_wine(conn, "Test Merlot", "2020", 6)
  let base = wine_path(wine_id, "Test Merlot") <> "/cellar/" <> entry_id
  let response =
    simulate.request(http.Get, base <> "/drink")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let response =
    simulate.request(http.Post, base <> "/drink")
    |> simulate.form_body([#("notes", "Delicious"), #("date", "2026-03-01")])
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let assert 5 = db.cellar_bottle_count(conn, "test", wine_id)
  let response =
    simulate.request(http.Post, base <> "/delete")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let assert 0 = db.cellar_bottle_count(conn, "test", wine_id)
  Nil
}

pub fn cellar_set_public_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let response =
    simulate.request(http.Post, "/~test/cellar/public")
    |> simulate.form_body([#("public", "1")])
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert Ok(wl) = db.get_list_by_slug(conn, "test", "cellar")
  let assert True = wl.public
  Nil
}

pub fn cellar_set_public_forbidden_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let response =
    simulate.request(http.Post, "/~other/cellar/public")
    |> simulate.form_body([#("public", "1")])
    |> router.handle_request(conn, test_config)
  let assert 403 = response.status
  Nil
}
