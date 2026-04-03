import gleam/int
import gleam/list
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/auth.{type User}
import rebstock/db.{type Winery}
import rebstock/web/components as c
import rebstock/web/wines

pub fn wineries(conn: Connection, user: User) -> Response {
  let winery_list = db.list_wineries(conn, user.username)
  let count = int.to_string(list.length(winery_list))

  c.page("Wineries \u{2014} Rebstock", user, [
    c.page_header("Wineries", count <> " total"),
    c.table(
      ["Winery", "Country", "Wines"],
      list.index_map(winery_list, winery_row),
    ),
  ])
}

pub fn winery_detail(conn: Connection, id: String, user: User) -> Response {
  case db.get_winery(conn, user.username, id) {
    Error(_) -> c.not_found(user)
    Ok(winery) -> {
      let winery_wines = db.wines_by_winery(conn, user.username, id)
      let display = c.display_winery(winery.name)
      c.page(display <> " \u{2014} Rebstock", user, [
        c.back_link("/wineries", "All wineries"),
        c.page_header(display, int.to_string(winery.wine_count) <> " wines"),
        wines.wine_table(winery_wines),
      ])
    }
  }
}

fn winery_row(winery: Winery, idx: Int) -> Node {
  html.tr([attr.class(c.row_class(idx))], [
    html.td([attr.class("px-4 py-3 font-medium text-stone-800")], [
      c.link(c.winery_url(winery.id, winery.name), [
        html.Text(c.display_winery(winery.name)),
      ]),
    ]),
    html.td([attr.class("px-4 py-3 text-stone-600")], [
      html.Text(c.display_country(winery.country)),
    ]),
    html.td([attr.class("px-4 py-3 tabular-nums text-stone-600")], [
      html.Text(int.to_string(winery.wine_count)),
    ]),
  ])
}
