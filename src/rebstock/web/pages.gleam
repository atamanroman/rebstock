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
    html.div([attr.class("max-w-6xl mx-auto px-4 py-8")], [
      html.div([attr.class("mb-8")], [
        html.h1([attr.class("text-3xl font-light text-stone-800 tracking-tight")], [
          html.Text("Rebstock"),
        ]),
        html.p([attr.class("text-stone-500 mt-1")], [
          html.Text(count <> " wines"),
        ]),
      ]),
      html.div([attr.class("overflow-x-auto rounded-lg border border-stone-200")], [
        html.table([attr.class("w-full text-sm")], [
          html.thead([], [
            html.tr([attr.class("bg-stone-50 border-b border-stone-200")], [
              th("Winery"),
              th("Wine"),
              th("Vintage"),
              th("Country"),
              th("Type"),
              th("Rating"),
              th("Cellar"),
            ]),
          ]),
          html.tbody([], list.index_map(wines, wine_row)),
        ]),
      ]),
    ]),
  ])
  |> render
}

fn th(label: String) -> Node {
  html.th(
    [attr.class("px-4 py-3 text-left font-medium text-stone-600 text-xs uppercase tracking-wider")],
    [html.Text(label)],
  )
}

fn wine_row(wine: Wine, idx: Int) -> Node {
  let bg = case idx % 2 {
    0 -> "bg-white"
    _ -> "bg-stone-50/50"
  }
  html.tr(
    [attr.class(bg <> " border-b border-stone-100 hover:bg-amber-50/50 transition-colors")],
    [
      html.td([attr.class("px-4 py-3 text-stone-700")], [
        html.Text(wine.winery),
      ]),
      html.td([attr.class("px-4 py-3 font-medium text-stone-800")], [
        case wine.vivino_link {
          "" -> html.Text(wine.name)
          link ->
            html.a(
              [attr.href(link), attr.class("hover:text-rose-800 transition-colors")],
              [html.Text(wine.name)],
            )
        },
      ]),
      html.td([attr.class("px-4 py-3 text-stone-500 tabular-nums")], [
        html.Text(case wine.vintage {
          Some(v) -> int.to_string(v)
          None -> "\u{2014}"
        }),
      ]),
      html.td([attr.class("px-4 py-3 text-stone-600")], [
        html.Text(wine.country),
      ]),
      html.td([attr.class("px-4 py-3")], [wine_type_badge(wine.wine_type)]),
      html.td([attr.class("px-4 py-3 tabular-nums")], [
        rating_display(wine.avg_rating),
      ]),
      html.td([attr.class("px-4 py-3 text-center tabular-nums")], [
        html.Text(case wine.in_cellar {
          0 -> ""
          n -> int.to_string(n)
        }),
      ]),
    ],
  )
}

fn wine_type_badge(wine_type: String) -> Node {
  let #(bg, text) = case wine_type {
    "Red Wine" -> #("bg-rose-900/10 text-rose-900", wine_type)
    "White Wine" -> #("bg-amber-100 text-amber-800", wine_type)
    "Rosé Wine" -> #("bg-pink-100 text-pink-700", wine_type)
    "Sparkling" -> #("bg-stone-100 text-stone-600", wine_type)
    other -> #("bg-stone-100 text-stone-600", other)
  }
  html.span(
    [attr.class("inline-block px-2 py-0.5 rounded text-xs font-medium " <> bg)],
    [html.Text(text)],
  )
}

fn rating_display(rating: option.Option(Float)) -> Node {
  case rating {
    None -> html.Text("")
    Some(r) -> {
      let stars = float.round(r)
      let color = case stars {
        n if n >= 4 -> "text-amber-700"
        _ -> "text-stone-500"
      }
      html.span([attr.class(color <> " font-medium")], [
        html.Text(float.to_string(r)),
      ])
    }
  }
}

fn layout(title: String, content: List(Node)) -> Node {
  html.Html([attr.class("antialiased")], [
    html.Head([
      html.meta([attr.charset("utf-8")]),
      html.meta([
        attr.name("viewport"),
        attr.content("width=device-width, initial-scale=1"),
      ]),
      html.title(title),
      html.link([
        attr.rel("stylesheet"),
        attr.href("/static/css/app.css"),
      ]),
    ]),
    html.Body([attr.class("bg-stone-100 text-stone-900 min-h-screen font-sans")], content),
  ])
}

fn render(page: Node) -> Response {
  page
  |> nakai.to_string
  |> wisp.html_response(200)
}
