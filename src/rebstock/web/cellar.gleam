import gleam/bytes_tree
import gleam/http
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import nakai/attr
import nakai/html
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type User}
import rebstock/db.{type CellarEntry, type CellarWine, type Wine}
import rebstock/web/components as c
import rebstock/web/lists
import rebstock/web/ratings

pub fn cellar(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
) -> Response {
  let filter = c.rating_filter(req)
  let wines = db.cellar_wines(conn, username, filter)
  let total_bottles = list.fold(wines, 0, fn(acc, cw) { acc + cw.bottles })
  let total_value =
    list.fold(wines, 0, fn(acc, cw) {
      case db.held_value(cw.price_breakdown) {
        Some(cents) -> acc + cents
        None -> acc
      }
    })
  let subtitle =
    int.to_string(total_bottles)
    <> " bottles"
    <> case total_value {
      0 -> ""
      cents -> " \u{00b7} " <> db.format_price(cents)
    }
  let cellar_list = db.get_list_by_slug(conn, username, "cellar")
  let is_owner = user.username == username

  c.page("Cellar \u{2014} Rebstock", user, conn, [
    html.div([attr.class("flex items-end justify-between mb-6")], [
      html.div([], [
        html.h1(
          [attr.class("text-3xl font-light text-stone-800 tracking-tight")],
          [html.Text("Cellar")],
        ),
        html.p([attr.class("text-stone-500 mt-1")], [html.Text(subtitle)]),
      ]),
      case is_owner {
        False -> html.Nothing
        True ->
          html.div([attr.class("flex items-center gap-2")], case cellar_list {
            Error(_) -> [
              html.a(
                [
                  attr.href("/~" <> username <> "/cellar/export.csv"),
                  attr.class(
                    "px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors",
                  ),
                ],
                [html.Text("Export CSV")],
              ),
            ]
            Ok(wl) -> {
              let share_path = "/shared/" <> wl.id <> "/" <> wl.slug
              let full_share_url = c.base_url(req) <> share_path
              [
                lists.share_control(
                  wl,
                  full_share_url,
                  "/~" <> username <> "/cellar/public",
                ),
                html.a(
                  [
                    attr.href("/~" <> username <> "/cellar/export.csv"),
                    attr.class(
                      "px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors",
                    ),
                  ],
                  [html.Text("Export CSV")],
                ),
                html.a(
                  [
                    attr.href(
                      "/~" <> username <> "/lists/" <> wl.id <> "/print",
                    ),
                    attr.Attr("target", "_blank"),
                    attr.class(
                      "px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors",
                    ),
                  ],
                  [html.Text("Print")],
                ),
              ]
            }
          })
      },
    ]),
    c.filter_chips(filter, "/~" <> username <> "/cellar"),
    c.table_filter("cellar-table", "Filter wines\u{2026}"),
    html.div([attr.id("cellar-table")], [cellar_wine_table(wines)]),
  ])
}

pub fn cellar_set_public(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
) -> Response {
  case user.username == username {
    False -> wisp.response(403)
    True -> {
      case db.get_list_by_slug(conn, username, "cellar") {
        Error(_) -> c.not_found(user, conn)
        Ok(wl) -> {
          use form <- wisp.require_form(req)
          let public = case list.key_find(form.values, "public") {
            Ok("1") -> True
            _ -> False
          }
          db.set_list_public(conn, wl.id, public)
          wisp.redirect("/~" <> username <> "/cellar")
        }
      }
    }
  }
}

pub fn cellar_csv(conn: Connection, user: User, username: String) -> Response {
  case user.username == username {
    False -> wisp.response(403)
    True -> cellar_csv_body(conn, username)
  }
}

fn cellar_csv_body(conn: Connection, username: String) -> Response {
  let wines = db.cellar_wines(conn, username, db.unfiltered)
  let header = "Winery,Wine,Vintage,Country,Type,Bottles,Value"
  let rows =
    list.map(wines, fn(cw) {
      [
        csv_field(cw.wine.winery_name),
        csv_field(cw.wine.name),
        c.display_vintage(cw.vintage),
        csv_field(c.display_country(cw.wine.country)),
        db.wine_type_to_string(cw.wine.wine_type),
        int.to_string(cw.bottles),
        case db.held_value(cw.price_breakdown) {
          Some(cents) -> db.format_price_plain(cents)
          None -> ""
        },
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

pub fn cellar_entry_detail(
  conn: Connection,
  id: String,
  user: User,
) -> Response {
  case db.get_cellar_entry_by_id(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(entry) ->
      case db.get_wine_by_id(conn, entry.wine_id) {
        Error(_) -> c.not_found(user, conn)
        Ok(wine) ->
          c.page(wine.name <> " Cellar Entry \u{2014} Rebstock", user, conn, [
            c.back_link(c.wine_url(wine), wine.name),
            cellar_entry_card(entry, wine),
          ])
      }
  }
}

pub fn cellar_entry_overlay(conn: Connection, id: String) -> Response {
  case db.get_cellar_entry_by_id(conn, id) {
    Error(_) -> wisp.not_found()
    Ok(entry) ->
      case db.get_wine_by_id(conn, entry.wine_id) {
        Error(_) -> wisp.not_found()
        Ok(wine) -> c.overlay_wrapper(cellar_entry_card(entry, wine))
      }
  }
}

/// GET: show form overlay for new cellar entry. POST: create entry.
pub fn handle_new(
  req: Request,
  conn: Connection,
  wine_id: String,
  user: User,
) -> Response {
  case db.get_wine(conn, user.username, wine_id) {
    Error(_) -> c.not_found(user, conn)
    Ok(wine) -> {
      let vintages = db.vintages_for_wine(conn, wine.id)
      case req.method {
        http.Get ->
          case is_htmx(req) {
            True -> c.overlay_wrapper(cellar_form(wine, vintages, None))
            False ->
              c.page("Add to Cellar \u{2014} Rebstock", user, conn, [
                c.back_link(c.wine_url(wine), wine.name),
                cellar_form(wine, vintages, None),
              ])
          }
        http.Post -> {
          use form <- wisp.require_form(req)
          let vintage = form_value(form, "vintage")
          let quantity = form_int(form, "quantity")
          let notes = form_value(form, "notes")
          let date = form_value(form, "date")
          case quantity < 1, form_price(form) {
            True, _ ->
              form_error(
                cellar_form(wine, vintages, None),
                "Quantity must be at least 1",
              )
            _, Error(msg) -> form_error(cellar_form(wine, vintages, None), msg)
            False, Ok(price_cents) -> {
              db.insert_cellar_entry(
                conn,
                username: user.username,
                wine_id: wine.id,
                vintage: vintage,
                quantity: quantity,
                notes: notes,
                date: date,
                price_cents: price_cents,
              )
              wisp.response(200)
              |> wisp.set_header("HX-Redirect", c.wine_url(wine))
            }
          }
        }
        _ -> wisp.method_not_allowed([http.Get, http.Post])
      }
    }
  }
}

/// GET: show form overlay for editing. POST: update cellar entry.
pub fn handle_edit(
  req: Request,
  conn: Connection,
  id: String,
  user: User,
) -> Response {
  case db.get_cellar_entry_by_id(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(entry) ->
      case entry.username == user.username {
        False -> wisp.response(403)
        True ->
          case db.get_wine_by_id(conn, entry.wine_id) {
            Error(_) -> c.not_found(user, conn)
            Ok(wine) -> {
              let vintages = db.vintages_for_wine(conn, wine.id)
              case req.method {
                http.Get ->
                  case is_htmx(req) {
                    True ->
                      c.overlay_wrapper(cellar_form(wine, vintages, Some(entry)))
                    False ->
                      c.page("Edit Cellar Entry \u{2014} Rebstock", user, conn, [
                        c.back_link(c.wine_url(wine), wine.name),
                        cellar_form(wine, vintages, Some(entry)),
                      ])
                  }
                http.Post -> {
                  use form <- wisp.require_form(req)
                  let vintage = form_value(form, "vintage")
                  let quantity = form_int(form, "quantity")
                  let notes = form_value(form, "notes")
                  let date = form_value(form, "date")
                  // A drink event must never carry its own price: the held-value
                  // query reads the parent's price, so a price here would double
                  // count while the group itself drops out of the breakdown.
                  let price = case entry.parent_id {
                    Some(_) -> Ok(None)
                    None -> form_price(form)
                  }
                  case quantity_error(conn, entry, quantity), price {
                    Some(msg), _ ->
                      form_error(cellar_form(wine, vintages, Some(entry)), msg)
                    _, Error(msg) ->
                      form_error(cellar_form(wine, vintages, Some(entry)), msg)
                    None, Ok(price_cents) -> {
                      db.update_cellar_entry(
                        conn,
                        id: entry.id,
                        vintage: vintage,
                        quantity: quantity,
                        notes: notes,
                        date: date,
                        price_cents: price_cents,
                      )
                      wisp.response(200)
                      |> wisp.set_header("HX-Redirect", c.wine_url(wine))
                    }
                  }
                }
                _ -> wisp.method_not_allowed([http.Get, http.Post])
              }
            }
          }
      }
  }
}

/// GET: show drink overlay form. POST: create -1 entry.
pub fn handle_drink(
  req: Request,
  conn: Connection,
  id: String,
  user: User,
) -> Response {
  case db.get_cellar_entry_by_id(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(entry) ->
      case entry.username == user.username {
        False -> wisp.response(403)
        True ->
          case db.get_wine_by_id(conn, entry.wine_id) {
            Error(_) -> c.not_found(user, conn)
            Ok(wine) ->
              case req.method {
                http.Get ->
                  case is_htmx(req) {
                    True -> c.overlay_wrapper(drink_form(wine, entry))
                    False ->
                      c.page("Drink \u{2014} Rebstock", user, conn, [
                        c.back_link(c.wine_url(wine), wine.name),
                        drink_form(wine, entry),
                      ])
                  }
                http.Post -> {
                  use form <- wisp.require_form(req)
                  let notes = form_value(form, "notes")
                  let date = form_value(form, "date")
                  let rate = case list.key_find(form.values, "rate") {
                    Ok("on") -> True
                    _ -> False
                  }
                  case entry_remaining(conn, entry) < 1 {
                    True ->
                      form_error(
                        drink_form(wine, entry),
                        "No bottles left in this entry",
                      )
                    False -> {
                      db.insert_cellar_drink(
                        conn,
                        parent_id: entry.id,
                        username: user.username,
                        wine_id: entry.wine_id,
                        vintage: entry.vintage,
                        notes: notes,
                        date: date,
                      )
                      case rate {
                        True -> {
                          let rating_url = c.wine_url(wine) <> "/ratings/new"
                          ratings.new_rating_overlay(wine, conn, date)
                          |> wisp.set_header("HX-Push-Url", rating_url)
                          |> wisp.set_header("HX-Retarget", "#overlay")
                          |> wisp.set_header("HX-Reswap", "outerHTML")
                        }
                        False ->
                          wisp.response(200)
                          |> wisp.set_header("HX-Redirect", c.wine_url(wine))
                      }
                    }
                  }
                }
                _ -> wisp.method_not_allowed([http.Get, http.Post])
              }
          }
      }
  }
}

/// POST: delete cellar entry (cascades to drink events if parent).
pub fn handle_delete(
  req: Request,
  conn: Connection,
  id: String,
  user: User,
) -> Response {
  case req.method {
    http.Post ->
      case db.get_cellar_entry_by_id(conn, id) {
        Error(_) -> c.not_found(user, conn)
        Ok(entry) ->
          case entry.username == user.username {
            False -> wisp.response(403)
            True ->
              case db.get_wine_by_id(conn, entry.wine_id) {
                Error(_) -> c.not_found(user, conn)
                Ok(wine) -> {
                  db.delete_cellar_entry(conn, id)
                  wisp.response(200)
                  |> wisp.set_header("HX-Redirect", c.wine_url(wine))
                }
              }
          }
      }
    _ -> wisp.method_not_allowed([http.Post])
  }
}

/// Re-render an overlay form with an error message on invalid input.
fn form_error(form: html.Node, message: String) -> Response {
  c.overlay_wrapper(
    html.div([], [
      html.div(
        [
          attr.class(
            "mb-4 p-3 rounded-lg border bg-red-50 border-red-200 text-red-700 text-sm",
          ),
        ],
        [html.Text(message)],
      ),
      form,
    ]),
  )
  |> wisp.set_header("HX-Retarget", "#overlay")
  |> wisp.set_header("HX-Reswap", "outerHTML")
}

/// Bottles left in a purchase entry after subtracting its drink events.
fn entry_remaining(conn: Connection, entry: CellarEntry) -> Int {
  db.cellar_entries_for_wine(conn, entry.wine_id)
  |> list.filter(fn(e) { e.parent_id == Some(entry.id) })
  |> list.fold(entry.quantity, fn(acc, e) { acc + e.quantity })
}

/// Validate a quantity edit against the event-sourcing invariants:
/// purchases must stay at or above what has already been drunk,
/// drink events must stay negative and not overdraw their parent.
fn quantity_error(
  conn: Connection,
  entry: CellarEntry,
  quantity: Int,
) -> Option(String) {
  case entry.parent_id {
    None -> {
      let consumed = entry.quantity - entry_remaining(conn, entry)
      let min = int.max(consumed, 1)
      case quantity < min {
        True ->
          Some(
            "Quantity cannot be below "
            <> int.to_string(min)
            <> " ("
            <> int.to_string(consumed)
            <> " bottles already drunk from this entry)",
          )
        False -> None
      }
    }
    Some(parent_id) ->
      case quantity >= 0 {
        True -> Some("A drink entry must have a negative quantity")
        False ->
          case db.get_cellar_entry_by_id(conn, parent_id) {
            Error(_) -> None
            Ok(parent) -> {
              let remaining_without_this =
                entry_remaining(conn, parent) - entry.quantity
              case remaining_without_this + quantity < 0 {
                True ->
                  Some(
                    "Only "
                    <> int.to_string(remaining_without_this)
                    <> " bottles left in the parent entry",
                  )
                False -> None
              }
            }
          }
      }
  }
}

fn drink_form(wine: Wine, entry: CellarEntry) -> html.Node {
  let action = c.wine_url(wine) <> "/cellar/" <> entry.id <> "/drink"
  let subtitle =
    wine.name
    <> " \u{2014} "
    <> c.display_winery(wine.winery_name)
    <> case entry.vintage {
      Some(_) -> " \u{00b7} " <> c.display_vintage(entry.vintage)
      None -> ""
    }
  html.div([attr.class("bg-white rounded-lg border border-stone-200 p-6")], [
    html.h2([attr.class("text-xl font-light text-stone-800 mb-4")], [
      html.Text("Drink a Bottle"),
    ]),
    html.p([attr.class("text-sm text-stone-500 mb-4")], [
      html.Text(subtitle),
    ]),
    html.Element(
      "form",
      [
        attr.Attr("method", "POST"),
        attr.Attr("action", action),
        attr.Attr("hx-post", action),
        attr.class("space-y-4"),
      ],
      [
        // Date (defaults to today)
        req_field("Date", [
          html.Element(
            "input",
            [
              attr.type_("date"),
              attr.name("date"),
              attr.id("drink-date"),
              attr.Attr("required", "required"),
              attr.class(
                "w-full border border-stone-300 rounded-md px-3 py-2 text-sm",
              ),
            ],
            [],
          ),
          html.Element("script", [], [
            html.Text(
              "document.getElementById('drink-date').valueAsDate=new Date()",
            ),
          ]),
        ]),
        // Notes
        form_field("Notes", [
          html.Element(
            "textarea",
            [
              attr.name("notes"),
              attr.Attr("rows", "2"),
              attr.Attr("placeholder", "Occasion, pairing..."),
              attr.class(
                "w-full border border-stone-300 rounded-md px-3 py-2 text-sm",
              ),
            ],
            [],
          ),
        ]),
        // Rate checkbox
        html.div([attr.class("flex items-center gap-2")], [
          html.Element(
            "input",
            [
              attr.type_("checkbox"),
              attr.name("rate"),
              attr.id("rate-checkbox"),
              attr.class("accent-rose-800"),
            ],
            [],
          ),
          html.Element(
            "label",
            [
              attr.Attr("for", "rate-checkbox"),
              attr.class("text-sm text-stone-600"),
            ],
            [html.Text("Rate this bottle")],
          ),
        ]),
        // Submit
        html.Element(
          "button",
          [
            attr.type_("submit"),
            attr.class(
              "w-full px-4 py-2 bg-rose-800 text-white rounded-md text-sm font-medium hover:bg-rose-900 transition-colors",
            ),
          ],
          [html.Text("Drink")],
        ),
      ],
    ),
  ])
}

fn cellar_form(
  wine: Wine,
  vintages: List(String),
  existing: Option(CellarEntry),
) -> html.Node {
  let wine_base = c.wine_url(wine)
  let action = case existing {
    Some(e) -> wine_base <> "/cellar/" <> e.id <> "/edit"
    None -> wine_base <> "/cellar/new"
  }
  let title = case existing {
    Some(_) -> "Edit Cellar Entry"
    None -> "Add to Cellar"
  }
  let subtitle = wine.name <> " \u{2014} " <> c.display_winery(wine.winery_name)
  html.div([attr.class("bg-white rounded-lg border border-stone-200 p-6")], [
    html.h2([attr.class("text-xl font-light text-stone-800 mb-4")], [
      html.Text(title),
    ]),
    html.p([attr.class("text-sm text-stone-500 mb-4")], [
      html.Text(subtitle),
    ]),
    html.Element(
      "form",
      [
        attr.Attr("method", "POST"),
        attr.Attr("action", action),
        attr.Attr("hx-post", action),
        attr.class("space-y-4"),
      ],
      [
        // Vintage
        case vintages {
          [] -> html.Nothing
          _ -> {
            let cur_vintage = case existing {
              Some(e) ->
                case e.vintage {
                  Some(v) -> v
                  None -> ""
                }
              None ->
                case vintages {
                  [first, ..] -> first
                  [] -> ""
                }
            }
            req_field("Vintage", [
              html.Element(
                "input",
                [
                  attr.type_("hidden"),
                  attr.name("vintage"),
                  attr.id("vintage-input"),
                  attr.value(cur_vintage),
                ],
                [],
              ),
              html.div(
                [attr.class("flex flex-wrap gap-2")],
                list.map(vintages, fn(v) {
                  let active = v == cur_vintage
                  let active_cls =
                    "px-3 py-1 rounded-full text-sm bg-rose-800 text-white"
                  let idle_cls =
                    "px-3 py-1 rounded-full text-sm bg-stone-100 text-stone-600 hover:bg-stone-200 transition-colors cursor-pointer"
                  html.Element(
                    "button",
                    [
                      attr.type_("button"),
                      attr.class(case active {
                        True -> active_cls
                        False -> idle_cls
                      }),
                      attr.Attr(
                        "onclick",
                        "document.getElementById('vintage-input').value='"
                          <> v
                          <> "';this.parentElement.querySelectorAll('button').forEach(function(b){b.className='"
                          <> idle_cls
                          <> "'});this.className='"
                          <> active_cls
                          <> "'",
                      ),
                    ],
                    [html.Text(v)],
                  )
                }),
              ),
            ])
          }
        },
        // Quantity
        req_field("Quantity", [
          html.Element(
            "input",
            [
              attr.type_("number"),
              attr.name("quantity"),
              attr.Attr("required", "required"),
              attr.Attr("min", "0"),
              attr.value(case existing {
                Some(e) -> int.to_string(e.quantity)
                None -> "1"
              }),
              attr.class(
                "w-full border border-stone-300 rounded-md px-3 py-2 text-sm",
              ),
            ],
            [],
          ),
        ]),
        // Price per bottle (purchases only — a drink row must never carry its own price)
        case existing {
          Some(e) if e.parent_id != None -> html.Nothing
          _ ->
            form_field("Price per bottle (\u{20ac})", [
              html.Element(
                "input",
                [
                  attr.type_("number"),
                  attr.name("price"),
                  attr.Attr("step", "0.01"),
                  attr.Attr("min", "0"),
                  attr.Attr("placeholder", "13.70"),
                  attr.class(
                    "w-full border border-stone-300 rounded-md px-3 py-2 text-sm",
                  ),
                  ..case existing {
                    Some(e) ->
                      case e.price_cents {
                        Some(cents) -> [
                          attr.value(db.format_price_plain(cents)),
                        ]
                        None -> []
                      }
                    None -> []
                  }
                ],
                [],
              ),
            ])
        },
        // Date
        req_field("Date", [
          html.Element(
            "input",
            [
              attr.type_("date"),
              attr.name("date"),
              attr.id("cellar-date"),
              attr.Attr("required", "required"),
              attr.class(
                "w-full border border-stone-300 rounded-md px-3 py-2 text-sm",
              ),
              ..case existing {
                Some(e) ->
                  case e.date {
                    Some(d) -> [attr.value(d)]
                    None -> []
                  }
                None -> []
              }
            ],
            [],
          ),
          case existing {
            Some(_) -> html.Nothing
            None ->
              html.Element("script", [], [
                html.Text(
                  "document.getElementById('cellar-date').valueAsDate=new Date()",
                ),
              ])
          },
        ]),
        // Notes
        form_field("Notes", [
          html.Element(
            "textarea",
            [
              attr.name("notes"),
              attr.Attr("rows", "3"),
              attr.Attr("placeholder", "Notes..."),
              attr.class(
                "w-full border border-stone-300 rounded-md px-3 py-2 text-sm",
              ),
            ],
            case existing {
              Some(e) ->
                case e.notes {
                  Some(notes) -> [html.Text(notes)]
                  None -> []
                }
              None -> []
            },
          ),
        ]),
        // Submit
        html.Element(
          "button",
          [
            attr.type_("submit"),
            attr.class(
              "w-full px-4 py-2 bg-rose-800 text-white rounded-md text-sm font-medium hover:bg-rose-900 transition-colors",
            ),
          ],
          [
            html.Text(case existing {
              Some(_) -> "Update Entry"
              None -> "Add to Cellar"
            }),
          ],
        ),
        // Delete (only when editing)
        case existing {
          Some(e) -> {
            let delete_url = wine_base <> "/cellar/" <> e.id <> "/delete"
            html.div([attr.class("text-center pt-2")], [
              html.a(
                [
                  attr.href(delete_url),
                  attr.class(
                    "text-xs text-stone-400 hover:text-red-600 transition-colors cursor-pointer",
                  ),
                  attr.Attr("hx-post", delete_url),
                  attr.Attr("hx-confirm", "Delete this entry?"),
                ],
                [html.Text("Delete this entry")],
              ),
            ])
          }
          None -> html.Nothing
        },
      ],
    ),
  ])
}

fn is_htmx(req: Request) -> Bool {
  case list.key_find(req.headers, "hx-request") {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn req_field(label: String, children: List(html.Node)) -> html.Node {
  html.div([], [
    html.Element(
      "label",
      [attr.class("block text-sm font-medium text-stone-600 mb-1")],
      [
        html.Text(label),
        html.span([attr.class("text-rose-600 ml-0.5")], [html.Text("*")]),
      ],
    ),
    ..children
  ])
}

fn form_field(label: String, children: List(html.Node)) -> html.Node {
  html.div([], [
    html.Element(
      "label",
      [attr.class("block text-sm font-medium text-stone-600 mb-1")],
      [html.Text(label)],
    ),
    ..children
  ])
}

fn form_value(form: wisp.FormData, key: String) -> Option(String) {
  case list.key_find(form.values, key) {
    Ok("") -> None
    Ok(v) -> Some(v)
    Error(_) -> None
  }
}

fn form_int(form: wisp.FormData, key: String) -> Int {
  case form_value(form, key) {
    None -> 1
    Some(s) ->
      case int.parse(s) {
        Ok(n) -> n
        Error(_) -> 1
      }
  }
}

const price_message = "Price must be an amount like 13.70"

/// An empty field means the entry has no price. Anything else that is not a
/// non-negative amount is a mistake worth reporting, not an instruction to
/// forget the price that is already stored.
fn form_price(form: wisp.FormData) -> Result(Option(Int), String) {
  case form_value(form, "price") {
    None -> Ok(None)
    Some(s) ->
      case db.parse_price_cents(s) {
        None -> Error(price_message)
        Some(cents) if cents < 0 -> Error(price_message)
        parsed -> Ok(parsed)
      }
  }
}

fn cellar_entry_card(entry: CellarEntry, wine: Wine) -> html.Node {
  c.card([
    html.div([attr.class("flex items-start justify-between mb-2")], [
      html.div([], [
        html.h1([attr.class("text-2xl font-light text-stone-800")], [
          c.link(c.wine_url(wine), [html.Text(wine.name)]),
        ]),
        html.p([attr.class("text-stone-500 mt-1")], [
          c.link(c.winery_url(wine.winery_id, wine.winery_name), [
            html.Text(c.display_winery(wine.winery_name)),
          ]),
          html.Text(case entry.vintage {
            None -> ""
            Some(_) -> " \u{00b7} " <> c.display_vintage(entry.vintage)
          }),
        ]),
      ]),
      html.div([attr.class("flex items-center gap-2")], [
        c.wine_type_badge(wine.wine_type),
        html.span(
          [attr.class("text-2xl font-light text-stone-800 tabular-nums")],
          [html.Text(int.to_string(entry.quantity) <> "\u{00d7}")],
        ),
      ]),
    ]),
    html.p([attr.class("text-sm text-stone-500 mb-4")], [
      c.date_node(case entry.date {
        Some(d) -> d
        None -> entry.created_at
      }),
    ]),
    case entry.price_cents {
      None -> html.Nothing
      Some(cents) ->
        html.p([attr.class("text-sm text-stone-500 mb-4")], [
          html.Text(case entry.quantity {
            1 -> db.format_price(cents)
            n ->
              db.format_price(cents)
              <> " \u{00b7} "
              <> db.format_price(cents * n)
              <> " for "
              <> int.to_string(n)
              <> " bottles"
          }),
        ])
    },
    case entry.notes {
      Some(notes) ->
        html.div([attr.class("mt-4 pt-4 border-t border-stone-100")], [
          html.p([attr.class("text-stone-700 whitespace-pre-line")], [
            html.Text(notes),
          ]),
        ])
      None -> html.Nothing
    },
  ])
}

fn cellar_wine_table(wines: List(CellarWine)) -> html.Node {
  c.table(
    ["Winery", "Wine", "Vintage", "Country", "Type", "Cellar", "Value"],
    list.index_map(wines, cellar_wine_row),
  )
}

fn cellar_wine_row(cw: CellarWine, idx: Int) -> html.Node {
  let wine = cw.wine
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
        html.Text(c.display_vintage(cw.vintage)),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(c.display_country(wine.country)),
      ]),
      html.td([attr.class("px-4 py-3")], [c.wine_type_badge(wine.wine_type)]),
      html.td([attr.class("px-4 py-3 text-center tabular-nums")], [
        html.Text(int.to_string(cw.bottles)),
      ]),
      value_cell(cw),
    ],
  )
}

/// Held value, with the prices behind it on hover so the answer costs no request
fn value_cell(cw: CellarWine) -> html.Node {
  case db.held_value(cw.price_breakdown) {
    None -> html.td([attr.class("px-4 py-3")], [])
    Some(cents) ->
      html.td(
        [
          attr.class("px-4 py-3 text-right tabular-nums text-stone-600"),
          attr.Attr("title", breakdown_title(cw.price_breakdown)),
        ],
        [html.Text(db.format_price(cents))],
      )
  }
}

fn breakdown_title(breakdown: List(#(Int, Int))) -> String {
  breakdown
  |> list.map(fn(pair) {
    int.to_string(pair.0) <> "\u{00d7}" <> db.format_price(pair.1)
  })
  |> string.join(", ")
}

fn csv_field(value: String) -> String {
  case string.contains(value, ",") || string.contains(value, "\"") {
    True -> "\"" <> string.replace(value, each: "\"", with: "\"\"") <> "\""
    False -> value
  }
}
