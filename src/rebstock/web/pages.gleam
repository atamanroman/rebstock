import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import nakai
import nakai/attr
import nakai/html.{type Node}
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/db.{type Wine}

pub fn home(conn: Connection) -> Response {
  let wines = db.list_wines(conn)
  let count = int.to_string(list.length(wines))

  layout("Rebstock", [
    html.h1([], [html.Text("Rebstock")]),
    html.p([], [html.Text(count <> " wines")]),
    html.table([], [
      html.thead([], [
        html.tr([], [
          html.th([], [html.Text("Winery")]),
          html.th([], [html.Text("Wine")]),
          html.th([], [html.Text("Vintage")]),
          html.th([], [html.Text("Country")]),
          html.th([], [html.Text("Type")]),
          html.th([], [html.Text("Rating")]),
          html.th([], [html.Text("Cellar")]),
        ]),
      ]),
      html.tbody([], list.map(wines, wine_row)),
    ]),
  ])
  |> render
}

fn wine_row(wine: Wine) -> Node {
  html.tr([], [
    html.td([], [html.Text(wine.winery)]),
    html.td([], [
      case wine.vivino_link {
        "" -> html.Text(wine.name)
        link -> html.a([attr.href(link)], [html.Text(wine.name)])
      },
    ]),
    html.td([], [
      html.Text(case wine.vintage {
        Some(v) -> int.to_string(v)
        None -> ""
      }),
    ]),
    html.td([], [html.Text(wine.country)]),
    html.td([], [html.Text(wine.wine_type)]),
    html.td([], [
      html.Text(case wine.avg_rating {
        Some(r) -> float.to_string(r)
        None -> ""
      }),
    ]),
    html.td([], [
      html.Text(case wine.in_cellar {
        0 -> ""
        n -> int.to_string(n)
      }),
    ]),
  ])
}

fn layout(title: String, content: List(Node)) -> Node {
  html.Html([], [
    html.Head([
      html.meta([attr.charset("utf-8")]),
      html.meta([
        attr.name("viewport"),
        attr.content("width=device-width, initial-scale=1"),
      ]),
      html.title(title),
    ]),
    html.Body([], content),
  ])
}

fn render(page: Node) -> Response {
  page
  |> nakai.to_string
  |> wisp.html_response(200)
}
