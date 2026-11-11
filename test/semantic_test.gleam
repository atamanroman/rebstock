import gleam/http
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import nakai
import nakai/attr
import nakai/html
import wisp/simulate

import rebstock/auth
import rebstock/db
import rebstock/router
import rebstock/web/components as c
import rebstock/web/shared
import test_helpers.{create_test_cellar_wine, test_config, with_empty_db}

pub fn dates_have_machine_readable_date_values_test() {
  list.each(
    ["2026-09-05", "2026-09-05 12:34:56", "2026-09-05T12:34:56Z"],
    fn(date) {
      let body = c.date_node(date) |> nakai.to_inline_string
      let assert True =
        string.contains(body, "<time datetime=\"2026-09-05\">05.09.2026</time>")
    },
  )
}

pub fn metadata_uses_description_lists_and_escapes_values_test() {
  let body =
    c.detail_grid([#("Country", "Germany"), #("Empty", ""), #("Style", "<dry>")])
    |> nakai.to_inline_string
  let assert True = string.contains(body, "<dl class=\"detail-grid\">")
  let assert True = string.contains(body, "<dt")
  let assert True = string.contains(body, "<dd")
  let assert False = string.contains(body, "Empty")
  let assert True = string.contains(body, "&lt;dry&gt;")
  Nil
}

pub fn item_lists_preserve_list_semantics_and_skip_absent_items_test() {
  let body =
    c.item_list("activity-list", [
      html.a([attr.href("/wine")], [html.Text("Wine")]),
      html.Nothing,
    ])
    |> nakai.to_inline_string
  let assert True =
    string.contains(
      body,
      "<ul class=\"item-list activity-list\" role=\"list\">",
    )
  let assert True = string.contains(body, "<li><a href=\"/wine\">Wine</a></li>")
  let assert 2 = list.length(string.split(body, "<li>"))
  Nil
}

pub fn charts_have_captions_named_links_and_equivalent_data_tables_test() {
  let side = fn(label) { c.ButterflySide(label, fn(_) { "/ratings" }) }
  let body =
    c.rating_butterfly("Distribution", "ratings", side("You"), side("Vivino"), [
      #(Some(4.0), 2, 1),
      #(None, 1, 0),
    ])
    |> nakai.to_inline_string
  let assert True = string.contains(body, "<figure class=\"rating-chart\">")
  let assert True = string.contains(body, "<figcaption")
  let assert True = string.contains(body, "aria-label=\"You 4.0 · 2 ratings\"")
  let assert True =
    string.contains(body, "aria-label=\"Vivino 4.0 · 1 rating\"")
  let assert True =
    string.contains(body, "<caption>Distribution — ratings</caption>")
  let assert True = string.contains(body, "<th scope=\"row\">Unrated</th>")
  Nil
}

pub fn standalone_forms_have_page_headings_while_dialogs_keep_h2_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let #(wine, entry) = create_test_cellar_wine(conn, "Riesling", "2023", 2)
  let base = "/wines/" <> wine <> "/riesling"
  list.each(
    [
      base <> "/cellar/new",
      base <> "/ratings/new",
      base <> "/cellar/" <> entry <> "/edit",
      base <> "/cellar/" <> entry <> "/drink",
    ],
    fn(path) {
      let body =
        simulate.request(http.Get, path)
        |> router.handle_request(conn, test_config)
        |> simulate.read_body
      let assert True = string.contains(body, "<h1")
      let assert False = string.contains(body, "<h2")
      let fragment =
        simulate.request(http.Get, path)
        |> simulate.header("hx-request", "true")
        |> router.handle_request(conn, test_config)
        |> simulate.read_body
      let assert True = string.contains(fragment, "<h2")
      let assert False = string.contains(fragment, "<h1")
    },
  )
}

pub fn field_errors_link_to_the_message_and_preserve_existing_help_test() {
  use conn <- with_empty_db
  let req = simulate.request(http.Post, "/")
  let user = auth.get_user(req, test_config.auth)
  let form =
    html.div([attr.class("form-card")], [
      c.form_title("Purchase", False),
      html.form([], [
        html.input([
          attr.name("quantity"),
          attr.Attr("aria-describedby", "quantity-help"),
        ]),
        html.p([attr.id("quantity-help")], [html.Text("Number of bottles")]),
        html.input([attr.name("price")]),
      ]),
    ])
  let body =
    c.form_error(
      req,
      conn,
      user,
      form,
      [#("quantity", "0")],
      ["quantity"],
      "Quantity must be at least 1",
    )
    |> simulate.read_body
  let assert True = string.contains(body, "id=\"validation-quantity\"")
  let assert True =
    string.contains(
      body,
      "aria-invalid=\"true\" aria-describedby=\"quantity-help validation-quantity\"",
    )
  let assert True =
    string.contains(body, "<form aria-describedby=\"validation-quantity\">")
  let assert 2 = list.length(string.split(body, "aria-invalid="))
  let assert True = string.contains(body, ">Purchase</h1>")
  Nil
}

pub fn server_rating_errors_identify_only_the_invalid_rating_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let #(wine, _) = create_test_cellar_wine(conn, "Riesling", "2023", 1)
  let body =
    simulate.request(http.Post, "/wines/" <> wine <> "/riesling/ratings/new")
    |> simulate.header("hx-request", "true")
    |> simulate.form_body([#("rating", "6"), #("vintage", "2023")])
    |> router.handle_request(conn, test_config)
    |> simulate.read_body
  let assert True =
    string.contains(
      body,
      "aria-invalid=\"true\" aria-describedby=\"validation-rating\"",
    )
  let assert True = string.contains(body, "id=\"validation-rating\"")
  let assert 2 = list.length(string.split(body, "aria-invalid="))
  Nil
}

pub fn shared_menus_and_not_found_pages_have_native_landmarks_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let #(wine, _) = create_test_cellar_wine(conn, "Riesling", "2023", 1)
  let id = db.create_list(conn, "test", "Dinner", None, False)
  db.add_wine_to_list(conn, id, wine, Some("2023"), None)
  db.set_list_public(conn, id, True)
  let body = shared.shared_list(conn, id) |> simulate.read_body
  let assert True = string.contains(body, "<main><header")
  let assert True = string.contains(body, "<section class=\"wine-section\"><h2")
  let assert True =
    string.contains(body, "<ul class=\"wine-items\" role=\"list\"><li")
  let assert True = string.contains(body, "<footer class=\"menu-footer\">")
  db.set_list_public(conn, id, False)
  let missing = shared.shared_list(conn, id) |> simulate.read_body
  let assert True = string.contains(missing, "<main")
  let assert True = string.contains(missing, "<h1")
  Nil
}

pub fn other_users_notes_use_blockquotes_with_separate_attribution_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  db.ensure_user(conn, "other")
  let #(wine, _) = create_test_cellar_wine(conn, "Riesling", "2023", 1)
  db.insert_rating(
    conn,
    username: "other",
    wine_id: wine,
    vintage: Some("2023"),
    rating: Some(4.2),
    tasting_notes: Some("Lemon & slate"),
    rated_at: Some("2026-09-05"),
  )
  let body =
    simulate.request(http.Get, "/wines/" <> wine <> "/riesling")
    |> router.handle_request(conn, test_config)
    |> simulate.read_body
  let assert True = string.contains(body, "<blockquote")
  let assert True =
    string.contains(body, "<p>Lemon &amp; slate</p></blockquote>")
  let assert True = string.contains(body, "href=\"/~other/ratings\"")
  let assert True = string.contains(body, ">Others</h3>")
  let assert True = string.contains(body, ">Ratings</h2>")
  Nil
}

pub fn action_columns_have_a_nonvisual_header_test() {
  let body = c.table(["Wine", ""], []) |> nakai.to_inline_string
  let assert True =
    string.contains(body, "<span class=\"sr-only\">Actions</span>")
  Nil
}
