import gleam/bytes_tree
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import nakai
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/auth.{type User}
import rebstock/db.{type CellarEntry, type CellarWine, type Rating, type Wine, type WishlistWine, type Winery}

// --- Home ---

pub fn home(conn: Connection, user: User) -> Response {
  let u = user.username
  let wine_count = db.count_wines(conn)
  let all_cellar = db.cellar_wines(conn, u)
  let cellar_count =
    list.fold(all_cellar, 0, fn(acc, cw) { acc + cw.bottles })

  let top_cellar = db.top_cellar(conn, u, 10)
  let top_rated = db.top_ratings_by_user(conn, u, 10)
  let latest_rated = db.latest_ratings(conn, u, 10)
  let latest_cellar = db.latest_cellar_entries(conn, u, 10)

  page("Rebstock", user, [
    html.div([attr.class("grid grid-cols-1 sm:grid-cols-3 gap-4 mb-10")], [
      stat_card("Known Wines", int.to_string(wine_count), "/wines"),
      stat_card(
        "Known Wineries",
        int.to_string(list.length(db.list_wineries(conn, u))),
        "/wineries",
      ),
      stat_card(
             "In Cellar",
             int.to_string(cellar_count) <> " bottles",
             "/~" <> u <> "/cellar",
           ),
    ]),
    html.div([attr.class("grid grid-cols-1 lg:grid-cols-2 gap-8")], [
      cellar_entry_section("Recently Added to Cellar", "/~" <> u <> "/cellar", latest_cellar, conn),
      cellar_wine_section("Top Cellar Wines", "/~" <> u <> "/cellar", top_cellar),
      rating_section("Recently Rated", "/~" <> u <> "/ratings", latest_rated, conn),
      rating_section("Your Top Rated", "/~" <> u <> "/ratings", top_rated, conn),
    ]),
  ])
}

fn section_header(title: String, link: String) -> Node {
  html.div([attr.class("flex items-baseline justify-between mb-3")], [
    html.h2([attr.class("text-lg font-medium text-stone-800")], [
      html.Text(title),
    ]),
    html.a(
      [attr.href(link), attr.class("text-xs text-stone-400 hover:text-stone-600 transition-colors")],
      [html.Text("View all \u{2192}")],
    ),
  ])
}

fn rating_section(title: String, link: String, ratings: List(Rating), conn: Connection) -> Node {
  case ratings {
    [] -> html.Nothing
    _ ->
      html.div([], [
        section_header(title, link),
        html.div(
          [attr.class("bg-white rounded-lg border border-stone-200 divide-y divide-stone-100")],
          list.map(ratings, fn(r) { compact_rating_row(r, conn) }),
        ),
      ])
  }
}

fn compact_rating_row(rating: Rating, conn: Connection) -> Node {
  case db.get_wine_by_id(conn, rating.wine_id) {
    Error(_) -> html.Nothing
    Ok(wine) ->
      html.a(
        [attr.href(wine_url(wine)), attr.class("flex items-center justify-between px-4 py-3 hover:bg-amber-50/50 transition-colors block")],
        [
          html.div([attr.class("min-w-0 flex-1")], [
            html.div([attr.class("flex items-center gap-2")], [
              html.span([attr.class("font-medium text-stone-800 text-sm truncate")], [
                html.Text(wine.name),
              ]),
              html.span([attr.class("text-xs text-stone-400 shrink-0")], [
                html.Text(display_vintage(rating.vintage)),
              ]),
            ]),
            html.div([attr.class("text-xs text-stone-500 truncate mt-0.5")], [
              html.Text(display_winery(wine.winery_name)),
            ]),
          ]),
          html.div([attr.class("flex items-center gap-3 ml-4 shrink-0")], [
            wine_type_badge(wine.wine_type),
            ..case rating.rating {
              Some(r) ->
                [html.span([attr.class("text-sm font-medium text-amber-700 tabular-nums")], [
                  html.Text(float.to_string(r)),
                ])]
              None -> []
            }
          ]),
        ],
      )
  }
}

fn cellar_wine_section(title: String, link: String, wines: List(CellarWine)) -> Node {
  case wines {
    [] -> html.Nothing
    _ ->
      html.div([], [
        section_header(title, link),
        html.div(
          [attr.class("bg-white rounded-lg border border-stone-200 divide-y divide-stone-100")],
          list.map(wines, fn(cw) {
            html.a(
              [attr.href(wine_url(cw.wine)), attr.class("flex items-center justify-between px-4 py-3 hover:bg-amber-50/50 transition-colors block")],
              [
                html.div([attr.class("min-w-0 flex-1")], [
                  html.div([attr.class("flex items-center gap-2")], [
                    html.span([attr.class("font-medium text-stone-800 text-sm truncate")], [
                      html.Text(cw.wine.name),
                    ]),
                    html.span([attr.class("text-xs text-stone-400 shrink-0")], [
                      html.Text(display_vintage(cw.vintage)),
                    ]),
                  ]),
                  html.div([attr.class("text-xs text-stone-500 truncate mt-0.5")], [
                    html.Text(display_winery(cw.wine.winery_name)),
                  ]),
                ]),
                html.div([attr.class("flex items-center gap-3 ml-4 shrink-0")], [
                  wine_type_badge(cw.wine.wine_type),
                  html.span([attr.class("text-xs text-stone-400 tabular-nums")], [
                    html.Text(int.to_string(cw.bottles) <> "\u{00d7}"),
                  ]),
                ]),
              ],
            )
          }),
        ),
      ])
  }
}

fn cellar_entry_section(title: String, link: String, entries: List(CellarEntry), conn: Connection) -> Node {
  case entries {
    [] -> html.Nothing
    _ ->
      html.div([], [
        section_header(title, link),
        html.div(
          [attr.class("bg-white rounded-lg border border-stone-200 divide-y divide-stone-100")],
          list.map(entries, fn(e) {
            case db.get_wine_by_id(conn, e.wine_id) {
              Error(_) -> html.Nothing
              Ok(wine) ->
                html.a(
                  [attr.href(wine_url(wine)), attr.class("flex items-center justify-between px-4 py-3 hover:bg-amber-50/50 transition-colors block")],
                  [
                    html.div([attr.class("min-w-0 flex-1")], [
                      html.div([attr.class("flex items-center gap-2")], [
                        html.span([attr.class("font-medium text-stone-800 text-sm truncate")], [
                          html.Text(wine.name),
                        ]),
                        html.span([attr.class("text-xs text-stone-400 shrink-0")], [
                          html.Text(display_vintages(wine.vintages)),
                        ]),
                      ]),
                      html.div([attr.class("text-xs text-stone-500 truncate mt-0.5")], [
                        html.Text(display_winery(wine.winery_name)),
                      ]),
                    ]),
                    html.div([attr.class("flex items-center gap-3 ml-4 shrink-0")], [
                      wine_type_badge(wine.wine_type),
                      html.span([attr.class("text-xs text-stone-400 tabular-nums")], [
                        html.Text("+" <> int.to_string(e.quantity)),
                      ]),
                    ]),
                  ],
                )
            }
          }),
        ),
      ])
  }
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

  page("All Wines \u{2014} Rebstock", user, [
    page_header("All Wines", count <> " total"),
    wine_table(wines),
  ])
}

// --- Wishlist ---

pub fn wishlist(conn: Connection, user: User, username: String) -> Response {
  let wishlist = db.wishlist_wines(conn, username)
  let count = int.to_string(list.length(wishlist))

  page("Wishlist \u{2014} Rebstock", user, [
    page_header("Wishlist", count <> " wines"),
    wishlist_table(wishlist),
  ])
}

// --- My Ratings ---

pub fn my_ratings(conn: Connection, user: User, username: String) -> Response {
  let ratings = db.ratings_by_user(conn, username)
  let count = int.to_string(list.length(ratings))

  page("My Ratings \u{2014} Rebstock", user, [
    page_header("My Ratings", count <> " ratings"),
    rating_table(ratings, conn),
  ])
}

pub fn rating_detail(conn: Connection, id: String, user: User) -> Response {
  case db.get_rating_by_id(conn, id) {
    Error(_) -> wisp.not_found()
    Ok(rating) ->
      case db.get_wine_by_id(conn, rating.wine_id) {
        Error(_) -> wisp.not_found()
        Ok(wine) -> {
          let title = wine.name <> " Rating \u{2014} Rebstock"
          page(title, user, [
            html.div([attr.class("mb-6")], [
              html.a(
                [attr.href(wine_url(wine)), attr.class("text-sm text-stone-500 hover:text-stone-700")],
                [html.Text("\u{2190} " <> wine.name)],
              ),
            ]),
            html.div([attr.class("bg-white rounded-lg border border-stone-200 p-6")], [
              html.div([attr.class("flex items-start justify-between mb-2")], [
                html.div([], [
                  html.h1([attr.class("text-2xl font-light text-stone-800")], [
                    html.a(
                      [attr.href(wine_url(wine)), attr.class("hover:text-rose-800 transition-colors")],
                      [html.Text(wine.name)],
                    ),
                  ]),
                  html.p([attr.class("text-stone-500 mt-1")], [
                    html.a(
                      [attr.href(winery_url(wine.winery_id, wine.winery_name)), attr.class("hover:text-stone-700 transition-colors")],
                      [html.Text(display_winery(wine.winery_name))],
                    ),
                    html.Text(case rating.vintage {
                      None -> ""
                      Some(_) -> " \u{00b7} " <> display_vintage(rating.vintage)
                    }),
                  ]),
                ]),
                html.div([attr.class("text-2xl")], [
                  rating_display(rating.rating),
                ]),
              ]),
              html.p([attr.class("text-sm text-stone-500 mb-4")], [
                date_node(case rating.rated_at {
                  Some(date) -> date
                  None -> rating.created_at
                }),
              ]),
              html.div([attr.class("mt-4 pt-4 border-t border-stone-100")], [
                case rating.tasting_notes {
                  Some(notes) ->
                    html.p([attr.class("text-stone-700 whitespace-pre-line")], [
                      html.Text(notes),
                    ])
                  None ->
                    html.p([attr.class("text-stone-400 italic")], [
                      html.Text("No tasting notes"),
                    ])
                },
              ]),
            ]),
          ])
        }
      }
  }
}

pub fn wine_detail(conn: Connection, id: String, user: User) -> Response {
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
                html.Text(case wine.vintages {
                  None -> ""
                  Some(_) -> " \u{00b7} " <> display_vintages(wine.vintages)
                }),
              ]),
            ]),
            wine_type_badge(wine.wine_type),
          ]),
          detail_grid([
            #("Region", display_optional(wine.region)),
            #("Country", display_country(wine.country)),
            #("Style", display_optional(wine.style)),
          ]),
          ..{
            let all_ratings = db.ratings_for_wine(conn, wine.id)
            let wine_vintages = db.vintages_for_wine(conn, wine.id)
            // Build vintage rows from vintages table
            let vintage_rows = list.map(wine_vintages, fn(v) {
              let year = Some(v)
              let vivino_r = list.find(all_ratings, fn(r) { r.source == "vivino" && r.vintage == year })
              let my_r = list.find(all_ratings, fn(r) { r.source == "user" && r.username == user.username && r.vintage == year })
              let other_rs = list.filter(all_ratings, fn(r) { r.source == "user" && r.username != user.username && r.vintage == year })
              #(v, year, vivino_r, my_r, other_rs)
            })
            // Ratings without a vintage (general ratings)
            let my_general = list.filter(all_ratings, fn(r) { r.source == "user" && r.username == user.username && r.vintage == None })
            let other_general = list.filter(all_ratings, fn(r) { r.source == "user" && r.username != user.username && r.vintage == None })
            let vivino_general = list.find(all_ratings, fn(r) { r.source == "vivino" && r.vintage == None })
            [
              case vintage_rows {
                [] -> html.Nothing
                _ ->
                  html.div([attr.class("mt-6 pt-6 border-t border-stone-100")], [
                    html.table([attr.class("w-full text-sm")], [
                      html.thead([], [
                        html.tr([], [
                          html.th([attr.class("py-1 pr-4 text-left text-xs uppercase tracking-wider text-stone-400 font-medium")], [html.Text("Vintage")]),
                          html.th([attr.class("py-1 pr-4 text-left text-xs uppercase tracking-wider text-stone-400 font-medium")], [html.Text("Vivino")]),
                          html.th([attr.class("py-1 pr-4 text-left text-xs uppercase tracking-wider text-stone-400 font-medium")], [html.Text("Your Rating")]),
                        ]),
                      ]),
                      html.tbody([], list.map(vintage_rows, fn(row) {
                        let #(v_str, _year, vivino_r, my_r, _other_rs) = row
                        html.tr([], [
                          html.td([attr.class("py-1 pr-4 font-medium tabular-nums")], [
                            html.Text(v_str),
                          ]),
                          html.td([attr.class("py-1 pr-4 tabular-nums")], [
                            case vivino_r, wine.vivino_id {
                              Ok(r), Some(id) ->
                                html.a(
                                  [attr.href("https://www.vivino.com/wines/" <> id <> "?year=" <> v_str), attr.class("underline decoration-2 decoration-rose-800 underline-offset-2 hover:text-rose-800 transition-colors")],
                                  [rating_display(r.rating)],
                                )
                              Ok(r), None -> rating_display(r.rating)
                              Error(_), Some(id) ->
                                html.a(
                                  [attr.href("https://www.vivino.com/wines/" <> id <> "?year=" <> v_str), attr.class("text-xs text-stone-400 underline decoration-2 decoration-rose-800 underline-offset-2 hover:text-rose-800")],
                                  [html.Text("view")],
                                )
                              Error(_), None -> html.Text("\u{2014}")
                            },
                          ]),
                          html.td([attr.class("py-1 pr-4 tabular-nums")], [
                            case my_r {
                                Ok(r) ->
                                  html.a([attr.href("/ratings/" <> r.id), attr.class("inline-flex items-center gap-2 underline decoration-2 decoration-rose-800 underline-offset-2 hover:text-rose-800 transition-colors")], [
                                    rating_display(r.rating),
                                    case r.tasting_notes {
                                      Some(_) ->
                                        html.span([attr.class("text-xs text-stone-400")], [
                                          html.Text("w/ notes"),
                                        ])
                                      None -> html.Nothing
                                    },
                                  ])
                                Error(_) -> html.Text("\u{2014}")
                              },
                            ]),
                        ])
                      })),
                    ]),
                  ])
              },
              // General ratings (no vintage)
              case my_general, vivino_general {
                [], Error(_) -> html.Nothing
                _, _ ->
                  html.div([attr.class("mt-4 pt-4 border-t border-stone-100")], [
                    html.h3([attr.class("text-xs uppercase tracking-wider text-stone-400 mb-2")], [
                      html.Text("General (no vintage)"),
                    ]),
                    html.div([attr.class("flex items-center gap-6")], [
                      case vivino_general {
                        Ok(r) ->
                          html.span([attr.class("inline-flex items-center gap-1")], [
                            html.span([attr.class("text-xs text-stone-400")], [html.Text("Vivino:")]),
                            rating_display(r.rating),
                          ])
                        Error(_) -> html.Nothing
                      },
                      ..list.map(my_general, fn(r) {
                        html.span([attr.class("inline-flex items-center gap-1")], [
                          html.span([attr.class("text-xs text-stone-400")], [html.Text("You:")]),
                          html.a([attr.href("/ratings/" <> r.id), attr.class("underline decoration-2 decoration-rose-800 underline-offset-2 hover:text-rose-800 transition-colors")], [
                            rating_display(r.rating),
                          ]),
                          case r.tasting_notes {
                            Some(_) ->
                              html.span([attr.class("text-xs text-stone-400")], [html.Text("w/ notes")])
                            None -> html.Nothing
                          },
                        ])
                      })
                    ]),
                  ])
              },
              case other_general {
                [] -> html.Nothing
                _ ->
                  html.div([attr.class("mt-4 pt-4 border-t border-stone-100")], [
                    html.h3([attr.class("text-xs uppercase tracking-wider text-stone-400 mb-3")], [
                      html.Text("Other Ratings"),
                    ]),
                    html.div([attr.class("space-y-2")], list.map(other_general, fn(r) {
                      rating_entry(r, show_username: True)
                    })),
                  ])
              },
              case wine.personal_note {
                None -> html.Nothing
                Some(note) ->
                  html.div([attr.class("mt-4")], [
                    html.h3([attr.class("text-xs uppercase tracking-wider text-stone-500 mb-2")], [
                      html.Text("Personal Note"),
                    ]),
                    html.p([attr.class("text-stone-700")], [html.Text(note)]),
                  ])
              },
              {
                let bottles = db.cellar_bottle_count(conn, user.username, wine.id)
                let wishlisted = db.is_wishlisted(conn, user.username, wine.id)
                let links = [
                  case bottles > 0 {
                    True -> [html.a(
                      [attr.href("/~" <> user.username <> "/cellar"), attr.class("text-sm text-rose-800 hover:text-rose-900")],
                      [html.Text("View in cellar (" <> int.to_string(bottles) <> " bottles)")],
                    )]
                    False -> []
                  },
                  case wishlisted {
                    True -> [html.a(
                      [attr.href("/~" <> user.username <> "/wishlist#wine-" <> wine.id), attr.class("text-sm text-rose-800 hover:text-rose-900")],
                      [html.Text("View in wishlist \u{2192}")],
                    )]
                    False -> []
                  },
                  case wine.vivino_id {
                    Some(id) -> [html.a(
                      [attr.href("https://www.vivino.com/wines/" <> id), attr.class("text-sm text-rose-800 hover:text-rose-900")],
                      [html.Text("View on Vivino \u{2192}")],
                    )]
                    None -> []
                  },
                ] |> list.flatten
                case links {
                  [] -> html.Nothing
                  _ -> html.div([attr.class("mt-6 pt-6 border-t border-stone-100 flex flex-col gap-2")], links)
                }
              },
            ]
          }
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

pub fn winery_detail(conn: Connection, id: String, user: User) -> Response {
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
        wine_table(wines),
      ])
    }
  }
}

// --- Cellar ---

pub fn cellar(conn: Connection, user: User, username: String) -> Response {
  let wines = db.cellar_wines(conn, username)
  let total_bottles =
    list.fold(wines, 0, fn(acc, cw) { acc + cw.bottles })

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
            attr.href("/~" <> username <> "/cellar/export.csv"),
            attr.class("px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors"),
          ],
          [html.Text("Export CSV")],
        ),
        html.a(
          [
            attr.href("/~" <> username <> "/cellar/print"),
            attr.class("px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors"),
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
  let total_bottles =
    list.fold(wines, 0, fn(acc, cw) { acc + cw.bottles })

  let grouped =
    list.chunk(wines, fn(cw) { cw.wine.wine_type })
    |> list.flat_map(fn(group) {
      case group {
        [first, ..] -> [
          html.h2([attr.class("cellar-type-heading")], [
            html.Text(wine_type_label(first.wine.wine_type)),
          ]),
          cellar_wine_table(group),
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

pub fn cellar_csv(conn: Connection, _user: User, username: String) -> Response {
  let wines = db.cellar_wines(conn, username)
  let header = "Winery,Wine,Vintage,Country,Type,Bottles"
  let rows =
    list.map(wines, fn(cw) {
      [
        csv_field(cw.wine.winery_name),
        csv_field(cw.wine.name),
        display_vintage(cw.vintage),
        csv_field(display_country(cw.wine.country)),
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
    [attr.href(href), attr.class("text-stone-500 hover:text-red-900 transition-colors")],
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

fn wine_table(wines: List(Wine)) -> Node {
  html.div([attr.class("overflow-x-auto rounded-lg border border-stone-200")], [
    html.table([attr.class("w-full text-sm")], [
      html.thead([], [
        html.tr([attr.class("bg-stone-50 border-b border-stone-200")], [
          th("Winery"),
          th("Wine"),
          th("Vintage"),
          th("Country"),
          th("Type"),
        ]),
      ]),
      html.tbody([], list.index_map(wines, wine_row)),
    ]),
  ])
}

fn cellar_wine_table(wines: List(CellarWine)) -> Node {
  html.div([attr.class("overflow-x-auto rounded-lg border border-stone-200")], [
    html.table([attr.class("w-full text-sm")], [
      html.thead([], [
        html.tr([attr.class("bg-stone-50 border-b border-stone-200")], [
          th("Winery"),
          th("Wine"),
          th("Vintage"),
          th("Country"),
          th("Type"),
          th("Cellar"),
        ]),
      ]),
      html.tbody([], list.index_map(wines, cellar_wine_row)),
    ]),
  ])
}

fn wishlist_table(wines: List(WishlistWine)) -> Node {
  html.div([attr.class("overflow-x-auto rounded-lg border border-stone-200")], [
    html.table([attr.class("w-full text-sm")], [
      html.thead([], [
        html.tr([attr.class("bg-stone-50 border-b border-stone-200")], [
          th("Winery"),
          th("Wine"),
          th("Vintage"),
          th("Country"),
          th("Type"),
          th("Notes"),
        ]),
      ]),
      html.tbody([], list.index_map(wines, wishlist_row)),
    ]),
  ])
}

fn wishlist_row(ww: WishlistWine, idx: Int) -> Node {
  let wine = ww.wine
  let bg = case idx % 2 {
    0 -> "bg-white"
    _ -> "bg-stone-50/30"
  }
  html.tr(
    [attr.id("wine-" <> wine.id), attr.class(bg <> " target-highlight border-b border-stone-100 hover:bg-amber-50/50 transition-colors")],
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
        html.Text(display_vintages(wine.vintages)),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(display_country(wine.country)),
      ]),
      html.td([attr.class("px-4 py-3")], [wine_type_badge(wine.wine_type)]),
      html.td([attr.class("px-4 py-3 text-stone-600 max-w-xs truncate")], [
        html.Text(display_optional(ww.notes)),
      ]),
    ],
  )
}

fn rating_table(ratings: List(Rating), conn: Connection) -> Node {
  html.div([attr.class("overflow-x-auto rounded-lg border border-stone-200")], [
    html.table([attr.class("w-full text-sm")], [
      html.thead([], [
        html.tr([attr.class("bg-stone-50 border-b border-stone-200")], [
          th("Wine"),
          th("Winery"),
          th("Vintage"),
          th("Rating"),
          th("Notes"),
          th("Date"),
        ]),
      ]),
      html.tbody([], list.index_map(ratings, fn(r, i) { rating_row(r, i, conn) })),
    ]),
  ])
}

fn rating_row(rating: Rating, idx: Int, conn: Connection) -> Node {
  let bg = case idx % 2 {
    0 -> "bg-white"
    _ -> "bg-stone-50/30"
  }
  case db.get_wine_by_id(conn, rating.wine_id) {
    Error(_) -> html.Nothing
    Ok(wine) ->
      html.tr(
        [attr.class(bg <> " border-b border-stone-100 hover:bg-amber-50/50 transition-colors")],
        [
          html.td([attr.class("px-4 py-3 font-medium text-stone-800")], [
            html.a(
              [attr.href(wine_url(wine)), attr.class("hover:text-rose-800 transition-colors")],
              [html.Text(wine.name)],
            ),
          ]),
          html.td([attr.class("px-4 py-3 text-stone-700")], [
            html.Text(display_winery(wine.winery_name)),
          ]),
          html.td([attr.class("px-4 py-3 text-stone-500 tabular-nums")], [
            html.Text(display_vintage(rating.vintage)),
          ]),
          html.td([attr.class("px-4 py-3 tabular-nums")], [
            html.a(
              [attr.href("/ratings/" <> rating.id), attr.class("underline decoration-2 decoration-rose-800 underline-offset-2 hover:text-rose-800 transition-colors")],
              [rating_display(rating.rating)],
            ),
          ]),
          html.td([attr.class("px-4 py-3 text-stone-600 max-w-xs truncate")], [
            html.Text(case rating.tasting_notes {
              Some(notes) -> notes
              None -> ""
            }),
          ]),
          html.td([attr.class("px-4 py-3 text-stone-500 text-xs")], [
            date_node(case rating.rated_at {
              Some(date) -> date
              None -> rating.created_at
            }),
          ]),
        ],
      )
  }
}

fn rating_entry(r: Rating, show_username su: Bool) -> Node {
  html.div([attr.class("flex items-start justify-between")], [
    html.div([], [
      case r.tasting_notes {
        Some(notes) ->
          html.p([attr.class("text-stone-700")], [html.Text(notes)])
        None -> html.Nothing
      },
      html.p([attr.class("text-xs text-stone-400 mt-1")], [
        html.Text({
          let who = case su { True -> r.username <> " \u{00b7} " False -> "" }
          let yr = case r.vintage { Some(_) -> display_vintage(r.vintage) <> " \u{00b7} " None -> "" }
          who <> yr
        }),
        date_node(case r.rated_at {
          Some(date) -> date
          None -> r.created_at
        }),
      ]),
    ]),
    case r.rating {
      Some(v) -> rating_display(Some(v))
      None -> html.Nothing
    },
  ])
}

fn th(label: String) -> Node {
  html.th(
    [attr.class("px-4 py-3 text-left font-medium text-stone-600 text-xs uppercase tracking-wider")],
    [html.Text(label)],
  )
}

fn wine_row(wine: Wine, idx: Int) -> Node {
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
        html.Text(display_vintages(wine.vintages)),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(display_country(wine.country)),
      ]),
      html.td([attr.class("px-4 py-3")], [wine_type_badge(wine.wine_type)]),
    ],
  )
}

fn cellar_wine_row(cw: CellarWine, idx: Int) -> Node {
  let wine = cw.wine
  let bg = case idx % 2 {
    0 -> "bg-white"
    _ -> "bg-stone-50/30"
  }
  html.tr(
    [attr.id("wine-" <> wine.id <> "-" <> option.unwrap(cw.vintage, "")), attr.class(bg <> " target-highlight border-b border-stone-100 hover:bg-amber-50/50 transition-colors")],
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
        html.Text(display_vintage(cw.vintage)),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(display_country(wine.country)),
      ]),
      html.td([attr.class("px-4 py-3")], [wine_type_badge(wine.wine_type)]),
      html.td([attr.class("px-4 py-3 text-center tabular-nums")], [
        html.Text(int.to_string(cw.bottles)),
      ]),
    ],
  )
}

fn wine_type_label(wt: db.WineType) -> String {
  case wt {
    db.Red -> "Red"
    db.White -> "White"
    db.Rose -> "Rosé"
    db.Orange -> "Orange"
    db.Sparkling -> "Sparkling"
    db.Dessert -> "Dessert"
    db.Sake -> "Sake"
    db.Other -> "Other"
  }
}

fn wine_type_badge(wine_type: db.WineType) -> Node {
  let #(classes, text) = case wine_type {
    db.Red -> #("bg-red-900 text-red-100 border-red-800", "Red")
    db.White -> #("bg-amber-50/60 text-amber-800 border-amber-200", "White")
    db.Rose -> #("bg-pink-50 text-pink-700 border-pink-200", "Rosé")
    db.Orange -> #("bg-orange-50 text-orange-700 border-orange-200", "Orange")
    db.Sparkling -> #("bg-stone-50 text-stone-700 border-stone-200", "Sparkling")
    db.Dessert -> #("bg-amber-100 text-amber-900 border-amber-300", "Dessert")
    db.Sake -> #("bg-stone-100 text-stone-700 border-stone-300", "Sake")
    db.Other -> #("bg-stone-50 text-stone-700 border-stone-200", "Other")
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

      html.span([
        attr.class("font-medium tabular-nums"),
        attr.style("color: " <> red_green_scale(r)),
      ], [
        html.Text(float.to_string(r)),
      ])
    }
  }
}

// Map 3..5 to hue 0 (red) → 60 (yellow) → 120 (green)
fn red_green_scale(rating: Float) -> String {
  let clamped = case rating <. 3.0 { True -> 3.0 False -> case rating >. 5.0 { True -> 5.0 False -> rating } }
  let t = { clamped -. 3.0 } /. 2.0
  let hue = float.round(t *. 120.0)
  "hsl(" <> int.to_string(hue) <> " 70% 35%)"
}

fn display_winery(winery: String) -> String {
  case winery {
    "" -> "Unknown"
    w -> w
  }
}

fn display_vintage(vintage: Option(String)) -> String {
  case vintage {
    None -> ""
    Some("NV") -> "N.V."
    Some(v) -> v
  }
}

fn display_vintages(vintages: Option(String)) -> String {
  case vintages {
    None -> ""
    Some(v) -> v
  }
}

fn format_date(iso: String) -> String {
  case string.split(iso, " ") {
    [date, ..] -> {
      case string.split(date, "-") {
        [y, m, d] -> d <> "." <> m <> "." <> y
        _ -> date
      }
    }
    _ -> iso
  }
}

fn date_node(iso: String) -> Node {
  html.span([attr.Attr("title", iso)], [
    html.Text(format_date(iso)),
  ])
}

fn display_country(country: Option(String)) -> String {
  case country {
    None -> ""
    Some(c) -> iso_to_country(c)
  }
}

fn iso_to_country(code: String) -> String {
  case string.uppercase(string.trim(code)) {
    "FR" -> "France"
    "IT" -> "Italy"
    "ES" -> "Spain"
    "DE" -> "Germany"
    "PT" -> "Portugal"
    "AT" -> "Austria"
    "US" -> "United States"
    "AR" -> "Argentina"
    "CL" -> "Chile"
    "AU" -> "Australia"
    "NZ" -> "New Zealand"
    "ZA" -> "South Africa"
    "GR" -> "Greece"
    "HU" -> "Hungary"
    "GE" -> "Georgia"
    "LB" -> "Lebanon"
    "IL" -> "Israel"
    "HR" -> "Croatia"
    "SI" -> "Slovenia"
    "CH" -> "Switzerland"
    "RO" -> "Romania"
    "BG" -> "Bulgaria"
    "MD" -> "Moldova"
    "TR" -> "Turkey"
    "UY" -> "Uruguay"
    "BR" -> "Brazil"
    "MX" -> "Mexico"
    "CA" -> "Canada"
    "GB" -> "United Kingdom"
    "JP" -> "Japan"
    "CN" -> "China"
    "CZ" -> "Czech Republic"
    "UA" -> "Ukraine"
    other -> other
  }
}

fn display_optional(value: Option(String)) -> String {
  case value {
    None -> ""
    Some(v) -> v
  }
}

fn wine_url(wine: Wine) -> String {
  "/wines/" <> wine.id <> "/" <> db.slugify(wine.name)
}

fn winery_url(id: String, name: String) -> String {
  "/wineries/" <> id <> "/" <> db.slugify(name)
}

fn page(title: String, user: User, content: List(Node)) -> Response {
  layout(title, [
    site_header(user),
    html.div([attr.class("max-w-6xl mx-auto px-4 pb-12")], content),
  ])
  |> render
}

fn site_header(user: User) -> Node {
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
            nav_link("All Wines", "/wines"),
            nav_link("All Wineries", "/wineries"),
            html.span([attr.class("text-stone-300")], [html.Text("//")]),
            html.span([attr.class("text-sm text-stone-400")], [
              html.Text("~" <> user.username <> ":"),
            ]),
            nav_link("Cellar", "/~" <> user.username <> "/cellar"),
            nav_link("Wishlist", "/~" <> user.username <> "/wishlist"),
            nav_link("Ratings", "/~" <> user.username <> "/ratings"),
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
