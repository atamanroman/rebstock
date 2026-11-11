import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/auth.{type User}
import rebstock/db.{type CellarEntry, type CellarWine, type Rating}
import rebstock/web/components as c
import rebstock/web/profiles

pub fn home(conn: Connection, user: User) -> Response {
  case db.count_wines(conn) {
    0 ->
      c.page("Rebstock", user, conn, [
        welcome_empty_state(),
      ])
    _ ->
      c.page("Rebstock", user, conn, [
        user_section(conn, user.username, True, None),
        rating_insights(conn, user.username),
        activity_grid(conn, user.username),
      ])
  }
}

fn welcome_empty_state() -> Node {
  html.div([attr.class("welcome-state")], [
    c.page_header("Welcome to Rebstock", "Start your collection with a bottle."),
    html.div([attr.class("flex flex-wrap gap-3")], [
      html.a([attr.href("/wines/new"), attr.class("primary-action")], [
        html.Text("+ Add your first wine"),
      ]),
    ]),
  ])
}

pub fn profile(conn: Connection, user: User, username: String) -> Response {
  case db.get_profile(conn, username) {
    Error(_) -> c.not_found(user, conn)
    Ok(profile) ->
      c.page(profiles.display_name(profile) <> " — Rebstock", user, conn, [
        user_section(conn, username, username == user.username, Some(profile)),
        rating_insights(conn, username),
        activity_grid(conn, username),
      ])
  }
}

fn user_section(
  conn: Connection,
  username: String,
  is_self: Bool,
  profile: Option(db.Profile),
) -> Node {
  let all_cellar = db.cellar_wines(conn, username, db.unfiltered)
  let cellar_bottles =
    list.fold(all_cellar, 0, fn(acc, cw) { acc + cw.bottles })
  let cellar_wines = db.count_cellar_wines(conn, username)
  let rated_wines = db.count_rated_wines(conn, username)
  let heading = case is_self {
    True -> "Your collection"
    False -> username <> "'s collection"
  }

  html.div([attr.class("collection-overview")], [
    html.div([attr.class("page-toolbar")], [
      case profile {
        Some(profile) -> profiles.heading(profile)
        None -> c.page_header(heading, "Cellar and recent activity.")
      },
      case is_self {
        True ->
          html.a([attr.href("/wines/new"), attr.class("primary-action")], [
            html.Text("+ Add wine"),
          ])
        False -> html.Nothing
      },
    ]),
    html.dl([attr.class("stats-grid")], [
      c.stat_card(
        "Bottles in cellar",
        int.to_string(cellar_bottles),
        "/~" <> username <> "/cellar",
      ),
      c.stat_card(
        "Wines in cellar",
        int.to_string(cellar_wines),
        "/~" <> username <> "/cellar",
      ),
      c.stat_card(
        "Wines tasted",
        int.to_string(rated_wines),
        "/~" <> username <> "/ratings",
      ),
    ]),
  ])
}

fn rating_insights(conn: Connection, username: String) -> Node {
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

  case ratings_vs_vivino, cellar_vs_vivino {
    [], [] -> html.Nothing
    _, _ ->
      html.section([attr.class("rating-insights")], [
        html.hr([attr.class("section-divider")]),
        html.div([attr.class("flex items-baseline justify-between gap-3")], [
          html.h2([], [html.Text("Rating insights")]),
          html.span([attr.class("text-xs text-stone-600")], [
            html.Text("You & Vivino"),
          ]),
        ]),
        html.div([attr.class("grid grid-cols-1 md:grid-cols-2 gap-4 mt-4")], [
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
        ]),
      ])
  }
}

fn butterfly_side(
  label: String,
  base: String,
  rater: c.Rater,
) -> c.ButterflySide {
  c.ButterflySide(label, fn(bucket) { c.bar_url(base, rater, bucket) })
}

fn activity_grid(conn: Connection, username: String) -> Node {
  let top_cellar = db.top_cellar(conn, username, 5)
  let top_rated = db.top_ratings_by_user(conn, username, 5)
  let latest_rated = db.latest_ratings(conn, username, 5)
  let latest_cellar = db.latest_cellar_entries(conn, username, 5)

  html.div([], [
    html.div([attr.class("activity-grid")], [
      cellar_entry_section(
        "Recently cellared",
        "/~" <> username <> "/cellar",
        latest_cellar,
        conn,
      ),
      rating_section(
        "Recently tasted",
        "/~" <> username <> "/ratings",
        latest_rated,
        conn,
      ),
    ]),
    case top_cellar, top_rated {
      [], [] -> html.Nothing
      _, _ ->
        html.div([], [
          html.hr([attr.class("section-divider")]),
          html.div([attr.class("collection-highlights activity-grid")], [
            cellar_wine_section(
              "Cellar highlights",
              "/~" <> username <> "/cellar",
              top_cellar,
            ),
            rating_section(
              "Top rated",
              "/~" <> username <> "/ratings",
              top_rated,
              conn,
            ),
          ]),
        ])
    },
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
      html.section([], [
        c.section_header(title, link),
        c.item_list(
          "activity-list divide-y divide-stone-100",
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
          attr.class("activity-row items-center transition-colors"),
        ],
        [
          html.div([attr.class("min-w-0 flex-1")], [
            html.div([attr.class("flex items-center gap-2")], [
              html.span([attr.class("font-medium text-stone-800 text-sm")], [
                html.Text(wine.name),
              ]),
              html.span([attr.class("text-xs text-stone-500 shrink-0")], [
                html.Text(c.display_vintage(rating.vintage)),
              ]),
            ]),
            html.div([attr.class("text-xs text-stone-500 mt-0.5")], [
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
      html.section([], [
        c.section_header(title, link),
        c.item_list(
          "activity-list divide-y divide-stone-100",
          list.map(wines, fn(cw) {
            html.a(
              [
                attr.href(c.wine_url(cw.wine)),
                attr.class("activity-row items-center transition-colors"),
              ],
              [
                html.div([attr.class("min-w-0 flex-1")], [
                  html.div([attr.class("flex items-center gap-2")], [
                    html.span(
                      [
                        attr.class("font-medium text-stone-800 text-sm"),
                      ],
                      [html.Text(cw.wine.name)],
                    ),
                    html.span([attr.class("text-xs text-stone-500 shrink-0")], [
                      html.Text(c.display_vintage(cw.vintage)),
                    ]),
                  ]),
                  html.div([attr.class("text-xs text-stone-500 mt-0.5")], [
                    html.Text(c.display_winery(cw.wine.winery_name)),
                  ]),
                ]),
                html.div([attr.class("flex items-center gap-3 ml-4 shrink-0")], [
                  c.wine_type_badge(cw.wine.wine_type),
                  html.span(
                    [attr.class("text-xs text-stone-500 tabular-nums")],
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
      html.section([], [
        c.section_header(title, link),
        c.item_list(
          "activity-list divide-y divide-stone-100",
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
                    attr.class("activity-row items-center transition-colors"),
                  ],
                  [
                    html.div([attr.class("min-w-0 flex-1")], [
                      html.div([attr.class("flex items-center gap-2")], [
                        html.span(
                          [
                            attr.class("font-medium text-stone-800 text-sm"),
                          ],
                          [html.Text(wine.name)],
                        ),
                        html.span(
                          [attr.class("text-xs text-stone-500 shrink-0")],
                          [html.Text(c.display_vintage(e.vintage))],
                        ),
                      ]),
                      html.div([attr.class("text-xs text-stone-500 mt-0.5")], [
                        html.Text(c.display_winery(wine.winery_name)),
                      ]),
                    ]),
                    html.div(
                      [attr.class("flex items-center gap-3 ml-4 shrink-0")],
                      [
                        c.wine_type_badge(wine.wine_type),
                        html.span(
                          [attr.class("text-xs text-stone-500 tabular-nums")],
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
