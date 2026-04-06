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
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  Nil
}

pub fn home_contains_rebstock_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
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
  let wines = db.list_wines(conn, "test")
  let assert [first, ..] = wines
  let response =
    simulate.request(http.Get, "/wines/" <> first.id)
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
  let cfg =
    config.parse(
      "{\"port\": 8080, \"auth\": {\"forward\": {\"header_user\": \"x-user\"}}}",
    )
  let assert auth.Forward(
    header_user: "x-user",
    header_name: "x-webauth-name",
    ..,
  ) = cfg.auth
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

fn seed_two_users(conn: sqlight.Connection) -> #(String, String) {
  db.ensure_user(conn, "alice")
  db.ensure_user(conn, "bob")
  let wine_a =
    db.upsert_wine(
      conn,
      created_by: "alice",
      winery: "Domaine Alice",
      name: "Pinot Noir Reserve",
      vintage: Some("2020"),
      region: Some("Burgundy"),
      country: Some("FR"),
      style: None,
      personal_note: None,
      wine_type: db.Red,
      vivino_id: None,
    )
  let wine_b =
    db.upsert_wine(
      conn,
      created_by: "bob",
      winery: "Bodega Bob",
      name: "Tempranillo Gran Reserva",
      vintage: Some("2018"),
      region: Some("Rioja"),
      country: Some("ES"),
      style: None,
      personal_note: None,
      wine_type: db.Red,
      vivino_id: None,
    )
  db.upsert_vintage(conn, wine_a, "2020")
  db.upsert_vintage(conn, wine_b, "2018")
  db.insert_cellar_entry(
    conn,
    username: "alice",
    wine_id: wine_a,
    vintage: Some("2020"),
    quantity: 6,
    notes: None,
    date: None,
  )
  db.insert_cellar_entry(
    conn,
    username: "bob",
    wine_id: wine_b,
    vintage: Some("2018"),
    quantity: 3,
    notes: None,
    date: None,
  )
  db.insert_rating(
    conn,
    username: "alice",
    wine_id: wine_a,
    vintage: Some("2020"),
    rating: Some(4.5),
    tasting_notes: Some("Excellent"),
    rated_at: None,
    source: "user",
  )
  db.insert_rating(
    conn,
    username: "bob",
    wine_id: wine_b,
    vintage: Some("2018"),
    rating: Some(3.8),
    tasting_notes: None,
    rated_at: None,
    source: "user",
  )
  let alice_wl = db.get_user_wishlist(conn, "alice")
  db.add_wine_to_list(
    conn,
    alice_wl.id,
    wine_b,
    Some("2018"),
    Some("Want to try"),
  )
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
  let alice_wl = db.get_user_wishlist(conn, "alice")
  let bob_wl = db.get_user_wishlist(conn, "bob")
  let alice_wishlist = db.list_wines_for_list(conn, alice_wl.id)
  let bob_wishlist = db.list_wines_for_list(conn, bob_wl.id)
  let assert 1 = list.length(alice_wishlist)
  let assert 0 = list.length(bob_wishlist)
  let assert True = db.is_wine_in_list(conn, alice_wl.id, wine_b)
  let assert False = db.is_wine_in_list(conn, bob_wl.id, wine_b)
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
  db.ensure_user(conn, "alice")
  let id1 =
    db.upsert_wine(
      conn,
      created_by: "alice",
      winery: "Domaine Test",
      name: "Chardonnay",
      vintage: Some("2020"),
      region: Some("Burgundy"),
      country: Some("FR"),
      style: None,
      personal_note: None,
      wine_type: db.White,
      vivino_id: Some("111"),
    )
  let id2 =
    db.upsert_wine(
      conn,
      created_by: "alice",
      winery: "Domaine Test",
      name: "Chardonnay",
      vintage: Some("2022"),
      region: None,
      country: None,
      style: None,
      personal_note: None,
      wine_type: db.White,
      vivino_id: Some("222"),
    )
  // Same wine, same id
  let assert True = id1 == id2
  // Only one wine exists
  let assert 1 = db.count_wines(conn)
  // Vintages in vintages table
  let vintages = db.vintages_for_wine(conn, id1)
  let assert 2 = list.length(vintages)
  Nil
}

pub fn upsert_wine_no_duplicate_vintage_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "alice")
  let _id1 =
    db.upsert_wine(
      conn,
      created_by: "alice",
      winery: "Domaine Test",
      name: "Merlot",
      vintage: Some("2020"),
      region: None,
      country: None,
      style: None,
      personal_note: None,
      wine_type: db.Red,
      vivino_id: None,
    )
  let id2 =
    db.upsert_wine(
      conn,
      created_by: "alice",
      winery: "Domaine Test",
      name: "Merlot",
      vintage: Some("2020"),
      region: None,
      country: None,
      style: None,
      personal_note: None,
      wine_type: db.Red,
      vivino_id: None,
    )
  // Same vintage twice should not duplicate
  let vintages = db.vintages_for_wine(conn, id2)
  let assert 1 = list.length(vintages)
  let assert ["2020"] = vintages
  Nil
}

pub fn upsert_wine_different_vivino_ids_merge_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "alice")
  let id1 =
    db.upsert_wine(
      conn,
      created_by: "alice",
      winery: "Domaine Test",
      name: "Syrah",
      vintage: Some("2019"),
      region: None,
      country: None,
      style: None,
      personal_note: None,
      wine_type: db.Red,
      vivino_id: Some("aaa"),
    )
  let id2 =
    db.upsert_wine(
      conn,
      created_by: "alice",
      winery: "Domaine Test",
      name: "Syrah",
      vintage: Some("2021"),
      region: None,
      country: None,
      style: None,
      personal_note: None,
      wine_type: db.Red,
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
    simulate.request(http.Get, "/wines/nonexistent")
    |> router.handle_request(conn, test_auth)
  let assert 404 = response.status
  Nil
}

pub fn country_to_iso_test() {
  let assert Some("FR") = db.country_to_iso("France")
  let assert Some("IT") = db.country_to_iso("Italy")
  let assert Some("DE") = db.country_to_iso("Germany")
  let assert Some("DE") = db.country_to_iso("de")
  let assert Some("US") = db.country_to_iso("United States")
  let assert Some("CZ") = db.country_to_iso("Czech Republic")
  let assert None = db.country_to_iso("")
  Nil
}

pub fn import_page_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/~test/import")
    |> router.handle_request(conn, test_auth)
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
    |> router.handle_request(conn, test_auth)
  let assert 403 = response.status
  Nil
}

pub fn import_from_zip_test() {
  use conn <- with_empty_db
  let wine_list_csv =
    "Winery,Wine,Vintage,Region,Country,Style,Average Rating,Scan Date,Scan Location,User Rating,User Review,Personal Note,Wine Type,Drinking Window,Vivino Link\nTest Winery,Test Riesling,2021,Mosel,Germany,,4.2,,,3.5,,Great wine,White,,https://www.vivino.com/wines/12345\n"
  let cellar_csv =
    "Winery,Wine,Vintage,Region,Country,Style,Average Rating,Rating Count,Wine Type,Vivino Link,Cellar Count\nTest Winery,Test Riesling,2021,Mosel,Germany,,4.2,100,White,https://www.vivino.com/wines/12345,3\n"
  let zip_bytes =
    create_test_zip([
      #("full_wine_list.csv", wine_list_csv),
      #("cellar.csv", cellar_csv),
    ])
  let assert Ok(result) = vivino.import_from_zip(conn, zip_bytes, "test")
  let assert True = result.wines_created > 0
  let assert True = result.cellar_created > 0
  let assert 1 = db.count_wines(conn)
  Nil
}

pub fn import_from_zip_missing_wine_list_test() {
  use conn <- with_empty_db
  let cellar_csv =
    "Winery,Wine,Vintage,Region,Country,Style,Average Rating,Rating Count,Wine Type,Vivino Link,Cellar Count\n"
  let zip_bytes = create_test_zip([#("cellar.csv", cellar_csv)])
  let assert Error("Zip must contain full_wine_list.csv") =
    vivino.import_from_zip(conn, zip_bytes, "test")
  Nil
}

pub fn ulid_generation_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "alice")
  let id1 =
    db.upsert_wine(
      conn,
      created_by: "alice",
      winery: "Test Winery",
      name: "Test Wine",
      vintage: None,
      region: None,
      country: None,
      style: None,
      personal_note: None,
      wine_type: db.Red,
      vivino_id: None,
    )
  // ULID is 26 chars
  let assert 26 = string.length(id1)
  Nil
}

pub fn home_empty_shows_import_cta_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_auth)
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
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Your Stats")
  let assert False = string.contains(body, "Welcome to Rebstock")
  Nil
}

pub fn nav_contains_username_dropdown_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_auth)
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "~test")
  let assert True = string.contains(body, "/~test/import")
  Nil
}

pub fn create_list_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let id =
    db.create_list(conn, "test", "My Favourites", Some("Top picks"), False)
  let assert Ok(wine_list) = db.get_list(conn, id)
  let assert "My Favourites" = wine_list.name
  let assert Some("Top picks") = wine_list.description
  let assert "my-favourites" = wine_list.slug
  let assert db.CustomList = wine_list.list_type
  let assert False = wine_list.public
  Nil
}

pub fn system_lists_auto_created_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let lists = db.lists_for_user(conn, "test")
  let assert 3 = list.length(lists)
  let assert Ok(_) = db.get_list_by_slug(conn, "test", "cellar")
  let assert Ok(_) = db.get_list_by_slug(conn, "test", "rated")
  let assert Ok(_) = db.get_list_by_slug(conn, "test", "wishlist")
  Nil
}

pub fn add_wine_to_list_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let list_id = db.create_list(conn, "test", "Test List", None, False)
  let wine_id =
    db.upsert_wine(
      conn,
      created_by: "test",
      winery: "Test Winery",
      name: "Test Wine",
      vintage: None,
      region: None,
      country: None,
      style: None,
      personal_note: None,
      wine_type: db.Red,
      vivino_id: None,
    )
  db.add_wine_to_list(conn, list_id, wine_id, None, None)
  let wines = db.list_wines_for_list(conn, list_id)
  let assert 1 = list.length(wines)
  let assert True = db.is_wine_in_list(conn, list_id, wine_id)
  Nil
}

pub fn set_list_public_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let id = db.create_list(conn, "test", "Public List", None, False)
  let assert Ok(wine_list) = db.get_list(conn, id)
  let assert False = wine_list.public
  db.set_list_public(conn, id, True)
  let assert Ok(updated) = db.get_list(conn, id)
  let assert True = updated.public
  Nil
}

pub fn shared_view_returns_200_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let id = db.create_list(conn, "test", "Shared List", None, False)
  db.set_list_public(conn, id, True)
  let assert Ok(wine_list) = db.get_list(conn, id)
  let response =
    simulate.request(http.Get, "/shared/" <> id <> "/" <> wine_list.slug)
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  Nil
}

pub fn shared_view_private_returns_404_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let id = db.create_list(conn, "test", "Private List", None, False)
  let assert Ok(wine_list) = db.get_list(conn, id)
  let response =
    simulate.request(http.Get, "/shared/" <> id <> "/" <> wine_list.slug)
    |> router.handle_request(conn, test_auth)
  let assert 404 = response.status
  Nil
}

pub fn lists_page_returns_200_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/~test/lists")
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  Nil
}

@external(erlang, "rebstock_test_ffi", "create_zip")
fn create_test_zip(files: List(#(String, String))) -> BitArray
