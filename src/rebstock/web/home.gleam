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
  case db.count_wines(conn) {
    0 ->
      c.page("Rebstock", user, conn, [
        welcome_empty_state(),
      ])
    _ ->
      c.page("Rebstock", user, conn, [
        user_section(conn, user.username, True),
        activity_grid(conn, user.username),
      ])
  }
}

fn welcome_empty_state() -> Node {
  html.div([attr.class("text-center pt-16 pb-24")], [
    html.div([attr.class("text-6xl mb-6")], [html.Text("\u{1f347}")]),
    html.h1(
      [attr.class("text-3xl font-light text-stone-800 tracking-tight mb-3")],
      [html.Text("Welcome to Rebstock")],
    ),
    html.p([attr.class("text-stone-500 mb-8")], [
      html.Text("Start your collection with a bottle."),
    ]),
    html.a(
      [
        attr.href("/wines/new"),
        attr.class(
          "inline-block px-6 py-3 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors font-medium",
        ),
      ],
      [html.Text("Add your first wine")],
    ),
  ])
}

pub fn profile(conn: Connection, user: User, username: String) -> Response {
  let title = case username == user.username {
    True -> "Rebstock"
    False -> username
  }

  c.page(title, user, conn, [
    user_section(conn, username, False),
    activity_grid(conn, username),
  ])
}

fn user_section(conn: Connection, username: String, is_self: Bool) -> Node {
  let all_cellar = db.cellar_wines(conn, username, db.unfiltered)
  let cellar_bottles =
    list.fold(all_cellar, 0, fn(acc, cw) { acc + cw.bottles })
  let cellar_wines = db.count_cellar_wines(conn, username)
  let cellar_wineries = db.count_cellar_wineries(conn, username)
  let rated_wines = db.count_rated_wines(conn, username)
  let rated_wineries = db.count_rated_wineries(conn, username)
  let total_wines = db.count_wines(conn)
  let ratings_vs_vivino =
    db.pair_distributions(
      db.rating_distribution(conn, username),
      db.vivino_distribution_of_rated(conn, username),
    )
  let cellar_vs_vivino =
    db.pair_distributions(
      db.cellar_own_distribution(conn, username),
      db.cellar_vivino_distribution(conn, username),
    )

  let heading = case is_self {
    True -> "Your Stats"
    False -> username <> "'s Stats"
  }

  html.div([attr.class("mb-10")], [
    html.h2([attr.class("text-lg font-semibold text-stone-800 mb-4")], [
      html.Text(heading),
    ]),
    html.div([attr.class("grid grid-cols-1 sm:grid-cols-3 gap-4")], [
      c.stat_card(
        "Tasted",
        int.to_string(rated_wines)
          <> " wines from "
          <> int.to_string(rated_wineries)
          <> " wineries",
        "/~" <> username <> "/ratings",
      ),
      c.stat_card(
        "In Cellar",
        int.to_string(cellar_bottles)
          <> " bottles \u{00b7} "
          <> int.to_string(cellar_wines)
          <> " wines from "
          <> int.to_string(cellar_wineries)
          <> " wineries",
        "/~" <> username <> "/cellar",
      ),
      c.stat_card(
        "Rated",
        int.to_string(rated_wines)
          <> " of "
          <> int.to_string(total_wines)
          <> " wines",
        "/~" <> username <> "/ratings",
      ),
    ]),
    case ratings_vs_vivino, cellar_vs_vivino {
      [], [] -> html.Nothing
      _, _ ->
        html.div([attr.class("mt-4 grid grid-cols-1 lg:grid-cols-2 gap-4")], [
          c.rating_butterfly(
            "Rating Distribution",
            "ratings",
            butterfly_side("You", "/~" <> username <> "/ratings", c.Mine),
            butterfly_side("Vivino", "/~" <> username <> "/ratings", c.Vivino),
            ratings_vs_vivino,
          ),
          c.rating_butterfly(
            "Cellar Quality",
            "bottles",
            butterfly_side("You", "/~" <> username <> "/cellar", c.Mine),
            butterfly_side("Vivino", "/~" <> username <> "/cellar", c.Vivino),
            cellar_vs_vivino,
          ),
        ])
    },
  ])
}

fn butterfly_side(
  label: String,
  base: String,
  rater: c.Rater,
) -> c.ButterflySide {
  c.ButterflySide(label, fn(bucket) { c.bar_url(base, rater, bucket) })
}

fn activity_grid(conn: Connection, username: String) -> Node {
  let top_cellar = db.top_cellar(conn, username, 10)
  let top_rated = db.top_ratings_by_user(conn, username, 10)
  let latest_rated = db.latest_ratings(conn, username, 10)
  let latest_cellar = db.latest_cellar_entries(conn, username, 10)

  html.div([attr.class("grid grid-cols-1 lg:grid-cols-2 gap-8")], [
    cellar_entry_section(
      "Recently Added to Cellar",
      "/~" <> username <> "/cellar",
      latest_cellar,
      conn,
    ),
    cellar_wine_section(
      "Cellar Highlights",
      "/~" <> username <> "/cellar",
      top_cellar,
    ),
    rating_section(
      "Recently Rated",
      "/~" <> username <> "/ratings",
      latest_rated,
      conn,
    ),
    rating_section("Top Rated", "/~" <> username <> "/ratings", top_rated, conn),
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
                    attr.href(
                      c.wine_url(wine)
                      <> "#cellar-"
                      <> option.unwrap(e.parent_id, e.id),
                    ),
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
                          [html.Text(wine.name)],
                        ),
                        html.span(
                          [attr.class("text-xs text-stone-400 shrink-0")],
                          [html.Text(c.display_vintage(e.vintage))],
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
