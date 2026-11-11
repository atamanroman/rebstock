import gleam/http
import gleam/http/response
import gleam/option.{None, Some}
import gleam/string
import wisp/simulate

import rebstock/db
import rebstock/router
import rebstock/web/components as c
import test_helpers.{test_config, with_empty_db, with_seeded_db}

pub fn existing_users_have_default_profiles_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let assert Ok(db.Profile("test", None, None)) = db.get_profile(conn, "test")
  let assert Error(Nil) = db.get_profile(conn, "missing")
  Nil
}

pub fn profiles_are_persistent_and_user_scoped_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "alice")
  db.ensure_user(conn, "bob")
  db.update_profile(conn, "alice", "Alice Wine", Some("picture.png"))
  db.ensure_user(conn, "alice")
  let assert Ok(db.Profile("alice", Some("Alice Wine"), Some("picture.png"))) =
    db.get_profile(conn, "alice")
  let assert Ok(db.Profile("bob", None, None)) = db.get_profile(conn, "bob")
  Nil
}

pub fn settings_menu_links_are_distinct_test() {
  use conn <- with_empty_db
  let body =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_config)
    |> simulate.read_body
  let assert True = string.contains(body, "href=\"/settings\">Settings</a>")
  let assert True = string.contains(body, "href=\"/~test\">Your profile</a>")
  let assert "/~alice%20smith" = c.profile_url("alice smith")
  Nil
}

pub fn settings_form_has_native_labels_and_limits_test() {
  use conn <- with_empty_db
  let res =
    simulate.request(http.Get, "/settings")
    |> router.handle_request(conn, test_config)
  let assert 200 = res.status
  let body = simulate.read_body(res)
  let assert True = string.contains(body, ">Settings</h1>")
  let assert True = string.contains(body, "for=\"profile-name\"")
  let assert True = string.contains(body, "Display name")
  let assert True = string.contains(body, "placeholder=\"test\"")
  let assert True = string.contains(body, "name=\"display_name\" value=\"\"")
  let assert True =
    string.contains(body, "id=\"profile-username\" value=\"test\" readonly")
  let assert True =
    string.contains(body, "Provided by authentication. Cannot be changed here.")
  let assert True = string.contains(body, "for=\"profile-picture\"")
  let assert True = string.contains(body, "enctype=\"multipart/form-data\"")
  let assert True = string.contains(body, "maxlength=\"100\"")
  let assert True = string.contains(body, "profile-picture-placeholder")
  Nil
}

pub fn saving_updates_only_the_authenticated_user_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "other")
  let res =
    simulate.request(http.Post, "/settings")
    |> simulate.form_body([
      #("display_name", "  Wine Person  "),
      #("username", "other"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 303 = res.status
  let assert Ok("/settings?saved=1") = response.get_header(res, "location")
  let assert Ok(db.Profile("test", Some("Wine Person"), None)) =
    db.get_profile(conn, "test")
  let assert Ok(db.Profile("other", None, None)) = db.get_profile(conn, "other")
  let public =
    simulate.request(http.Get, "/~test")
    |> router.handle_request(conn, test_config)
    |> simulate.read_body
  let assert True = string.contains(public, "<h1>Wine Person</h1>")
  let assert True = string.contains(public, "profile-picture-placeholder")
  Nil
}

pub fn clearing_the_display_name_restores_username_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.update_profile(conn, "test", "Original", Some("picture.png"))
  let res =
    simulate.request(http.Post, "/settings")
    |> simulate.form_body([#("display_name", "   ")])
    |> router.handle_request(conn, test_config)
  let assert 303 = res.status
  let assert Ok(db.Profile("test", None, Some("picture.png"))) =
    db.get_profile(conn, "test")
  let public =
    simulate.request(http.Get, "/~test")
    |> router.handle_request(conn, test_config)
    |> simulate.read_body
  let assert True = string.contains(public, "<h1>test</h1>")
  Nil
}

pub fn invalid_names_preserve_the_profile_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.update_profile(conn, "test", "Original", None)
  let too_long = string.repeat("a", 101)
  let res =
    simulate.request(http.Post, "/settings")
    |> simulate.form_body([#("display_name", too_long)])
    |> router.handle_request(conn, test_config)
  let assert 422 = res.status
  let body = simulate.read_body(res)
  let assert True = string.contains(body, "aria-invalid=\"true\"")
  let assert True = string.contains(body, "validation-display_name")
  let assert Ok(db.Profile("test", Some("Original"), None)) =
    db.get_profile(conn, "test")
  let assert True = string.contains(body, "value=\"" <> too_long <> "\"")
  let assert Ok(db.Profile("test", Some("Original"), None)) =
    db.get_profile(conn, "test")
  Nil
}

pub fn public_profile_escapes_names_and_has_no_home_picture_test() {
  use conn <- with_seeded_db
  db.update_profile(conn, "test", "Test", Some("own.png"))
  db.ensure_user(conn, "other")
  db.update_profile(
    conn,
    "other",
    "Alice <script>test</script>",
    Some("example.png"),
  )
  let public =
    simulate.request(http.Get, "/~other")
    |> router.handle_request(conn, test_config)
    |> simulate.read_body
  let assert True =
    string.contains(public, "Alice &lt;script&gt;test&lt;/script&gt;")
  let assert False = string.contains(public, "<script>test</script>")
  let assert True = string.contains(public, "/images/profiles/example.png")
  let assert True = string.contains(public, "~other")
  let home =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_config)
    |> simulate.read_body
  let assert False = string.contains(home, "profile-picture")
  let assert True =
    string.contains(
      home,
      "src=\"/images/profiles/own.png\" class=\"user-avatar\"",
    )
  let assert False = string.contains(home, "/images/profiles/example.png")
  let assert True =
    string.contains(
      public,
      "src=\"/images/profiles/own.png\" class=\"user-avatar\"",
    )
  Nil
}

pub fn missing_profiles_and_invalid_methods_test() {
  use conn <- with_empty_db
  let res =
    simulate.request(http.Get, "/~missing")
    |> router.handle_request(conn, test_config)
  let assert 404 = res.status
  let res =
    simulate.request(http.Post, "/~test")
    |> router.handle_request(conn, test_config)
  let assert 405 = res.status
  let res =
    simulate.request(http.Put, "/settings")
    |> router.handle_request(conn, test_config)
  let assert 405 = res.status
  let res =
    simulate.request(http.Post, "/~other/settings")
    |> router.handle_request(conn, test_config)
  let assert 404 = res.status
  Nil
}

pub fn cross_origin_settings_posts_are_rejected_test() {
  use conn <- with_empty_db
  let res =
    simulate.request(http.Post, "/settings")
    |> simulate.header("origin", "https://attacker.example")
    |> simulate.form_body([#("display_name", "Unwanted")])
    |> router.handle_request(conn, test_config)
  let assert 403 = res.status
  Nil
}
