import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type User}
import rebstock/db.{type CellarEntry, type Rating, type Wine}
import rebstock/web/components as c

pub fn wines(conn: Connection, user: User) -> Response {
  let wines = db.list_wines(conn, user.username)
  let count = int.to_string(list.length(wines))

  c.page("All Wines \u{2014} Rebstock", user, [
    c.page_header("All Wines", count <> " total"),
    wine_table(wines),
  ])
}

pub fn wine_detail(
  req: Request,
  conn: Connection,
  id: String,
  user: User,
) -> Response {
  let selected = case list.key_find(wisp.get_query(req), "vintage") {
    Ok("") -> None
    Ok(v) -> Some(v)
    Error(_) -> None
  }

  case db.get_wine(conn, user.username, id) {
    Error(_) -> wisp.not_found()
    Ok(wine) -> {
      let all_ratings = db.ratings_for_wine(conn, wine.id)
      let vintages = db.vintages_for_wine(conn, wine.id)

      let my =
        list.filter(all_ratings, fn(r) {
          r.source == "user" && r.username == user.username
        })
      let others =
        list.filter(all_ratings, fn(r) {
          r.source == "user" && r.username != user.username
        })
      let vivino = list.filter(all_ratings, fn(r) { r.source == "vivino" })

      let has_nv = list.any(all_ratings, fn(r) { r.vintage == None })
      let vintage_opts = case has_nv {
        True -> list.append(vintages, ["NV"])
        False -> vintages
      }

      c.page(wine.name <> " \u{2014} Rebstock", user, [
        c.back_link("/wines", "All wines"),
        c.card([
          wine_header(wine),
          ..wine_body(
            wine,
            vintage_opts,
            selected,
            vivino,
            my,
            others,
            conn,
            user,
          )
        ]),
      ])
    }
  }
}

// --- Header ---

fn wine_header(wine: Wine) -> Node {
  html.div([], [
    html.div([attr.class("flex gap-6")], [
      // Bottle image placeholder
      html.div(
        [
          attr.class(
            "hidden sm:flex w-28 h-28 shrink-0 rounded-lg bg-stone-100 border border-stone-200 items-center justify-center p-1",
          ),
        ],
        [
          html.UnsafeInlineHtml(
            "<svg class=\"w-full h-full\" viewBox=\"0 0 80 220\" fill=\"#2d5a27\" xmlns=\"http://www.w3.org/2000/svg\">"
            <> "<path d=\"M30,0 L30,4 L26,4 L26,8 L30,8 L30,38 C30,52 10,62 10,80 L10,206 C10,214 16,220 24,220 L56,220 C64,220 70,214 70,206 L70,80 C70,62 50,52 50,38 L50,8 L54,8 L54,4 L50,4 L50,0 Z\"/>"
            <> "</svg>",
          ),
        ],
      ),
      // Wine details
      html.div([attr.class("flex-1 min-w-0")], [
        html.div([attr.class("flex items-start justify-between mb-2")], [
          html.h1([attr.class("text-2xl font-light text-stone-800")], [
            html.Text(wine.name),
          ]),
          c.wine_type_badge(wine.wine_type),
        ]),
        html.p([attr.class("text-stone-500")], [
          c.link(c.winery_url(wine.winery_id, wine.winery_name), [
            html.Text(c.display_winery(wine.winery_name)),
          ]),
        ]),
        c.detail_grid([
          #("Region", c.display_optional(wine.region)),
          #("Country", c.display_country(wine.country)),
          #("Style", c.display_optional(wine.style)),
        ]),
      ]),
    ]),
  ])
}

fn vintage_pills(
  wine: Wine,
  options: List(String),
  selected: Option(String),
) -> Node {
  case options {
    [] -> html.Nothing
    _ -> {
      let base = c.wine_url(wine)
      html.div([attr.class("flex flex-wrap gap-2 mt-4")], [
        vintage_pill("All", base, selected == None),
        ..list.map(options, fn(v) {
          let label = case v {
            "NV" -> "N.V."
            year -> year
          }
          vintage_pill(label, base <> "?vintage=" <> v, selected == Some(v))
        })
      ])
    }
  }
}

fn vintage_pill(label: String, href: String, active: Bool) -> Node {
  let classes = case active {
    True -> "px-3 py-1 rounded-full text-sm bg-rose-800 text-white"
    False ->
      "px-3 py-1 rounded-full text-sm bg-stone-100 text-stone-600 hover:bg-stone-200 transition-colors"
  }
  html.a([attr.href(href), attr.class(classes)], [html.Text(label)])
}

fn stat_boxes(
  vivino: List(Rating),
  my: List(Rating),
  others: List(Rating),
) -> Node {
  html.div([attr.class("grid grid-cols-3 gap-3 mt-4")], [
    stat_box("Vivino", avg_rating(vivino), count_rated(vivino)),
    stat_box("You", avg_rating(my), count_rated(my)),
    stat_box("Others", avg_rating(others), count_rated(others)),
  ])
}

fn stat_box(label: String, avg: Option(Float), count: Int) -> Node {
  html.div(
    [
      attr.class(
        "p-3 bg-stone-50 rounded-lg border border-stone-100 text-center",
      ),
    ],
    [
      html.div([attr.class("text-lg font-light")], [c.rating_display(avg)]),
      html.div([attr.class("text-xs text-stone-400 mt-0.5")], [
        html.Text(label),
      ]),
      html.div([attr.class("text-xs text-stone-400")], [
        html.Text(
          int.to_string(count)
          <> case count {
            1 -> " rating"
            _ -> " ratings"
          },
        ),
      ]),
    ],
  )
}

// --- Rating helpers ---

fn count_rated(ratings: List(Rating)) -> Int {
  list.length(list.filter(ratings, fn(r) { option.is_some(r.rating) }))
}

fn avg_rating(ratings: List(Rating)) -> Option(Float) {
  let vals =
    list.filter_map(ratings, fn(r) {
      case r.rating {
        Some(v) -> Ok(v)
        None -> Error(Nil)
      }
    })
  case vals {
    [] -> None
    _ -> {
      let sum = list.fold(vals, 0.0, fn(acc, v) { acc +. v })
      Some(round1(sum /. int.to_float(list.length(vals))))
    }
  }
}

fn round1(f: Float) -> Float {
  int.to_float(float.round(f *. 10.0)) /. 10.0
}

fn filter_by_vintage(
  ratings: List(Rating),
  selected: Option(String),
) -> List(Rating) {
  case selected {
    None -> ratings
    Some(v) -> list.filter(ratings, fn(r) { vintage_matches(r, v) })
  }
}

fn vintage_matches(r: Rating, v: String) -> Bool {
  case v {
    "NV" -> r.vintage == None
    year -> r.vintage == Some(year)
  }
}

// --- Body sections ---

fn wine_body(
  wine: Wine,
  vintage_opts: List(String),
  selected: Option(String),
  vivino: List(Rating),
  my: List(Rating),
  others: List(Rating),
  conn: Connection,
  user: User,
) -> List(Node) {
  let fv = filter_by_vintage(vivino, selected)
  let fm = filter_by_vintage(my, selected)
  let fo = filter_by_vintage(others, selected)
  let cellar_entries =
    list.filter(db.cellar_entries_for_wine(conn, wine.id), fn(e) {
      e.username == user.username
    })

  [
    html.div([attr.class("mt-8")], [
      section_label("Ratings"),
      vintage_pills(wine, vintage_opts, selected),
      html.div([attr.class("pl-4 ml-1 border-l-2 border-stone-200")], [
        stat_boxes(fv, fm, fo),
        my_ratings_section(fm, wine),
        others_ratings_section(fo),
      ]),
    ]),
    cellar_section(cellar_entries, wine),
    personal_note_section(wine),
    action_links_section(wine, conn, user),
  ]
}

fn my_ratings_section(ratings: List(Rating), wine: Wine) -> Node {
  html.div([attr.class("mt-6")], [
    html.div([attr.class("flex items-baseline justify-between mb-3")], [
      section_label("You"),
      rate_button(wine, case ratings {
        [] -> "Rate this wine"
        _ -> "Add rating"
      }),
    ]),
    case ratings {
      [] -> html.Nothing
      _ ->
        html.div(
          [attr.class("space-y-2")],
          list.map(ratings, fn(r) { my_rating_card(r, wine) }),
        )
    },
  ])
}

fn others_ratings_section(ratings: List(Rating)) -> Node {
  case ratings {
    [] -> html.Nothing
    _ ->
      html.div([attr.class("mt-8")], [
        section_label("Others"),
        html.div(
          [attr.class("space-y-2")],
          list.map(ratings, other_rating_card),
        ),
      ])
  }
}

fn personal_note_section(wine: Wine) -> Node {
  case wine.personal_note {
    None -> html.Nothing
    Some(note) ->
      html.div([attr.class("mt-8")], [
        section_label("Personal Note"),
        html.p([attr.class("text-stone-700")], [html.Text(note)]),
      ])
  }
}

fn action_links_section(wine: Wine, conn: Connection, user: User) -> Node {
  let wishlisted = db.is_wishlisted(conn, user.username, wine.id)
  let links =
    [
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
        Some(vid) -> [
          c.action_link(
            "https://www.vivino.com/wines/" <> vid,
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
          attr.class("mt-8 flex flex-col gap-2"),
        ],
        links,
      )
  }
}

// --- Rating card components ---

fn rate_button(wine: Wine, label: String) -> Node {
  let url = c.wine_url(wine) <> "/ratings/new"
  html.a(
    [
      attr.href(url),
      attr.class(
        "text-xs text-rose-800 hover:text-rose-900 transition-colors cursor-pointer",
      ),
      attr.Attr("hx-get", url),
      attr.Attr("hx-push-url", url),
      attr.Attr("hx-target", "#overlay"),
      attr.Attr("hx-swap", "outerHTML"),
    ],
    [html.Text(label)],
  )
}

fn edit_button(rating: Rating, wine: Wine) -> Node {
  let url = c.wine_url(wine) <> "/ratings/" <> rating.id <> "/edit"
  html.a(
    [
      attr.href(url),
      attr.class(
        "text-xs text-rose-800 hover:text-rose-900 transition-colors cursor-pointer",
      ),
      attr.Attr("hx-get", url),
      attr.Attr("hx-push-url", url),
      attr.Attr("hx-target", "#overlay"),
      attr.Attr("hx-swap", "outerHTML"),
    ],
    [html.Text("Edit")],
  )
}

fn section_label(text: String) -> Node {
  html.h3(
    [
      attr.class(
        "text-sm font-medium uppercase tracking-wider text-stone-400 mb-3",
      ),
    ],
    [html.Text(text)],
  )
}

fn my_rating_card(r: Rating, wine: Wine) -> Node {
  html.div(
    [
      attr.class(
        "bg-stone-50/50 rounded-lg border border-stone-100 p-2 relative",
      ),
    ],
    [
      // Edit top-right
      html.div([attr.class("absolute top-2 right-2 flex gap-2")], [
        edit_button(r, wine),
      ]),
      html.div([attr.class("flex gap-4")], [
        // Left: rating, vintage, date
        html.div(
          [attr.class("shrink-0 flex flex-col items-center justify-center")],
          [
            html.p([attr.class("text-xs text-stone-400")], [
              html.Text(case r.vintage {
                Some(_) -> c.display_vintage(r.vintage)
                None -> ""
              }),
            ]),
            html.div([attr.class("text-3xl")], [c.rating_display(r.rating)]),
            html.p([attr.class("text-xs text-stone-400")], [
              c.date_node(case r.rated_at {
                Some(date) -> date
                None -> r.created_at
              }),
            ]),
          ],
        ),
        // Divider
        html.div([attr.class("w-px bg-stone-200 self-stretch")], []),
        // Right: tasting notes
        html.div([attr.class("flex-1 min-w-0")], [
          case r.tasting_notes {
            Some(notes) ->
              html.p([attr.class("text-stone-700 whitespace-pre-line")], [
                html.Text(notes),
              ])
            None ->
              html.p([attr.class("text-stone-400 italic text-sm")], [
                html.Text("No tasting notes"),
              ])
          },
        ]),
      ]),
    ],
  )
}

fn other_rating_card(r: Rating) -> Node {
  html.div(
    [
      attr.class("bg-stone-50/50 rounded-lg border border-stone-100 p-2"),
    ],
    [
      html.div([attr.class("flex gap-4")], [
        // Left: rating, vintage, date
        html.div(
          [attr.class("shrink-0 flex flex-col items-center justify-center")],
          [
            html.p([attr.class("text-xs text-stone-400")], [
              html.Text(case r.vintage {
                Some(_) -> c.display_vintage(r.vintage)
                None -> ""
              }),
            ]),
            html.div([attr.class("text-3xl")], [c.rating_display(r.rating)]),
            html.p([attr.class("text-xs text-stone-400")], [
              c.date_node(case r.rated_at {
                Some(date) -> date
                None -> r.created_at
              }),
            ]),
          ],
        ),
        // Divider
        html.div([attr.class("w-px bg-stone-200 self-stretch")], []),
        // Right: quoted notes + attribution
        html.div([attr.class("flex-1 min-w-0")], [
          case r.tasting_notes {
            Some(notes) ->
              html.p([attr.class("text-stone-700 italic whitespace-pre-line")], [
                html.Text("\u{201c}" <> notes <> "\u{201d}"),
              ])
            None ->
              html.p([attr.class("text-stone-400 italic text-sm")], [
                html.Text("No tasting notes"),
              ])
          },
          html.p([attr.class("text-xs text-stone-400 mt-1")], [
            html.Text("\u{2014} "),
            c.link("/~" <> r.username <> "/ratings", [
              html.Text(r.username),
            ]),
          ]),
        ]),
      ]),
    ],
  )
}

// --- Cellar section ---

fn cellar_section(entries: List(CellarEntry), wine: Wine) -> Node {
  let net = list.fold(entries, 0, fn(acc, e) { acc + e.quantity })
  let net_label = int.to_string(net) <> " bottles"
  // Sort newest first by date, then created_at
  let sorted =
    list.sort(entries, fn(a, b) {
      let da = option.unwrap(a.date, a.created_at)
      let db = option.unwrap(b.date, b.created_at)
      string.compare(db, da)
    })
  // Compute remaining per parent for drink button visibility
  let parent_remaining = compute_parent_remaining(entries)

  html.div([attr.class("mt-8")], [
    html.div([attr.class("flex items-baseline justify-between mb-3")], [
      html.div([attr.class("flex items-baseline gap-2")], [
        section_label("Cellar"),
        html.span(
          [
            attr.class(case net < 0 {
              True -> "text-xs text-red-500"
              False -> "text-xs text-stone-400"
            }),
          ],
          [html.Text(net_label)],
        ),
      ]),
      add_cellar_button(wine),
    ]),
    case sorted {
      [] ->
        html.p([attr.class("text-sm text-stone-400 italic")], [
          html.Text("No cellar entries"),
        ])
      _ ->
        html.div(
          [attr.class("space-y-2")],
          list.map(sorted, fn(e) {
            cellar_entry_inline(e, wine, parent_remaining)
          }),
        )
    },
  ])
}

fn compute_parent_remaining(entries: List(CellarEntry)) -> List(#(String, Int)) {
  // For each parent entry, compute: original quantity + sum of child quantities
  let parents = list.filter(entries, fn(e) { e.parent_id == None })
  list.map(parents, fn(p) {
    let children = list.filter(entries, fn(e) { e.parent_id == Some(p.id) })
    let consumed = list.fold(children, 0, fn(acc, c) { acc + c.quantity })
    #(p.id, p.quantity + consumed)
  })
}

fn cellar_entry_inline(
  entry: CellarEntry,
  wine: Wine,
  parent_remaining: List(#(String, Int)),
) -> Node {
  let is_drink = option.is_some(entry.parent_id)
  let qty_text = case is_drink {
    True -> "\u{2212}" <> int.to_string(int.absolute_value(entry.quantity))
    False -> int.to_string(entry.quantity) <> "\u{00d7}"
  }
  let qty_class = case is_drink {
    True -> "text-2xl font-light text-stone-400 tabular-nums"
    False -> "text-3xl font-light text-stone-800 tabular-nums"
  }

  html.div(
    [
      attr.id("cellar-" <> entry.id),
      attr.class(
        "bg-stone-50/50 rounded-lg border border-stone-100 p-2 relative target-highlight",
      ),
    ],
    [
      // Action links top-right
      html.div(
        [attr.class("absolute top-2 right-2 flex gap-2")],
        case is_drink {
          False -> {
            let remaining = case list.key_find(parent_remaining, entry.id) {
              Ok(r) -> r
              Error(_) -> entry.quantity
            }
            list.flatten([
              case remaining > 0 {
                True -> [drink_button(entry, wine)]
                False -> []
              },
              [
                cellar_action_link(
                  c.wine_url(wine) <> "/cellar/" <> entry.id <> "/edit",
                  "Edit",
                ),
              ],
            ])
          }
          True -> [
            cellar_action_link(
              c.wine_url(wine) <> "/cellar/" <> entry.id <> "/edit",
              "Edit",
            ),
          ]
        },
      ),
      html.div([attr.class("flex gap-4")], [
        // Left: quantity, vintage, date
        html.div(
          [attr.class("shrink-0 flex flex-col items-center justify-center")],
          [
            html.p([attr.class("text-xs text-stone-400")], [
              html.Text(case entry.vintage {
                Some(_) -> c.display_vintage(entry.vintage)
                None -> ""
              }),
            ]),
            html.div([attr.class(qty_class)], [html.Text(qty_text)]),
            html.p([attr.class("text-xs text-stone-400")], [
              c.date_node(case entry.date {
                Some(d) -> d
                None -> entry.created_at
              }),
            ]),
          ],
        ),
        // Divider
        html.div([attr.class("w-px bg-stone-200 self-stretch")], []),
        // Right: notes
        html.div([attr.class("flex-1 min-w-0")], [
          case entry.notes {
            Some(notes) ->
              html.p([attr.class("text-stone-700 whitespace-pre-line")], [
                html.Text(notes),
              ])
            None ->
              html.p([attr.class("text-stone-400 italic text-sm")], [
                html.Text(case is_drink {
                  True -> "Drank a bottle"
                  False -> "No notes"
                }),
              ])
          },
        ]),
      ]),
    ],
  )
}

fn add_cellar_button(wine: Wine) -> Node {
  let url = c.wine_url(wine) <> "/cellar/new"
  html.a(
    [
      attr.href(url),
      attr.class(
        "text-xs text-rose-800 hover:text-rose-900 transition-colors cursor-pointer",
      ),
      attr.Attr("hx-get", url),
      attr.Attr("hx-push-url", url),
      attr.Attr("hx-target", "#overlay"),
      attr.Attr("hx-swap", "outerHTML"),
    ],
    [html.Text("Add to cellar")],
  )
}

fn drink_button(entry: CellarEntry, wine: Wine) -> Node {
  let url = c.wine_url(wine) <> "/cellar/" <> entry.id <> "/drink"
  html.a(
    [
      attr.href(url),
      attr.class(
        "text-xs text-rose-800 hover:text-rose-900 transition-colors cursor-pointer",
      ),
      attr.Attr("hx-get", url),
      attr.Attr("hx-push-url", url),
      attr.Attr("hx-target", "#overlay"),
      attr.Attr("hx-swap", "outerHTML"),
    ],
    [html.Text("Drink")],
  )
}

fn cellar_action_link(url: String, label: String) -> Node {
  html.a(
    [
      attr.href(url),
      attr.class(
        "text-xs text-rose-800 hover:text-rose-900 transition-colors cursor-pointer",
      ),
      attr.Attr("hx-get", url),
      attr.Attr("hx-push-url", url),
      attr.Attr("hx-target", "#overlay"),
      attr.Attr("hx-swap", "outerHTML"),
    ],
    [html.Text(label)],
  )
}

// --- Wine table ---

pub fn wine_table(wines: List(Wine)) -> Node {
  c.table(
    ["Winery", "Wine", "Vintage", "Country", "Type"],
    list.index_map(wines, wine_row),
  )
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
