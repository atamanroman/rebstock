import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import nakai
import nakai/attr
import nakai/html.{type Node}
import wisp.{type Response}

import rebstock/auth.{type User}
import rebstock/db

// --- Links ---

/// Standard entity link with wine-red hover
pub fn link(href: String, children: List(Node)) -> Node {
  html.a(
    [
      attr.href(href),
      attr.class("hover:text-rose-800 transition-colors"),
    ],
    children,
  )
}

/// Entity link that stops event propagation (for use inside clickable table rows)
pub fn link_stop(href: String, children: List(Node)) -> Node {
  html.a(
    [
      attr.href(href),
      attr.class("hover:text-rose-800 transition-colors"),
      attr.Attr("onclick", "event.stopPropagation()"),
    ],
    children,
  )
}

/// Back/breadcrumb link: "← label"
pub fn back_link(href: String, label: String) -> Node {
  html.div([attr.class("mb-6")], [
    html.a(
      [
        attr.href(href),
        attr.class("text-sm text-stone-500 hover:text-rose-800"),
      ],
      [html.Text("\u{2190} " <> label)],
    ),
  ])
}

/// Navigation link in site header
pub fn nav_link(label: String, href: String) -> Node {
  html.a(
    [
      attr.href(href),
      attr.class("text-stone-500 hover:text-rose-800 transition-colors"),
    ],
    [html.Text(label)],
  )
}

/// Action link (e.g. "View in cellar", "View on Vivino")
pub fn action_link(href: String, label: String) -> Node {
  html.a(
    [
      attr.href(href),
      attr.class("text-sm text-rose-800 hover:text-rose-900"),
    ],
    [html.Text(label)],
  )
}

// --- URLs ---

pub fn wine_url(wine: db.Wine) -> String {
  "/wines/" <> wine.id <> "/" <> db.slugify(wine.name)
}

pub fn winery_url(id: String, name: String) -> String {
  "/wineries/" <> id <> "/" <> db.slugify(name)
}

// --- Display helpers ---

pub fn display_winery(winery: String) -> String {
  case winery {
    "" -> "Unknown"
    w -> w
  }
}

pub fn display_vintage(vintage: Option(String)) -> String {
  case vintage {
    None -> ""
    Some("NV") -> "N.V."
    Some(v) -> v
  }
}

pub fn display_vintages(vintages: Option(String)) -> String {
  case vintages {
    None -> ""
    Some(v) -> v
  }
}

pub fn display_country(country: Option(String)) -> String {
  case country {
    None -> ""
    Some(c) -> iso_to_country(c)
  }
}

pub fn display_optional(value: Option(String)) -> String {
  case value {
    None -> ""
    Some(v) -> v
  }
}

fn iso_to_country(code: String) -> String {
  case string.uppercase(string.trim(code)) {
    "FR" -> "France"
    "IT" -> "Italy"
    "ES" -> "Spain"
    "DE" -> "Germany"
    "PT" -> "Portugal"
    "AT" -> "Austria"
    "US" -> "United States"
    "AR" -> "Argentina"
    "CL" -> "Chile"
    "AU" -> "Australia"
    "NZ" -> "New Zealand"
    "ZA" -> "South Africa"
    "GR" -> "Greece"
    "HU" -> "Hungary"
    "GE" -> "Georgia"
    "LB" -> "Lebanon"
    "IL" -> "Israel"
    "HR" -> "Croatia"
    "SI" -> "Slovenia"
    "CH" -> "Switzerland"
    "RO" -> "Romania"
    "BG" -> "Bulgaria"
    "MD" -> "Moldova"
    "TR" -> "Turkey"
    "UY" -> "Uruguay"
    "BR" -> "Brazil"
    "MX" -> "Mexico"
    "CA" -> "Canada"
    "GB" -> "United Kingdom"
    "JP" -> "Japan"
    "CN" -> "China"
    "CZ" -> "Czech Republic"
    "UA" -> "Ukraine"
    other -> other
  }
}

pub fn format_date(iso: String) -> String {
  case string.split(iso, " ") {
    [date, ..] -> {
      case string.split(date, "-") {
        [y, m, d] -> d <> "." <> m <> "." <> y
        _ -> date
      }
    }
    _ -> iso
  }
}

pub fn date_node(iso: String) -> Node {
  html.span([attr.Attr("title", iso)], [
    html.Text(format_date(iso)),
  ])
}

// --- Wine type ---

pub fn wine_type_label(wt: db.WineType) -> String {
  case wt {
    db.Red -> "Red"
    db.White -> "White"
    db.Rose -> "Rosé"
    db.Orange -> "Orange"
    db.Sparkling -> "Sparkling"
    db.Dessert -> "Dessert"
    db.Sake -> "Sake"
    db.Other -> "Other"
  }
}

pub fn wine_type_badge(wine_type: db.WineType) -> Node {
  let #(classes, text) = case wine_type {
    db.Red -> #("bg-red-900 text-red-100 border-red-800", "Red")
    db.White -> #("bg-amber-50/60 text-amber-800 border-amber-200", "White")
    db.Rose -> #("bg-pink-50 text-pink-700 border-pink-200", "Rosé")
    db.Orange -> #("bg-orange-50 text-orange-700 border-orange-200", "Orange")
    db.Sparkling -> #(
      "bg-stone-50 text-stone-700 border-stone-200",
      "Sparkling",
    )
    db.Dessert -> #("bg-amber-100 text-amber-900 border-amber-300", "Dessert")
    db.Sake -> #("bg-stone-100 text-stone-700 border-stone-300", "Sake")
    db.Other -> #("bg-stone-50 text-stone-700 border-stone-200", "Other")
  }
  html.span(
    [
      attr.class(
        "inline-block px-2 py-0.5 rounded border text-xs font-medium "
        <> classes,
      ),
    ],
    [html.Text(text)],
  )
}

// --- Rating display ---

pub fn rating_display(rating: Option(Float)) -> Node {
  case rating {
    None -> html.Text("\u{2014}")
    Some(r) -> {
      html.span(
        [
          attr.class("font-medium tabular-nums"),
          attr.style("color: " <> red_green_scale(r)),
        ],
        [html.Text(float.to_string(r))],
      )
    }
  }
}

pub fn red_green_scale(rating: Float) -> String {
  let clamped = case rating <. 3.0 {
    True -> 3.0
    False ->
      case rating >. 5.0 {
        True -> 5.0
        False -> rating
      }
  }
  let t = { clamped -. 3.0 } /. 2.0
  let hue = float.round(t *. 120.0)
  "hsl(" <> int.to_string(hue) <> " 70% 35%)"
}

// --- Card helpers ---

pub fn card(content: List(Node)) -> Node {
  html.div(
    [attr.class("bg-white rounded-lg border border-stone-200 p-6")],
    content,
  )
}

// --- Table helpers ---

pub fn table(headers: List(String), rows: List(Node)) -> Node {
  html.div([attr.class("overflow-x-auto rounded-lg border border-stone-200")], [
    html.table([attr.class("w-full text-sm")], [
      html.thead([], [
        html.tr(
          [attr.class("bg-stone-50 border-b border-stone-200")],
          list.map(headers, th),
        ),
      ]),
      html.tbody([], rows),
    ]),
  ])
}

fn th(label: String) -> Node {
  html.th(
    [
      attr.class(
        "px-4 py-3 text-left font-medium text-stone-600 text-xs uppercase tracking-wider",
      ),
    ],
    [html.Text(label)],
  )
}

pub fn row_class(idx: Int) -> String {
  let bg = case idx % 2 {
    0 -> "bg-white"
    _ -> "bg-stone-50/30"
  }
  bg <> " border-b border-stone-100 hover:bg-amber-50/50 transition-colors"
}

pub fn clickable_row_class(idx: Int) -> String {
  row_class(idx) <> " cursor-pointer"
}

// --- Section helpers (home page cards) ---

pub fn section_header(title: String, link_href: String) -> Node {
  html.div([attr.class("flex items-baseline justify-between mb-3")], [
    html.h2([attr.class("text-lg font-medium text-stone-800")], [
      html.Text(title),
    ]),
    html.a(
      [
        attr.href(link_href),
        attr.class(
          "text-xs text-stone-400 hover:text-stone-600 transition-colors",
        ),
      ],
      [html.Text("View all \u{2192}")],
    ),
  ])
}

pub fn stat_card(label: String, value: String, href: String) -> Node {
  html.a(
    [
      attr.href(href),
      attr.class(
        "block p-6 bg-white rounded-lg border border-stone-200 hover:border-amber-300 transition-colors",
      ),
    ],
    [
      html.div([attr.class("text-2xl font-light text-stone-800")], [
        html.Text(value),
      ]),
      html.div([attr.class("text-sm text-stone-500 mt-1")], [
        html.Text(label),
      ]),
    ],
  )
}

pub fn page_header(title: String, subtitle: String) -> Node {
  html.div([attr.class("mb-6")], [
    html.h1([attr.class("text-3xl font-light text-stone-800 tracking-tight")], [
      html.Text(title),
    ]),
    html.p([attr.class("text-stone-500 mt-1")], [html.Text(subtitle)]),
  ])
}

pub fn detail_grid(items: List(#(String, String))) -> Node {
  html.div(
    [attr.class("grid grid-cols-2 sm:grid-cols-3 gap-4 mt-4")],
    list.filter_map(items, fn(item) {
      case item.1 {
        "" -> Error(Nil)
        val ->
          Ok(
            html.div([], [
              html.div(
                [attr.class("text-xs uppercase tracking-wider text-stone-400")],
                [html.Text(item.0)],
              ),
              html.div([attr.class("text-stone-700 mt-0.5")], [html.Text(val)]),
            ]),
          )
      }
    }),
  )
}

// --- Layout ---

pub fn page(title: String, user: User, content: List(Node)) -> Response {
  layout(title, [
    site_header(user, None),
    html.div([attr.class("max-w-6xl mx-auto px-4 pb-12")], content),
  ])
  |> render
}

pub fn page_with_subtitle(
  title: String,
  user: User,
  subtitle: String,
  content: List(Node),
) -> Response {
  layout(title, [
    site_header(user, Some(subtitle)),
    html.div([attr.class("max-w-6xl mx-auto px-4 pb-12")], content),
  ])
  |> render
}

pub fn layout(title: String, content: List(Node)) -> Node {
  html.Html([attr.lang("en"), attr.class("antialiased")], [
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
      html.link([
        attr.rel("icon"),
        attr.type_("image/svg+xml"),
        attr.href(favicon_data_uri()),
      ]),
      html.Element("script", [attr.src("/static/js/htmx.min.js")], []),
    ]),
    html.Body(
      [
        attr.class("bg-stone-100 text-stone-900 min-h-screen font-sans"),
        attr.Attr(
          "hx-on::after-swap",
          "if(event.detail.target.id==='overlay'){document.addEventListener('keydown',function h(e){if(e.key==='Escape'){var o=document.getElementById('overlay');o.innerHTML='';o.className='hidden';if(o.dataset.pushed){history.back();delete o.dataset.pushed}document.removeEventListener('keydown',h)}})}",
        ),
        attr.Attr(
          "hx-on::pushed-into-history",
          "var o=document.getElementById('overlay');if(o)o.dataset.pushed='1'",
        ),
      ],
      list.append(content, [
        html.div([attr.id("overlay"), attr.class("hidden")], []),
      ]),
    ),
  ])
}

pub fn render(node: Node) -> Response {
  node
  |> nakai.to_string
  |> wisp.html_response(200)
}

pub fn not_found(user: User) -> Response {
  layout("Not Found", [
    site_header(user, None),
    html.div([attr.class("max-w-6xl mx-auto px-4 pb-12 text-center pt-24")], [
      html.Element(
        "svg",
        [
          attr.class("mx-auto mb-6 text-stone-300"),
          attr.Attr("width", "120"),
          attr.Attr("height", "120"),
          attr.Attr("viewBox", "0 0 120 120"),
          attr.Attr("fill", "none"),
          attr.Attr("stroke", "currentColor"),
          attr.Attr("stroke-width", "2"),
          attr.Attr("stroke-linecap", "round"),
          attr.Attr("stroke-linejoin", "round"),
        ],
        [
          // Wine glass bowl (empty)
          html.Element(
            "path",
            [
              attr.Attr(
                "d",
                "M38 20 C38 20 35 50 42 62 C46 68 54 72 60 72 C66 72 74 68 78 62 C85 50 82 20 82 20",
              ),
            ],
            [],
          ),
          // Rim
          html.Element(
            "line",
            [
              attr.Attr("x1", "34"),
              attr.Attr("y1", "20"),
              attr.Attr("x2", "86"),
              attr.Attr("y2", "20"),
            ],
            [],
          ),
          // Stem
          html.Element(
            "line",
            [
              attr.Attr("x1", "60"),
              attr.Attr("y1", "72"),
              attr.Attr("x2", "60"),
              attr.Attr("y2", "95"),
            ],
            [],
          ),
          // Base
          html.Element(
            "line",
            [
              attr.Attr("x1", "44"),
              attr.Attr("y1", "95"),
              attr.Attr("x2", "76"),
              attr.Attr("y2", "95"),
            ],
            [],
          ),
        ],
      ),
      html.h1([attr.class("text-3xl font-semibold text-stone-800 mb-2")], [
        html.Text("This glass is empty"),
      ]),
      html.p([attr.class("text-stone-500 mb-8")], [
        html.Text("The page you're looking for has been uncorked and consumed."),
      ]),
      html.a(
        [
          attr.href("/"),
          attr.class(
            "inline-block px-5 py-2.5 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors",
          ),
        ],
        [html.Text("Back to your wines")],
      ),
    ]),
  ])
  |> nakai.to_string
  |> wisp.html_response(404)
}

pub fn overlay_wrapper(content: Node) -> Response {
  let close =
    "var o=document.getElementById('overlay');o.innerHTML='';o.className='hidden';if(o.dataset.pushed){history.back();delete o.dataset.pushed}"
  html.div(
    [
      attr.id("overlay"),
      attr.class(
        "fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm",
      ),
      attr.Attr("onclick", "if(event.target===this){" <> close <> "}"),
    ],
    [
      html.div([attr.class("relative w-full max-w-lg mx-4")], [
        html.button(
          [
            attr.class(
              "absolute -top-3 -right-3 w-8 h-8 rounded-full bg-white border border-stone-200 text-stone-500 hover:text-stone-800 flex items-center justify-center shadow-sm",
            ),
            attr.Attr("onclick", close),
          ],
          [html.Text("\u{00d7}")],
        ),
        content,
      ]),
    ],
  )
  |> nakai.to_inline_string
  |> wisp.html_response(200)
}

fn site_header(user: User, subtitle: Option(String)) -> Node {
  html.header(
    [
      attr.class(
        "border-b border-stone-200 bg-white/80 backdrop-blur-sm sticky top-0 z-10 mb-8",
      ),
    ],
    [
      html.div(
        [
          attr.class(
            "max-w-6xl mx-auto px-4 py-4 flex items-center justify-between",
          ),
        ],
        [
          html.a([attr.href("/"), attr.class("flex items-center gap-3 group")], [
            html.UnsafeInlineHtml(logo_svg()),
            html.div([], [
              html.span(
                [
                  attr.class(
                    "text-xl font-light tracking-tight text-stone-800 group-hover:text-rose-800 transition-colors",
                  ),
                ],
                [html.Text("Rebstock")],
              ),
              case subtitle {
                None -> html.Nothing
                Some(s) ->
                  html.div([attr.class("text-xs text-stone-400 -mt-0.5")], [
                    html.Text(s),
                  ])
              },
            ]),
          ]),
          html.div([attr.class("flex items-center gap-6")], [
            html.nav([attr.class("flex gap-6 text-sm")], [
              nav_link("All Wines", "/wines"),
              nav_link("All Wineries", "/wineries"),
              html.span([attr.class("text-stone-300")], [html.Text("//")]),
              html.span([attr.class("text-sm text-stone-400")], [
                html.Text("~" <> user.username <> ":"),
              ]),
              nav_link("Cellar", "/~" <> user.username <> "/cellar"),
              nav_link("Wishlist", "/~" <> user.username <> "/wishlist"),
              nav_link("Ratings", "/~" <> user.username <> "/ratings"),
            ]),
          ]),
        ],
      ),
    ],
  )
}

fn logo_svg() -> String {
  "<svg width=\"32\" height=\"32\" viewBox=\"0 0 32 32\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">
    <circle cx=\"10\" cy=\"8\" r=\"4\" fill=\"#78180e\" opacity=\"0.8\"/>
    <circle cx=\"18\" cy=\"6\" r=\"3.5\" fill=\"#78180e\" opacity=\"0.65\"/>
    <circle cx=\"14\" cy=\"13\" r=\"3.5\" fill=\"#78180e\" opacity=\"0.75\"/>
    <circle cx=\"22\" cy=\"11\" r=\"3\" fill=\"#78180e\" opacity=\"0.5\"/>
    <path d=\"M14 18 C14 18 13 24 16 28\" stroke=\"#78716c\" stroke-width=\"1.5\" stroke-linecap=\"round\"/>
    <path d=\"M16 28 C16 28 12 29 10 28\" stroke=\"#78716c\" stroke-width=\"1\" stroke-linecap=\"round\" opacity=\"0.5\"/>
    <path d=\"M16 28 C16 28 20 29 22 28\" stroke=\"#78716c\" stroke-width=\"1\" stroke-linecap=\"round\" opacity=\"0.5\"/>
    <path d=\"M14 20 C11 19 8 20 7 18\" stroke=\"#78716c\" stroke-width=\"1\" stroke-linecap=\"round\" opacity=\"0.4\"/>
    <path d=\"M15 22 C18 21 20 22 22 20\" stroke=\"#78716c\" stroke-width=\"1\" stroke-linecap=\"round\" opacity=\"0.4\"/>
  </svg>"
}

fn favicon_data_uri() -> String {
  "data:image/svg+xml,%3Csvg width='32' height='32' viewBox='0 0 32 32' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Ccircle cx='10' cy='8' r='4' fill='%2378180e' opacity='0.8'/%3E%3Ccircle cx='18' cy='6' r='3.5' fill='%2378180e' opacity='0.65'/%3E%3Ccircle cx='14' cy='13' r='3.5' fill='%2378180e' opacity='0.75'/%3E%3Ccircle cx='22' cy='11' r='3' fill='%2378180e' opacity='0.5'/%3E%3Cpath d='M14 18 C14 18 13 24 16 28' stroke='%2378716c' stroke-width='1.5' stroke-linecap='round'/%3E%3Cpath d='M16 28 C16 28 12 29 10 28' stroke='%2378716c' stroke-width='1' stroke-linecap='round' opacity='0.5'/%3E%3Cpath d='M16 28 C16 28 20 29 22 28' stroke='%2378716c' stroke-width='1' stroke-linecap='round' opacity='0.5'/%3E%3Cpath d='M14 20 C11 19 8 20 7 18' stroke='%2378716c' stroke-width='1' stroke-linecap='round' opacity='0.4'/%3E%3Cpath d='M15 22 C18 21 20 22 22 20' stroke='%2378716c' stroke-width='1' stroke-linecap='round' opacity='0.4'/%3E%3C/svg%3E"
}
