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
import rebstock/web/ratings

pub fn cellar(conn: Connection, user: User, username: String) -> Response {
  let wines = db.cellar_wines(conn, username)
  let total_bottles = list.fold(wines, 0, fn(acc, cw) { acc + cw.bottles })

  c.page("Cellar \u{2014} Rebstock", user, conn, [
    html.div([attr.class("flex items-end justify-between mb-6")], [
      html.div([], [
        html.h1(
          [attr.class("text-3xl font-light text-stone-800 tracking-tight")],
          [html.Text("Cellar")],
        ),
        html.p([attr.class("text-stone-500 mt-1")], [
          html.Text(int.to_string(total_bottles) <> " bottles"),
        ]),
      ]),
      html.div([attr.class("flex gap-2")], [
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
            attr.href("/~" <> username <> "/cellar/print"),
            attr.class(
              "px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors",
            ),
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
  let total_bottles = list.fold(wines, 0, fn(acc, cw) { acc + cw.bottles })

  let grouped =
    list.chunk(wines, fn(cw) { cw.wine.wine_type })
    |> list.flat_map(fn(group) {
      case group {
        [first, ..] -> [
          html.h2([attr.class("cellar-type-heading")], [
            html.Text(c.wine_type_label(first.wine.wine_type)),
          ]),
          cellar_wine_table(group),
        ]
        _ -> []
      }
    })

  c.layout("Cellar Inventory \u{2014} Rebstock", [
    html.div([attr.class("cellar-print-page")], [
      html.div([attr.class("print-header")], [
        html.div([attr.class("flex items-center gap-3")], [
          html.span([attr.class("text-2xl")], [html.Text("\u{1f347}")]),
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
  |> c.render
}

pub fn cellar_csv(conn: Connection, _user: User, username: String) -> Response {
  let wines = db.cellar_wines(conn, username)
  let header = "Winery,Wine,Vintage,Country,Type,Bottles"
  let rows =
    list.map(wines, fn(cw) {
      [
        csv_field(cw.wine.winery_name),
        csv_field(cw.wine.name),
        c.display_vintage(cw.vintage),
        csv_field(c.display_country(cw.wine.country)),
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

pub fn cellar_entry_detail(conn: Connection, id: String, user: User) -> Response {
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
          db.insert_cellar_entry(
            conn,
            username: user.username,
            wine_id: wine.id,
            vintage: vintage,
            quantity: quantity,
            notes: notes,
            date: date,
          )
          wisp.response(200)
          |> wisp.set_header("HX-Redirect", c.wine_url(wine))
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
                  db.update_cellar_entry(
                    conn,
                    id: entry.id,
                    vintage: vintage,
                    quantity: quantity,
                    notes: notes,
                    date: date,
                  )
                  wisp.response(200)
                  |> wisp.set_header("HX-Redirect", c.wine_url(wine))
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
    ["Winery", "Wine", "Vintage", "Country", "Type", "Cellar"],
    list.index_map(wines, cellar_wine_row),
  )
}

fn cellar_wine_row(cw: CellarWine, idx: Int) -> html.Node {
  let wine = cw.wine
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
        html.Text(c.display_vintage(cw.vintage)),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(c.display_country(wine.country)),
      ]),
      html.td([attr.class("px-4 py-3")], [c.wine_type_badge(wine.wine_type)]),
      html.td([attr.class("px-4 py-3 text-center tabular-nums")], [
        html.Text(int.to_string(cw.bottles)),
      ]),
    ],
  )
}

fn csv_field(value: String) -> String {
  case string.contains(value, ",") || string.contains(value, "\"") {
    True -> "\"" <> string.replace(value, each: "\"", with: "\"\"") <> "\""
    False -> value
  }
}
