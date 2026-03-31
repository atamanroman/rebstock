import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/auth.{type User}
import rebstock/db.{type CellarEntry, type CellarWine, type Rating}
import rebstock/web/components as c

pub fn home(conn: Connection, user: User) -> Response {
  let u = user.username
  let wine_count = db.count_wines(conn)
  let all_cellar = db.cellar_wines(conn, u)
  let cellar_count = list.fold(all_cellar, 0, fn(acc, cw) { acc + cw.bottles })

  let top_cellar = db.top_cellar(conn, u, 10)
  let top_rated = db.top_ratings_by_user(conn, u, 10)
  let latest_rated = db.latest_ratings(conn, u, 10)
  let latest_cellar = db.latest_cellar_entries(conn, u, 10)

  c.page("Rebstock", user, [
    html.div([attr.class("grid grid-cols-1 sm:grid-cols-3 gap-4 mb-10")], [
      c.stat_card("Known Wines", int.to_string(wine_count), "/wines"),
      c.stat_card(
        "Known Wineries",
        int.to_string(list.length(db.list_wineries(conn, u))),
        "/wineries",
      ),
      c.stat_card(
        "In Cellar",
        int.to_string(cellar_count) <> " bottles",
        "/~" <> u <> "/cellar",
      ),
    ]),
    html.div([attr.class("grid grid-cols-1 lg:grid-cols-2 gap-8")], [
      cellar_entry_section(
        "Recently Added to Cellar",
        "/~" <> u <> "/cellar",
        latest_cellar,
        conn,
      ),
      cellar_wine_section(
        "Top Cellar Wines",
        "/~" <> u <> "/cellar",
        top_cellar,
      ),
      rating_section(
        "Recently Rated",
        "/~" <> u <> "/ratings",
        latest_rated,
        conn,
      ),
      rating_section("Your Top Rated", "/~" <> u <> "/ratings", top_rated, conn),
    ]),
  ])
}

fn rating_section(
  title: String,
  link: String,
  ratings: List(Rating),
  conn: Connection,
) -> Node {
  case ratings {
    [] -> html.Nothing
    _ ->
      html.div([], [
        c.section_header(title, link),
        html.div(
          [
            attr.class(
              "bg-white rounded-lg border border-stone-200 divide-y divide-stone-100",
            ),
          ],
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
        [
          attr.href(c.wine_url(wine)),
          attr.class(
            "flex items-center justify-between px-4 py-3 hover:bg-amber-50/50 transition-colors block",
          ),
        ],
        [
          html.div([attr.class("min-w-0 flex-1")], [
            html.div([attr.class("flex items-center gap-2")], [
              html.span(
                [attr.class("font-medium text-stone-800 text-sm truncate")],
                [html.Text(wine.name)],
              ),
              html.span([attr.class("text-xs text-stone-400 shrink-0")], [
                html.Text(c.display_vintage(rating.vintage)),
              ]),
            ]),
            html.div([attr.class("text-xs text-stone-500 truncate mt-0.5")], [
              html.Text(c.display_winery(wine.winery_name)),
            ]),
          ]),
          html.div([attr.class("flex items-center gap-3 ml-4 shrink-0")], [
            c.wine_type_badge(wine.wine_type),
            ..case rating.rating {
              Some(r) -> [
                html.span(
                  [
                    attr.class(
                      "text-sm font-medium text-amber-700 tabular-nums",
                    ),
                  ],
                  [html.Text(float.to_string(r))],
                ),
              ]
              None -> []
            }
          ]),
        ],
      )
  }
}

fn cellar_wine_section(
  title: String,
  link: String,
  wines: List(CellarWine),
) -> Node {
  case wines {
    [] -> html.Nothing
    _ ->
      html.div([], [
        c.section_header(title, link),
        html.div(
          [
            attr.class(
              "bg-white rounded-lg border border-stone-200 divide-y divide-stone-100",
            ),
          ],
          list.map(wines, fn(cw) {
            html.a(
              [
                attr.href(c.wine_url(cw.wine)),
                attr.class(
                  "flex items-center justify-between px-4 py-3 hover:bg-amber-50/50 transition-colors block",
                ),
              ],
              [
                html.div([attr.class("min-w-0 flex-1")], [
                  html.div([attr.class("flex items-center gap-2")], [
                    html.span(
                      [
                        attr.class(
                          "font-medium text-stone-800 text-sm truncate",
                        ),
                      ],
                      [html.Text(cw.wine.name)],
                    ),
                    html.span([attr.class("text-xs text-stone-400 shrink-0")], [
                      html.Text(c.display_vintage(cw.vintage)),
                    ]),
                  ]),
                  html.div(
                    [attr.class("text-xs text-stone-500 truncate mt-0.5")],
                    [html.Text(c.display_winery(cw.wine.winery_name))],
                  ),
                ]),
                html.div([attr.class("flex items-center gap-3 ml-4 shrink-0")], [
                  c.wine_type_badge(cw.wine.wine_type),
                  html.span(
                    [attr.class("text-xs text-stone-400 tabular-nums")],
                    [html.Text(int.to_string(cw.bottles) <> "\u{00d7}")],
                  ),
                ]),
              ],
            )
          }),
        ),
      ])
  }
}

fn cellar_entry_section(
  title: String,
  link: String,
  entries: List(CellarEntry),
  conn: Connection,
) -> Node {
  case entries {
    [] -> html.Nothing
    _ ->
      html.div([], [
        c.section_header(title, link),
        html.div(
          [
            attr.class(
              "bg-white rounded-lg border border-stone-200 divide-y divide-stone-100",
            ),
          ],
          list.map(entries, fn(e) {
            case db.get_wine_by_id(conn, e.wine_id) {
              Error(_) -> html.Nothing
              Ok(wine) ->
                html.a(
                  [
                    attr.href("/cellar/" <> e.id),
                    attr.class(
                      "flex items-center justify-between px-4 py-3 hover:bg-amber-50/50 transition-colors block",
                    ),
                    attr.Attr("hx-get", "/cellar/" <> e.id <> "/overlay"),
                    attr.Attr("hx-target", "#overlay"),
                    attr.Attr("hx-swap", "outerHTML"),
                  ],
                  [
                    html.div([attr.class("min-w-0 flex-1")], [
                      html.div([attr.class("flex items-center gap-2")], [
                        html.span(
                          [
                            attr.class(
                              "font-medium text-stone-800 text-sm truncate",
                            ),
                          ],
                          [html.Text(wine.name)],
                        ),
                        html.span(
                          [attr.class("text-xs text-stone-400 shrink-0")],
                          [html.Text(c.display_vintages(wine.vintages))],
                        ),
                      ]),
                      html.div(
                        [attr.class("text-xs text-stone-500 truncate mt-0.5")],
                        [html.Text(c.display_winery(wine.winery_name))],
                      ),
                    ]),
                    html.div(
                      [attr.class("flex items-center gap-3 ml-4 shrink-0")],
                      [
                        c.wine_type_badge(wine.wine_type),
                        html.span(
                          [attr.class("text-xs text-stone-400 tabular-nums")],
                          [html.Text("+" <> int.to_string(e.quantity))],
                        ),
                      ],
                    ),
                  ],
                )
            }
          }),
        ),
      ])
  }
}
