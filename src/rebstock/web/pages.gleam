import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import nakai
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/db.{type Wine, type Winery}

// --- Home ---

pub fn home(conn: Connection) -> Response {
  let wine_count = db.count_wines(conn)
  let cellar_wines = db.cellar_wines(conn)
  let cellar_count =
    list.fold(cellar_wines, 0, fn(acc, w) { acc + w.in_cellar })

  page("Rebstock", [
    html.div([attr.class("mb-8")], [
      html.h1([attr.class("text-3xl font-light text-stone-800 tracking-tight")], [
        html.Text("Rebstock"),
      ]),
      html.p([attr.class("text-stone-500 mt-1")], [
        html.Text("Your wine cellar"),
      ]),
    ]),
    html.div([attr.class("grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8")], [
      stat_card("Wines", int.to_string(wine_count), "/wines"),
      stat_card(
        "In Cellar",
        int.to_string(cellar_count) <> " bottles",
        "/cellar",
      ),
      stat_card(
        "Wineries",
        int.to_string(list.length(db.list_wineries(conn))),
        "/wineries",
      ),
    ]),
    nav_links(),
  ])
}

fn stat_card(label: String, value: String, href: String) -> Node {
  html.a([attr.href(href), attr.class("block p-6 bg-white rounded-lg border border-stone-200 hover:border-amber-300 transition-colors")], [
    html.div([attr.class("text-2xl font-light text-stone-800")], [
      html.Text(value),
    ]),
    html.div([attr.class("text-sm text-stone-500 mt-1")], [
      html.Text(label),
    ]),
  ])
}

// --- Wines ---

pub fn wines(conn: Connection) -> Response {
  let wines = db.list_wines(conn)
  let count = int.to_string(list.length(wines))

  page("Wines \u{2014} Rebstock", [
    page_header("Wines", count <> " total"),
    nav_links(),
    wine_table(wines, show_cellar: True),
  ])
}

pub fn wine_detail(conn: Connection, id: Int) -> Response {
  case db.get_wine(conn, id) {
    Error(_) -> wisp.not_found()
    Ok(wine) ->
      page(wine.name <> " \u{2014} Rebstock", [
        html.div([attr.class("mb-6")], [
          html.a(
            [attr.href("/wines"), attr.class("text-sm text-stone-500 hover:text-stone-700")],
            [html.Text("\u{2190} All wines")],
          ),
        ]),
        html.div([attr.class("bg-white rounded-lg border border-stone-200 p-6")], [
          html.div([attr.class("flex items-start justify-between mb-4")], [
            html.div([], [
              html.h1([attr.class("text-2xl font-light text-stone-800")], [
                html.Text(wine.name),
              ]),
              html.p([attr.class("text-stone-500 mt-1")], [
                html.a(
                  [attr.href("/wineries/" <> wine.winery), attr.class("hover:text-stone-700")],
                  [html.Text(wine.winery)],
                ),
                html.Text(case wine.vintage {
                  0 -> ""
                  v -> " \u{00b7} " <> int.to_string(v)
                }),
              ]),
            ]),
            wine_type_badge(wine.wine_type),
          ]),
          detail_grid([
            #("Region", wine.region),
            #("Country", wine.country),
            #("Style", wine.style),
          ]),
          html.div([attr.class("grid grid-cols-2 sm:grid-cols-4 gap-4 mt-6 pt-6 border-t border-stone-100")], [
            detail_stat("Avg Rating", case wine.avg_rating {
              Some(r) -> float.to_string(r)
              None -> "\u{2014}"
            }),
            detail_stat("Your Rating", case wine.user_rating {
              Some(r) -> float.to_string(r)
              None -> "\u{2014}"
            }),
            detail_stat("In Cellar", case wine.in_cellar {
              0 -> "No"
              n -> int.to_string(n) <> " bottles"
            }),
            detail_stat("Wishlisted", case wine.wishlisted {
              True -> "Yes"
              False -> "No"
            }),
          ]),
          case wine.user_review {
            "" -> html.Nothing
            review ->
              html.div([attr.class("mt-6 pt-6 border-t border-stone-100")], [
                html.h3([attr.class("text-xs uppercase tracking-wider text-stone-500 mb-2")], [
                  html.Text("Your Review"),
                ]),
                html.p([attr.class("text-stone-700")], [html.Text(review)]),
              ])
          },
          case wine.personal_note {
            "" -> html.Nothing
            note ->
              html.div([attr.class("mt-4")], [
                html.h3([attr.class("text-xs uppercase tracking-wider text-stone-500 mb-2")], [
                  html.Text("Personal Note"),
                ]),
                html.p([attr.class("text-stone-700")], [html.Text(note)]),
              ])
          },
          case wine.vivino_link {
            "" -> html.Nothing
            link ->
              html.div([attr.class("mt-6 pt-6 border-t border-stone-100")], [
                html.a(
                  [attr.href(link), attr.class("text-sm text-rose-800 hover:text-rose-900")],
                  [html.Text("View on Vivino \u{2192}")],
                ),
              ])
          },
        ]),
      ])
  }
}

fn detail_grid(items: List(#(String, String))) -> Node {
  html.div(
    [attr.class("grid grid-cols-2 sm:grid-cols-3 gap-4 mt-4")],
    list.filter_map(items, fn(item) {
      case item.1 {
        "" -> Error(Nil)
        val ->
          Ok(html.div([], [
            html.div([attr.class("text-xs uppercase tracking-wider text-stone-400")], [
              html.Text(item.0),
            ]),
            html.div([attr.class("text-stone-700 mt-0.5")], [html.Text(val)]),
          ]))
      }
    }),
  )
}

fn detail_stat(label: String, value: String) -> Node {
  html.div([], [
    html.div([attr.class("text-xs uppercase tracking-wider text-stone-400")], [
      html.Text(label),
    ]),
    html.div([attr.class("text-lg text-stone-800 mt-0.5")], [
      html.Text(value),
    ]),
  ])
}

// --- Wineries ---

pub fn wineries(conn: Connection) -> Response {
  let wineries = db.list_wineries(conn)
  let count = int.to_string(list.length(wineries))

  page("Wineries \u{2014} Rebstock", [
    page_header("Wineries", count <> " total"),
    nav_links(),
    html.div([attr.class("overflow-x-auto rounded-lg border border-stone-200")], [
      html.table([attr.class("w-full text-sm")], [
        html.thead([], [
          html.tr([attr.class("bg-stone-50 border-b border-stone-200")], [
            th("Winery"),
            th("Country"),
            th("Wines"),
          ]),
        ]),
        html.tbody([], list.index_map(wineries, winery_row)),
      ]),
    ]),
  ])
}

fn winery_row(winery: Winery, idx: Int) -> Node {
  let bg = case idx % 2 {
    0 -> "bg-white"
    _ -> "bg-stone-50/50"
  }
  html.tr(
    [attr.class(bg <> " border-b border-stone-100 hover:bg-amber-50/50 transition-colors")],
    [
      html.td([attr.class("px-4 py-3 font-medium text-stone-800")], [
        html.a(
          [attr.href("/wineries/" <> winery.name), attr.class("hover:text-rose-800 transition-colors")],
          [html.Text(winery.name)],
        ),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(winery.country),
      ]),
      html.td([attr.class("px-4 py-3 tabular-nums text-stone-600")], [
        html.Text(int.to_string(winery.wine_count)),
      ]),
    ],
  )
}

pub fn winery_detail(conn: Connection, name: String) -> Response {
  let wines = db.wines_by_winery(conn, name)
  case wines {
    [] -> wisp.not_found()
    _ -> {
      let count = int.to_string(list.length(wines))
      page(name <> " \u{2014} Rebstock", [
        html.div([attr.class("mb-6")], [
          html.a(
            [attr.href("/wineries"), attr.class("text-sm text-stone-500 hover:text-stone-700")],
            [html.Text("\u{2190} All wineries")],
          ),
        ]),
        page_header(name, count <> " wines"),
        wine_table(wines, show_cellar: True),
      ])
    }
  }
}

// --- Cellar ---

pub fn cellar(conn: Connection) -> Response {
  let wines = db.cellar_wines(conn)
  let total_bottles =
    list.fold(wines, 0, fn(acc, w) { acc + w.in_cellar })

  page("Cellar \u{2014} Rebstock", [
    page_header("Cellar", int.to_string(total_bottles) <> " bottles"),
    nav_links(),
    wine_table(wines, show_cellar: True),
  ])
}

// --- Shared components ---

fn nav_links() -> Node {
  html.nav([attr.class("flex gap-6 mb-6 text-sm")], [
    nav_link("Wines", "/wines"),
    nav_link("Wineries", "/wineries"),
    nav_link("Cellar", "/cellar"),
  ])
}

fn nav_link(label: String, href: String) -> Node {
  html.a(
    [attr.href(href), attr.class("text-stone-500 hover:text-stone-800 transition-colors")],
    [html.Text(label)],
  )
}

fn page_header(title: String, subtitle: String) -> Node {
  html.div([attr.class("mb-6")], [
    html.h1([attr.class("text-3xl font-light text-stone-800 tracking-tight")], [
      html.Text(title),
    ]),
    html.p([attr.class("text-stone-500 mt-1")], [html.Text(subtitle)]),
  ])
}

fn wine_table(wines: List(Wine), show_cellar sc: Bool) -> Node {
  html.div([attr.class("overflow-x-auto rounded-lg border border-stone-200")], [
    html.table([attr.class("w-full text-sm")], [
      html.thead([], [
        html.tr([attr.class("bg-stone-50 border-b border-stone-200")], [
          th("Winery"),
          th("Wine"),
          th("Vintage"),
          th("Country"),
          th("Type"),
          th("Rating"),
          ..case sc {
            True -> [th("Cellar")]
            False -> []
          }
        ]),
      ]),
      html.tbody([], list.index_map(wines, fn(w, i) { wine_row(w, i, sc) })),
    ]),
  ])
}

fn th(label: String) -> Node {
  html.th(
    [attr.class("px-4 py-3 text-left font-medium text-stone-600 text-xs uppercase tracking-wider")],
    [html.Text(label)],
  )
}

fn wine_row(wine: Wine, idx: Int, show_cellar: Bool) -> Node {
  let bg = case idx % 2 {
    0 -> "bg-white"
    _ -> "bg-stone-50/50"
  }
  html.tr(
    [attr.class(bg <> " border-b border-stone-100 hover:bg-amber-50/50 transition-colors")],
    [
      html.td([attr.class("px-4 py-3 text-stone-700")], [
        html.a(
          [attr.href("/wineries/" <> wine.winery), attr.class("hover:text-rose-800 transition-colors")],
          [html.Text(wine.winery)],
        ),
      ]),
      html.td([attr.class("px-4 py-3 font-medium text-stone-800")], [
        html.a(
          [attr.href("/wines/" <> int.to_string(wine.id)), attr.class("hover:text-rose-800 transition-colors")],
          [html.Text(wine.name)],
        ),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-500 tabular-nums")], [
        html.Text(case wine.vintage {
          0 -> "\u{2014}"
          v -> int.to_string(v)
        }),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(wine.country),
      ]),
      html.td([attr.class("px-4 py-3")], [wine_type_badge(wine.wine_type)]),
      html.td([attr.class("px-4 py-3 tabular-nums")], [
        rating_display(wine.avg_rating),
      ]),
      ..case show_cellar {
        True -> [
          html.td([attr.class("px-4 py-3 text-center tabular-nums")], [
            html.Text(case wine.in_cellar {
              0 -> ""
              n -> int.to_string(n)
            }),
          ]),
        ]
        False -> []
      }
    ],
  )
}

fn wine_type_badge(wine_type: String) -> Node {
  let #(bg, text) = case wine_type {
    "Red Wine" -> #("bg-rose-900/10 text-rose-900", wine_type)
    "White Wine" -> #("bg-amber-100 text-amber-800", wine_type)
    "Rosé Wine" -> #("bg-pink-100 text-pink-700", wine_type)
    "Sparkling" -> #("bg-stone-100 text-stone-600", wine_type)
    other -> #("bg-stone-100 text-stone-600", other)
  }
  html.span(
    [attr.class("inline-block px-2 py-0.5 rounded text-xs font-medium " <> bg)],
    [html.Text(text)],
  )
}

fn rating_display(rating: option.Option(Float)) -> Node {
  case rating {
    None -> html.Text("")
    Some(r) -> {
      let stars = float.round(r)
      let color = case stars {
        n if n >= 4 -> "text-amber-700"
        _ -> "text-stone-500"
      }
      html.span([attr.class(color <> " font-medium")], [
        html.Text(float.to_string(r)),
      ])
    }
  }
}

fn page(title: String, content: List(Node)) -> Response {
  layout(title, [
    html.div([attr.class("max-w-6xl mx-auto px-4 py-8")], content),
  ])
  |> render
}

fn layout(title: String, content: List(Node)) -> Node {
  html.Html([attr.class("antialiased")], [
    html.Head([
      html.meta([attr.charset("utf-8")]),
      html.meta([
        attr.name("viewport"),
        attr.content("width=device-width, initial-scale=1"),
      ]),
      html.title(title),
      html.link([
        attr.rel("stylesheet"),
        attr.href("/static/css/app.css"),
      ]),
    ]),
    html.Body([attr.class("bg-stone-100 text-stone-900 min-h-screen font-sans")], content),
  ])
}

fn render(node: Node) -> Response {
  node
  |> nakai.to_string
  |> wisp.html_response(200)
}
