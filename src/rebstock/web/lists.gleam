import gleam/http
import gleam/http/request
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import nakai/attr
import nakai/html
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type User}
import rebstock/db.{type WineList}
import rebstock/web/components as c
import rebstock/web/shared

fn base_url(req: Request) -> String {
  let scheme = case request.get_header(req, "x-forwarded-proto") {
    Ok(s) -> s
    _ ->
      case req.scheme {
        http.Https -> "https"
        http.Http -> "http"
      }
  }
  let host = case request.get_header(req, "x-forwarded-host") {
    Ok(h) -> h
    _ ->
      case request.get_header(req, "host") {
        Ok(h) -> h
        _ -> "localhost"
      }
  }
  scheme <> "://" <> host
}

type ListViewWine {
  ListViewWine(
    wine: db.Wine,
    vintage: Option(String),
    notes: Option(String),
    bottles: Option(Int),
  )
}

// --- Index ---

pub fn lists_index(conn: Connection, user: User, username: String) -> Response {
  let user_lists = db.lists_for_user(conn, username)
  let is_owner = user.username == username
  let title = case is_owner {
    True -> "Your Lists"
    False -> username <> "'s Lists"
  }

  c.page(title <> " \u{2014} Rebstock", user, conn, [
    html.div([attr.class("flex items-end justify-between mb-6")], [
      html.div([], [
        html.h1(
          [attr.class("text-3xl font-light text-stone-800 tracking-tight")],
          [html.Text(title)],
        ),
        html.p([attr.class("text-stone-500 mt-1")], [
          html.Text(int.to_string(list.length(user_lists)) <> " lists"),
        ]),
      ]),
      case is_owner {
        False -> html.Nothing
        True ->
          html.a(
            [
              attr.href("/~" <> username <> "/lists/new"),
              attr.class(
                "px-4 py-2 bg-rose-800 text-white rounded-lg text-sm hover:bg-rose-900 transition-colors",
              ),
            ],
            [html.Text("New List")],
          )
      },
    ]),
    html.div(
      [attr.class("grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4")],
      list.map(user_lists, fn(wl) { list_card(wl, username) }),
    ),
  ])
}

fn list_card(wl: WineList, username: String) -> html.Node {
  let href = "/~" <> username <> "/lists/" <> wl.id
  let type_label = case wl.list_type {
    db.CellarList -> "Cellar"
    db.RatedList -> "Rated"
    db.WishlistList -> "Wishlist"
    db.CustomList -> "Custom"
  }
  html.a(
    [
      attr.href(href),
      attr.class(
        "block bg-white rounded-lg border border-stone-200 p-5 hover:border-amber-300 transition-colors",
      ),
    ],
    [
      html.div([attr.class("flex items-start justify-between mb-2")], [
        html.div([attr.class("flex-1 min-w-0")], [
          html.div([attr.class("font-medium text-stone-800 truncate")], [
            html.Text(wl.name),
          ]),
          case wl.description {
            None -> html.Nothing
            Some(d) ->
              html.p(
                [attr.class("text-sm text-stone-500 mt-0.5 line-clamp-2")],
                [html.Text(d)],
              )
          },
        ]),
        html.div([attr.class("ml-3 flex flex-col items-end gap-1 shrink-0")], [
          html.span(
            [
              attr.class(
                "text-xs px-2 py-0.5 rounded border bg-stone-50 text-stone-600 border-stone-200",
              ),
            ],
            [html.Text(type_label)],
          ),
          case wl.public {
            False -> html.Nothing
            True ->
              html.span(
                [
                  attr.class(
                    "text-xs px-2 py-0.5 rounded border bg-amber-50 text-amber-700 border-amber-200",
                  ),
                ],
                [html.Text("Shared")],
              )
          },
        ]),
      ]),
    ],
  )
}

// --- New list form ---

pub fn new_list_form(conn: Connection, user: User) -> Response {
  c.page("New List \u{2014} Rebstock", user, conn, [
    c.back_link("/~" <> user.username <> "/lists", "Lists"),
    html.div([attr.class("max-w-lg")], [
      html.h1([attr.class("text-3xl font-light text-stone-800 mb-6")], [
        html.Text("New List"),
      ]),
      list_form_fields(
        None,
        None,
        False,
        "/~" <> user.username <> "/lists",
        "Create List",
      ),
    ]),
  ])
}

fn list_form_fields(
  name_val: Option(String),
  desc_val: Option(String),
  show_bottles: Bool,
  action: String,
  submit_label: String,
) -> html.Node {
  html.Element(
    "form",
    [
      attr.method("post"),
      attr.Attr("action", action),
      attr.class("space-y-4"),
    ],
    [
      html.div([], [
        html.Element(
          "label",
          [
            attr.Attr("for", "name"),
            attr.class("block text-sm font-medium text-stone-700 mb-1"),
          ],
          [html.Text("Name")],
        ),
        html.Element(
          "input",
          [
            attr.type_("text"),
            attr.id("name"),
            attr.name("name"),
            attr.Attr("required", ""),
            attr.Attr("autofocus", ""),
            attr.value(option.unwrap(name_val, "")),
            attr.class(
              "w-full px-3 py-2 border border-stone-300 rounded-lg text-stone-900 focus:outline-none focus:ring-2 focus:ring-rose-800/20 focus:border-rose-800",
            ),
          ],
          [],
        ),
      ]),
      html.div([], [
        html.Element(
          "label",
          [
            attr.Attr("for", "description"),
            attr.class("block text-sm font-medium text-stone-700 mb-1"),
          ],
          [html.Text("Description")],
        ),
        html.Element(
          "textarea",
          [
            attr.id("description"),
            attr.name("description"),
            attr.Attr("rows", "3"),
            attr.class(
              "w-full px-3 py-2 border border-stone-300 rounded-lg text-stone-900 focus:outline-none focus:ring-2 focus:ring-rose-800/20 focus:border-rose-800 resize-none",
            ),
          ],
          [html.Text(option.unwrap(desc_val, ""))],
        ),
      ]),
      html.Element(
        "label",
        [attr.class("flex items-center gap-2 cursor-pointer")],
        [
          html.Element(
            "input",
            list.flatten([
              [
                attr.type_("checkbox"),
                attr.name("show_bottles"),
                attr.value("1"),
                attr.class("rounded border-stone-300 text-rose-800"),
              ],
              case show_bottles {
                True -> [attr.Attr("checked", "")]
                False -> []
              },
            ]),
            [],
          ),
          html.span([attr.class("text-sm text-stone-700")], [
            html.Text("Show stock in cellar"),
          ]),
        ],
      ),
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

// --- Create list ---

pub fn create_list(req: Request, conn: Connection, user: User) -> Response {
  use form <- wisp.require_form(req)
  case list.key_find(form.values, "name") {
    Error(_) -> wisp.redirect("/~" <> user.username <> "/lists")
    Ok(name) -> {
      let description = case list.key_find(form.values, "description") {
        Ok(d) if d != "" -> Some(d)
        _ -> None
      }
      let show_bottles = case list.key_find(form.values, "show_bottles") {
        Ok("1") -> True
        _ -> False
      }
      let id =
        db.create_list(conn, user.username, name, description, show_bottles)
      wisp.redirect("/~" <> user.username <> "/lists/" <> id)
    }
  }
}

// --- List detail ---

pub fn edit_list_form(
  conn: Connection,
  user: User,
  username: String,
  id: String,
) -> Response {
  case db.get_list(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(wl) ->
      case
        wl.username == username
        && user.username == username
        && wl.list_type == db.CustomList
      {
        False -> c.not_found(user, conn)
        True ->
          c.page("Edit " <> wl.name <> " \u{2014} Rebstock", user, conn, [
            c.back_link("/~" <> username <> "/lists/" <> wl.id, wl.name),
            html.div([attr.class("max-w-lg")], [
              html.h1([attr.class("text-3xl font-light text-stone-800 mb-6")], [
                html.Text("Edit List"),
              ]),
              list_form_fields(
                Some(wl.name),
                wl.description,
                wl.show_bottles,
                "/~" <> username <> "/lists/" <> wl.id,
                "Update",
              ),
            ]),
          ])
      }
  }
}

pub fn list_detail(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
  id: String,
) -> Response {
  case db.get_list(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(wl) -> {
      case wl.username == username {
        False -> c.not_found(user, conn)
        True ->
          case req.method {
            http.Get -> render_list_detail(req, conn, user, username, wl)
            http.Post -> handle_list_post(req, conn, user, username, wl)
            _ -> wisp.method_not_allowed([http.Get, http.Post])
          }
      }
    }
  }
}

fn render_list_detail(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
  wl: WineList,
) -> Response {
  let wines = wines_for_list(conn, wl)
  let is_owner = user.username == username
  let is_custom = wl.list_type == db.CustomList
  let count = int.to_string(list.length(wines))
  let share_path = "/shared/" <> wl.id <> "/" <> wl.slug
  let full_share_url = base_url(req) <> share_path

  c.page(wl.name <> " \u{2014} Rebstock", user, conn, [
    c.back_link("/~" <> username <> "/lists", "Lists"),
    html.div([attr.class("flex items-end justify-between mb-6")], [
      html.div([], [
        html.h1(
          [attr.class("text-3xl font-light text-stone-800 tracking-tight")],
          [html.Text(wl.name)],
        ),
        html.div([attr.class("flex items-center gap-3 mt-1")], [
          html.p([attr.class("text-stone-500")], [html.Text(count <> " wines")]),
          case wl.description {
            None -> html.Nothing
            Some(d) ->
              html.p([attr.class("text-stone-400 text-sm")], [html.Text(d)])
          },
        ]),
      ]),
      case is_owner {
        False -> html.Nothing
        True ->
          html.div([attr.class("flex items-center gap-2")], [
            case is_custom {
              True -> html.Nothing
              False -> bottles_toggle_form(wl, username)
            },
            share_control(wl, username, full_share_url),
            html.a(
              [
                attr.href("/~" <> username <> "/lists/" <> wl.id <> "/print"),
                attr.Attr("target", "_blank"),
                attr.class(
                  "px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors",
                ),
              ],
              [html.Text("Print view")],
            ),
            case is_custom {
              False -> html.Nothing
              True ->
                html.a(
                  [
                    attr.href("/~" <> username <> "/lists/" <> wl.id <> "/edit"),
                    attr.class(
                      "px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors",
                    ),
                  ],
                  [html.Text("Edit")],
                )
            },
          ])
      },
    ]),
    list_wines_table(wines, username, wl, is_owner, wl.show_bottles),
  ])
}

pub fn print_view(
  conn: Connection,
  user: User,
  username: String,
  id: String,
) -> Response {
  case db.get_list(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(wl) -> {
      case wl.username == username {
        False -> c.not_found(user, conn)
        True -> shared.render_menu(conn, wl)
      }
    }
  }
}

fn share_control(
  wl: WineList,
  username: String,
  full_share_url: String,
) -> html.Node {
  let #(label, public_val) = case wl.public {
    True -> #("Unshare", "0")
    False -> #("Share", "1")
  }
  let btn = "px-3 py-1.5 text-sm transition-colors"
  html.div(
    [
      attr.class(
        "inline-flex border border-stone-300 rounded-md overflow-hidden",
      ),
    ],
    [
      html.Element(
        "form",
        [
          attr.method("post"),
          attr.Attr(
            "action",
            "/~" <> username <> "/lists/" <> wl.id <> "/public",
          ),
          attr.class("flex"),
        ],
        [
          html.Element(
            "input",
            [
              attr.type_("hidden"),
              attr.name("public"),
              attr.value(public_val),
            ],
            [],
          ),
          html.Element(
            "button",
            [
              attr.type_("submit"),
              attr.class(btn <> " text-stone-600 hover:bg-stone-50"),
            ],
            [html.Text(label)],
          ),
        ],
      ),
      case wl.public {
        True ->
          html.a(
            [
              attr.href(full_share_url),
              attr.Attr("target", "_blank"),
              attr.class(
                btn
                <> " border-l border-stone-300 text-stone-600 hover:bg-stone-50",
              ),
            ],
            [html.Text("\u{1f517}")],
          )
        False ->
          html.span(
            [
              attr.class(
                btn
                <> " border-l border-stone-300 opacity-25 cursor-not-allowed",
              ),
            ],
            [html.Text("\u{1f517}")],
          )
      },
    ],
  )
}

fn bottles_toggle_form(wl: WineList, username: String) -> html.Node {
  let #(label, val) = case wl.show_bottles {
    True -> #("Hide stock", "0")
    False -> #("Show stock", "1")
  }
  html.Element(
    "form",
    [
      attr.method("post"),
      attr.Attr(
        "action",
        "/~" <> username <> "/lists/" <> wl.id <> "/show-bottles",
      ),
    ],
    [
      html.Element(
        "input",
        [attr.type_("hidden"), attr.name("show_bottles"), attr.value(val)],
        [],
      ),
      html.Element(
        "button",
        [
          attr.type_("submit"),
          attr.class(
            "px-3 py-1.5 text-sm border border-stone-300 rounded-md text-stone-600 hover:bg-stone-50 transition-colors",
          ),
        ],
        [html.Text(label)],
      ),
    ],
  )
}

pub fn set_show_bottles(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
  id: String,
) -> Response {
  case user.username == username {
    False -> wisp.response(403)
    True -> {
      case db.get_list(conn, id) {
        Error(_) -> c.not_found(user, conn)
        Ok(wl) -> {
          case wl.username == username {
            False -> wisp.response(403)
            True -> {
              use form <- wisp.require_form(req)
              let show = case list.key_find(form.values, "show_bottles") {
                Ok("1") -> True
                _ -> False
              }
              db.set_list_show_bottles(conn, id, show)
              wisp.redirect("/~" <> username <> "/lists/" <> id)
            }
          }
        }
      }
    }
  }
}

fn handle_list_post(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
  wl: WineList,
) -> Response {
  case user.username == username {
    False -> wisp.response(403)
    True -> {
      use form <- wisp.require_form(req)
      case list.key_find(form.values, "_method") {
        Ok("delete") -> {
          case wl.list_type {
            db.CustomList -> {
              db.delete_list(conn, wl.id)
              wisp.redirect("/~" <> username <> "/lists")
            }
            _ -> wisp.response(403)
          }
        }
        _ -> {
          case wl.list_type {
            db.CustomList -> {
              let name = case list.key_find(form.values, "name") {
                Ok(n) if n != "" -> n
                _ -> wl.name
              }
              let description = case list.key_find(form.values, "description") {
                Ok(d) if d != "" -> Some(d)
                _ -> None
              }
              let show_bottles = case
                list.key_find(form.values, "show_bottles")
              {
                Ok("1") -> True
                _ -> False
              }
              db.update_list(conn, wl.id, name, description, show_bottles)
              wisp.redirect("/~" <> username <> "/lists/" <> wl.id)
            }
            _ -> wisp.response(403)
          }
        }
      }
    }
  }
}

// --- Set public ---

pub fn set_public(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
  id: String,
) -> Response {
  case user.username == username {
    False -> wisp.response(403)
    True -> {
      case db.get_list(conn, id) {
        Error(_) -> c.not_found(user, conn)
        Ok(wl) -> {
          case wl.username == username {
            False -> wisp.response(403)
            True -> {
              use form <- wisp.require_form(req)
              let public = case list.key_find(form.values, "public") {
                Ok("1") -> True
                _ -> False
              }
              db.set_list_public(conn, id, public)
              wisp.redirect("/~" <> username <> "/lists/" <> id)
            }
          }
        }
      }
    }
  }
}

// --- Add wine ---

pub fn add_wine(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
  list_id: String,
) -> Response {
  case user.username == username {
    False -> wisp.response(403)
    True -> {
      case db.get_list(conn, list_id) {
        Error(_) -> c.not_found(user, conn)
        Ok(wl) -> {
          case wl.list_type {
            db.CellarList | db.RatedList -> wisp.response(403)
            db.WishlistList | db.CustomList -> {
              use form <- wisp.require_form(req)
              case list.key_find(form.values, "wine_id") {
                Error(_) ->
                  wisp.redirect("/~" <> username <> "/lists/" <> list_id)
                Ok(wine_id) -> {
                  let vintage = case list.key_find(form.values, "vintage") {
                    Ok(v) if v != "" -> Some(v)
                    _ -> None
                  }
                  let notes = case list.key_find(form.values, "notes") {
                    Ok(n) if n != "" -> Some(n)
                    _ -> None
                  }
                  db.add_wine_to_list(conn, list_id, wine_id, vintage, notes)
                  wisp.redirect("/~" <> username <> "/lists/" <> list_id)
                }
              }
            }
          }
        }
      }
    }
  }
}

// --- Remove wine ---

pub fn remove_wine(
  conn: Connection,
  user: User,
  username: String,
  list_id: String,
  wine_id: String,
) -> Response {
  case user.username == username {
    False -> wisp.response(403)
    True -> {
      case db.get_list(conn, list_id) {
        Error(_) -> c.not_found(user, conn)
        Ok(wl) -> {
          case wl.list_type {
            db.CellarList | db.RatedList -> wisp.response(403)
            db.WishlistList | db.CustomList -> {
              db.remove_wine_from_list(conn, list_id, wine_id)
              wisp.redirect("/~" <> username <> "/lists/" <> list_id)
            }
          }
        }
      }
    }
  }
}

// --- Wine table ---

fn list_wines_table(
  wines: List(ListViewWine),
  username: String,
  wl: WineList,
  is_owner: Bool,
  show_bottles: Bool,
) -> html.Node {
  let can_modify = case wl.list_type {
    db.WishlistList | db.CustomList -> is_owner
    _ -> False
  }
  let base_headers = ["Winery", "Wine", "Vintage", "Country", "Type", "Notes"]
  let headers = case show_bottles, can_modify {
    True, True -> list.append(base_headers, ["Bottles", ""])
    True, False -> list.append(base_headers, ["Bottles"])
    False, True -> list.append(base_headers, [""])
    False, False -> base_headers
  }
  c.table(
    headers,
    list.index_map(wines, fn(lw, idx) {
      list_wine_row(lw, idx, username, wl, can_modify, show_bottles)
    }),
  )
}

fn list_wine_row(
  lw: ListViewWine,
  idx: Int,
  username: String,
  wl: WineList,
  can_modify: Bool,
  show_bottles: Bool,
) -> html.Node {
  let wine = lw.wine
  html.tr(
    [
      attr.id("wine-" <> wine.id),
      attr.class(c.clickable_row_class(idx) <> " target-highlight"),
      attr.Attr("hx-get", c.wine_url(wine) <> "/overlay"),
      attr.Attr("hx-target", "#overlay"),
      attr.Attr("hx-swap", "outerHTML"),
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
        html.Text(c.display_optional(lw.vintage)),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(c.display_country(wine.country)),
      ]),
      html.td([attr.class("px-4 py-3")], [c.wine_type_badge(wine.wine_type)]),
      html.td([attr.class("px-4 py-3 text-stone-600 max-w-xs truncate")], [
        html.Text(c.display_optional(lw.notes)),
      ]),
      case show_bottles {
        False -> html.Nothing
        True ->
          html.td(
            [attr.class("px-4 py-3 text-stone-500 tabular-nums text-right")],
            [
              html.Text(case lw.bottles {
                Some(b) -> int.to_string(b)
                None -> ""
              }),
            ],
          )
      },
      case can_modify {
        False -> html.Nothing
        True ->
          html.td([attr.class("px-4 py-3")], [
            remove_wine_form(username, wl.id, wine.id),
          ])
      },
    ],
  )
}

fn remove_wine_form(
  username: String,
  list_id: String,
  wine_id: String,
) -> html.Node {
  html.Element(
    "form",
    [
      attr.method("post"),
      attr.Attr(
        "action",
        "/~" <> username <> "/lists/" <> list_id <> "/wines/" <> wine_id,
      ),
      attr.Attr("onclick", "event.stopPropagation()"),
    ],
    [
      html.Element(
        "input",
        [attr.type_("hidden"), attr.name("_method"), attr.value("delete")],
        [],
      ),
      html.Element(
        "button",
        [
          attr.type_("submit"),
          attr.class(
            "text-xs text-stone-400 hover:text-rose-700 transition-colors",
          ),
        ],
        [html.Text("Remove")],
      ),
    ],
  )
}

fn wines_for_list(conn: Connection, wl: WineList) -> List(ListViewWine) {
  let base = case wl.list_type {
    db.CellarList ->
      db.cellar_wines_by_type(conn, wl.username)
      |> list.map(fn(cw) {
        ListViewWine(
          wine: cw.wine,
          vintage: cw.vintage,
          notes: None,
          bottles: None,
        )
      })
    db.RatedList ->
      db.rated_wines(conn, wl.username)
      |> list.map(fn(w) {
        ListViewWine(wine: w, vintage: None, notes: None, bottles: None)
      })
    _ ->
      db.list_wines_for_list(conn, wl.id)
      |> list.map(fn(lw) {
        ListViewWine(
          wine: lw.wine,
          vintage: lw.vintage,
          notes: lw.notes,
          bottles: None,
        )
      })
  }
  case wl.show_bottles {
    False -> base
    True -> {
      let counts = db.bottle_counts_for_user(conn, wl.username)
      list.map(base, fn(lw) {
        let b = list.key_find(counts, lw.wine.id)
        ListViewWine(..lw, bottles: option.from_result(b))
      })
    }
  }
}
