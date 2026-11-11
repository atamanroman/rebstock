import gleam/http
import gleam/option.{Some}
import gleam/string
import wisp/simulate

import rebstock/auth
import rebstock/config
import rebstock/db
import rebstock/router
import test_helpers.{
  seed_two_users, test_config, user_ratings, wine_path, with_empty_db,
  with_seeded_db,
}

pub fn ratings_page_test() {
  use conn <- with_seeded_db
  let response =
    simulate.request(http.Get, "/~test/ratings")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Your Ratings")
  Nil
}

pub fn ratings_page_other_user_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let response =
    simulate.request(http.Get, "/~alice/ratings")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "alice's Ratings")
  Nil
}

pub fn rating_detail_page_test() {
  use conn <- with_empty_db
  let #(wine_a, _wb) = seed_two_users(conn)
  let ratings = db.ratings_for_wine(conn, wine_a)
  let assert [rating, ..] = ratings
  let response =
    simulate.request(http.Get, "/ratings/" <> rating.id)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn rating_detail_not_found_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/ratings/nonexistent")
    |> router.handle_request(conn, test_config)
  let assert 404 = response.status
  Nil
}

pub fn rating_overlay_test() {
  use conn <- with_empty_db
  let #(wine_a, _wb) = seed_two_users(conn)
  let ratings = db.ratings_for_wine(conn, wine_a)
  let assert [rating, ..] = ratings
  let response =
    simulate.request(http.Get, "/ratings/" <> rating.id <> "/overlay")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn create_and_delete_rating_test() {
  use conn <- with_seeded_db
  let wines = db.list_wines(conn, "test")
  let assert [wine, ..] = wines
  let base = wine_path(wine.id, wine.name)
  let response =
    simulate.request(http.Post, base <> "/ratings/new")
    |> simulate.form_body([
      #("rating", "4.5"),
      #("tasting_notes", "Great wine"),
      #("rated_at", "2026-01-01"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert [r, ..] = user_ratings(db.ratings_for_wine(conn, wine.id), "test")
  let response =
    simulate.request(http.Post, base <> "/ratings/" <> r.id <> "/edit")
    |> simulate.form_body([
      #("rating", "3.0"),
      #("tasting_notes", "Actually ok"),
      #("rated_at", "2026-01-02"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert Ok(updated) = db.get_rating_by_id(conn, r.id)
  let assert Some(3.0) = updated.rating
  let response =
    simulate.request(http.Post, base <> "/ratings/" <> r.id <> "/delete")
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert Error(_) = db.get_rating_by_id(conn, r.id)
  Nil
}

pub fn rating_new_form_get_test() {
  use conn <- with_seeded_db
  let wines = db.list_wines(conn, "test")
  let assert [wine, ..] = wines
  let response =
    simulate.request(http.Get, wine_path(wine.id, wine.name) <> "/ratings/new")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Rate")
  Nil
}

pub fn rating_edit_form_get_test() {
  use conn <- with_empty_db
  let #(wine_a, _wb) = seed_two_users(conn)
  let assert [rating, ..] =
    user_ratings(db.ratings_for_wine(conn, wine_a), "alice")
  let base = wine_path(wine_a, "Pinot Noir Reserve")
  let response =
    simulate.request(http.Get, base <> "/ratings/" <> rating.id <> "/edit")
    |> router.handle_request(
      conn,
      config.Config(..test_config, auth: auth.Single("alice")),
    )
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Edit Rating")
  Nil
}

pub fn rating_delete_forbidden_test() {
  use conn <- with_empty_db
  let #(wine_a, _wb) = seed_two_users(conn)
  let assert [rating, ..] =
    user_ratings(db.ratings_for_wine(conn, wine_a), "alice")
  let response =
    simulate.request(
      http.Post,
      wine_path(wine_a, "Pinot Noir Reserve")
        <> "/ratings/"
        <> rating.id
        <> "/delete",
    )
    |> router.handle_request(conn, test_config)
  let assert 403 = response.status
  Nil
}
