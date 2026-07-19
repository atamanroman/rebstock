import gleam/int
import gleam/list
import gleam/option.{None, Some}
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type User}
import rebstock/db.{type Winery}
import rebstock/web/components as c
import rebstock/web/wines

pub fn wineries(conn: Connection, user: User) -> Response {
  let winery_list = db.list_wineries(conn)
  let count = int.to_string(list.length(winery_list))

  c.page("Wineries \u{2014} Rebstock", user, conn, [
    html.div([attr.class("flex items-end justify-between mb-6")], [
      c.page_header("Wineries", count <> " total"),
      html.a(
        [
          attr.href("/wineries/new"),
          attr.class(
            "px-4 py-2 bg-rose-800 text-white rounded-lg text-sm hover:bg-rose-900 transition-colors",
          ),
        ],
        [html.Text("Add Winery")],
      ),
    ]),
    c.table_filter("wineries-table", "Filter wineries\u{2026}"),
    html.div([attr.id("wineries-table")], [
      c.table(
        ["Winery", "Country", "Wines"],
        list.index_map(winery_list, winery_row),
      ),
    ]),
  ])
}

pub fn winery_detail(conn: Connection, id: String, user: User) -> Response {
  case db.get_winery(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(winery) -> {
      let winery_wines = db.wines_by_winery(conn, user.username, id)
      let display = c.display_winery(winery.name)
      c.page(display <> " \u{2014} Rebstock", user, conn, [
        c.back_link("/wineries", "All wineries"),
        html.div([attr.class("flex items-end justify-between mb-6")], [
          c.page_header(display, int.to_string(winery.wine_count) <> " wines"),
          html.div([attr.class("flex items-center gap-2")], [
            html.a(
              [
                attr.href("/wines/new?winery=" <> winery.name),
                attr.class(
                  "px-4 py-2 bg-rose-800 text-white rounded-lg text-sm hover:bg-rose-900 transition-colors",
                ),
              ],
              [html.Text("Add Wine")],
            ),
            case winery.created_by == user.username {
              False -> html.Nothing
              True ->
                html.a(
                  [
                    attr.href("/wineries/" <> winery.id <> "/edit"),
                    attr.class(
                      "px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors",
                    ),
                  ],
                  [html.Text("Edit")],
                )
            },
          ]),
        ]),
        wines.wine_table(winery_wines),
      ])
    }
  }
}

pub fn new_winery_form(conn: Connection, user: User) -> Response {
  c.page("Add Winery \u{2014} Rebstock", user, conn, [
    c.back_link("/wineries", "Wineries"),
    html.div([attr.class("max-w-lg")], [
      html.h1([attr.class("text-3xl font-light text-stone-800 mb-6")], [
        html.Text("Add Winery"),
      ]),
      winery_form(None, "/wineries", "Add Winery"),
    ]),
  ])
}

pub fn create_winery(req: Request, conn: Connection, user: User) -> Response {
  use form <- wisp.require_form(req)
  case list.key_find(form.values, "name") {
    Error(_) | Ok("") -> wisp.redirect("/wineries/new")
    Ok(name) -> {
      let country = wines.opt_val(form, "country")
      let vivino_id = wines.opt_val(form, "vivino_id")
      let id = db.upsert_winery(conn, user.username, name, country, vivino_id)
      wisp.redirect("/wineries/" <> id)
    }
  }
}

pub fn edit_winery_form(conn: Connection, id: String, user: User) -> Response {
  case db.get_winery(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(winery) if winery.created_by != user.username -> wisp.response(403)
    Ok(winery) -> {
      c.page("Edit " <> winery.name <> " \u{2014} Rebstock", user, conn, [
        c.back_link("/wineries/" <> id, winery.name),
        html.div([attr.class("max-w-lg")], [
          html.h1([attr.class("text-3xl font-light text-stone-800 mb-6")], [
            html.Text("Edit Winery"),
          ]),
          winery_form(Some(winery), "/wineries/" <> id <> "/edit", "Update"),
        ]),
      ])
    }
  }
}

pub fn handle_edit_winery(
  req: Request,
  conn: Connection,
  id: String,
  user: User,
) -> Response {
  case db.get_winery(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(winery) if winery.created_by != user.username -> wisp.response(403)
    Ok(_) -> {
      use form <- wisp.require_form(req)
      case list.key_find(form.values, "name") {
        Error(_) | Ok("") -> wisp.redirect("/wineries/" <> id <> "/edit")
        Ok(name) -> {
          let country = wines.opt_val(form, "country")
          let vivino_id = wines.opt_val(form, "vivino_id")
          db.update_winery(conn, id, name, country, vivino_id)
          wisp.redirect("/wineries/" <> id)
        }
      }
    }
  }
}

fn winery_form(
  existing: option.Option(Winery),
  action: String,
  submit_label: String,
) -> Node {
  let name_val = case existing {
    Some(w) -> w.name
    None -> ""
  }
  let country_val = case existing {
    Some(w) -> w.country
    None -> None
  }
  let vivino_id_val = case existing {
    Some(w) ->
      case w.vivino_id {
        Some(v) -> v
        None -> ""
      }
    None -> ""
  }
  html.Element(
    "form",
    [
      attr.method("post"),
      attr.Attr("action", action),
      attr.class("space-y-4"),
    ],
    [
      c.form_field("Name", True, [
        html.Element(
          "input",
          [
            attr.type_("text"),
            attr.name("name"),
            attr.Attr("required", ""),
            attr.Attr("autofocus", ""),
            attr.value(name_val),
            attr.class(c.input_class),
          ],
          [],
        ),
      ]),
      c.form_field("Country", False, [
        c.country_input("country", country_val, c.input_class),
      ]),
      c.form_field("Vivino ID", False, [
        html.Element(
          "input",
          [
            attr.type_("text"),
            attr.name("vivino_id"),
            attr.value(vivino_id_val),
            attr.Attr("placeholder", "e.g. 12345"),
            attr.class(c.input_class),
          ],
          [],
        ),
      ]),
      html.div([attr.class("flex gap-3")], [
        html.Element(
          "button",
          [
            attr.type_("submit"),
            attr.class(
              "px-4 py-2 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors",
            ),
          ],
          [html.Text(submit_label)],
        ),
      ]),
    ],
  )
}

fn winery_row(winery: Winery, idx: Int) -> Node {
  html.tr(
    [
      attr.class(c.clickable_row_class(idx)),
      attr.Attr(
        "onclick",
        "window.location='" <> c.winery_url(winery.id, winery.name) <> "'",
      ),
    ],
    [
      html.td([attr.class("px-4 py-3 font-medium text-stone-800")], [
        c.link_stop(c.winery_url(winery.id, winery.name), [
          html.Text(c.display_winery(winery.name)),
        ]),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(c.display_country(winery.country)),
      ]),
      html.td([attr.class("px-4 py-3 tabular-nums text-stone-600")], [
        html.Text(int.to_string(winery.wine_count)),
      ]),
    ],
  )
}
