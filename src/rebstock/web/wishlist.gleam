import gleam/int
import gleam/list
import nakai/attr
import nakai/html
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/auth.{type User}
import rebstock/db.{type ListWine, type Wine}
import rebstock/web/components as c

pub fn wishlist(conn: Connection, user: User, username: String) -> Response {
  let wl = db.get_user_wishlist(conn, username)
  let wines = db.list_wines_for_list(conn, wl.id)
  let count = int.to_string(list.length(wines))

  c.page("Wishlist \u{2014} Rebstock", user, conn, [
    c.page_header("Wishlist", count <> " wines"),
    wishlist_table(wines),
  ])
}

pub fn wishlist_entry_detail(
  conn: Connection,
  id: String,
  user: User,
) -> Response {
  case db.get_wine_by_id(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(wine) ->
      c.page(wine.name <> " Wishlist \u{2014} Rebstock", user, conn, [
        c.back_link(c.wine_url(wine), wine.name),
        wishlist_wine_card(wine),
      ])
  }
}

pub fn wishlist_entry_overlay(conn: Connection, id: String) -> Response {
  case db.get_wine_by_id(conn, id) {
    Error(_) -> wisp.not_found()
    Ok(wine) -> c.overlay_wrapper(wishlist_wine_card(wine))
  }
}

fn wishlist_wine_card(wine: Wine) -> html.Node {
  c.card([
    html.div([attr.class("flex items-start justify-between mb-2")], [
      html.div([], [
        html.h1([attr.class("text-2xl font-light text-stone-800")], [
          c.link(c.wine_url(wine), [html.Text(wine.name)]),
        ]),
        html.p([attr.class("text-stone-500 mt-1")], [
          c.link(c.winery_url(wine.winery_id, wine.winery_name), [
            html.Text(c.display_winery(wine.winery_name)),
          ]),
        ]),
      ]),
      c.wine_type_badge(wine.wine_type),
    ]),
  ])
}

fn wishlist_table(wines: List(ListWine)) -> html.Node {
  c.table(
    ["Winery", "Wine", "Vintage", "Country", "Type", "Notes"],
    list.index_map(wines, wishlist_row),
  )
}

fn wishlist_row(lw: ListWine, idx: Int) -> html.Node {
  let wine = lw.wine
  html.tr(
    [
      attr.id("wine-" <> wine.id),
      attr.class(c.clickable_row_class(idx) <> " target-highlight"),
      attr.Attr("hx-get", "/wishlist/" <> wine.id <> "/overlay"),
      attr.Attr("hx-target", "#overlay"),
      attr.Attr("hx-swap", "outerHTML"),
    ],
    [
      html.td([attr.class("px-4 py-3 text-stone-700")], [
        c.link_stop(c.winery_url(wine.winery_id, wine.winery_name), [
          html.Text(c.display_winery(wine.winery_name)),
        ]),
      ]),
      html.td([attr.class("px-4 py-3 font-medium text-stone-800")], [
        c.link_stop(c.wine_url(wine), [html.Text(wine.name)]),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-500 tabular-nums")], [
        html.Text(c.display_vintages(wine.vintages)),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(c.display_country(wine.country)),
      ]),
      html.td([attr.class("px-4 py-3")], [c.wine_type_badge(wine.wine_type)]),
      html.td([attr.class("px-4 py-3 text-stone-600 max-w-xs truncate")], [
        html.Text(c.display_optional(lw.notes)),
      ]),
    ],
  )
}
