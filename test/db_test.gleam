import gleam/list
import gleam/option.{None, Some}
import gleam/string

import rebstock/db
import rebstock/seed
import test_helpers.{
  create_test_wine, seed_two_users, with_empty_db, with_seeded_db,
}

pub fn demo_seed_has_varied_wine_types_and_multiple_vintages_test() {
  use conn <- with_seeded_db
  let wines = db.list_wines(conn, "test")
  let assert 6 = list.length(wines)
  let assert 6 =
    list.length(list.unique(list.map(wines, fn(w) { w.wine_type })))
  let assert True =
    list.any(wines, fn(w) { list.length(db.vintages_for_wine(conn, w.id)) == 3 })
  let assert 6 = db.count_cellar_wines(conn, "test")
  let assert 6 = db.count_rated_wines(conn, "test")
  Nil
}

pub fn cellar_isolation_test() {
  use conn <- with_empty_db
  let #(wine_a, _wine_b) = seed_two_users(conn)
  let alice_cellar = db.cellar_wines(conn, "alice", db.unfiltered)
  let bob_cellar = db.cellar_wines(conn, "bob", db.unfiltered)
  let assert 1 = list.length(alice_cellar)
  let assert 1 = list.length(bob_cellar)
  let assert 6 = db.cellar_bottle_count(conn, "alice", wine_a)
  let assert 0 = db.cellar_bottle_count(conn, "bob", wine_a)
  Nil
}

pub fn ratings_isolation_test() {
  use conn <- with_empty_db
  let #(_wine_a, _wine_b) = seed_two_users(conn)
  let alice_ratings = db.ratings_by_user(conn, "alice", db.unfiltered)
  let bob_ratings = db.ratings_by_user(conn, "bob", db.unfiltered)
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
  let assert True = id1 == id2
  let assert 1 = db.count_wines(conn)
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
  let assert True = id1 == id2
  let assert 1 = db.count_wines(conn)
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

pub fn ulid_generation_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let id1 = create_test_wine(conn, "Test Wine", db.Red)
  let assert 26 = string.length(id1)
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
  let wine_id = create_test_wine(conn, "Test Wine", db.Red)
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

pub fn seed_alice_test() {
  use conn <- with_seeded_db
  seed.seed_alice(conn, "test")
  let alice_ratings = db.ratings_by_user(conn, "alice", db.unfiltered)
  let assert True = alice_ratings != []
  let alice_cellar = db.cellar_wines(conn, "alice", db.unfiltered)
  let assert True = alice_cellar != []
  Nil
}

pub fn seed_alice_few_wines_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  create_test_wine(conn, "Solo Wine", db.Red)
  seed.seed_alice(conn, "test")
  let alice_ratings = db.ratings_by_user(conn, "alice", db.unfiltered)
  let assert 1 = list.length(alice_ratings)
  Nil
}

pub fn wine_type_roundtrip_test() {
  let assert "RED" = db.wine_type_to_string(db.Red)
  let assert db.Red = db.wine_type_from_string("RED")
  let assert "WHITE" = db.wine_type_to_string(db.White)
  let assert db.White = db.wine_type_from_string("WHITE")
  let assert "ROSE" = db.wine_type_to_string(db.Rose)
  let assert db.Rose = db.wine_type_from_string("ROSE")
  let assert "SPARKLING" = db.wine_type_to_string(db.Sparkling)
  let assert db.Sparkling = db.wine_type_from_string("SPARKLING")
  let assert "DESSERT" = db.wine_type_to_string(db.Dessert)
  let assert db.Dessert = db.wine_type_from_string("DESSERT")
  let assert "ORANGE" = db.wine_type_to_string(db.Orange)
  let assert db.Orange = db.wine_type_from_string("ORANGE")
  let assert "SAKE" = db.wine_type_to_string(db.Sake)
  let assert db.Sake = db.wine_type_from_string("SAKE")
  let assert "OTHER" = db.wine_type_to_string(db.Other)
  let assert db.Other = db.wine_type_from_string("OTHER")
  let assert db.Other = db.wine_type_from_string("UNKNOWN")
  Nil
}

pub fn wine_type_label_test() {
  let assert "Red" = db.wine_type_label(db.Red)
  let assert "White" = db.wine_type_label(db.White)
  let assert "Rosé" = db.wine_type_label(db.Rose)
  let assert "Orange" = db.wine_type_label(db.Orange)
  let assert "Sparkling" = db.wine_type_label(db.Sparkling)
  let assert "Dessert" = db.wine_type_label(db.Dessert)
  let assert "Sake" = db.wine_type_label(db.Sake)
  let assert "Other" = db.wine_type_label(db.Other)
  Nil
}

pub fn list_type_roundtrip_test() {
  let assert "cellar" = db.list_type_to_string(db.CellarList)
  let assert db.CellarList = db.list_type_from_string("cellar")
  let assert "rated" = db.list_type_to_string(db.RatedList)
  let assert db.RatedList = db.list_type_from_string("rated")
  let assert "wishlist" = db.list_type_to_string(db.WishlistList)
  let assert db.WishlistList = db.list_type_from_string("wishlist")
  let assert "custom" = db.list_type_to_string(db.CustomList)
  let assert db.CustomList = db.list_type_from_string("custom")
  let assert db.CustomList = db.list_type_from_string("anything")
  Nil
}

pub fn parse_utility_functions_test() {
  let assert Some(42) = db.parse_optional_int("42")
  let assert None = db.parse_optional_int("")
  let assert None = db.parse_optional_int("abc")
  let assert 42 = db.parse_int_or_zero("42")
  let assert 0 = db.parse_int_or_zero("")
  let assert 0 = db.parse_int_or_zero("nope")
  let assert Some("2020") = db.parse_vintage("2020")
  let assert None = db.parse_vintage("")
  let assert None = db.parse_vintage("abc")
  let assert Some(4.5) = db.parse_optional_float("4.5")
  let assert None = db.parse_optional_float("")
  let assert None = db.parse_optional_float("nope")
  let assert Some("hello") = db.optional_non_empty("hello")
  let assert None = db.optional_non_empty("")
  Nil
}

pub fn slugify_test() {
  let assert "hello-world" = db.slugify("Hello World")
  let assert "pinot-noir-reserve" = db.slugify("Pinot Noir Reserve")
  let assert "test" = db.slugify("TEST")
  let assert "a---b" = db.slugify("A   B")
  Nil
}

pub fn db_count_functions_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let assert 2 = db.count_wines(conn)
  let assert 2 = db.count_wineries(conn)
  let assert 2 = db.count_users(conn)
  Nil
}

pub fn db_rating_distribution_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let dist = db.rating_distribution(conn, "alice")
  let assert True = dist != []
  Nil
}

pub fn db_top_cellar_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let top = db.top_cellar(conn, "alice", 5)
  let assert True = top != []
  Nil
}

pub fn db_top_ratings_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let top = db.top_ratings_by_user(conn, "alice", 5)
  let assert True = top != []
  Nil
}

pub fn db_latest_ratings_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let latest = db.latest_ratings(conn, "alice", 5)
  let assert True = latest != []
  Nil
}

pub fn db_latest_cellar_entries_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let latest = db.latest_cellar_entries(conn, "alice", 5)
  let assert True = latest != []
  Nil
}

pub fn db_vivino_rating_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Rated Wine", db.Red)
  db.set_wine_vivino_rating(conn, wine_id, 4.2, Some(1500))
  let assert Ok(wine) = db.get_wine(conn, "test", wine_id)
  let assert Some(4.2) = wine.vivino_rating
  let assert Some(1500) = wine.vivino_rating_count

  db.upsert_vintage(conn, wine_id, "2020")
  db.set_vintage_vivino_rating(conn, wine_id, "2020", 4.4, None)
  let assert [vr] = db.vintage_ratings_for_wine(conn, wine_id)
  let assert "2020" = vr.year
  let assert Some(4.4) = vr.rating
  let assert None = vr.rating_count
  Nil
}

pub fn db_count_rated_wines_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let assert True = db.count_rated_wines(conn, "alice") > 0
  let assert True = db.count_rated_wineries(conn, "alice") > 0
  Nil
}

pub fn db_count_cellar_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let assert True = db.count_cellar_wines(conn, "alice") > 0
  let assert True = db.count_cellar_wineries(conn, "alice") > 0
  Nil
}

pub fn db_update_and_delete_list_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let id = db.create_list(conn, "test", "Original Name", Some("desc"), False)
  db.update_list(conn, id, "New Name", Some("new desc"), True)
  let assert Ok(updated) = db.get_list(conn, id)
  let assert "New Name" = updated.name
  let assert Some("new desc") = updated.description
  let assert True = updated.show_bottles
  db.delete_list(conn, id)
  let assert Error(_) = db.get_list(conn, id)
  Nil
}

pub fn db_all_winery_names_test() {
  use conn <- with_seeded_db
  let names = db.all_winery_names(conn)
  let assert True = names != []
  Nil
}

pub fn db_wines_by_winery_test() {
  use conn <- with_seeded_db
  let wineries = db.list_wineries(conn)
  let assert [winery, ..] = wineries
  let wines = db.wines_by_winery(conn, "test", winery.id)
  let assert True = wines != []
  Nil
}

pub fn db_cellar_wines_by_type_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let cellar = db.cellar_wines_by_type(conn, "alice")
  let assert True = cellar != []
  Nil
}

pub fn db_rated_wines_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let rated = db.rated_wines(conn, "alice")
  let assert True = rated != []
  Nil
}

pub fn db_bottle_counts_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let counts = db.bottle_counts_for_user(conn, "alice")
  let assert True = counts != []
  Nil
}

pub fn parse_price_cents_test() {
  let assert None = db.parse_price_cents("")
  let assert None = db.parse_price_cents("  ")
  let assert None = db.parse_price_cents("free")
  let assert Some(1370) = db.parse_price_cents("13.70")
  let assert Some(1370) = db.parse_price_cents("13.7")
  let assert Some(1371) = db.parse_price_cents("13.705")
  let assert Some(1300) = db.parse_price_cents("13")
  Nil
}

pub fn format_price_test() {
  let assert "\u{20ac}13.70" = db.format_price(1370)
  let assert "\u{20ac}0.05" = db.format_price(5)
  let assert "\u{20ac}1234.56" = db.format_price(123_456)
  let assert "13.70" = db.format_price_plain(1370)
  let assert "1234.56" = db.format_price_plain(123_456)
  Nil
}

pub fn format_price_negative_test() {
  let assert "-5.50" = db.format_price_plain(-550)
  let assert "\u{20ac}-5.50" = db.format_price(-550)
  Nil
}

pub fn cellar_entry_stores_price_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Priced Cab", db.Red)
  db.upsert_vintage(conn, wine_id, "2020")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2020"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: Some(1370),
  )
  let assert [entry] = db.cellar_entries_for_wine(conn, wine_id)
  let assert Some(1370) = entry.price_cents
  db.update_cellar_entry(
    conn,
    id: entry.id,
    vintage: Some("2020"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: None,
  )
  let assert [cleared] = db.cellar_entries_for_wine(conn, wine_id)
  let assert None = cleared.price_cents
  Nil
}

pub fn cellar_value_survives_drinking_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Tenner", db.Red)
  db.upsert_vintage(conn, wine_id, "2021")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2021"),
    quantity: 3,
    notes: None,
    date: None,
    price_cents: Some(1000),
  )
  let assert [entry] = db.cellar_entries_for_wine(conn, wine_id)
  db.insert_cellar_drink(
    conn,
    parent_id: entry.id,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2021"),
    notes: None,
    date: None,
  )
  let assert [cw] = db.cellar_wines(conn, "test", db.unfiltered)
  let assert 2 = cw.bottles
  let assert Some(2000) = db.held_value(cw.price_breakdown)
  Nil
}

pub fn cellar_price_breakdown_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Two Prices", db.White)
  db.upsert_vintage(conn, wine_id, "2022")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2022"),
    quantity: 1,
    notes: None,
    date: None,
    price_cents: Some(1420),
  )
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2022"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: Some(1370),
  )
  let assert [cw] = db.cellar_wines(conn, "test", db.unfiltered)
  let assert [#(2, 1370), #(1, 1420)] = cw.price_breakdown
  let assert Some(4160) = db.held_value(cw.price_breakdown)
  Nil
}

pub fn cellar_price_breakdown_drops_fully_drunk_group_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Drunk One Price", db.Red)
  db.upsert_vintage(conn, wine_id, "2019")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2019"),
    quantity: 1,
    notes: None,
    date: None,
    price_cents: Some(2000),
  )
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2019"),
    quantity: 1,
    notes: None,
    date: None,
    price_cents: Some(1000),
  )
  let assert [cheap] =
    db.cellar_entries_for_wine(conn, wine_id)
    |> list.filter(fn(e) { e.price_cents == Some(1000) })
  db.insert_cellar_drink(
    conn,
    parent_id: cheap.id,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2019"),
    notes: None,
    date: None,
  )
  let assert [cw] = db.cellar_wines(conn, "test", db.unfiltered)
  let assert 1 = cw.bottles
  let assert [#(1, 2000)] = cw.price_breakdown
  Nil
}

pub fn cellar_price_breakdown_no_vintage_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "No Vintage Wine", db.Red)
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: None,
    quantity: 2,
    notes: None,
    date: None,
    price_cents: Some(1500),
  )
  let assert [cw] = db.cellar_wines(conn, "test", db.unfiltered)
  let assert 2 = cw.bottles
  let assert [#(2, 1500)] = cw.price_breakdown
  Nil
}

pub fn cellar_price_breakdown_mixed_priced_and_unpriced_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Mixed Pricing", db.Red)
  db.upsert_vintage(conn, wine_id, "2018")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2018"),
    quantity: 3,
    notes: None,
    date: None,
    price_cents: Some(1100),
  )
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2018"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: None,
  )
  let assert [cw] = db.cellar_wines(conn, "test", db.unfiltered)
  let assert 5 = cw.bottles
  let assert [#(3, 1100)] = cw.price_breakdown
  Nil
}

pub fn cellar_without_price_has_no_value_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Unpriced", db.Red)
  db.upsert_vintage(conn, wine_id, "2019")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2019"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: None,
  )
  let assert [cw] = db.cellar_wines(conn, "test", db.unfiltered)
  let assert [] = cw.price_breakdown
  let assert None = db.held_value(cw.price_breakdown)
  Nil
}

pub fn entries_held_value_charges_drinks_to_their_purchase_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Entry Fold", db.Red)
  db.upsert_vintage(conn, wine_id, "2021")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2021"),
    quantity: 3,
    notes: None,
    date: None,
    price_cents: Some(1000),
  )
  let assert [purchase] = db.cellar_entries_for_wine(conn, wine_id)
  db.insert_cellar_drink(
    conn,
    parent_id: purchase.id,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2021"),
    notes: None,
    date: None,
  )
  let entries = db.cellar_entries_for_wine(conn, wine_id)
  let assert Some(2000) = db.entries_held_value(entries)
  Nil
}

pub fn entries_held_value_drops_a_fully_drunk_price_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "All Drunk", db.Red)
  db.upsert_vintage(conn, wine_id, "2020")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2020"),
    quantity: 1,
    notes: None,
    date: None,
    price_cents: Some(1875),
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
  let entries = db.cellar_entries_for_wine(conn, wine_id)
  let assert None = db.entries_held_value(entries)
  Nil
}

pub fn entries_held_value_ignores_unpriced_entries_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Half Priced", db.Red)
  db.upsert_vintage(conn, wine_id, "2018")
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2018"),
    quantity: 2,
    notes: None,
    date: None,
    price_cents: Some(1100),
  )
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some("2018"),
    quantity: 4,
    notes: None,
    date: None,
    price_cents: None,
  )
  let entries = db.cellar_entries_for_wine(conn, wine_id)
  let assert Some(2200) = db.entries_held_value(entries)
  let unpriced = list.filter(entries, fn(e) { e.price_cents == None })
  let assert None = db.entries_held_value(unpriced)
  Nil
}
