import gleam/float
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
import rebstock/db.{type Rating, type Wine}
import rebstock/web/components as c

pub fn my_ratings(conn: Connection, user: User, username: String) -> Response {
  let ratings = db.ratings_by_user(conn, username)
  let count = int.to_string(list.length(ratings))
  let title = case username == user.username {
    True -> "Your Ratings"
    False -> username <> "'s Ratings"
  }

  c.page(title <> " \u{2014} Rebstock", user, conn, [
    c.page_header(title, count <> " ratings"),
    rating_table(ratings, conn),
  ])
}

pub fn rating_detail(conn: Connection, id: String, user: User) -> Response {
  case db.get_rating_by_id(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(rating) ->
      case db.get_wine_by_id(conn, rating.wine_id) {
        Error(_) -> c.not_found(user, conn)
        Ok(wine) ->
          c.page(wine.name <> " Rating \u{2014} Rebstock", user, conn, [
            c.back_link(c.wine_url(wine), wine.name),
            rating_card(rating, wine),
          ])
      }
  }
}

pub fn rating_overlay(conn: Connection, id: String) -> Response {
  case db.get_rating_by_id(conn, id) {
    Error(_) -> wisp.not_found()
    Ok(rating) ->
      case db.get_wine_by_id(conn, rating.wine_id) {
        Error(_) -> wisp.not_found()
        Ok(wine) -> c.overlay_wrapper(rating_card(rating, wine))
      }
  }
}

/// GET: show form overlay for new rating. POST: create rating.
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
            True -> c.overlay_wrapper(rating_form(wine, vintages, None, None))
            False ->
              c.page("Rate " <> wine.name <> " \u{2014} Rebstock", user, conn, [
                c.back_link(c.wine_url(wine), wine.name),
                rating_form(wine, vintages, None, None),
              ])
          }
        http.Post -> {
          use form <- wisp.require_form(req)
          let vintage = form_value(form, "vintage")
          let rating = form_float(form, "rating")
          let notes = form_value(form, "tasting_notes")
          let date = form_value(form, "rated_at")
          db.insert_rating(
            conn,
            username: user.username,
            wine_id: wine.id,
            vintage: vintage,
            rating: rating,
            tasting_notes: notes,
            rated_at: date,
          )
          wisp.response(200)
          |> wisp.set_header("HX-Redirect", c.wine_url(wine))
        }
        _ -> wisp.method_not_allowed([http.Get, http.Post])
      }
    }
  }
}

/// GET: show form overlay for editing. POST: update rating.
pub fn handle_edit(
  req: Request,
  conn: Connection,
  id: String,
  user: User,
) -> Response {
  case db.get_rating_by_id(conn, id) {
    Error(_) -> c.not_found(user, conn)
    Ok(rating) ->
      case rating.username == user.username {
        False -> wisp.response(403)
        True ->
          case db.get_wine_by_id(conn, rating.wine_id) {
            Error(_) -> c.not_found(user, conn)
            Ok(wine) -> {
              let vintages = db.vintages_for_wine(conn, wine.id)
              case req.method {
                http.Get ->
                  case is_htmx(req) {
                    True ->
                      c.overlay_wrapper(rating_form(
                        wine,
                        vintages,
                        Some(rating),
                        None,
                      ))
                    False ->
                      c.page("Edit Rating \u{2014} Rebstock", user, conn, [
                        c.back_link(c.wine_url(wine), wine.name),
                        rating_form(wine, vintages, Some(rating), None),
                      ])
                  }
                http.Post -> {
                  use form <- wisp.require_form(req)
                  let vintage = form_value(form, "vintage")
                  let rating_val = form_float(form, "rating")
                  let notes = form_value(form, "tasting_notes")
                  let date = form_value(form, "rated_at")
                  db.update_rating(
                    conn,
                    id: rating.id,
                    vintage: vintage,
                    rating: rating_val,
                    tasting_notes: notes,
                    rated_at: date,
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

/// POST: delete rating.
pub fn handle_delete(
  req: Request,
  conn: Connection,
  id: String,
  user: User,
) -> Response {
  case req.method {
    http.Post ->
      case db.get_rating_by_id(conn, id) {
        Error(_) -> c.not_found(user, conn)
        Ok(rating) ->
          case rating.username == user.username {
            False -> wisp.response(403)
            True ->
              case db.get_wine_by_id(conn, rating.wine_id) {
                Error(_) -> c.not_found(user, conn)
                Ok(wine) -> {
                  db.delete_rating(conn, id)
                  wisp.response(200)
                  |> wisp.set_header("HX-Redirect", c.wine_url(wine))
                }
              }
          }
      }
    _ -> wisp.method_not_allowed([http.Post])
  }
}

pub fn new_rating_overlay(
  wine: Wine,
  conn: Connection,
  default_date: Option(String),
) -> Response {
  let vintages = db.vintages_for_wine(conn, wine.id)
  c.overlay_wrapper(rating_form(wine, vintages, None, default_date))
}

fn rating_form(
  wine: Wine,
  vintages: List(String),
  existing: Option(Rating),
  default_date: Option(String),
) -> html.Node {
  let wine_base = c.wine_url(wine)
  let action = case existing {
    Some(r) -> wine_base <> "/ratings/" <> r.id <> "/edit"
    None -> wine_base <> "/ratings/new"
  }
  let title = case existing {
    Some(_) -> "Edit Rating"
    None -> "Rate " <> wine.name
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
              Some(r) ->
                case r.vintage {
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
        // Rating
        {
          let cur_rating = case existing {
            Some(r) ->
              case r.rating {
                Some(v) -> float.to_string(v)
                None -> "3.0"
              }
            None -> "3.0"
          }
          let cur_stars = case existing {
            Some(r) ->
              case r.rating {
                Some(v) -> stars_for(v)
                None -> stars_for(3.0)
              }
            None -> stars_for(3.0)
          }
          req_field("Rating", [
            html.div([attr.class("flex items-center gap-3")], [
              html.Element(
                "input",
                [
                  attr.type_("range"),
                  attr.name("rating"),
                  attr.Attr("step", "0.1"),
                  attr.Attr("min", "0"),
                  attr.Attr("max", "5"),
                  attr.value(cur_rating),
                  attr.class("flex-1 accent-amber-500"),
                  attr.Attr(
                    "oninput",
                    "var v=parseFloat(this.value);this.parentElement.querySelector('.rv').textContent=v.toFixed(1);var s=Math.round(v);this.parentElement.querySelector('.rs').textContent='\\u2605'.repeat(s)+'\\u2606'.repeat(5-s)",
                  ),
                ],
                [],
              ),
              html.span(
                [
                  attr.class(
                    "rv text-lg font-medium tabular-nums text-stone-800 w-8 text-right",
                  ),
                ],
                [html.Text(cur_rating)],
              ),
              html.span([attr.class("rs text-amber-500 text-lg")], [
                html.Text(cur_stars),
              ]),
            ]),
          ])
        },
        // Date
        req_field("Date", [
          html.Element(
            "input",
            [
              attr.type_("date"),
              attr.name("rated_at"),
              attr.id("rating-date"),
              attr.Attr("required", "required"),
              attr.class(
                "w-full border border-stone-300 rounded-md px-3 py-2 text-sm",
              ),
              ..case existing {
                Some(r) ->
                  case r.rated_at {
                    Some(d) -> [attr.value(d)]
                    None -> []
                  }
                None ->
                  case default_date {
                    Some(d) -> [attr.value(d)]
                    None -> []
                  }
              }
            ],
            [],
          ),
          case existing {
            Some(_) -> html.Nothing
            None ->
              case default_date {
                Some(_) -> html.Nothing
                None ->
                  html.Element("script", [], [
                    html.Text(
                      "document.getElementById('rating-date').valueAsDate=new Date()",
                    ),
                  ])
              }
          },
        ]),
        // Tasting notes
        form_field("Tasting Notes", [
          html.Element(
            "textarea",
            [
              attr.name("tasting_notes"),
              attr.Attr("rows", "3"),
              attr.Attr("placeholder", "Your tasting notes..."),
              attr.class(
                "w-full border border-stone-300 rounded-md px-3 py-2 text-sm",
              ),
            ],
            case existing {
              Some(r) ->
                case r.tasting_notes {
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
              Some(_) -> "Update Rating"
              None -> "Save Rating"
            }),
          ],
        ),
        // Delete (only when editing)
        case existing {
          Some(r) -> {
            let delete_url = wine_base <> "/ratings/" <> r.id <> "/delete"
            html.div([attr.class("text-center pt-2")], [
              html.a(
                [
                  attr.href(delete_url),
                  attr.class(
                    "text-xs text-stone-400 hover:text-red-600 transition-colors cursor-pointer",
                  ),
                  attr.Attr("hx-post", delete_url),
                  attr.Attr("hx-confirm", "Delete this rating?"),
                ],
                [html.Text("Delete this rating")],
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

fn stars_for(rating: Float) -> String {
  let full = float.round(rating)
  let empty = 5 - full
  string.repeat("\u{2605}", full) <> string.repeat("\u{2606}", empty)
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

fn form_float(form: wisp.FormData, key: String) -> Option(Float) {
  case form_value(form, key) {
    None -> None
    Some(s) -> db.parse_optional_float(s)
  }
}

fn rating_card(rating: Rating, wine: Wine) -> html.Node {
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
          html.Text(case rating.vintage {
            None -> ""
            Some(_) -> " \u{00b7} " <> c.display_vintage(rating.vintage)
          }),
        ]),
      ]),
      html.div([attr.class("text-2xl")], [
        c.rating_display(rating.rating),
      ]),
    ]),
    html.p([attr.class("text-sm text-stone-500 mb-4")], [
      c.date_node(case rating.rated_at {
        Some(date) -> date
        None -> rating.created_at
      }),
    ]),
    html.div([attr.class("mt-4 pt-4 border-t border-stone-100")], [
      case rating.tasting_notes {
        Some(notes) ->
          html.p([attr.class("text-stone-700 whitespace-pre-line")], [
            html.Text(notes),
          ])
        None ->
          html.p([attr.class("text-stone-400 italic")], [
            html.Text("No tasting notes"),
          ])
      },
    ]),
  ])
}

fn rating_table(ratings: List(Rating), conn: Connection) -> html.Node {
  c.table(
    ["Winery", "Wine", "Vintage", "Rating", "Notes", "Date"],
    list.index_map(ratings, fn(r, i) { rating_row(r, i, conn) }),
  )
}

fn rating_row(rating: Rating, idx: Int, conn: Connection) -> html.Node {
  case db.get_wine_by_id(conn, rating.wine_id) {
    Error(_) -> html.Nothing
    Ok(wine) ->
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
            html.Text(c.display_vintage(rating.vintage)),
          ]),
          html.td([attr.class("px-4 py-3 tabular-nums")], [
            c.rating_display(rating.rating),
          ]),
          html.td([attr.class("px-4 py-3 text-stone-600 max-w-xs truncate")], [
            html.Text(case rating.tasting_notes {
              Some(notes) -> notes
              None -> ""
            }),
          ]),
          html.td([attr.class("px-4 py-3 text-stone-500 text-xs")], [
            c.date_node(case rating.rated_at {
              Some(date) -> date
              None -> rating.created_at
            }),
          ]),
        ],
      )
  }
}
