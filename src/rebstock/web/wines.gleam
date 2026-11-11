import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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
    html.div([attr.class("page-toolbar flex items-end justify-between mb-6")], [
      c.page_header("All Wines", count <> " total"),
      html.div([attr.class("flex gap-2")], [
        html.a(
          [
            attr.href("/wines/new"),
            attr.class(
              "button px-4 py-2 bg-rose-800 text-white rounded-lg text-sm hover:bg-rose-900 transition-colors",
            ),
          ],
          [html.Text("Add Wine")],
        ),
      ]),
    ]),
    c.table_filter("wines-table", "Filter wines\u{2026}"),
    html.div([attr.id("wines-table")], [wine_table(wines)]),
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
        html.div([attr.class("detail-content")], [
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
        html.div(
          [attr.class("wine-heading flex items-start justify-between mb-2")],
          [
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
                  html.Element("details", [attr.class("relative list-menu")], [
                    html.Element(
                      "summary",
                      [
                        attr.class(
                          "cursor-pointer text-xs text-stone-500 hover:text-rose-800 transition-colors list-none",
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
                        "text-xs text-stone-500 hover:text-rose-800 transition-colors",
                      ),
                    ],
                    [html.Text("Edit")],
                  )
              },
            ]),
          ],
        ),
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
  html.Element(
    "form",
    [
      attr.id(row_id),
      attr.method("post"),
      attr.Attr(
        "action",
        "/~" <> username <> "/lists/" <> l.id <> "/wines/toggle",
      ),
      attr.Attr(
        "hx-action",
        "/~" <> username <> "/lists/" <> l.id <> "/wines/toggle",
      ),
      attr.Attr("hx-target", "this"),
      attr.Attr("hx-swap", "outerHTML"),
      attr.Attr("hx-disable", "find button"),
      attr.Attr("hx-sync", "this:drop"),
      attr.class("list-membership"),
    ],
    [
      html.Element(
        "input",
        [attr.type_("hidden"), attr.name("wine_id"), attr.value(wine.id)],
        [],
      ),
      html.Element(
        "input",
        [attr.type_("hidden"), attr.name("vintage"), attr.value(vintage_val)],
        [],
      ),
      html.a([attr.href("/~" <> username <> "/lists/" <> l.id)], [
        html.Text(l.name),
      ]),
      html.button(
        [
          attr.type_("submit"),
          attr.Attr(
            "aria-label",
            case checked {
              True -> "Remove from "
              False -> "Add to "
            }
              <> l.name,
          ),
          attr.class("list-toggle"),
        ],
        [
          html.Text(case checked {
            True -> "Remove"
            False -> "Add"
          }),
        ],
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
      html.nav(
        [
          attr.class("flex flex-wrap gap-2 mt-4"),
          attr.Attr("aria-label", "Filter by vintage"),
        ],
        [
          vintage_pill("All", base, selected == None),
          ..list.map(options, fn(v) {
            let label = case v {
              "NV" -> "N.V."
              year -> year
            }
            vintage_pill(label, base <> "?vintage=" <> v, selected == Some(v))
          })
        ],
      )
    }
  }
}

fn vintage_pill(label: String, href: String, active: Bool) -> Node {
  let classes = case active {
    True -> "px-3 py-1 rounded-full text-sm bg-rose-800 text-white"
    False ->
      "button px-3 py-1 rounded-full text-sm bg-stone-100 text-stone-600 hover:bg-stone-200 transition-colors"
  }
  html.a(
    [
      attr.href(href),
      attr.class(classes),
      ..case active {
        True -> [attr.Attr("aria-current", "true")]
        False -> []
      }
    ],
    [html.Text(label)],
  )
}

fn stat_boxes(
  vivino: #(Option(Float), Option(Int)),
  my: List(Rating),
  others: List(Rating),
) -> Node {
  let #(vivino_rating, vivino_count) = vivino
  html.dl([attr.class("wine-stats grid grid-cols-3 gap-3 mt-4")], [
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
      attr.class("wine-stat p-3 text-center"),
    ],
    [
      html.dt([attr.class("text-xs text-stone-500")], [html.Text(label)]),
      html.dd([], [
        html.div([attr.class("text-lg font-light")], [c.rating_display(avg)]),
        html.div([attr.class("text-xs text-stone-500")], [html.Text(count_text)]),
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
    html.section([attr.class("mt-8")], [
      section_label("Ratings", 2),
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
  html.section([attr.class("mt-6")], [
    html.div([attr.class("flex items-baseline justify-between mb-3")], [
      section_label("You", 3),
      rate_button(wine, case ratings {
        [] -> "Rate this wine"
        _ -> "Add rating"
      }),
    ]),
    case ratings {
      [] -> html.Nothing
      _ ->
        c.item_list(
          "space-y-2",
          list.map(ratings, fn(r) { my_rating_card(r, wine) }),
        )
    },
  ])
}

fn others_ratings_section(ratings: List(Rating)) -> Node {
  case ratings {
    [] -> html.Nothing
    _ ->
      html.section([attr.class("mt-8")], [
        section_label("Others", 3),
        c.item_list("space-y-2", list.map(ratings, other_rating_card)),
      ])
  }
}

fn personal_note_section(wine: Wine) -> Node {
  case wine.personal_note {
    None -> html.Nothing
    Some(note) ->
      html.section([attr.class("mt-8")], [
        section_label("Personal Note", 2),
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
        "wine-action text-sm text-rose-800 hover:text-rose-900 transition-colors cursor-pointer",
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
      attr.Attr(
        "aria-label",
        "Edit rating for "
          <> wine.name
          <> ", "
          <> c.format_date(option.unwrap(rating.rated_at, rating.created_at)),
      ),
      attr.class(
        "wine-action text-sm text-rose-800 hover:text-rose-900 transition-colors cursor-pointer",
      ),
      attr.Attr("hx-get", url),
      attr.Attr("hx-push-url", url),
      attr.Attr("hx-target", "#overlay"),
      attr.Attr("hx-swap", "outerHTML"),
    ],
    [html.Text("Edit")],
  )
}

fn section_label(text: String, level: Int) -> Node {
  html.Element(
    "h" <> int.to_string(level),
    [
      attr.class(
        "text-sm font-medium uppercase tracking-wider text-stone-500 mb-3",
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
      html.div([attr.class("flex justify-end gap-3 mb-2")], [
        edit_button(r, wine),
      ]),
      html.div([attr.class("flex gap-4")], [
        // Left: rating, vintage, date
        html.div(
          [attr.class("shrink-0 flex flex-col items-center justify-center")],
          [
            html.p([attr.class("text-xs text-stone-500")], [
              html.Text(case r.vintage {
                Some(_) -> c.display_vintage(r.vintage)
                None -> ""
              }),
            ]),
            html.div([attr.class("text-3xl")], [c.rating_display(r.rating)]),
            html.p([attr.class("text-xs text-stone-500")], [
              c.date_node(case r.rated_at {
                Some(date) -> date
                None -> r.created_at
              }),
            ]),
          ],
        ),
        // Right: tasting notes
        html.div([attr.class("entry-notes flex-1 min-w-0")], [
          case r.tasting_notes {
            Some(notes) ->
              html.p([attr.class("text-stone-700 whitespace-pre-line")], [
                html.Text(notes),
              ])
            None ->
              html.p([attr.class("text-stone-500 italic text-sm")], [
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
            html.p([attr.class("text-xs text-stone-500")], [
              html.Text(case r.vintage {
                Some(_) -> c.display_vintage(r.vintage)
                None -> ""
              }),
            ]),
            html.div([attr.class("text-3xl")], [c.rating_display(r.rating)]),
            html.p([attr.class("text-xs text-stone-500")], [
              c.date_node(case r.rated_at {
                Some(date) -> date
                None -> r.created_at
              }),
            ]),
          ],
        ),
        // Right: quoted notes + attribution
        html.div([attr.class("entry-notes flex-1 min-w-0")], [
          case r.tasting_notes {
            Some(notes) ->
              html.blockquote(
                [attr.class("text-stone-700 italic whitespace-pre-line")],
                [
                  html.p([], [html.Text(notes)]),
                ],
              )
            None ->
              html.p([attr.class("text-stone-500 italic text-sm")], [
                html.Text("No tasting notes"),
              ])
          },
          html.p([attr.class("text-xs text-stone-500 mt-1")], [
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
  let net_label =
    int.to_string(net)
    <> " bottles"
    <> case db.entries_held_value(entries) {
      None -> ""
      Some(cents) -> " \u{00b7} " <> db.format_price(cents)
    }
  // Sort newest first by date, then created_at
  let sorted =
    list.sort(entries, fn(a, b) {
      let da = option.unwrap(a.date, a.created_at)
      let db = option.unwrap(b.date, b.created_at)
      string.compare(db, da)
    })
  // Compute remaining per parent for drink button visibility
  let parent_remaining = compute_parent_remaining(entries)

  html.section([attr.class("mt-8")], [
    html.div([attr.class("flex items-baseline justify-between mb-3")], [
      html.div([attr.class("flex items-baseline gap-2")], [
        section_label("Cellar", 2),
        html.span(
          [
            attr.class(case net < 0 {
              True -> "text-xs text-red-500"
              False -> "text-xs text-stone-500"
            }),
          ],
          [html.Text(net_label)],
        ),
      ]),
      add_cellar_button(wine),
    ]),
    case sorted {
      [] ->
        html.p([attr.class("text-sm text-stone-500 italic")], [
          html.Text("No cellar entries"),
        ])
      _ ->
        c.item_list(
          "space-y-2",
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
    True -> "text-2xl font-light text-stone-500 tabular-nums"
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
      html.div([attr.class("flex justify-end gap-3 mb-2")], case is_drink {
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
                entry,
                wine,
              ),
            ],
          ])
        }
        True -> [
          cellar_action_link(
            c.wine_url(wine) <> "/cellar/" <> entry.id <> "/edit",
            "Edit",
            entry,
            wine,
          ),
        ]
      }),
      html.div([attr.class("flex gap-4")], [
        // Left: quantity, vintage, date
        html.div(
          [attr.class("shrink-0 flex flex-col items-center justify-center")],
          [
            html.p([attr.class("text-xs text-stone-500")], [
              html.Text(case entry.vintage {
                Some(_) -> c.display_vintage(entry.vintage)
                None -> ""
              }),
            ]),
            html.div([attr.class(qty_class)], [html.Text(qty_text)]),
            html.p([attr.class("text-xs text-stone-500")], [
              c.date_node(case entry.date {
                Some(d) -> d
                None -> entry.created_at
              }),
            ]),
            // Only a purchase carries a price; a drink's bottle cost whatever
            // the purchase above it says it did
            case entry.price_cents {
              Some(cents) ->
                html.p([attr.class("text-xs text-stone-500 tabular-nums")], [
                  html.Text(db.format_price(cents)),
                ])
              None -> html.Nothing
            },
          ],
        ),
        // Right: notes
        html.div([attr.class("entry-notes flex-1 min-w-0")], [
          case entry.notes {
            Some(notes) ->
              html.p([attr.class("text-stone-700 whitespace-pre-line")], [
                html.Text(notes),
              ])
            None ->
              html.p([attr.class("text-stone-500 italic text-sm")], [
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
        "wine-action text-sm text-rose-800 hover:text-rose-900 transition-colors cursor-pointer",
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
      attr.Attr(
        "aria-label",
        "Drink cellar entry for "
          <> wine.name
          <> ", "
          <> c.format_date(option.unwrap(entry.date, entry.created_at)),
      ),
      attr.class(
        "wine-action text-sm text-rose-800 hover:text-rose-900 transition-colors cursor-pointer",
      ),
      attr.Attr("hx-get", url),
      attr.Attr("hx-push-url", url),
      attr.Attr("hx-target", "#overlay"),
      attr.Attr("hx-swap", "outerHTML"),
    ],
    [html.Text("Drink")],
  )
}

fn cellar_action_link(
  url: String,
  label: String,
  entry: CellarEntry,
  wine: Wine,
) -> Node {
  html.a(
    [
      attr.href(url),
      attr.Attr(
        "aria-label",
        label
          <> " cellar entry for "
          <> wine.name
          <> ", "
          <> c.format_date(option.unwrap(entry.date, entry.created_at)),
      ),
      attr.class(
        "wine-action text-sm text-rose-800 hover:text-rose-900 transition-colors cursor-pointer",
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
      c.row_onclick(c.wine_url(wine)),
      c.row_onauxclick(c.wine_url(wine)),
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
      c.form_field("name", "Name", True, [
        html.Element(
          "input",
          [
            attr.type_("text"),
            attr.id("name"),
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
        html.label([attr.Attr("for", "wine-image"), attr.class("field-label")], [
          html.Text("Label Photo"),
        ]),
        html.input([
          attr.type_("file"),
          attr.id("wine-image"),
          attr.name("image"),
          attr.Attr("aria-describedby", "wine-image-help"),
          attr.Attr("accept", "image/*"),
          attr.class(
            "block w-full text-sm text-stone-500 file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border file:border-stone-300 file:text-sm file:text-stone-700 file:bg-white hover:file:bg-stone-50",
          ),
        ]),
        html.p(
          [
            attr.id("wine-image-help"),
            attr.class("text-xs text-stone-500 mt-1"),
          ],
          [
            html.Text(
              "Portrait orientation, ideally 300\u{00d7}400px or larger",
            ),
          ],
        ),
      ]),
      c.form_field("winery", "Winery", True, [
        html.Element(
          "input",
          [
            attr.type_("text"),
            attr.id("winery"),
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
      html.div([attr.class("grid grid-cols-1 sm:grid-cols-2 gap-4")], [
        c.form_field("region", "Region", False, [
          html.Element(
            "input",
            [
              attr.type_("text"),
              attr.id("region"),
              attr.name("region"),
              attr.value(ov(fn(w) { w.region }, prefill.region)),
              attr.class(c.input_class),
            ],
            [],
          ),
        ]),
        c.form_field("country", "Country", False, [
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
      html.div([attr.class("grid grid-cols-1 sm:grid-cols-2 gap-4")], [
        c.form_field("style", "Style", False, [
          html.Element(
            "input",
            [
              attr.type_("text"),
              attr.id("style"),
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
            c.form_field("vintage", "Vintage", False, [
              html.Element(
                "input",
                [
                  attr.type_("text"),
                  attr.id("vintage"),
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
      c.form_field("wine_type", "Type", True, [
        html.Element(
          "select",
          [
            attr.id("wine_type"),
            attr.name("wine_type"),
            attr.class(c.input_class),
          ],
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
      c.form_field("personal_note", "Personal Note", False, [
        html.Element(
          "textarea",
          [
            attr.id("personal_note"),
            attr.name("personal_note"),
            attr.Attr("rows", "3"),
            attr.class(c.input_class <> " resize-none"),
          ],
          [html.Text(ov(fn(w) { w.personal_note }, ""))],
        ),
      ]),
      c.form_field("vivino_id", "Vivino ID", False, [
        html.Element(
          "input",
          [
            attr.type_("text"),
            attr.id("vivino_id"),
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
              "button px-4 py-2 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors",
            ),
          ],
          [html.Text(submit_label)],
        ),
      ]),
    ],
  )
}
