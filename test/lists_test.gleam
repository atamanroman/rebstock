import gleam/http
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import wisp/simulate

import rebstock/auth
import rebstock/config
import rebstock/db
import rebstock/router
import test_helpers.{
  create_test_wine, seed_two_users, test_config, with_empty_db,
}

pub fn lists_index_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let response =
    simulate.request(http.Get, "/~test/lists")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Lists")
  Nil
}

pub fn new_list_form_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/~test/lists/new")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn create_custom_list_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Post, "/~test/lists")
    |> simulate.form_body([
      #("name", "Summer Picks"),
      #("description", "My summer favourites"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let lists = db.lists_for_user(conn, "test")
  let custom = list.filter(lists, fn(l) { l.list_type == db.CustomList })
  let assert 1 = list.length(custom)
  Nil
}

pub fn list_detail_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let assert Ok(wl) = db.get_list_by_slug(conn, "test", "cellar")
  let response =
    simulate.request(http.Get, "/~test/lists/" <> wl.id)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn list_set_public_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let id = db.create_list(conn, "test", "Test List", None, False)
  let response =
    simulate.request(http.Post, "/~test/lists/" <> id <> "/public")
    |> simulate.form_body([#("public", "1")])
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert Ok(updated) = db.get_list(conn, id)
  let assert True = updated.public
  Nil
}

pub fn list_set_show_bottles_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let id = db.create_list(conn, "test", "Test List", None, False)
  let response =
    simulate.request(http.Post, "/~test/lists/" <> id <> "/show-bottles")
    |> simulate.form_body([#("show_bottles", "1")])
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert Ok(updated) = db.get_list(conn, id)
  let assert True = updated.show_bottles
  Nil
}

pub fn list_add_and_remove_wine_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let list_id = db.create_list(conn, "test", "Test List", None, False)
  let wine_id = create_test_wine(conn, "Test Wine", db.Red)
  let response =
    simulate.request(http.Post, "/~test/lists/" <> list_id <> "/wines")
    |> simulate.form_body([#("wine_id", wine_id)])
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert True = db.is_wine_in_list(conn, list_id, wine_id)
  let response =
    simulate.request(
      http.Post,
      "/~test/lists/" <> list_id <> "/wines/" <> wine_id,
    )
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert False = db.is_wine_in_list(conn, list_id, wine_id)
  Nil
}

pub fn list_edit_form_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let id = db.create_list(conn, "test", "Edit Me", None, False)
  let response =
    simulate.request(http.Get, "/~test/lists/" <> id <> "/edit")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn list_print_view_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let assert Ok(wl) = db.get_list_by_slug(conn, "test", "cellar")
  let response =
    simulate.request(http.Get, "/~test/lists/" <> wl.id <> "/print")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn wishlist_shows_entry_vintage_only_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let wine_id = create_test_wine(conn, "Multi Vintage Riesling", db.White)
  db.upsert_vintage(conn, wine_id, "2018")
  db.upsert_vintage(conn, wine_id, "2019")
  db.upsert_vintage(conn, wine_id, "2020")
  let wl = db.get_user_wishlist(conn, "test")
  db.add_wine_to_list(conn, wl.id, wine_id, Some("2020"), None)
  let response =
    simulate.request(http.Get, "/~test/wishlist")
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "2020")
  let assert False = string.contains(body, "2018")
  Nil
}

pub fn list_detail_with_wines_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let list_id =
    db.create_list(conn, "test", "Favourites", Some("Best of"), True)
  let wine_id = create_test_wine(conn, "List Wine", db.Red)
  db.add_wine_to_list(conn, list_id, wine_id, None, Some("Excellent"))
  let response =
    simulate.request(http.Get, "/~test/lists/" <> list_id)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Favourites")
  let assert True = string.contains(body, "List Wine")
  let response =
    simulate.request(http.Post, "/~test/lists/" <> list_id)
    |> simulate.form_body([
      #("name", "Updated Favourites"),
      #("description", "Updated desc"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert Ok(updated) = db.get_list(conn, list_id)
  let assert "Updated Favourites" = updated.name
  let response =
    simulate.request(http.Post, "/~test/lists/" <> list_id)
    |> simulate.form_body([#("_method", "delete")])
    |> router.handle_request(conn, test_config)
  let assert 303 = response.status
  let assert Error(_) = db.get_list(conn, list_id)
  Nil
}

pub fn list_detail_cellar_type_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let assert Ok(wl) = db.get_list_by_slug(conn, "test", "cellar")
  let response =
    simulate.request(http.Get, "/~test/lists/" <> wl.id)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Cellar")
  Nil
}

pub fn list_detail_rated_type_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "alice")
  db.ensure_system_lists(conn, "alice")
  let assert Ok(wl) = db.get_list_by_slug(conn, "alice", "rated")
  let response =
    simulate.request(http.Get, "/~alice/lists/" <> wl.id)
    |> router.handle_request(
      conn,
      config.Config(..test_config, auth: auth.Single("alice")),
    )
  let assert 200 = response.status
  Nil
}

pub fn list_detail_wishlist_type_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "alice")
  let wl = db.get_user_wishlist(conn, "alice")
  let response =
    simulate.request(http.Get, "/~alice/lists/" <> wl.id)
    |> router.handle_request(
      conn,
      config.Config(..test_config, auth: auth.Single("alice")),
    )
  let assert 200 = response.status
  Nil
}

pub fn list_detail_with_show_bottles_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_system_lists(conn, "test")
  let assert Ok(cellar) = db.get_list_by_slug(conn, "test", "cellar")
  db.set_list_show_bottles(conn, cellar.id, True)
  let response =
    simulate.request(http.Get, "/~test/lists/" <> cellar.id)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
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
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "© 2026 Roman Ataman")
  let assert True = string.contains(body, "rebstock.atamanroman.dev")
  let assert True =
    string.contains(body, "polyformproject.org/licenses/noncommercial/1.0.0/")
  Nil
}

pub fn shared_view_private_returns_404_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let id = db.create_list(conn, "test", "Private List", None, False)
  let assert Ok(wine_list) = db.get_list(conn, id)
  let response =
    simulate.request(http.Get, "/shared/" <> id <> "/" <> wine_list.slug)
    |> router.handle_request(conn, test_config)
  let assert 404 = response.status
  Nil
}

pub fn shared_view_with_wines_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let id = db.create_list(conn, "test", "Wine Menu", Some("Fine wines"), False)
  let wine_id = create_test_wine(conn, "Test Pinot", db.Red)
  db.add_wine_to_list(conn, id, wine_id, None, None)
  db.set_list_public(conn, id, True)
  let assert Ok(wl) = db.get_list(conn, id)
  let response =
    simulate.request(http.Get, "/shared/" <> id <> "/" <> wl.slug)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Wine Menu")
  let assert True = string.contains(body, "Test Pinot")
  Nil
}

pub fn shared_not_found_test() {
  use conn <- with_empty_db
  let response =
    simulate.request(http.Get, "/shared/nonexistent/slug")
    |> router.handle_request(conn, test_config)
  let assert 404 = response.status
  Nil
}

pub fn shared_cellar_list_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "alice")
  db.ensure_system_lists(conn, "alice")
  let assert Ok(wl) = db.get_list_by_slug(conn, "alice", "cellar")
  db.set_list_public(conn, wl.id, True)
  let response =
    simulate.request(http.Get, "/shared/" <> wl.id <> "/" <> wl.slug)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Cellar")
  Nil
}

pub fn shared_rated_list_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "alice")
  db.ensure_system_lists(conn, "alice")
  let assert Ok(wl) = db.get_list_by_slug(conn, "alice", "rated")
  db.set_list_public(conn, wl.id, True)
  let response =
    simulate.request(http.Get, "/shared/" <> wl.id <> "/" <> wl.slug)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn shared_show_bottles_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "alice")
  db.ensure_system_lists(conn, "alice")
  let assert Ok(wl) = db.get_list_by_slug(conn, "alice", "cellar")
  db.set_list_public(conn, wl.id, True)
  db.set_list_show_bottles(conn, wl.id, True)
  let response =
    simulate.request(http.Get, "/shared/" <> wl.id <> "/" <> wl.slug)
    |> router.handle_request(conn, test_config)
  let assert 200 = response.status
  Nil
}

pub fn wishlist_page_test() {
  use conn <- with_empty_db
  let #(_wa, _wb) = seed_two_users(conn)
  let response =
    simulate.request(http.Get, "/~alice/wishlist")
    |> router.handle_request(
      conn,
      config.Config(..test_config, auth: auth.Single("alice")),
    )
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Wishlist")
  Nil
}

pub fn wishlist_entry_detail_test() {
  use conn <- with_empty_db
  let #(_wa, wine_b) = seed_two_users(conn)
  let response =
    simulate.request(http.Get, "/wishlist/" <> wine_b)
    |> router.handle_request(
      conn,
      config.Config(..test_config, auth: auth.Single("alice")),
    )
  let assert 200 = response.status
  Nil
}

pub fn wishlist_entry_overlay_test() {
  use conn <- with_empty_db
  let #(_wa, wine_b) = seed_two_users(conn)
  let response =
    simulate.request(http.Get, "/wishlist/" <> wine_b <> "/overlay")
    |> router.handle_request(
      conn,
      config.Config(..test_config, auth: auth.Single("alice")),
    )
  let assert 200 = response.status
  Nil
}

pub fn wishlist_entry_not_found_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/wishlist/nonexistent")
    |> router.handle_request(conn, test_config)
  let assert 404 = response.status
  Nil
}

pub fn remove_requires_post_and_checks_actual_list_owner_test() {
  use conn <- with_empty_db
  let #(wine_id, _) = seed_two_users(conn)
  let id = db.create_list(conn, "alice", "Private dinner", None, False)
  db.add_wine_to_list(conn, id, wine_id, None, None)
  let base = "/~test/lists/" <> id <> "/wines"
  let get =
    simulate.request(http.Get, base <> "/" <> wine_id)
    |> router.handle_request(conn, test_config)
  let assert 405 = get.status
  let remove =
    simulate.request(http.Post, base <> "/" <> wine_id)
    |> router.handle_request(conn, test_config)
  let assert 403 = remove.status
  let toggle =
    simulate.request(http.Post, base <> "/toggle")
    |> simulate.form_body([#("wine_id", wine_id)])
    |> router.handle_request(conn, test_config)
  let assert 403 = toggle.status
  let add =
    simulate.request(http.Post, base)
    |> simulate.form_body([#("wine_id", wine_id)])
    |> router.handle_request(conn, test_config)
  let assert 403 = add.status
  let assert True = db.is_wine_in_list(conn, id, wine_id)
  Nil
}

pub fn toggle_returns_accessible_fragment_or_native_redirect_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let id = db.create_list(conn, "test", "Dinner", None, False)
  let wine_id = create_test_wine(conn, "Riesling", db.White)
  let url = "/~test/lists/" <> id <> "/wines/toggle"
  let fragment =
    simulate.request(http.Post, url)
    |> simulate.header("hx-request", "true")
    |> simulate.form_body([#("wine_id", wine_id)])
    |> router.handle_request(conn, test_config)
  let assert 200 = fragment.status
  let body = simulate.read_body(fragment)
  let assert False = string.contains(body, "aria-pressed=")
  let assert True = string.contains(body, "aria-label=\"Remove from Dinner\"")
  let native =
    simulate.request(http.Post, url)
    |> simulate.form_body([#("wine_id", wine_id)])
    |> router.handle_request(conn, test_config)
  let assert 303 = native.status
  let assert False = db.is_wine_in_list(conn, id, wine_id)
  Nil
}
