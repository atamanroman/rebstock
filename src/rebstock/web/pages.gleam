import nakai
import nakai/html.{type Node}
import nakai/attr
import wisp.{type Response}

pub fn home() -> Response {
  layout("Rebstock", [
    html.h1([], [html.Text("Rebstock")]),
    html.p([], [html.Text("Your wine cellar.")]),
  ])
  |> render
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
