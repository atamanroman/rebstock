import gleam/int
import gleam/list
import gleam/option.{None, Some}
import nakai
import nakai/attr
import nakai/html
import sqlight.{type Connection}
import wisp.{type Response}

import rebstock/db

const css =
  "
* { margin: 0; padding: 0; box-sizing: border-box; }

body {
  background: #fff;
  color: var(--stone-900);
}

.wine-menu {
  font-family: 'Cormorant Garamond', Georgia, serif;
  max-width: 680px;
  margin: 0 auto;
  padding: 48px 40px;
  line-height: 1.5;
}

.menu-header {
  text-align: center;
  margin-bottom: 36px;
  padding-bottom: 20px;
  border-bottom: 1px solid var(--stone-400);
}

.menu-title {
  font-size: 30px;
  font-weight: 300;
  letter-spacing: 0.04em;
  color: var(--stone-800);
}

.menu-description {
  font-size: 15px;
  color: var(--stone-500);
  font-style: italic;
  font-weight: 300;
  margin-top: 6px;
}

.menu-meta {
  font-size: 11px;
  font-family: system-ui, sans-serif;
  color: var(--stone-400);
  margin-top: 8px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}

.wine-section {
  margin-bottom: 32px;
}

.section-header {
  font-size: 10px;
  font-family: system-ui, sans-serif;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  margin-bottom: 16px;
  padding-bottom: 4px;
  border-bottom: 2px solid;
}

.wine-entry { margin-bottom: 14px; }

.wine-row {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.wine-name-col { flex: 1; }

.wine-name {
  font-size: 18px;
  font-weight: 500;
  color: var(--stone-900);
}

.wine-vintage {
  font-size: 14px;
  color: var(--stone-500);
  margin-left: 4px;
}

.wine-region {
  font-size: 13px;
  color: var(--stone-400);
  font-style: italic;
  font-weight: 300;
}

.wine-bottles {
  font-size: 12px;
  font-family: system-ui, sans-serif;
  color: var(--stone-400);
  margin-left: 16px;
  min-width: 24px;
  text-align: right;
}

.wine-winery {
  font-size: 13px;
  color: var(--stone-600);
  font-weight: 300;
  margin-top: 1px;
}

.menu-footer {
  display: flex;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 6px 20px;
  padding-top: 20px;
  border-top: 1px solid var(--stone-300);
  font-size: 11px;
  font-family: system-ui, sans-serif;
  color: var(--stone-400);
  letter-spacing: 0.04em;
}

.menu-footer a { color: inherit; }

@media print {
  .wine-menu { padding: 0; }
  body { font-size: 11pt; }
}
"

// Wine type order for sections
const wine_type_order = [
  db.Red,
  db.White,
  db.Rose,
  db.Orange,
  db.Sparkling,
  db.Dessert,
  db.Sake,
  db.Other,
]

fn wine_type_color(wt: db.WineType) -> String {
  case wt {
    db.Red -> "var(--wine-red)"
    db.White -> "var(--wine-white)"
    db.Rose -> "var(--wine-rose)"
    db.Orange -> "var(--wine-orange)"
    db.Sparkling -> "var(--wine-sparkling)"
    db.Dessert -> "var(--wine-dessert)"
    db.Sake -> "var(--wine-sake)"
    db.Other -> "var(--wine-other)"
  }
}

type WineEntry {
  WineEntry(
    wine: db.Wine,
    vintage: option.Option(String),
    bottles: option.Option(Int),
  )
}

fn render_section(wt: db.WineType, entries: List(WineEntry)) -> html.Node {
  let label = db.wine_type_label(wt)
  let color = wine_type_color(wt)
  html.div([attr.class("wine-section")], [
    html.div(
      [
        attr.class("section-header"),
        attr.Attr("style", "color: " <> color <> "; border-color: " <> color),
      ],
      [html.Text(label)],
    ),
    html.div([], list.map(entries, render_entry)),
  ])
}

fn render_entry(e: WineEntry) -> html.Node {
  let vintage_node = case e.vintage {
    None -> html.Nothing
    Some(v) -> html.span([attr.class("wine-vintage")], [html.Text(v)])
  }
  let region_node = case e.wine.region {
    None -> html.Nothing
    Some(r) -> html.span([attr.class("wine-region")], [html.Text(r)])
  }
  let bottles_node = case e.bottles {
    None -> html.Nothing
    Some(b) ->
      html.span([attr.class("wine-bottles")], [
        html.Text("(" <> int.to_string(b) <> ")"),
      ])
  }
  html.div([attr.class("wine-entry")], [
    html.div([attr.class("wine-row")], [
      html.div([attr.class("wine-name-col")], [
        html.span([attr.class("wine-name")], [html.Text(e.wine.name)]),
        vintage_node,
      ]),
      region_node,
      bottles_node,
    ]),
    html.div([attr.class("wine-winery")], [html.Text(e.wine.winery_name)]),
  ])
}

fn entries_for_list(conn: Connection, wl: db.WineList) -> List(WineEntry) {
  let base = case wl.list_type {
    db.CellarList ->
      db.cellar_wines_by_type(conn, wl.username)
      |> list.map(fn(cw) {
        WineEntry(wine: cw.wine, vintage: cw.vintage, bottles: None)
      })
    db.RatedList ->
      db.rated_wines(conn, wl.username)
      |> list.map(fn(w) { WineEntry(wine: w, vintage: None, bottles: None) })
    _ ->
      db.list_wines_for_list(conn, wl.id)
      |> list.map(fn(lw) {
        WineEntry(wine: lw.wine, vintage: lw.vintage, bottles: None)
      })
  }
  case wl.show_bottles {
    False -> base
    True -> {
      let counts = db.bottle_counts_for_user(conn, wl.username)
      list.map(base, fn(e) {
        let b = list.key_find(counts, e.wine.id)
        WineEntry(..e, bottles: option.from_result(b))
      })
    }
  }
}

pub fn shared_list(conn: Connection, id: String) -> Response {
  case db.get_list(conn, id) {
    Error(Nil) -> shared_not_found()
    Ok(wl) -> {
      case wl.public {
        False -> shared_not_found()
        True -> render_menu(conn, wl)
      }
    }
  }
}

fn menu_footer() -> html.Node {
  html.div([attr.class("menu-footer")], [
    html.span([], [html.Text("© 2026 Roman Ataman")]),
    html.span([], [
      html.a([attr.href("https://rebstock.atamanroman.dev")], [
        html.Text("rebstock.atamanroman.dev"),
      ]),
      html.Text(" · "),
      html.a(
        [
          attr.href("https://polyformproject.org/licenses/noncommercial/1.0.0/"),
        ],
        [html.Text("PolyForm Noncommercial 1.0.0")],
      ),
    ]),
  ])
}

fn shared_not_found() -> Response {
  let page =
    html.Html([attr.lang("en")], [
      html.Head([
        html.meta([attr.charset("utf-8")]),
        html.meta([
          attr.name("viewport"),
          attr.content("width=device-width, initial-scale=1"),
        ]),
        html.title("Not Found \u{2014} Rebstock"),
        html.Element("style", [], [html.UnsafeInlineHtml(css)]),
      ]),
      html.Body([], [
        html.div([attr.class("wine-menu")], [
          html.div(
            [
              attr.Attr(
                "style",
                "text-align: center; padding: 64px 0; color: var(--stone-500, #78716c);",
              ),
            ],
            [
              html.div(
                [attr.Attr("style", "font-size: 48px; margin-bottom: 16px;")],
                [html.Text("\u{1f377}")],
              ),
              html.h1(
                [
                  attr.class("menu-title"),
                  attr.Attr("style", "margin-bottom: 8px;"),
                ],
                [html.Text("This glass is empty")],
              ),
              html.p([attr.class("menu-description")], [
                html.Text(
                  "The list you\u{2019}re looking for doesn\u{2019}t exist or isn\u{2019}t public.",
                ),
              ]),
            ],
          ),
          menu_footer(),
        ]),
      ]),
    ])
  page
  |> nakai.to_string
  |> wisp.html_response(404)
}

pub fn render_menu(conn: Connection, wl: db.WineList) -> Response {
  let all_entries = entries_for_list(conn, wl)

  let total = list.length(all_entries)

  // Group by wine type in defined order
  let sections =
    list.filter_map(wine_type_order, fn(wt) {
      let group = list.filter(all_entries, fn(e) { e.wine.wine_type == wt })
      case group {
        [] -> Error(Nil)
        _ -> Ok(render_section(wt, group))
      }
    })

  let description_node = case wl.description {
    None -> html.Nothing
    Some(d) -> html.p([attr.class("menu-description")], [html.Text(d)])
  }

  let favicon =
    "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🍇</text></svg>"

  let page =
    html.Html([attr.lang("en")], [
      html.Head([
        html.meta([attr.charset("utf-8")]),
        html.meta([
          attr.name("viewport"),
          attr.content("width=device-width, initial-scale=1"),
        ]),
        html.title(wl.name <> " — Rebstock"),
        html.link([
          attr.rel("icon"),
          attr.href(favicon),
        ]),
        html.link([
          attr.rel("preconnect"),
          attr.href("https://fonts.googleapis.com"),
        ]),
        html.link([
          attr.rel("preconnect"),
          attr.href("https://fonts.gstatic.com"),
          attr.Attr("crossorigin", ""),
        ]),
        html.link([
          attr.rel("stylesheet"),
          attr.href(
            "https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;0,500;1,300;1,400&display=swap",
          ),
        ]),
        html.link([
          attr.rel("stylesheet"),
          attr.href("/static/css/colors.css"),
        ]),
        html.Element("style", [], [html.UnsafeInlineHtml(css)]),
      ]),
      html.Body([], [
        html.div([attr.class("wine-menu")], [
          html.div([attr.class("menu-header")], [
            html.h1([attr.class("menu-title")], [html.Text(wl.name)]),
            description_node,
            html.p([attr.class("menu-meta")], [
              html.Text(
                "Curated by "
                <> wl.username
                <> " · "
                <> int.to_string(total)
                <> " wines",
              ),
            ]),
          ]),
          html.div([], sections),
          menu_footer(),
        ]),
      ]),
    ])

  page
  |> nakai.to_string
  |> wisp.html_response(200)
}
