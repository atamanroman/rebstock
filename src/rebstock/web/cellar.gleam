import gleam/bytes_tree
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import nakai/attr
import nakai/html
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/auth.{type User}
import rebstock/db.{type CellarEntry, type CellarWine, type Wine}
import rebstock/web/components as c

pub fn cellar(conn: Connection, user: User, username: String) -> Response {
  let wines = db.cellar_wines(conn, username)
  let total_bottles = list.fold(wines, 0, fn(acc, cw) { acc + cw.bottles })

  c.page("Cellar \u{2014} Rebstock", user, [
    html.div([attr.class("flex items-end justify-between mb-6")], [
      html.div([], [
        html.h1(
          [attr.class("text-3xl font-light text-stone-800 tracking-tight")],
          [html.Text("Cellar")],
        ),
        html.p([attr.class("text-stone-500 mt-1")], [
          html.Text(int.to_string(total_bottles) <> " bottles"),
        ]),
      ]),
      html.div([attr.class("flex gap-2")], [
        html.a(
          [
            attr.href("/~" <> username <> "/cellar/export.csv"),
            attr.class(
              "px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors",
            ),
          ],
          [html.Text("Export CSV")],
        ),
        html.a(
          [
            attr.href("/~" <> username <> "/cellar/print"),
            attr.class(
              "px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors",
            ),
          ],
          [html.Text("Wine List")],
        ),
      ]),
    ]),
    cellar_wine_table(wines),
  ])
}

pub fn cellar_print(conn: Connection, _user: User, username: String) -> Response {
  let wines = db.cellar_wines_by_type(conn, username)
  let total_bottles = list.fold(wines, 0, fn(acc, cw) { acc + cw.bottles })

  let grouped =
    list.chunk(wines, fn(cw) { cw.wine.wine_type })
    |> list.flat_map(fn(group) {
      case group {
        [first, ..] -> [
          html.h2([attr.class("cellar-type-heading")], [
            html.Text(c.wine_type_label(first.wine.wine_type)),
          ]),
          cellar_wine_table(group),
        ]
        _ -> []
      }
    })

  c.layout("Cellar Inventory \u{2014} Rebstock", [
    html.div([attr.class("cellar-print-page")], [
      html.div([attr.class("print-header")], [
        html.div([attr.class("flex items-center gap-3")], [
          html.UnsafeInlineHtml(logo_svg()),
          html.span([attr.class("text-xl font-light tracking-tight")], [
            html.Text("Rebstock"),
          ]),
        ]),
        html.h1([attr.class("text-2xl font-light mt-4 mb-1")], [
          html.Text("Cellar Inventory"),
        ]),
        html.p([attr.class("text-sm text-stone-500")], [
          html.Text(int.to_string(total_bottles) <> " bottles"),
        ]),
      ]),
      ..grouped
    ]),
  ])
  |> c.render
}

pub fn cellar_csv(conn: Connection, _user: User, username: String) -> Response {
  let wines = db.cellar_wines(conn, username)
  let header = "Winery,Wine,Vintage,Country,Type,Bottles"
  let rows =
    list.map(wines, fn(cw) {
      [
        csv_field(cw.wine.winery_name),
        csv_field(cw.wine.name),
        c.display_vintage(cw.vintage),
        csv_field(c.display_country(cw.wine.country)),
        db.wine_type_to_string(cw.wine.wine_type),
        int.to_string(cw.bottles),
      ]
      |> string.join(",")
    })
  let csv = [header, ..rows] |> string.join("\n")
  wisp.response(200)
  |> wisp.file_download_from_memory(
    named: "cellar.csv",
    containing: bytes_tree.from_string(csv),
  )
}

pub fn cellar_entry_detail(conn: Connection, id: String, user: User) -> Response {
  case db.get_cellar_entry_by_id(conn, id) {
    Error(_) -> wisp.not_found()
    Ok(entry) ->
      case db.get_wine_by_id(conn, entry.wine_id) {
        Error(_) -> wisp.not_found()
        Ok(wine) ->
          c.page(wine.name <> " Cellar Entry \u{2014} Rebstock", user, [
            c.back_link(c.wine_url(wine), wine.name),
            cellar_entry_card(entry, wine),
          ])
      }
  }
}

pub fn cellar_entry_overlay(conn: Connection, id: String) -> Response {
  case db.get_cellar_entry_by_id(conn, id) {
    Error(_) -> wisp.not_found()
    Ok(entry) ->
      case db.get_wine_by_id(conn, entry.wine_id) {
        Error(_) -> wisp.not_found()
        Ok(wine) -> c.overlay_wrapper(cellar_entry_card(entry, wine))
      }
  }
}

fn cellar_entry_card(entry: CellarEntry, wine: Wine) -> html.Node {
  html.div([attr.class("bg-white rounded-lg border border-stone-200 p-6")], [
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
      html.div([attr.class("flex items-center gap-2")], [
        c.wine_type_badge(wine.wine_type),
        html.span(
          [attr.class("text-2xl font-light text-stone-800 tabular-nums")],
          [html.Text(int.to_string(entry.quantity) <> "\u{00d7}")],
        ),
      ]),
    ]),
    html.p([attr.class("text-sm text-stone-500 mb-4")], [
      c.date_node(case entry.date {
        Some(d) -> d
        None -> entry.created_at
      }),
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

fn cellar_wine_table(wines: List(CellarWine)) -> html.Node {
  html.div([attr.class("overflow-x-auto rounded-lg border border-stone-200")], [
    html.table([attr.class("w-full text-sm")], [
      html.thead([], [
        html.tr([attr.class("bg-stone-50 border-b border-stone-200")], [
          c.th("Winery"),
          c.th("Wine"),
          c.th("Vintage"),
          c.th("Country"),
          c.th("Type"),
          c.th("Cellar"),
        ]),
      ]),
      html.tbody([], list.index_map(wines, cellar_wine_row)),
    ]),
  ])
}

fn cellar_wine_row(cw: CellarWine, idx: Int) -> html.Node {
  let wine = cw.wine
  html.tr(
    [
      attr.id("wine-" <> wine.id <> "-" <> option.unwrap(cw.vintage, "")),
      attr.class(c.clickable_row_class(idx) <> " target-highlight"),
      attr.Attr("onclick", "window.location='" <> c.wine_url(wine) <> "'"),
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
        html.Text(c.display_vintage(cw.vintage)),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(c.display_country(wine.country)),
      ]),
      html.td([attr.class("px-4 py-3")], [c.wine_type_badge(wine.wine_type)]),
      html.td([attr.class("px-4 py-3 text-center tabular-nums")], [
        html.Text(int.to_string(cw.bottles)),
      ]),
    ],
  )
}

fn csv_field(value: String) -> String {
  case string.contains(value, ",") || string.contains(value, "\"") {
    True -> "\"" <> string.replace(value, each: "\"", with: "\"\"") <> "\""
    False -> value
  }
}

fn logo_svg() -> String {
  "<svg width=\"32\" height=\"32\" viewBox=\"0 0 32 32\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">
    <circle cx=\"10\" cy=\"8\" r=\"4\" fill=\"#78180e\" opacity=\"0.8\"/>
    <circle cx=\"18\" cy=\"6\" r=\"3.5\" fill=\"#78180e\" opacity=\"0.65\"/>
    <circle cx=\"14\" cy=\"13\" r=\"3.5\" fill=\"#78180e\" opacity=\"0.75\"/>
    <circle cx=\"22\" cy=\"11\" r=\"3\" fill=\"#78180e\" opacity=\"0.5\"/>
    <path d=\"M14 18 C14 18 13 24 16 28\" stroke=\"#78716c\" stroke-width=\"1.5\" stroke-linecap=\"round\"/>
    <path d=\"M16 28 C16 28 12 29 10 28\" stroke=\"#78716c\" stroke-width=\"1\" stroke-linecap=\"round\" opacity=\"0.5\"/>
    <path d=\"M16 28 C16 28 20 29 22 28\" stroke=\"#78716c\" stroke-width=\"1\" stroke-linecap=\"round\" opacity=\"0.5\"/>
    <path d=\"M14 20 C11 19 8 20 7 18\" stroke=\"#78716c\" stroke-width=\"1\" stroke-linecap=\"round\" opacity=\"0.4\"/>
    <path d=\"M15 22 C18 21 20 22 22 20\" stroke=\"#78716c\" stroke-width=\"1\" stroke-linecap=\"round\" opacity=\"0.4\"/>
  </svg>"
}
