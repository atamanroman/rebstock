import gleam/int
import gleam/list
import gleam/option.{None, Some}
import nakai/attr
import nakai/html
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/auth.{type User}
import rebstock/db.{type Rating, type Wine}
import rebstock/web/components as c

pub fn my_ratings(conn: Connection, user: User, username: String) -> Response {
  let ratings = db.ratings_by_user(conn, username)
  let count = int.to_string(list.length(ratings))

  c.page("My Ratings \u{2014} Rebstock", user, [
    c.page_header("My Ratings", count <> " ratings"),
    rating_table(ratings, conn),
  ])
}

pub fn rating_detail(conn: Connection, id: String, user: User) -> Response {
  case db.get_rating_by_id(conn, id) {
    Error(_) -> wisp.not_found()
    Ok(rating) ->
      case db.get_wine_by_id(conn, rating.wine_id) {
        Error(_) -> wisp.not_found()
        Ok(wine) ->
          c.page(wine.name <> " Rating \u{2014} Rebstock", user, [
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
          attr.Attr("hx-get", "/ratings/" <> rating.id <> "/overlay"),
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
