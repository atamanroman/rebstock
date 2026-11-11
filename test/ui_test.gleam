import gleam/http
import gleam/http/response
import gleam/string
import nakai
import nakai/attr
import nakai/html
import wisp/simulate

import rebstock/auth
import rebstock/db
import rebstock/router
import rebstock/web/components as c
import test_helpers.{create_test_cellar_wine, test_config, with_empty_db}

pub fn responsive_table_preserves_links_and_labels_test() {
  let table =
    c.table(["Wine", "Bottles", ""], [
      html.tr([attr.id("wine-1"), attr.Attr("hx-get", "/wines/1/overlay")], [
        html.td([], [c.link("/wines/1", [html.Text("Riesling")])]),
        html.td([], [html.Text("6")]),
        html.td([], [html.button([], [html.Text("Remove")])]),
      ]),
      html.Nothing,
    ])
    |> nakai.to_inline_string
  let assert True = string.contains(table, "data-label=\"Wine\"")
  let assert True = string.contains(table, "data-label=\"Bottles\"")
  let assert True = string.contains(table, "data-label=\"\"")
  let assert True = string.contains(table, "scope=\"col\"")
  let assert True = string.contains(table, "role=\"table\"")
  let assert True = string.contains(table, "role=\"row\"")
  let assert True = string.contains(table, "role=\"cell\"")
  let assert True = string.contains(table, "hx-get=\"/wines/1/overlay\"")
  let assert True = string.contains(table, "href=\"/wines/1\"")
  let assert True = string.contains(table, "Remove")
  Nil
}

pub fn responsive_table_escapes_labels_test() {
  let table =
    c.table(["Wine \"<script>\""], [html.tr([], [html.td([], [])])])
    |> nakai.to_inline_string
  let assert False = string.contains(table, "<script>")
  let assert True = string.contains(table, "&lt;script&gt;")
  Nil
}

pub fn layout_has_ledger_and_accessible_navigation_test() {
  use conn <- with_empty_db
  let body =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_config)
    |> simulate.read_body
  let assert True = string.contains(body, "data-ui=\"ledger\"")
  let assert True = string.contains(body, "brand-mark")
  let assert True = string.contains(body, "src=\"/static/grapevine.svg\"")
  let assert False = string.contains(body, "brand-description")
  let assert False = string.contains(body, "data-ui-choice")
  let assert True = string.contains(body, "aria-label=\"Main navigation\"")
  let assert True = string.contains(body, "Skip to content")
  let assert True = string.contains(body, "<main")
  let assert True = string.contains(body, "/static/js/ui.js")
  let assert True =
    string.contains(
      body,
      "<footer class=\"site-footer\"><hr class=\"section-divider\"",
    )
  let assert True = string.contains(body, "Add your first wine")
  Nil
}

pub fn wine_types_use_semantic_labels_without_utility_badges_test() {
  let badge = c.wine_type_badge(db.White) |> nakai.to_inline_string
  let assert True =
    string.contains(badge, "class=\"wine-type wine-type-white\"")
  let assert True = string.contains(badge, ">White</span>")
  let assert False = string.contains(badge, "bg-")
  let assert False = string.contains(badge, "rounded")
  Nil
}

pub fn dashboard_uses_compact_stats_and_visible_insights_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let _ = create_test_cellar_wine(conn, "Riesling", "2023", 6)
  let body =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_config)
    |> simulate.read_body
  let assert True = string.contains(body, "Your collection")
  let assert True = string.contains(body, "Bottles in cellar")
  let assert True = string.contains(body, "Wines in cellar")
  let assert True = string.contains(body, "Wines tasted")
  let assert True =
    string.contains(
      body,
      "<section class=\"rating-insights\"><hr class=\"section-divider\"",
    )
  let assert [before_activity, ..] = string.split(body, "Recently cellared")
  let assert True = string.contains(before_activity, "Rating insights")
  let assert True = string.contains(body, "collection-highlights activity-grid")
  let assert True = string.contains(body, "Cellar highlights")
  let assert False = string.contains(body, "<summary>Rating insights")
  let assert False = string.contains(body, "<summary>Collection highlights")
  Nil
}

pub fn cellar_rows_expose_mobile_bottle_and_value_labels_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let _ = create_test_cellar_wine(conn, "Riesling", "2023", 6)
  let body =
    simulate.request(http.Get, "/~test/cellar")
    |> router.handle_request(conn, test_config)
    |> simulate.read_body
  let assert True = string.contains(body, "data-label=\"Bottles\"")
  let assert True = string.contains(body, "data-label=\"Value\"")
  let assert True = string.contains(body, "aria-label=\"Filter wines")
  Nil
}

pub fn overlay_has_named_dialog_and_close_control_test() {
  let body =
    c.overlay_wrapper(c.card([html.Text("Wine")])) |> simulate.read_body
  let assert True = string.contains(body, "role=\"dialog\"")
  let assert True = string.contains(body, "aria-modal=\"true\"")
  let assert True = string.contains(body, "aria-label=\"Close dialog\"")
  let assert True = string.contains(body, "overlay-panel")
  Nil
}

pub fn fragment_detection_excludes_full_navigation_and_history_test() {
  let request = simulate.request(http.Get, "/")
  let assert False = c.is_fragment(request)
  let partial = request |> simulate.header("hx-request", "true")
  let assert True = c.is_fragment(partial)
  let assert False =
    partial
    |> simulate.header("hx-request-type", "full")
    |> c.is_fragment
  let assert False =
    partial
    |> simulate.header("hx-history-restore-request", "true")
    |> c.is_fragment
  Nil
}

pub fn redirect_uses_canonical_replace_url_or_native_prg_test() {
  let request = simulate.request(http.Post, "/")
  let native = c.redirect(request, "/wines/123/riesling")
  let assert 303 = native.status
  let assert Ok("/wines/123/riesling") = response.get_header(native, "location")
  let enhanced =
    request
    |> simulate.header("hx-request", "true")
    |> c.redirect("/wines/123/riesling")
  let assert 200 = enhanced.status
  let assert Ok(location) = response.get_header(enhanced, "hx-location")
  let assert True =
    string.contains(location, "\"replace\":\"/wines/123/riesling\"")
  Nil
}

pub fn form_page_and_fragment_have_distinct_cache_variants_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let #(wine_id, _) = create_test_cellar_wine(conn, "Riesling", "2023", 1)
  let url = "/wines/" <> wine_id <> "/riesling/cellar/new"
  let partial =
    simulate.request(http.Get, url)
    |> simulate.header("hx-request", "true")
    |> router.handle_request(conn, test_config)
  let assert Ok("HX-Request, HX-Request-Type, HX-History-Restore-Request") =
    response.get_header(partial, "vary")
  let assert True =
    string.contains(simulate.read_body(partial), "role=\"dialog\"")
  let full =
    simulate.request(http.Get, url)
    |> simulate.header("hx-request", "true")
    |> simulate.header("hx-request-type", "full")
    |> router.handle_request(conn, test_config)
    |> simulate.read_body
  let assert True = string.contains(full, "<main")
  let assert False = string.contains(full, "role=\"dialog\"")
  let assert True = string.contains(full, "for=\"cellar-vintage\"")
  let assert True = string.contains(full, "id=\"cellar-vintage\"")
  Nil
}

pub fn optional_table_cells_do_not_shift_mobile_labels_test() {
  let table =
    c.table(["Wine", ""], [
      html.tr([], [
        html.td([], [html.Text("Riesling")]),
        html.Nothing,
        html.td([], [html.Text("Remove")]),
      ]),
    ])
    |> nakai.to_inline_string
  let assert True =
    string.contains(table, "data-label=\"\" role=\"cell\">Remove</td>")
  Nil
}

pub fn validation_preserves_native_fields_and_checkbox_state_test() {
  use conn <- with_empty_db
  let req = simulate.request(http.Post, "/")
  let user = auth.get_user(req, test_config.auth)
  let form =
    c.card([
      html.input([attr.name("quantity"), attr.value("1")]),
      html.input([
        attr.type_("checkbox"),
        attr.name("rate"),
        attr.value("on"),
      ]),
      html.textarea([attr.name("notes")], []),
    ])
  let rendered =
    c.form_error(
      req,
      conn,
      user,
      form,
      [#("quantity", "0"), #("notes", "Keep <&>"), #("rate", "on")],
      ["quantity"],
      "Check quantity",
    )
  let assert 422 = rendered.status
  let body = simulate.read_body(rendered)
  let assert True = string.contains(body, "<main")
  let assert True = string.contains(body, "value=\"0\"")
  let assert True = string.contains(body, "checked=\"\"")
  let assert True = string.contains(body, "Keep &lt;&amp;&gt;")
  let assert True = string.contains(body, "role=\"alert\"")
  let unchecked =
    c.form_error(req, conn, user, form, [], ["quantity"], "Check quantity")
    |> simulate.read_body
  let assert False = string.contains(unchecked, "checked=")
  Nil
}

pub fn invalid_rating_keeps_form_without_mutating_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let #(wine_id, _) = create_test_cellar_wine(conn, "Riesling", "2023", 1)
  let response =
    simulate.request(http.Post, "/wines/" <> wine_id <> "/riesling/ratings/new")
    |> simulate.header("hx-request", "true")
    |> simulate.form_body([
      #("rating", "6"),
      #("vintage", "2023"),
      #("tasting_notes", "Keep this note"),
    ])
    |> router.handle_request(conn, test_config)
  let assert 422 = response.status
  let body = simulate.read_body(response)
  let assert False = string.contains(body, "<main")
  let assert True = string.contains(body, "Keep this note")
  let assert True = string.contains(body, "value=\"6\"")
  let assert [] = db.ratings_for_wine(conn, wine_id)
  Nil
}
