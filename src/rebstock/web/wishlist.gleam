import gleam/int
import gleam/list
import gleam/option.{None, Some}
import nakai/attr
import nakai/html
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/auth.{type User}
import rebstock/db.{type Wine, type WishlistEntry, type WishlistWine}
import rebstock/web/components as c

pub fn wishlist(conn: Connection, user: User, username: String) -> Response {
  let wines = db.wishlist_wines(conn, username)
  let count = int.to_string(list.length(wines))

  c.page("Wishlist \u{2014} Rebstock", user, [
    c.page_header("Wishlist", count <> " wines"),
    wishlist_table(wines),
  ])
}

pub fn wishlist_entry_detail(
  conn: Connection,
  id: String,
  user: User,
) -> Response {
  case db.get_wishlist_entry_by_id(conn, id) {
    Error(_) -> c.not_found(user)
    Ok(entry) ->
      case db.get_wine_by_id(conn, entry.wine_id) {
        Error(_) -> c.not_found(user)
        Ok(wine) ->
          c.page(wine.name <> " Wishlist \u{2014} Rebstock", user, [
            c.back_link(c.wine_url(wine), wine.name),
            wishlist_entry_card(entry, wine),
          ])
      }
  }
}

pub fn wishlist_entry_overlay(conn: Connection, id: String) -> Response {
  case db.get_wishlist_entry_by_id(conn, id) {
    Error(_) -> wisp.not_found()
    Ok(entry) ->
      case db.get_wine_by_id(conn, entry.wine_id) {
        Error(_) -> wisp.not_found()
        Ok(wine) -> c.overlay_wrapper(wishlist_entry_card(entry, wine))
      }
  }
}

fn wishlist_entry_card(entry: WishlistEntry, wine: Wine) -> html.Node {
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
          html.Text(case entry.vintage {
            None -> ""
            Some(_) -> " \u{00b7} " <> c.display_vintage(entry.vintage)
          }),
        ]),
      ]),
      c.wine_type_badge(wine.wine_type),
    ]),
    html.p([attr.class("text-sm text-stone-500 mb-4")], [
      c.date_node(entry.created_at),
    ]),
    case entry.notes {
      Some(notes) ->
        html.div([attr.class("mt-4 pt-4 border-t border-stone-100")], [
          html.p([attr.class("text-stone-700 whitespace-pre-line")], [
            html.Text(notes),
          ]),
        ])
      None -> html.Nothing
    },
  ])
}

fn wishlist_table(wines: List(WishlistWine)) -> html.Node {
  c.table(
    ["Winery", "Wine", "Vintage", "Country", "Type", "Notes"],
    list.index_map(wines, wishlist_row),
  )
}

fn wishlist_row(ww: WishlistWine, idx: Int) -> html.Node {
  let wine = ww.wine
  html.tr(
    [
      attr.id("wine-" <> wine.id),
      attr.class(c.clickable_row_class(idx) <> " target-highlight"),
      attr.Attr("hx-get", "/wishlist/" <> ww.id <> "/overlay"),
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
        html.Text(c.display_optional(ww.notes)),
      ]),
    ],
  )
}
