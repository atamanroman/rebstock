import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/auth.{type User}
import rebstock/db.{type Rating, type Wine}
import rebstock/web/components as c

pub fn wines(conn: Connection, user: User) -> Response {
  let wines = db.list_wines(conn, user.username)
  let count = int.to_string(list.length(wines))

  c.page("All Wines \u{2014} Rebstock", user, [
    c.page_header("All Wines", count <> " total"),
    wine_table(wines),
  ])
}

pub fn wine_detail(conn: Connection, id: String, user: User) -> Response {
  case db.get_wine(conn, user.username, id) {
    Error(_) -> wisp.not_found()
    Ok(wine) ->
      c.page(wine.name <> " \u{2014} Rebstock", user, [
        c.back_link("/wines", "All wines"),
        html.div(
          [attr.class("bg-white rounded-lg border border-stone-200 p-6")],
          [
            html.div([attr.class("flex items-start justify-between mb-4")], [
              html.div([], [
                html.h1([attr.class("text-2xl font-light text-stone-800")], [
                  html.Text(wine.name),
                ]),
                html.p([attr.class("text-stone-500 mt-1")], [
                  c.link(c.winery_url(wine.winery_id, wine.winery_name), [
                    html.Text(c.display_winery(wine.winery_name)),
                  ]),
                  html.Text(case wine.vintages {
                    None -> ""
                    Some(_) -> " \u{00b7} " <> c.display_vintages(wine.vintages)
                  }),
                ]),
              ]),
              c.wine_type_badge(wine.wine_type),
            ]),
            c.detail_grid([
              #("Region", c.display_optional(wine.region)),
              #("Country", c.display_country(wine.country)),
              #("Style", c.display_optional(wine.style)),
            ]),
            ..wine_detail_sections(conn, wine, user)
          ],
        ),
      ])
  }
}

fn wine_detail_sections(conn: Connection, wine: Wine, user: User) -> List(Node) {
  let all_ratings = db.ratings_for_wine(conn, wine.id)
  let wine_vintages = db.vintages_for_wine(conn, wine.id)
  let vintage_rows =
    list.map(wine_vintages, fn(v) {
      let year = Some(v)
      let vivino_r =
        list.find(all_ratings, fn(r) {
          r.source == "vivino" && r.vintage == year
        })
      let my_r =
        list.find(all_ratings, fn(r) {
          r.source == "user" && r.username == user.username && r.vintage == year
        })
      let other_rs =
        list.filter(all_ratings, fn(r) {
          r.source == "user" && r.username != user.username && r.vintage == year
        })
      #(v, year, vivino_r, my_r, other_rs)
    })
  let my_general =
    list.filter(all_ratings, fn(r) {
      r.source == "user" && r.username == user.username && r.vintage == None
    })
  let other_general =
    list.filter(all_ratings, fn(r) {
      r.source == "user" && r.username != user.username && r.vintage == None
    })
  let vivino_general =
    list.find(all_ratings, fn(r) { r.source == "vivino" && r.vintage == None })
  [
    case vintage_rows {
      [] -> html.Nothing
      _ ->
        html.div([attr.class("mt-6 pt-6 border-t border-stone-100")], [
          html.table([attr.class("w-full text-sm")], [
            html.thead([], [
              html.tr([], [
                html.th(
                  [
                    attr.class(
                      "py-1 pr-4 text-left text-xs uppercase tracking-wider text-stone-400 font-medium",
                    ),
                  ],
                  [html.Text("Vintage")],
                ),
                html.th(
                  [
                    attr.class(
                      "py-1 pr-4 text-left text-xs uppercase tracking-wider text-stone-400 font-medium",
                    ),
                  ],
                  [html.Text("Vivino")],
                ),
                html.th(
                  [
                    attr.class(
                      "py-1 pr-4 text-left text-xs uppercase tracking-wider text-stone-400 font-medium",
                    ),
                  ],
                  [html.Text("Your Rating")],
                ),
              ]),
            ]),
            html.tbody(
              [],
              list.map(vintage_rows, fn(row) {
                let #(v_str, _year, vivino_r, my_r, _other_rs) = row
                html.tr([], [
                  html.td([attr.class("py-1 pr-4 font-medium tabular-nums")], [
                    html.Text(v_str),
                  ]),
                  html.td([attr.class("py-1 pr-4 tabular-nums")], [
                    vivino_cell(vivino_r, wine.vivino_id, v_str),
                  ]),
                  html.td([attr.class("py-1 pr-4 tabular-nums")], [
                    case my_r {
                      Ok(r) ->
                        c.rating_link(r, [
                          c.rating_display(r.rating),
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
              }),
            ),
          ]),
        ])
    },
    case my_general, vivino_general {
      [], Error(_) -> html.Nothing
      _, _ ->
        html.div([attr.class("mt-4 pt-4 border-t border-stone-100")], [
          html.h3(
            [
              attr.class("text-xs uppercase tracking-wider text-stone-400 mb-2"),
            ],
            [html.Text("General (no vintage)")],
          ),
          html.div([attr.class("flex items-center gap-6")], [
            case vivino_general {
              Ok(r) ->
                html.span([attr.class("inline-flex items-center gap-1")], [
                  html.span([attr.class("text-xs text-stone-400")], [
                    html.Text("Vivino:"),
                  ]),
                  c.rating_display(r.rating),
                ])
              Error(_) -> html.Nothing
            },
            ..list.map(my_general, fn(r) {
              html.span([attr.class("inline-flex items-center gap-1")], [
                html.span([attr.class("text-xs text-stone-400")], [
                  html.Text("You:"),
                ]),
                c.rating_link(r, [c.rating_display(r.rating)]),
                case r.tasting_notes {
                  Some(_) ->
                    html.span([attr.class("text-xs text-stone-400")], [
                      html.Text("w/ notes"),
                    ])
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
          html.h3(
            [
              attr.class("text-xs uppercase tracking-wider text-stone-400 mb-3"),
            ],
            [html.Text("Other Ratings")],
          ),
          html.div(
            [attr.class("space-y-2")],
            list.map(other_general, fn(r) {
              rating_entry(r, show_username: True)
            }),
          ),
        ])
    },
    case wine.personal_note {
      None -> html.Nothing
      Some(note) ->
        html.div([attr.class("mt-4")], [
          html.h3(
            [
              attr.class("text-xs uppercase tracking-wider text-stone-500 mb-2"),
            ],
            [html.Text("Personal Note")],
          ),
          html.p([attr.class("text-stone-700")], [html.Text(note)]),
        ])
    },
    {
      let bottles = db.cellar_bottle_count(conn, user.username, wine.id)
      let wishlisted = db.is_wishlisted(conn, user.username, wine.id)
      let links =
        [
          case bottles > 0 {
            True -> [
              c.action_link(
                "/~" <> user.username <> "/cellar",
                "View in cellar (" <> int.to_string(bottles) <> " bottles)",
              ),
            ]
            False -> []
          },
          case wishlisted {
            True -> [
              c.action_link(
                "/~" <> user.username <> "/wishlist#wine-" <> wine.id,
                "View in wishlist \u{2192}",
              ),
            ]
            False -> []
          },
          case wine.vivino_id {
            Some(id) -> [
              c.action_link(
                "https://www.vivino.com/wines/" <> id,
                "View on Vivino \u{2192}",
              ),
            ]
            None -> []
          },
        ]
        |> list.flatten
      case links {
        [] -> html.Nothing
        _ ->
          html.div(
            [
              attr.class(
                "mt-6 pt-6 border-t border-stone-100 flex flex-col gap-2",
              ),
            ],
            links,
          )
      }
    },
  ]
}

fn vivino_cell(
  vivino_r: Result(Rating, Nil),
  vivino_id: Option(String),
  v_str: String,
) -> Node {
  case vivino_r, vivino_id {
    Ok(r), Some(id) ->
      html.a(
        [
          attr.href("https://www.vivino.com/wines/" <> id <> "?year=" <> v_str),
          attr.class(
            "underline decoration-2 decoration-rose-800 underline-offset-2 hover:text-rose-800 transition-colors",
          ),
        ],
        [c.rating_display(r.rating)],
      )
    Ok(r), None -> c.rating_display(r.rating)
    Error(_), Some(id) ->
      html.a(
        [
          attr.href("https://www.vivino.com/wines/" <> id <> "?year=" <> v_str),
          attr.class(
            "text-xs text-stone-400 underline decoration-2 decoration-rose-800 underline-offset-2 hover:text-rose-800",
          ),
        ],
        [html.Text("view")],
      )
    Error(_), None -> html.Text("\u{2014}")
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
          let who = case su {
            True -> r.username <> " \u{00b7} "
            False -> ""
          }
          let yr = case r.vintage {
            Some(_) -> c.display_vintage(r.vintage) <> " \u{00b7} "
            None -> ""
          }
          who <> yr
        }),
        c.date_node(case r.rated_at {
          Some(date) -> date
          None -> r.created_at
        }),
      ]),
    ]),
    case r.rating {
      Some(v) -> c.rating_display(Some(v))
      None -> html.Nothing
    },
  ])
}

pub fn wine_table(wines: List(Wine)) -> Node {
  html.div([attr.class("overflow-x-auto rounded-lg border border-stone-200")], [
    html.table([attr.class("w-full text-sm")], [
      html.thead([], [
        html.tr([attr.class("bg-stone-50 border-b border-stone-200")], [
          c.th("Winery"),
          c.th("Wine"),
          c.th("Vintage"),
          c.th("Country"),
          c.th("Type"),
        ]),
      ]),
      html.tbody([], list.index_map(wines, wine_row)),
    ]),
  ])
}

fn wine_row(wine: Wine, idx: Int) -> Node {
  html.tr([attr.class(c.row_class(idx))], [
    html.td([attr.class("px-4 py-3 text-stone-700")], [
      c.link(c.winery_url(wine.winery_id, wine.winery_name), [
        html.Text(c.display_winery(wine.winery_name)),
      ]),
    ]),
    html.td([attr.class("px-4 py-3 font-medium text-stone-800")], [
      c.link(c.wine_url(wine), [html.Text(wine.name)]),
    ]),
    html.td([attr.class("px-4 py-3 text-stone-500 tabular-nums")], [
      html.Text(c.display_vintages(wine.vintages)),
    ]),
    html.td([attr.class("px-4 py-3 text-stone-600")], [
      html.Text(c.display_country(wine.country)),
    ]),
    html.td([attr.class("px-4 py-3")], [c.wine_type_badge(wine.wine_type)]),
  ])
}
