import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import nakai/attr
import nakai/html.{type Node}
import simplifile
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type User}
import rebstock/db.{type CellarEntry, type Rating, type Wine, type WineList}
import rebstock/vivino
import rebstock/web/components as c

pub fn wines(conn: Connection, user: User) -> Response {
  let wines = db.list_wines(conn, user.username)
  let count = int.to_string(list.length(wines))

  c.page("All Wines \u{2014} Rebstock", user, conn, [
    html.div([attr.class("flex items-end justify-between mb-6")], [
      c.page_header("All Wines", count <> " total"),
      html.div([attr.class("flex gap-2")], [
        html.a(
          [
            attr.href("/wines/new"),
            attr.class(
              "px-4 py-2 bg-rose-800 text-white rounded-lg text-sm hover:bg-rose-900 transition-colors",
            ),
          ],
          [html.Text("Add Wine")],
        ),
        html.a(
          [
            attr.href("/wines/import/vivino"),
            attr.class(
              "px-4 py-2 border border-stone-300 text-stone-700 rounded-lg text-sm hover:bg-stone-50 transition-colors",
            ),
          ],
          [html.Text("Import from Vivino")],
        ),
      ]),
    ]),
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
    Error(_) -> c.not_found(user, conn)
    Ok(wine) -> {
      let all_ratings = db.ratings_for_wine(conn, wine.id)
      let vintage_ratings = db.vintage_ratings_for_wine(conn, wine.id)
      let vintages = list.map(vintage_ratings, fn(v) { v.year })
      let user_lists =
        db.lists_for_user(conn, user.username)
        |> list.filter(fn(l) {
          l.list_type == db.WishlistList || l.list_type == db.CustomList
        })
      let my = list.filter(all_ratings, fn(r) { r.username == user.username })
      let others =
        list.filter(all_ratings, fn(r) { r.username != user.username })

      let has_nv = list.any(all_ratings, fn(r) { r.vintage == None })
      let vintage_opts = case has_nv {
        True -> list.append(vintages, ["NV"])
        False -> vintages
      }

      let in_list_ids =
        db.list_ids_containing_wine(conn, user.username, wine.id)

      c.page(wine.name <> " \u{2014} Rebstock", user, conn, [
        c.back_link("/wines", "All wines"),
        c.card([
          wine_header(wine, user, user_lists, in_list_ids, selected),
          ..wine_body(
            wine,
            vintage_ratings,
            vintage_opts,
            selected,
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

fn wine_header(
  wine: Wine,
  user: User,
  user_lists: List(WineList),
  in_list_ids: List(String),
  selected_vintage: Option(String),
) -> Node {
  html.div([], [
    html.div([attr.class("flex gap-6")], [
      c.wine_image(wine.id, "hidden sm:flex w-28 h-28 shrink-0 rounded-lg"),
      // Wine details
      html.div([attr.class("flex-1 min-w-0")], [
        html.div([attr.class("flex items-start justify-between mb-2")], [
          html.div([attr.class("flex items-center gap-2")], [
            html.h1([attr.class("text-2xl font-light text-stone-800")], [
              html.Text(wine.name),
            ]),
            c.wine_type_badge(wine.wine_type),
          ]),
          html.div([attr.class("flex items-center gap-2")], [
            case user_lists {
              [] -> html.Nothing
              _ ->
                html.Element("details", [attr.class("relative")], [
                  html.Element(
                    "summary",
                    [
                      attr.class(
                        "cursor-pointer text-xs text-stone-400 hover:text-rose-800 transition-colors list-none",
                      ),
                    ],
                    [html.Text("Add to List")],
                  ),
                  html.div(
                    [
                      attr.class(
                        "absolute right-0 top-6 bg-white border border-stone-200 rounded-lg shadow-lg py-2 px-3 min-w-[180px] z-20",
                      ),
                    ],
                    list.map(user_lists, fn(l) {
                      let checked = list.contains(in_list_ids, l.id)
                      list_checkbox_row(
                        wine,
                        l,
                        checked,
                        selected_vintage,
                        user.username,
                      )
                    }),
                  ),
                ])
            },
            case wine.created_by == user.username {
              False -> html.Nothing
              True ->
                html.a(
                  [
                    attr.href(c.wine_url(wine) <> "/edit"),
                    attr.class(
                      "text-xs text-stone-400 hover:text-rose-800 transition-colors",
                    ),
                  ],
                  [html.Text("Edit")],
                )
            },
          ]),
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

pub fn list_checkbox_row(
  wine: Wine,
  l: WineList,
  checked: Bool,
  vintage: Option(String),
  username: String,
) -> Node {
  let vintage_val = option.unwrap(vintage, "")
  let row_id = "list-row-" <> l.id
  html.div(
    [attr.id(row_id), attr.class("flex items-center justify-between gap-2")],
    [
      html.a(
        [
          attr.href("/~" <> username <> "/lists/" <> l.id),
          attr.class(
            "text-sm text-stone-600 hover:text-rose-800 transition-colors",
          ),
        ],
        [html.Text(l.name)],
      ),
      html.Element(
        "input",
        [
          attr.type_("checkbox"),
          attr.class("accent-rose-800 cursor-pointer"),
          attr.Attr(
            "hx-post",
            "/~" <> username <> "/lists/" <> l.id <> "/wines/toggle",
          ),
          attr.Attr(
            "hx-vals",
            "{\"wine_id\":\""
              <> wine.id
              <> "\",\"vintage\":\""
              <> vintage_val
              <> "\"}",
          ),
          attr.Attr("hx-target", "#" <> row_id),
          attr.Attr("hx-swap", "outerHTML"),
          ..case checked {
            True -> [attr.Attr("checked", "")]
            False -> []
          }
        ],
        [],
      ),
    ],
  )
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
  vivino: #(Option(Float), Option(Int)),
  my: List(Rating),
  others: List(Rating),
) -> Node {
  let #(vivino_rating, vivino_count) = vivino
  html.div([attr.class("grid grid-cols-3 gap-3 mt-4")], [
    stat_box("Vivino", vivino_rating, case vivino_count {
      Some(n) -> int.to_string(n) <> " ratings"
      None -> ""
    }),
    stat_box("You", avg_rating(my), count_label(my)),
    stat_box("Others", avg_rating(others), count_label(others)),
  ])
}

fn count_label(ratings: List(Rating)) -> String {
  let count = count_rated(ratings)
  int.to_string(count)
  <> case count {
    1 -> " rating"
    _ -> " ratings"
  }
}

fn stat_box(label: String, avg: Option(Float), count_text: String) -> Node {
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
      html.div([attr.class("text-xs text-stone-400")], [html.Text(count_text)]),
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
  vintage_ratings: List(db.VintageRating),
  vintage_opts: List(String),
  selected: Option(String),
  my: List(Rating),
  others: List(Rating),
  conn: Connection,
  user: User,
) -> List(Node) {
  // NV and "All" show the wine-level Vivino rating; a year shows
  // that vintage's cached rating.
  let vivino_stat = case selected {
    None -> #(wine.vivino_rating, wine.vivino_rating_count)
    Some("NV") -> #(wine.vivino_rating, wine.vivino_rating_count)
    Some(year) ->
      case list.find(vintage_ratings, fn(v) { v.year == year }) {
        Ok(v) -> #(v.rating, v.rating_count)
        Error(_) -> #(None, None)
      }
  }
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
        stat_boxes(vivino_stat, fm, fo),
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
  let wishlist = db.get_user_wishlist(conn, user.username)
  let wishlisted = db.is_wine_in_list(conn, wishlist.id, wine.id)
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
          c.action_link(vivino.vivino_url(vid), "View on Vivino \u{2192}"),
          html.a(
            [
              attr.href(c.wine_url(wine) <> "/sync"),
              attr.class(
                "px-3 py-1.5 text-sm border border-amber-600 text-amber-700 rounded-lg hover:bg-amber-50 transition-colors inline-block w-fit",
              ),
            ],
            [html.Text("Sync from Vivino")],
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

fn compute_parent_remaining(
  entries: List(CellarEntry),
) -> List(#(String, Int)) {
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
  html.tr(
    [
      attr.class(c.clickable_row_class(idx)),
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
        html.Text(c.display_vintages(wine.vintages)),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(c.display_country(wine.country)),
      ]),
      html.td([attr.class("px-4 py-3")], [c.wine_type_badge(wine.wine_type)]),
    ],
  )
}

// --- Wine create/edit ---

pub fn new_wine_form(req: Request, conn: Connection, user: User) -> Response {
  let q = wisp.get_query(req)
  let qv = fn(key) {
    case list.key_find(q, key) {
      Ok(v) -> v
      _ -> ""
    }
  }
  let winery_names = db.all_winery_names(conn)
  let prefill =
    NewWinePrefill(
      name: qv("name"),
      winery: qv("winery"),
      region: qv("region"),
      country: qv("country"),
      style: qv("style"),
      vintage: qv("vintage"),
      wine_type: qv("wine_type"),
      vivino_id: qv("vivino_id"),
    )
  c.page("Add Wine \u{2014} Rebstock", user, conn, [
    c.back_link("/wines", "All wines"),
    html.div([attr.class("max-w-lg")], [
      html.h1([attr.class("text-3xl font-light text-stone-800 mb-6")], [
        html.Text("Add Wine"),
      ]),
      wine_form(None, prefill, winery_names, "/wines", "Add Wine"),
    ]),
  ])
}

type NewWinePrefill {
  NewWinePrefill(
    name: String,
    winery: String,
    region: String,
    country: String,
    style: String,
    vintage: String,
    wine_type: String,
    vivino_id: String,
  )
}

pub fn create_wine(
  req: Request,
  conn: Connection,
  user: User,
  image_dir: String,
) -> Response {
  use form <- wisp.require_form(req)
  let name = form_val(form, "name")
  let winery = form_val(form, "winery")
  case name, winery {
    "", _ | _, "" -> wisp.redirect("/wines/new")
    _, _ -> {
      let wine_type = db.wine_type_from_string(form_val(form, "wine_type"))
      let wine_id =
        db.upsert_wine(
          conn,
          created_by: user.username,
          winery: winery,
          name: name,
          vintage: opt_val(form, "vintage"),
          region: opt_val(form, "region"),
          country: opt_val(form, "country"),
          style: opt_val(form, "style"),
          personal_note: opt_val(form, "personal_note"),
          wine_type: wine_type,
          vivino_id: opt_val(form, "vivino_id"),
        )
      // Save uploaded image if present
      case list.key_find(form.files, "image") {
        Ok(file) ->
          case file.file_name {
            "" -> Nil
            _ -> {
              let _ =
                simplifile.copy(
                  file.path,
                  image_dir <> "/" <> wine_id <> ".jpg",
                )
              Nil
            }
          }
        Error(_) -> Nil
      }
      wisp.redirect("/wines/" <> wine_id)
    }
  }
}

pub fn edit_wine_form(
  req: Request,
  conn: Connection,
  id: String,
  user: User,
) -> Response {
  case db.get_wine(conn, user.username, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(wine) -> {
      let q = wisp.get_query(req)
      let qv = fn(key) {
        case list.key_find(q, key) {
          Ok(v) -> v
          _ -> ""
        }
      }
      let winery_names = db.all_winery_names(conn)
      let prefill =
        NewWinePrefill(
          name: "",
          winery: wine.winery_name,
          region: "",
          country: "",
          style: "",
          vintage: "",
          wine_type: "",
          vivino_id: qv("vivino_id"),
        )
      c.page("Edit " <> wine.name <> " \u{2014} Rebstock", user, conn, [
        c.back_link(c.wine_url(wine), wine.name),
        html.div([attr.class("max-w-lg")], [
          html.h1([attr.class("text-3xl font-light text-stone-800 mb-6")], [
            html.Text("Edit Wine"),
          ]),
          wine_form(
            Some(wine),
            prefill,
            winery_names,
            c.wine_url(wine) <> "/edit",
            "Update",
          ),
        ]),
      ])
    }
  }
}

pub fn handle_edit_wine(
  req: Request,
  conn: Connection,
  id: String,
  user: User,
  image_dir: String,
) -> Response {
  case db.get_wine(conn, user.username, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(wine) -> {
      case wine.created_by == user.username {
        False -> wisp.response(403)
        True -> {
          use form <- wisp.require_form(req)
          let name = form_val(form, "name")
          let winery = form_val(form, "winery")
          case name, winery {
            "", _ | _, "" -> wisp.redirect(c.wine_url(wine) <> "/edit")
            _, _ -> {
              let wine_type =
                db.wine_type_from_string(form_val(form, "wine_type"))
              db.update_wine(
                conn,
                id,
                name,
                winery,
                user.username,
                opt_val(form, "region"),
                opt_val(form, "country"),
                opt_val(form, "style"),
                opt_val(form, "personal_note"),
                wine_type,
                opt_val(form, "vivino_id"),
              )
              // Save uploaded image if present
              case list.key_find(form.files, "image") {
                Ok(file) ->
                  case file.file_name {
                    "" -> Nil
                    _ -> {
                      let _ =
                        simplifile.copy(
                          file.path,
                          image_dir <> "/" <> id <> ".jpg",
                        )
                      Nil
                    }
                  }
                Error(_) -> Nil
              }
              wisp.redirect("/wines/" <> id)
            }
          }
        }
      }
    }
  }
}

fn form_val(form: wisp.FormData, key: String) -> String {
  case list.key_find(form.values, key) {
    Ok(v) -> string.trim(v)
    _ -> ""
  }
}

pub fn opt_val(form: wisp.FormData, key: String) -> Option(String) {
  case form_val(form, key) {
    "" -> None
    v -> Some(v)
  }
}

fn wine_form(
  existing: Option(Wine),
  prefill: NewWinePrefill,
  winery_names: List(String),
  action: String,
  submit_label: String,
) -> Node {
  let v = fn(f: fn(Wine) -> String, fallback: String) -> String {
    case existing {
      Some(w) -> f(w)
      None -> fallback
    }
  }
  let ov = fn(f: fn(Wine) -> Option(String), fallback: String) -> String {
    case existing {
      Some(w) ->
        case f(w) {
          Some(s) -> s
          None -> ""
        }
      None -> fallback
    }
  }
  let cur_type = case existing {
    Some(w) -> db.wine_type_to_string(w.wine_type)
    None ->
      case prefill.wine_type {
        "" -> "RED"
        t -> t
      }
  }

  html.Element(
    "form",
    [
      attr.method("post"),
      attr.Attr("action", action),
      attr.Attr("enctype", "multipart/form-data"),
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
            attr.value(v(fn(w) { w.name }, prefill.name)),
            attr.class(c.input_class),
          ],
          [],
        ),
      ]),
      html.div([attr.class("space-y-1")], [
        html.label([attr.class("block text-sm text-stone-600")], [
          html.Text("Label Photo"),
        ]),
        html.input([
          attr.type_("file"),
          attr.name("image"),
          attr.Attr("accept", "image/*"),
          attr.class(
            "block w-full text-sm text-stone-500 file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border file:border-stone-300 file:text-sm file:text-stone-700 file:bg-white hover:file:bg-stone-50",
          ),
        ]),
        html.p([attr.class("text-xs text-stone-400 mt-1")], [
          html.Text("Portrait orientation, ideally 300\u{00d7}400px or larger"),
        ]),
      ]),
      c.form_field("Winery", True, [
        html.Element(
          "input",
          [
            attr.type_("text"),
            attr.name("winery"),
            attr.Attr("required", ""),
            attr.Attr("list", "winery-list"),
            attr.value(prefill.winery),
            attr.class(c.input_class),
          ],
          [],
        ),
        html.Element(
          "datalist",
          [attr.id("winery-list")],
          list.map(winery_names, fn(name) {
            html.Element("option", [attr.value(name)], [])
          }),
        ),
      ]),
      html.div([attr.class("grid grid-cols-2 gap-4")], [
        c.form_field("Region", False, [
          html.Element(
            "input",
            [
              attr.type_("text"),
              attr.name("region"),
              attr.value(ov(fn(w) { w.region }, prefill.region)),
              attr.class(c.input_class),
            ],
            [],
          ),
        ]),
        c.form_field("Country", False, [
          c.country_input(
            "country",
            case existing {
              Some(w) -> w.country
              None ->
                case prefill.country {
                  "" -> None
                  c -> Some(c)
                }
            },
            c.input_class,
          ),
        ]),
      ]),
      html.div([attr.class("grid grid-cols-2 gap-4")], [
        c.form_field("Style", False, [
          html.Element(
            "input",
            [
              attr.type_("text"),
              attr.name("style"),
              attr.value(ov(fn(w) { w.style }, prefill.style)),
              attr.class(c.input_class),
            ],
            [],
          ),
        ]),
        case existing {
          Some(_) -> html.Nothing
          None ->
            c.form_field("Vintage", False, [
              html.Element(
                "input",
                [
                  attr.type_("text"),
                  attr.name("vintage"),
                  attr.value(prefill.vintage),
                  attr.Attr("placeholder", "e.g. 2020"),
                  attr.class(c.input_class),
                ],
                [],
              ),
            ])
        },
      ]),
      c.form_field("Type", True, [
        html.Element(
          "select",
          [attr.name("wine_type"), attr.class(c.input_class)],
          list.map(db.all_wine_types, fn(wt) {
            let val = db.wine_type_to_string(wt)
            let attrs = [attr.value(val)]
            let attrs = case val == cur_type {
              True -> [attr.Attr("selected", ""), ..attrs]
              False -> attrs
            }
            html.Element("option", attrs, [html.Text(db.wine_type_label(wt))])
          }),
        ),
      ]),
      c.form_field("Personal Note", False, [
        html.Element(
          "textarea",
          [
            attr.name("personal_note"),
            attr.Attr("rows", "3"),
            attr.class(c.input_class <> " resize-none"),
          ],
          [html.Text(ov(fn(w) { w.personal_note }, ""))],
        ),
      ]),
      c.form_field("Vivino ID", False, [
        html.Element(
          "input",
          [
            attr.type_("text"),
            attr.name("vivino_id"),
            attr.value(ov(fn(w) { w.vivino_id }, prefill.vivino_id)),
            attr.Attr("placeholder", "Vivino URL or ID"),
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

// --- Vivino import ---

pub fn vivino_search(req: Request, conn: Connection, user: User) -> Response {
  let query = case list.key_find(wisp.get_query(req), "q") {
    Ok(q) -> string.trim(q)
    _ -> ""
  }
  let page = fn(content) {
    c.page("Import from Vivino \u{2014} Rebstock", user, conn, [
      c.back_link("/wines", "All wines"),
      html.h1(
        [attr.class("text-3xl font-light text-stone-800 tracking-tight mb-6")],
        [html.Text("Import from Vivino")],
      ),
      ..content
    ])
  }
  case query {
    "" -> page([vivino_id_form("")])
    q ->
      case vivino.parse_vivino_id(q) {
        Error(_) ->
          page([
            vivino_id_form(q),
            error_box("Enter a Vivino URL or wine ID"),
          ])
        Ok(vid) ->
          case vivino.fetch_wine_with_vintages(vid) {
            Error(msg) -> page([vivino_id_form(q), error_box(msg)])
            Ok(detail) -> {
              let existing =
                find_existing_wine(
                  conn,
                  user,
                  detail.wine_id,
                  detail.winery_name,
                  detail.wine_name,
                )
              page([vivino_preview(detail, existing)])
            }
          }
      }
  }
}

pub fn vivino_import(
  req: Request,
  conn: Connection,
  user: User,
  image_dir: String,
) -> Response {
  use form <- wisp.require_form(req)
  let name = form_val(form, "name")
  let winery = form_val(form, "winery")
  let vivino_id = form_val(form, "vivino_id")
  case name, winery, vivino_id {
    "", _, _ | _, "", _ | _, _, "" -> wisp.redirect("/wines/import/vivino")
    _, _, _ -> {
      let wine_type = db.wine_type_from_string(form_val(form, "wine_type"))

      let wine_id =
        db.upsert_wine(
          conn,
          created_by: user.username,
          winery: winery,
          name: name,
          vintage: None,
          region: opt_val(form, "region"),
          country: opt_val(form, "country"),
          style: None,
          personal_note: None,
          wine_type: wine_type,
          vivino_id: Some(vivino_id),
        )

      // Full sync: vintages + ratings
      case vivino.fetch_wine_with_vintages(vivino_id) {
        Ok(detail) -> {
          sync_vintages_and_ratings(conn, wine_id, detail)
          let _ = vivino.download_image(detail.thumb_url, image_dir, wine_id)
          Nil
        }
        Error(_) -> {
          // Fallback: use rating from form if vintage fetch fails
          case float.parse(form_val(form, "rating")) {
            Ok(rating) -> db.set_wine_vivino_rating(conn, wine_id, rating, None)
            _ -> Nil
          }
        }
      }

      wisp.redirect("/wines/" <> wine_id <> "/" <> db.slugify(name))
    }
  }
}

pub fn vivino_sync_preview(
  conn: Connection,
  id: String,
  user: User,
) -> Response {
  case db.get_wine(conn, user.username, id) {
    Error(_) -> wisp.redirect("/wines")
    Ok(wine) ->
      case wine.vivino_id {
        None -> wisp.redirect(c.wine_url(wine))
        Some(stored_vid) ->
          case
            vivino.ensure_wine_id(stored_vid)
            |> result.try(fn(vid) {
              vivino.fetch_wine_with_vintages(vid)
              |> result.map(fn(detail) { #(vid, detail) })
            })
          {
            Error(msg) ->
              c.page("Sync \u{2014} Rebstock", user, conn, [
                c.back_link(c.wine_url(wine), wine.name),
                error_box(msg),
              ])
            Ok(#(vid, detail)) -> {
              let country = case detail.country {
                "" -> None
                co -> db.country_to_iso(co)
              }
              let region = case detail.region {
                "" -> None
                r -> Some(r)
              }
              let wine_type =
                db.wine_type_from_string(string.uppercase(detail.wine_type))
              let sync_url = c.wine_url(wine) <> "/sync"

              // Compare vintages and rating against current db state
              let current_vintages = db.vintages_for_wine(conn, wine.id)
              let incoming_vintages =
                list.map(detail.vintages, fn(v) { v.year })
              let new_vintages =
                list.filter(incoming_vintages, fn(v) {
                  !list.contains(current_vintages, v)
                })

              let rating_changed = case
                detail.rating >. 0.0,
                wine.vivino_rating
              {
                False, _ -> False
                True, None -> True
                True, Some(v) ->
                  float.to_string(v) != float.to_string(detail.rating)
              }

              c.page("Sync \u{2014} Rebstock", user, conn, [
                c.back_link(c.wine_url(wine), wine.name),
                html.h1(
                  [
                    attr.class(
                      "text-3xl font-light text-stone-800 tracking-tight mb-6",
                    ),
                  ],
                  [html.Text("Sync from Vivino")],
                ),
                html.Element(
                  "form",
                  [attr.method("post"), attr.Attr("action", sync_url)],
                  [
                    hidden("vivino_id", vid),
                    hidden("name", detail.wine_name),
                    hidden("winery", detail.winery_name),
                    hidden("region", option.unwrap(region, "")),
                    hidden("country", option.unwrap(country, "")),
                    hidden("wine_type", db.wine_type_to_string(wine_type)),
                    hidden("rating", float.to_string(detail.rating)),
                    ..sync_diff_body(
                      wine,
                      detail,
                      wine_type,
                      region,
                      country,
                      new_vintages,
                      current_vintages,
                      rating_changed,
                    )
                  ],
                ),
              ])
            }
          }
      }
  }
}

pub fn vivino_sync_apply(
  req: Request,
  conn: Connection,
  id: String,
  user: User,
  image_dir: String,
) -> Response {
  case db.get_wine(conn, user.username, id) {
    Error(_) -> wisp.redirect("/wines")
    Ok(wine) -> {
      use form <- wisp.require_form(req)
      let vid = case vivino.ensure_wine_id(form_val(form, "vivino_id")) {
        Ok(resolved) -> resolved
        Error(_) -> form_val(form, "vivino_id")
      }
      case vid {
        "" -> wisp.redirect(c.wine_url(wine))
        _ -> {
          // Update wine metadata from form
          let name = form_val(form, "name")
          let winery = form_val(form, "winery")
          let wine_type = db.wine_type_from_string(form_val(form, "wine_type"))
          db.update_wine(
            conn,
            id,
            name,
            winery,
            user.username,
            opt_val(form, "region"),
            opt_val(form, "country"),
            wine.style,
            wine.personal_note,
            wine_type,
            Some(vid),
          )
          // Sync vintages and ratings from API
          case vivino.fetch_wine_with_vintages(vid) {
            Ok(detail) -> {
              sync_vintages_and_ratings(conn, wine.id, detail)
              let _ =
                vivino.download_image(detail.thumb_url, image_dir, wine.id)
              Nil
            }
            Error(_) -> Nil
          }
          wisp.redirect(c.wine_url(wine))
        }
      }
    }
  }
}

fn diff_row(label: String, current: String, incoming: String) -> Node {
  let cur = string.trim(current)
  let inc = string.trim(incoming)
  case cur == inc || inc == "" {
    True -> html.Nothing
    False ->
      html.div([attr.class("flex items-center gap-3 text-sm")], [
        html.span([attr.class("w-20 text-stone-400 shrink-0")], [
          html.Text(label),
        ]),
        case cur {
          "" -> html.span([attr.class("text-green-700")], [html.Text(inc)])
          _ ->
            html.div([attr.class("flex items-center gap-2")], [
              html.span([attr.class("line-through text-stone-400")], [
                html.Text(cur),
              ]),
              html.span([attr.class("text-stone-300")], [
                html.Text("\u{2192}"),
              ]),
              html.span([attr.class("text-green-700 font-medium")], [
                html.Text(inc),
              ]),
            ])
        },
      ])
  }
}

fn sync_diff_body(
  wine: Wine,
  detail: vivino.VivinoWineDetail,
  wine_type: db.WineType,
  region: Option(String),
  country: Option(String),
  new_vintages: List(String),
  current_vintages: List(String),
  rating_changed: Bool,
) -> List(Node) {
  let diff_rows =
    list.filter(
      [
        diff_row("Name", wine.name, detail.wine_name),
        diff_row("Winery", wine.winery_name, detail.winery_name),
        diff_row(
          "Region",
          option.unwrap(wine.region, ""),
          option.unwrap(region, ""),
        ),
        diff_row(
          "Country",
          c.display_country(wine.country),
          c.display_country(country),
        ),
        diff_row(
          "Type",
          db.wine_type_label(wine.wine_type),
          db.wine_type_label(wine_type),
        ),
        case new_vintages {
          [] -> html.Nothing
          _ ->
            diff_row(
              "Vintages",
              int.to_string(list.length(current_vintages)),
              int.to_string(
                list.length(current_vintages) + list.length(new_vintages),
              )
                <> " (+"
                <> int.to_string(list.length(new_vintages))
                <> ")",
            )
        },
        case rating_changed {
          False -> html.Nothing
          True ->
            diff_row(
              "Rating",
              case wine.vivino_rating {
                Some(v) -> float.to_string(v) <> "\u{2605}"
                None -> ""
              },
              float.to_string(detail.rating)
                <> "\u{2605} ("
                <> int.to_string(detail.rating_count)
                <> ")",
            )
        },
      ],
      fn(node) { node != html.Nothing },
    )
  case diff_rows {
    [] -> [
      html.p([attr.class("text-stone-500 italic mb-6")], [
        html.Text("Already up to date"),
      ]),
      html.a(
        [
          attr.href(c.wine_url(wine)),
          attr.class(
            "px-4 py-2 border border-stone-300 text-stone-600 rounded-lg hover:bg-stone-50 transition-colors",
          ),
        ],
        [html.Text("Back")],
      ),
    ]
    _ -> [
      html.div([attr.class("space-y-3 mb-6")], diff_rows),
      html.div([attr.class("flex gap-3")], [
        html.Element(
          "button",
          [
            attr.type_("submit"),
            attr.class(
              "px-4 py-2 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors",
            ),
          ],
          [html.Text("Apply sync")],
        ),
        html.a(
          [
            attr.href(c.wine_url(wine)),
            attr.class(
              "px-4 py-2 border border-stone-300 text-stone-600 rounded-lg hover:bg-stone-50 transition-colors",
            ),
          ],
          [html.Text("Cancel")],
        ),
      ]),
    ]
  }
}

fn sync_vintages_and_ratings(
  conn: Connection,
  wine_id: String,
  detail: vivino.VivinoWineDetail,
) -> Nil {
  // Overall wine rating
  case detail.rating >. 0.0 {
    True ->
      db.set_wine_vivino_rating(
        conn,
        wine_id,
        detail.rating,
        Some(detail.rating_count),
      )
    False -> Nil
  }
  // Each vintage and its rating
  list.each(detail.vintages, fn(v) {
    db.upsert_vintage(conn, wine_id, v.year)
    case v.rating >. 0.0 {
      True ->
        db.set_vintage_vivino_rating(
          conn,
          wine_id,
          v.year,
          v.rating,
          Some(v.rating_count),
        )
      False -> Nil
    }
  })
}

fn vivino_id_form(query: String) -> Node {
  html.Element(
    "form",
    [attr.method("get"), attr.Attr("action", "/wines/import/vivino")],
    [
      html.div([attr.class("flex gap-2 mb-6")], [
        html.Element(
          "input",
          [
            attr.type_("text"),
            attr.name("q"),
            attr.value(query),
            attr.Attr("placeholder", "Vivino URL or wine ID\u{2026}"),
            attr.Attr("autofocus", ""),
            attr.class(c.input_class <> " flex-1"),
          ],
          [],
        ),
        html.Element(
          "button",
          [
            attr.type_("submit"),
            attr.class(
              "px-4 py-2 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors",
            ),
          ],
          [html.Text("Lookup")],
        ),
      ]),
    ],
  )
}

fn error_box(msg: String) -> Node {
  html.div(
    [attr.class("p-4 rounded-lg border bg-red-50 border-red-200 text-red-700")],
    [html.Text(msg)],
  )
}

fn find_existing_wine(
  conn: Connection,
  user: User,
  wine_id: Int,
  winery_name: String,
  wine_name: String,
) -> option.Option(Wine) {
  let vivino_id = int.to_string(wine_id)
  case db.find_wine_by_vivino_id(conn, user.username, vivino_id) {
    Ok(wine) -> Some(wine)
    Error(_) ->
      case db.find_wine_by_name(conn, user.username, winery_name, wine_name) {
        Ok(wine) -> Some(wine)
        Error(_) -> None
      }
  }
}

fn vivino_preview(
  result: vivino.VivinoWineDetail,
  existing: option.Option(Wine),
) -> Node {
  let country_code = case db.country_to_iso(result.country) {
    Some(code) -> code
    None -> result.country
  }
  let vintage_count = list.length(result.vintages)
  let vivino_id = int.to_string(result.wine_id)

  let info_block =
    html.div([attr.class("flex items-center gap-6")], [
      case result.thumb_url {
        "" -> html.Nothing
        url ->
          html.img([
            attr.src(url),
            attr.Attr("alt", result.wine_name),
            attr.class("w-16 h-24 object-contain"),
          ])
      },
      html.div([attr.class("flex-1 min-w-0")], [
        html.div([attr.class("flex items-center gap-2 mb-1")], [
          html.span(
            [attr.class("text-lg font-medium text-stone-800 truncate")],
            [html.Text(result.wine_name)],
          ),
          c.wine_type_badge(db.wine_type_from_string(result.wine_type)),
        ]),
        html.div([attr.class("text-stone-600 mb-1")], [
          html.Text(result.winery_name),
        ]),
        html.div([attr.class("text-sm text-stone-500")], [
          html.Text(
            result.region
            <> ", "
            <> country_code
            <> " \u{00b7} "
            <> float.to_string(result.rating)
            <> "\u{2605} ("
            <> int.to_string(result.rating_count)
            <> " ratings)"
            <> case vintage_count {
              0 -> ""
              n -> " \u{00b7} " <> int.to_string(n) <> " vintages"
            },
          ),
        ]),
      ]),
    ])

  case existing {
    Some(wine) ->
      html.div(
        [attr.class("p-6 bg-amber-50/30 rounded-lg border border-amber-200")],
        [
          info_block,
          html.div([attr.class("flex gap-3 mt-4")], [
            html.a(
              [
                attr.href(c.wine_url(wine) <> "/sync"),
                attr.class(
                  "px-4 py-2 border border-amber-600 text-amber-700 rounded-lg hover:bg-amber-50 transition-colors",
                ),
              ],
              [html.Text("Sync")],
            ),
            html.a(
              [
                attr.href("/wines/import/vivino"),
                attr.class(
                  "px-4 py-2 border border-stone-300 text-stone-600 rounded-lg hover:bg-stone-50 transition-colors",
                ),
              ],
              [html.Text("Cancel")],
            ),
          ]),
        ],
      )
    None ->
      html.Element(
        "form",
        [
          attr.method("post"),
          attr.Attr("action", "/wines/import/vivino"),
          attr.class("p-6 bg-white rounded-lg border border-stone-200"),
        ],
        [
          hidden("name", result.wine_name),
          hidden("winery", result.winery_name),
          hidden("region", result.region),
          hidden("country", country_code),
          hidden("wine_type", string.uppercase(result.wine_type)),
          hidden("vivino_id", vivino_id),
          hidden("rating", float.to_string(result.rating)),
          info_block,
          html.div([attr.class("flex gap-3 mt-4")], [
            html.Element(
              "button",
              [
                attr.type_("submit"),
                attr.class(
                  "px-4 py-2 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors",
                ),
              ],
              [html.Text("Import")],
            ),
            html.a(
              [
                attr.href("/wines/import/vivino"),
                attr.class(
                  "px-4 py-2 border border-stone-300 text-stone-600 rounded-lg hover:bg-stone-50 transition-colors",
                ),
              ],
              [html.Text("Cancel")],
            ),
          ]),
        ],
      )
  }
}

fn hidden(name: String, value: String) -> Node {
  html.Element(
    "input",
    [attr.type_("hidden"), attr.name(name), attr.value(value)],
    [],
  )
}
