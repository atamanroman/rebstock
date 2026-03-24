import gleam/bytes_tree
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import nakai
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/auth.{type User}
import rebstock/db.{type Wine, type Winery}

// --- Home ---

pub fn home(conn: Connection, user: User) -> Response {
  let u = user.username
  let wine_count = db.count_wines(conn, u)
  let all_cellar = db.cellar_wines(conn, u)
  let cellar_count =
    list.fold(all_cellar, 0, fn(acc, w) { acc + w.in_cellar })

  let top_cellar = db.top_cellar(conn, u, 10)
  let top_rated = db.top_rated_by_user(conn, u, 10)
  let latest_rated = db.latest_rated(conn, u, 10)
  let latest_cellar = db.latest_cellar(conn, u, 10)

  page("Rebstock", user, [
    html.div([attr.class("grid grid-cols-1 sm:grid-cols-3 gap-4 mb-10")], [
      stat_card("Wines", int.to_string(wine_count), "/wines"),
      stat_card(
        "In Cellar",
        int.to_string(cellar_count) <> " bottles",
        "/cellar",
      ),
      stat_card(
        "Wineries",
        int.to_string(list.length(db.list_wineries(conn, u))),
        "/wineries",
      ),
    ]),
    html.div([attr.class("grid grid-cols-1 lg:grid-cols-2 gap-8")], [
      section("Top Cellar Wines", "/cellar", top_cellar),
      section("Your Top Rated", "/wines", top_rated),
      section("Recently Added to Cellar", "/cellar", latest_cellar),
      section("Recently Rated", "/wines", latest_rated),
    ]),
  ])
}

fn section(title: String, link: String, wines: List(Wine)) -> Node {
  case wines {
    [] -> html.Nothing
    _ ->
      html.div([], [
        html.div([attr.class("flex items-baseline justify-between mb-3")], [
          html.h2([attr.class("text-lg font-medium text-stone-800")], [
            html.Text(title),
          ]),
          html.a(
            [attr.href(link), attr.class("text-xs text-stone-400 hover:text-stone-600 transition-colors")],
            [html.Text("View all \u{2192}")],
          ),
        ]),
        compact_wine_list(wines),
      ])
  }
}

fn compact_wine_list(wines: List(Wine)) -> Node {
  html.div(
    [attr.class("bg-white rounded-lg border border-stone-200 divide-y divide-stone-100")],
    list.map(wines, compact_wine_row),
  )
}

fn compact_wine_row(wine: Wine) -> Node {
  html.a(
    [attr.href(wine_url(wine)), attr.class("flex items-center justify-between px-4 py-3 hover:bg-amber-50/50 transition-colors block")],
    [
      html.div([attr.class("min-w-0 flex-1")], [
        html.div([attr.class("flex items-center gap-2")], [
          html.span([attr.class("font-medium text-stone-800 text-sm truncate")], [
            html.Text(wine.name),
          ]),
          html.span([attr.class("text-xs text-stone-400 shrink-0")], [
            html.Text(display_vintage(wine.vintage)),
          ]),
        ]),
        html.div([attr.class("text-xs text-stone-500 truncate mt-0.5")], [
          html.Text(display_winery(wine.winery_name)),
        ]),
      ]),
      html.div([attr.class("flex items-center gap-3 ml-4 shrink-0")], [
        wine_type_badge(wine.wine_type),
        ..compact_stats(wine)
      ]),
    ],
  )
}

fn compact_stats(wine: Wine) -> List(Node) {
  let rating = case wine.user_rating {
    Some(r) ->
      [html.span([attr.class("text-sm font-medium text-amber-700 tabular-nums")], [
        html.Text(float.to_string(r)),
      ])]
    None -> case wine.avg_rating {
      Some(r) ->
        [html.span([attr.class("text-sm text-stone-500 tabular-nums")], [
          html.Text(float.to_string(r)),
        ])]
      None -> []
    }
  }
  let cellar = case wine.in_cellar {
    0 -> []
    n ->
      [html.span([attr.class("text-xs text-stone-400 tabular-nums")], [
        html.Text(int.to_string(n) <> "\u{00d7}"),
      ])]
  }
  list.append(rating, cellar)
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

pub fn wines(conn: Connection, user: User) -> Response {
  let wines = db.list_wines(conn, user.username)
  let count = int.to_string(list.length(wines))

  page("Wines \u{2014} Rebstock", user, [
    page_header("Wines", count <> " total"),
    wine_table(wines, show_cellar: True),
  ])
}

pub fn wine_detail(conn: Connection, id: Int, user: User) -> Response {
  case db.get_wine(conn, user.username, id) {
    Error(_) -> wisp.not_found()
    Ok(wine) ->
      page(wine.name <> " \u{2014} Rebstock", user, [
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
                  [attr.href(winery_url(wine.winery_id, wine.winery_name)), attr.class("hover:text-stone-700")],
                  [html.Text(display_winery(wine.winery_name))],
                ),
                html.Text(" \u{00b7} " <> display_vintage(wine.vintage)),
              ]),
            ]),
            wine_type_badge(wine.wine_type),
          ]),
          detail_grid([
            #("Region", wine.region),
            #("Country", display_country(wine.country)),
            #("Style", wine.style),
          ]),
          html.div([attr.class("grid grid-cols-2 sm:grid-cols-4 gap-4 mt-6 pt-6 border-t border-stone-100")], [
            detail_stat("Avg Rating", rating_display(wine.avg_rating)),
            detail_stat("Your Rating", rating_display(wine.user_rating)),
            detail_stat("In Cellar", html.Text(case wine.in_cellar {
              0 -> "No"
              n -> int.to_string(n) <> " bottles"
            })),
            detail_stat("Wishlisted", html.Text(case wine.wishlisted {
              True -> "Yes"
              False -> "No"
            })),
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

fn detail_stat(label: String, value: Node) -> Node {
  html.div([], [
    html.div([attr.class("text-xs uppercase tracking-wider text-stone-400")], [
      html.Text(label),
    ]),
    html.div([attr.class("text-lg text-stone-800 mt-0.5")], [
      value,
    ]),
  ])
}

// --- Wineries ---

pub fn wineries(conn: Connection, user: User) -> Response {
  let wineries = db.list_wineries(conn, user.username)
  let count = int.to_string(list.length(wineries))

  page("Wineries \u{2014} Rebstock", user, [
    page_header("Wineries", count <> " total"),
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
    _ -> "bg-stone-50/30"
  }
  html.tr(
    [attr.class(bg <> " border-b border-stone-100 hover:bg-amber-50/50 transition-colors")],
    [
      html.td([attr.class("px-4 py-3 font-medium text-stone-800")], [
        html.a(
          [attr.href(winery_url(winery.id, winery.name)), attr.class("hover:text-rose-800 transition-colors")],
          [html.Text(display_winery(winery.name))],
        ),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(display_country(winery.country)),
      ]),
      html.td([attr.class("px-4 py-3 tabular-nums text-stone-600")], [
        html.Text(int.to_string(winery.wine_count)),
      ]),
    ],
  )
}

pub fn winery_detail(conn: Connection, id: Int, user: User) -> Response {
  case db.get_winery(conn, user.username, id) {
    Error(_) -> wisp.not_found()
    Ok(winery) -> {
      let wines = db.wines_by_winery(conn, user.username, id)
      let display = display_winery(winery.name)
      page(display <> " \u{2014} Rebstock", user, [
        html.div([attr.class("mb-6")], [
          html.a(
            [attr.href("/wineries"), attr.class("text-sm text-stone-500 hover:text-stone-700")],
            [html.Text("\u{2190} All wineries")],
          ),
        ]),
        page_header(display, int.to_string(winery.wine_count) <> " wines"),
        wine_table(wines, show_cellar: True),
      ])
    }
  }
}

// --- Cellar ---

pub fn cellar(conn: Connection, user: User) -> Response {
  let wines = db.cellar_wines(conn, user.username)
  let total_bottles =
    list.fold(wines, 0, fn(acc, w) { acc + w.in_cellar })

  page("Cellar \u{2014} Rebstock", user, [
    html.div([attr.class("flex items-end justify-between mb-6")], [
      html.div([], [
        html.h1([attr.class("text-3xl font-light text-stone-800 tracking-tight")], [
          html.Text("Cellar"),
        ]),
        html.p([attr.class("text-stone-500 mt-1")], [
          html.Text(int.to_string(total_bottles) <> " bottles"),
        ]),
      ]),
      html.div([attr.class("flex gap-2")], [
        html.a(
          [
            attr.href("/cellar/export.csv"),
            attr.class("px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors"),
          ],
          [html.Text("Export CSV")],
        ),
        html.a(
          [
            attr.href("/cellar/print"),
            attr.class("px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors"),
          ],
          [html.Text("Wine List")],
        ),
      ]),
    ]),
    wine_table(wines, show_cellar: True),
  ])
}

pub fn cellar_print(conn: Connection, user: User) -> Response {
  let wines = db.cellar_wines_by_type(conn, user.username)
  let total_bottles =
    list.fold(wines, 0, fn(acc, w) { acc + w.in_cellar })

  let grouped =
    list.chunk(wines, fn(w) { w.wine_type })
    |> list.flat_map(fn(group) {
      case group {
        [first, ..] -> [
          html.h2([attr.class("cellar-type-heading")], [
            html.Text(first.wine_type),
          ]),
          wine_table(group, show_cellar: True),
        ]
        _ -> []
      }
    })

  layout("Cellar Inventory \u{2014} Rebstock", [
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
  |> render
}

pub fn cellar_csv(conn: Connection, user: User) -> Response {
  let wines = db.cellar_wines(conn, user.username)
  let header = "Winery,Wine,Vintage,Country,Type,Rating,Bottles"
  let rows =
    list.map(wines, fn(w) {
      [
        csv_field(w.winery_name),
        csv_field(w.name),
        case w.vintage {
          -1 -> ""
          0 -> "N.V."
          v -> int.to_string(v)
        },
        csv_field(w.country),
        w.wine_type,
        case w.avg_rating {
          Some(r) -> float.to_string(r)
          None -> ""
        },
        int.to_string(w.in_cellar),
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

fn csv_field(value: String) -> String {
  case string.contains(value, ",") || string.contains(value, "\"") {
    True ->
      "\"" <> string.replace(value, each: "\"", with: "\"\"") <> "\""
    False -> value
  }
}

// --- Shared components ---

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
    _ -> "bg-stone-50/30"
  }
  html.tr(
    [attr.class(bg <> " border-b border-stone-100 hover:bg-amber-50/50 transition-colors")],
    [
      html.td([attr.class("px-4 py-3 text-stone-700")], [
        html.a(
          [attr.href(winery_url(wine.winery_id, wine.winery_name)), attr.class("hover:text-rose-800 transition-colors")],
          [html.Text(display_winery(wine.winery_name))],
        ),
      ]),
      html.td([attr.class("px-4 py-3 font-medium text-stone-800")], [
        html.a(
          [attr.href(wine_url(wine)), attr.class("hover:text-rose-800 transition-colors")],
          [html.Text(wine.name)],
        ),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-500 tabular-nums")], [
        html.Text(display_vintage(wine.vintage)),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(display_country(wine.country)),
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
  let #(classes, text) = case wine_type {
    "Red Wine" -> #("bg-red-900 text-red-100 border-red-800", "Red")
    "White Wine" -> #("bg-amber-50/60 text-amber-800 border-amber-200", "White")
    "Rosé Wine" -> #("bg-pink-50 text-pink-700 border-pink-200", "Rosé")
    "Sparkling" -> #("bg-stone-50 text-stone-700 border-stone-200", "Sparkling")
    other -> #("bg-stone-50 text-stone-700 border-stone-200", other)
  }
  html.span(
    [attr.class("inline-block px-2 py-0.5 rounded border text-xs font-medium " <> classes)],
    [html.Text(text)],
  )
}

fn rating_display(rating: option.Option(Float)) -> Node {
  case rating {
    None -> html.Text("\u{2014}")
    Some(r) -> {
      // Map 3..5 to hue 0 (red) → 60 (yellow) → 120 (green)
      let clamped = case r <. 3.0 { True -> 3.0 False -> case r >. 5.0 { True -> 5.0 False -> r } }
      let t = { clamped -. 3.0 } /. 2.0
      let hue = float.round(t *. 120.0)
      let color = "hsl(" <> int.to_string(hue) <> " 70% 35%)"
      html.span([
        attr.class("font-medium tabular-nums"),
        attr.style("color: " <> color),
      ], [
        html.Text(float.to_string(r)),
      ])
    }
  }
}

fn display_winery(winery: String) -> String {
  case winery {
    "" -> "Unknown"
    w -> w
  }
}

fn display_vintage(vintage: Int) -> String {
  case vintage {
    -1 -> "Unknown"
    0 -> "N.V."
    v -> int.to_string(v)
  }
}

fn display_country(country: String) -> String {
  case country {
    "" -> "Unknown"
    c -> c
  }
}

fn wine_url(wine: Wine) -> String {
  "/wines/" <> int.to_string(wine.id) <> "/" <> db.slugify(wine.name)
}

fn winery_url(id: Int, name: String) -> String {
  "/wineries/" <> int.to_string(id) <> "/" <> db.slugify(name)
}

fn page(title: String, user: User, content: List(Node)) -> Response {
  layout(title, [
    site_header(user),
    html.div([attr.class("max-w-6xl mx-auto px-4 pb-12")], content),
  ])
  |> render
}

fn site_header(user: User) -> Node {
  let display_name = case user.display_name {
    Some(name) -> name
    None -> user.username
  }
  html.header(
    [attr.class("border-b border-stone-200 bg-white/80 backdrop-blur-sm sticky top-0 z-10 mb-8")],
    [
      html.div([attr.class("max-w-6xl mx-auto px-4 py-4 flex items-center justify-between")], [
        html.a([attr.href("/"), attr.class("flex items-center gap-3 group")], [
          html.UnsafeInlineHtml(logo_svg()),
          html.span(
            [attr.class("text-xl font-light tracking-tight text-stone-800 group-hover:text-rose-800 transition-colors")],
            [html.Text("Rebstock")],
          ),
        ]),
        html.div([attr.class("flex items-center gap-6")], [
          html.nav([attr.class("flex gap-6 text-sm")], [
            nav_link("Wines", "/wines"),
            nav_link("Wineries", "/wineries"),
            nav_link("Cellar", "/cellar"),
          ]),
          html.span([attr.class("text-xs text-stone-400")], [
            html.Text(display_name),
          ]),
        ]),
      ]),
    ],
  )
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

fn favicon_data_uri() -> String {
  "data:image/svg+xml,%3Csvg width='32' height='32' viewBox='0 0 32 32' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Ccircle cx='10' cy='8' r='4' fill='%2378180e' opacity='0.8'/%3E%3Ccircle cx='18' cy='6' r='3.5' fill='%2378180e' opacity='0.65'/%3E%3Ccircle cx='14' cy='13' r='3.5' fill='%2378180e' opacity='0.75'/%3E%3Ccircle cx='22' cy='11' r='3' fill='%2378180e' opacity='0.5'/%3E%3Cpath d='M14 18 C14 18 13 24 16 28' stroke='%2378716c' stroke-width='1.5' stroke-linecap='round'/%3E%3Cpath d='M16 28 C16 28 12 29 10 28' stroke='%2378716c' stroke-width='1' stroke-linecap='round' opacity='0.5'/%3E%3Cpath d='M16 28 C16 28 20 29 22 28' stroke='%2378716c' stroke-width='1' stroke-linecap='round' opacity='0.5'/%3E%3Cpath d='M14 20 C11 19 8 20 7 18' stroke='%2378716c' stroke-width='1' stroke-linecap='round' opacity='0.4'/%3E%3Cpath d='M15 22 C18 21 20 22 22 20' stroke='%2378716c' stroke-width='1' stroke-linecap='round' opacity='0.4'/%3E%3C/svg%3E"
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
      html.link([
        attr.rel("icon"),
        attr.type_("image/svg+xml"),
        attr.href(favicon_data_uri()),
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
