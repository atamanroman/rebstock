import gleam/http
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import wisp/simulate

import rebstock/db
import rebstock/router
import test_helpers.{
  create_test_cellar_wine, create_test_wine, seed_two_users, test_config,
  wine_path, with_empty_db, with_seeded_db,
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
  let assert 303 = response.status
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
  let assert 303 = response.status
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
  let assert 303 = response.status
  let assert 5 = db.cellar_bottle_count(conn, "test", wine_id)
  let response =
    simulate.request(http.Post, base <> "/delete")
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert 0 = db.cellar_bottle_count(conn, "test", wine_id)
  Nil
}

pub fn cellar_drink_edit_ignores_price_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Drunk Chablis", db.White)
  db.upsert_vintage(conn, wine_id, "2020")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2020"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: Some(3000),
  )
  let assert [purchase] = db.cellar_entries_for_wine(conn, wine_id)
  db.insert_cellar_drink(
    conn,
    parent_id: purchase.id,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2020"),
    notes: None,
    date: None,
  )
  let assert [drink] =
    db.cellar_entries_for_wine(conn, wine_id)
    |> list.filter(fn(e) { e.parent_id == Some(purchase.id) })
  let edit_url =
    wine_path(wine_id, "Drunk Chablis") <> "/cellar/" <> drink.id <> "/edit"
  let response =
    simulate.request(http.Post, edit_url)
    |> simulate.form_body([
      #("vintage", "2020"),
      #("quantity", "-1"),
      #("notes", ""),
      #("date", "2026-03-01"),
      #("price", "30.00"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert Ok(reloaded) = db.get_cellar_entry_by_id(conn, drink.id)
  let assert None = reloaded.price_cents
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

pub fn cellar_entry_price_round_trip_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let #(wine_id, entry_id) =
    create_test_cellar_wine(conn, "Priced Syrah", "2020", 2)
  let edit_url =
    wine_path(wine_id, "Priced Syrah") <> "/cellar/" <> entry_id <> "/edit"
  let response =
    simulate.request(http.Post, edit_url)
    |> simulate.form_body([
      #("vintage", "2020"),
      #("quantity", "2"),
      #("notes", ""),
      #("date", "2026-02-01"),
      #("price", "13.70"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert Ok(entry) = db.get_cellar_entry_by_id(conn, entry_id)
  let assert Some(1370) = entry.price_cents

  let response =
    simulate.request(http.Get, "/cellar/" <> entry_id)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "\u{20ac}13.70")
  let assert True = string.contains(body, "\u{20ac}27.40 for 2 bottles")

  let response =
    simulate.request(http.Get, edit_url)
    |> router.handle_request(conn, test_config)
  let assert True =
    string.contains(simulate.read_body(response), "value=\"13.70\"")
  Nil
}

fn priced_entry(conn, name: String, price_cents: Int) -> #(String, String) {
  let wine_id = create_test_wine(conn, name, db.Red)
  db.upsert_vintage(conn, wine_id, "2020")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2020"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: Some(price_cents),
  )
  let assert [entry] = db.cellar_entries_for_wine(conn, wine_id)
  #(wine_id, entry.id)
}

fn edit_with_price(
  conn,
  wine_id: String,
  name: String,
  entry_id: String,
  price: String,
) {
  simulate.request(
    http.Post,
    wine_path(wine_id, name) <> "/cellar/" <> entry_id <> "/edit",
  )
  |> simulate.form_body([
    #("vintage", "2020"),
    #("quantity", "2"),
    #("notes", ""),
    #("date", "2026-02-01"),
    #("price", price),
  ])
  |> router.handle_request(conn, test_config)
}

pub fn cellar_entry_negative_price_keeps_stored_price_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let #(wine_id, entry_id) = priced_entry(conn, "Discounted Pinot", 2000)
  let response =
    edit_with_price(conn, wine_id, "Discounted Pinot", entry_id, "-5.50")
  let assert 422 = response.status
  let assert True =
    string.contains(simulate.read_body(response), "Price must be an amount")
  let assert Ok(entry) = db.get_cellar_entry_by_id(conn, entry_id)
  let assert Some(2000) = entry.price_cents
  Nil
}

pub fn cellar_entry_unreadable_price_keeps_stored_price_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let #(wine_id, entry_id) = priced_entry(conn, "Mistyped Merlot", 2000)
  let response =
    edit_with_price(conn, wine_id, "Mistyped Merlot", entry_id, "13.70 EUR")
  let assert 422 = response.status
  let assert True =
    string.contains(simulate.read_body(response), "Price must be an amount")
  let assert Ok(entry) = db.get_cellar_entry_by_id(conn, entry_id)
  let assert Some(2000) = entry.price_cents
  Nil
}

pub fn cellar_entry_blank_price_clears_stored_price_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let #(wine_id, entry_id) = priced_entry(conn, "Forgotten Gamay", 2000)
  let response = edit_with_price(conn, wine_id, "Forgotten Gamay", entry_id, "")
  let assert 303 = response.status
  let assert Ok(entry) = db.get_cellar_entry_by_id(conn, entry_id)
  let assert None = entry.price_cents
  Nil
}

pub fn cellar_new_entry_unreadable_price_is_not_stored_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Rejected Riesling", db.White)
  db.upsert_vintage(conn, wine_id, "2020")
  let response =
    simulate.request(
      http.Post,
      wine_path(wine_id, "Rejected Riesling") <> "/cellar/new",
    )
    |> simulate.form_body([
      #("vintage", "2020"),
      #("quantity", "2"),
      #("notes", ""),
      #("date", "2026-02-01"),
      #("price", "abc"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 422 = response.status
  let assert True =
    string.contains(simulate.read_body(response), "Price must be an amount")
  let assert [] = db.cellar_entries_for_wine(conn, wine_id)
  Nil
}

pub fn cellar_entry_card_quantity_one_omits_bottle_count_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Single Bottle Barolo", db.Red)
  db.upsert_vintage(conn, wine_id, "2015")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2015"),
    quantity: 1,
    notes: None,
    date: None,
    price_cents: Some(4500),
  )
  let assert [entry] = db.cellar_entries_for_wine(conn, wine_id)
  let response =
    simulate.request(http.Get, "/cellar/" <> entry.id)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "\u{20ac}45.00")
  let assert False = string.contains(body, "for 1 bottles")
  Nil
}

pub fn cellar_page_shows_value_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Valued Malbec", db.Red)
  db.upsert_vintage(conn, wine_id, "2021")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2021"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: Some(1370),
  )
  let response =
    simulate.request(http.Get, "/~test/cellar")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "2 bottles \u{b7} \u{20ac}27.40")
  let assert True = string.contains(body, "2\u{d7}\u{20ac}13.70")
  Nil
}

pub fn cellar_csv_has_value_column_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Exported Riesling", db.White)
  db.upsert_vintage(conn, wine_id, "2021")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2021"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: Some(1370),
  )
  let response =
    simulate.request(http.Get, "/~test/cellar/export.csv")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True =
    string.contains(body, "Winery,Wine,Vintage,Country,Type,Bottles,Value")
  let assert True = string.contains(body, ",2,27.40")
  Nil
}
