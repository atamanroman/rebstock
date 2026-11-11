import gleam/float
import gleam/http
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import nakai/attr
import nakai/html
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type User}
import rebstock/db.{type Rating, type Wine}
import rebstock/web/components as c

pub fn my_ratings(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
) -> Response {
  let filter = c.rating_filter(req)
  let ratings = db.ratings_by_user(conn, username, filter)
  let count = int.to_string(list.length(ratings))
  let title = case username == user.username {
    True -> "Your Ratings"
    False -> username <> "'s Ratings"
  }

  c.page(title <> " \u{2014} Rebstock", user, conn, [
    c.page_header(title, count <> " ratings"),
    c.filter_chips(filter, "/~" <> username <> "/ratings"),
    c.table_filter("ratings-table", "Filter ratings…"),
    html.div([attr.id("ratings-table")], [rating_table(ratings, conn)]),
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
      let default_date =
        list.key_find(wisp.get_query(req), "rated_at") |> option.from_result
      case req.method {
        http.Get ->
          case c.is_fragment(req) {
            True ->
              c.overlay_wrapper(rating_form(
                wine,
                vintages,
                None,
                default_date,
                True,
              ))
            False ->
              c.page("Rate " <> wine.name <> " \u{2014} Rebstock", user, conn, [
                c.back_link(c.wine_url(wine), wine.name),
                rating_form(wine, vintages, None, default_date, False),
              ])
          }
        http.Post -> {
          use form <- wisp.require_form(req)
          let vintage = form_value(form, "vintage")
          let rating = form_float(form, "rating")
          let notes = form_value(form, "tasting_notes")
          let date = form_value(form, "rated_at")
          case rating {
            Some(score) if score >=. 1.0 && score <=. 5.0 -> {
              db.insert_rating(
                conn,
                username: user.username,
                wine_id: wine.id,
                vintage: vintage,
                rating: rating,
                tasting_notes: notes,
                rated_at: date,
              )
              c.redirect(req, c.wine_url(wine))
            }
            _ ->
              c.form_error(
                req,
                conn,
                user,
                rating_form(wine, vintages, None, None, c.is_fragment(req)),
                form.values,
                ["rating"],
                "Choose a rating between 1 and 5.",
              )
          }
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
                  case c.is_fragment(req) {
                    True ->
                      c.overlay_wrapper(rating_form(
                        wine,
                        vintages,
                        Some(rating),
                        None,
                        True,
                      ))
                    False ->
                      c.page("Edit Rating \u{2014} Rebstock", user, conn, [
                        c.back_link(c.wine_url(wine), wine.name),
                        rating_form(wine, vintages, Some(rating), None, False),
                      ])
                  }
                http.Post -> {
                  use form <- wisp.require_form(req)
                  let vintage = form_value(form, "vintage")
                  let rating_val = form_float(form, "rating")
                  let notes = form_value(form, "tasting_notes")
                  let date = form_value(form, "rated_at")
                  case rating_val {
                    Some(score) if score >=. 1.0 && score <=. 5.0 -> {
                      db.update_rating(
                        conn,
                        id: rating.id,
                        vintage: vintage,
                        rating: rating_val,
                        tasting_notes: notes,
                        rated_at: date,
                      )
                      c.redirect(req, c.wine_url(wine))
                    }
                    _ ->
                      c.form_error(
                        req,
                        conn,
                        user,
                        rating_form(
                          wine,
                          vintages,
                          Some(rating),
                          None,
                          c.is_fragment(req),
                        ),
                        form.values,
                        ["rating"],
                        "Choose a rating between 1 and 5.",
                      )
                  }
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
                  c.redirect(req, c.wine_url(wine))
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
  c.overlay_wrapper(rating_form(wine, vintages, None, default_date, True))
}

fn rating_form(
  wine: Wine,
  vintages: List(String),
  existing: Option(Rating),
  default_date: Option(String),
  fragment: Bool,
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
  html.div([attr.class("form-card card")], [
    c.form_title(title, fragment),
    html.p([attr.class("text-sm text-stone-500 mb-4")], [
      html.Text(subtitle),
    ]),
    html.Element(
      "form",
      [
        attr.Attr("method", "POST"),
        attr.Attr("action", action),
        attr.Attr("hx-action", action),
        attr.Attr("hx-target", "closest .form-card"),
        attr.Attr("hx-swap", "outerHTML"),
        attr.Attr("hx-disable", "find button[type=submit]"),
        attr.Attr("hx-sync", "this:drop"),
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
            c.form_field("ratings-vintage", "Vintage", False, [
              html.Element(
                "select",
                [
                  attr.id("ratings-vintage"),
                  attr.name("vintage"),
                  attr.class(c.input_class),
                ],
                [
                  html.Element(
                    "option",
                    [
                      attr.value(""),
                      ..case cur_vintage == "" {
                        True -> [attr.Attr("selected", "")]
                        False -> []
                      }
                    ],
                    [html.Text("No vintage / N.V.")],
                  ),
                  ..list.map(vintages, fn(v) {
                    html.Element(
                      "option",
                      [
                        attr.value(v),
                        ..case v == cur_vintage {
                          True -> [attr.Attr("selected", "")]
                          False -> []
                        }
                      ],
                      [html.Text(v)],
                    )
                  })
                ],
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
          c.form_field("ratings-rating", "Rating (1–5)", True, [
            html.input([
              attr.type_("number"),
              attr.id("ratings-rating"),
              attr.name("rating"),
              attr.Attr("step", "0.1"),
              attr.Attr("min", "1"),
              attr.Attr("max", "5"),
              attr.Attr("required", ""),
              attr.value(cur_rating),
              attr.class(c.input_class),
            ]),
          ])
        },
        // Date
        c.form_field("ratings-rated_at", "Date", True, [
          html.Element(
            "input",
            [
              attr.type_("date"),
              attr.name("rated_at"),
              attr.id("ratings-rated_at"),
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
                      "var d=document.getElementById('ratings-rated_at');if(!d.value)d.valueAsDate=new Date()",
                    ),
                  ])
              }
          },
        ]),
        // Tasting notes
        c.form_field("ratings-tasting_notes", "Tasting Notes", False, [
          html.Element(
            "textarea",
            [
              attr.id("ratings-tasting_notes"),
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
              "button w-full px-4 py-2 bg-rose-800 text-white rounded-md text-sm font-medium hover:bg-rose-900 transition-colors",
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
              html.button(
                [
                  attr.type_("submit"),
                  attr.Attr("formaction", delete_url),
                  attr.Attr("formnovalidate", ""),
                  attr.class(
                    "text-xs text-stone-500 hover:text-red-600 transition-colors cursor-pointer",
                  ),
                  attr.Attr("hx-post", delete_url),
                  attr.Attr("hx-disable", "this"),
                  attr.Attr("hx-sync", "closest form:drop"),
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
  html.div([attr.class("detail-content")], [
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
    html.hr([attr.class("section-divider section-divider-compact")]),
    case rating.tasting_notes {
      Some(notes) ->
        html.p([attr.class("text-stone-700 whitespace-pre-line")], [
          html.Text(notes),
        ])
      None ->
        html.p([attr.class("text-stone-500 italic")], [
          html.Text("No tasting notes"),
        ])
    },
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
