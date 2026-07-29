import gleam/float
import gleam/http
import gleam/http/request
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import nakai
import nakai/attr
import nakai/html.{type Node}
import sqlight
import wisp.{type Request, type Response}

import rebstock/auth.{type User}
import rebstock/db

// --- URL helpers ---

pub fn base_url(req: Request) -> String {
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

pub const countries = [
  #("AF", "Afghanistan"),
  #("AL", "Albania"),
  #("DZ", "Algeria"),
  #("AS", "American Samoa"),
  #("AD", "Andorra"),
  #("AO", "Angola"),
  #("AI", "Anguilla"),
  #("AG", "Antigua and Barbuda"),
  #("AR", "Argentina"),
  #("AM", "Armenia"),
  #("AW", "Aruba"),
  #("AU", "Australia"),
  #("AT", "Austria"),
  #("AZ", "Azerbaijan"),
  #("BS", "Bahamas"),
  #("BH", "Bahrain"),
  #("BD", "Bangladesh"),
  #("BB", "Barbados"),
  #("BY", "Belarus"),
  #("BE", "Belgium"),
  #("BZ", "Belize"),
  #("BJ", "Benin"),
  #("BM", "Bermuda"),
  #("BT", "Bhutan"),
  #("BO", "Bolivia"),
  #("BA", "Bosnia and Herzegovina"),
  #("BW", "Botswana"),
  #("BR", "Brazil"),
  #("BN", "Brunei"),
  #("BG", "Bulgaria"),
  #("BF", "Burkina Faso"),
  #("BI", "Burundi"),
  #("KH", "Cambodia"),
  #("CM", "Cameroon"),
  #("CA", "Canada"),
  #("CV", "Cape Verde"),
  #("KY", "Cayman Islands"),
  #("CF", "Central African Republic"),
  #("TD", "Chad"),
  #("CL", "Chile"),
  #("CN", "China"),
  #("CO", "Colombia"),
  #("KM", "Comoros"),
  #("CR", "Costa Rica"),
  #("HR", "Croatia"),
  #("CU", "Cuba"),
  #("CW", "Cura\u{00e7}ao"),
  #("CY", "Cyprus"),
  #("CZ", "Czechia"),
  #("CD", "DR Congo"),
  #("DK", "Denmark"),
  #("DJ", "Djibouti"),
  #("DM", "Dominica"),
  #("DO", "Dominican Republic"),
  #("EC", "Ecuador"),
  #("EG", "Egypt"),
  #("SV", "El Salvador"),
  #("GQ", "Equatorial Guinea"),
  #("ER", "Eritrea"),
  #("EE", "Estonia"),
  #("SZ", "Eswatini"),
  #("ET", "Ethiopia"),
  #("FJ", "Fiji"),
  #("FI", "Finland"),
  #("FR", "France"),
  #("GA", "Gabon"),
  #("GM", "Gambia"),
  #("GE", "Georgia"),
  #("DE", "Germany"),
  #("GH", "Ghana"),
  #("GR", "Greece"),
  #("GD", "Grenada"),
  #("GT", "Guatemala"),
  #("GN", "Guinea"),
  #("GW", "Guinea-Bissau"),
  #("GY", "Guyana"),
  #("HT", "Haiti"),
  #("HN", "Honduras"),
  #("HK", "Hong Kong"),
  #("HU", "Hungary"),
  #("IS", "Iceland"),
  #("IN", "India"),
  #("ID", "Indonesia"),
  #("IR", "Iran"),
  #("IQ", "Iraq"),
  #("IE", "Ireland"),
  #("IL", "Israel"),
  #("IT", "Italy"),
  #("CI", "Ivory Coast"),
  #("JM", "Jamaica"),
  #("JP", "Japan"),
  #("JO", "Jordan"),
  #("KZ", "Kazakhstan"),
  #("KE", "Kenya"),
  #("KI", "Kiribati"),
  #("XK", "Kosovo"),
  #("KW", "Kuwait"),
  #("KG", "Kyrgyzstan"),
  #("LA", "Laos"),
  #("LV", "Latvia"),
  #("LB", "Lebanon"),
  #("LS", "Lesotho"),
  #("LR", "Liberia"),
  #("LY", "Libya"),
  #("LI", "Liechtenstein"),
  #("LT", "Lithuania"),
  #("LU", "Luxembourg"),
  #("MO", "Macau"),
  #("MG", "Madagascar"),
  #("MW", "Malawi"),
  #("MY", "Malaysia"),
  #("MV", "Maldives"),
  #("ML", "Mali"),
  #("MT", "Malta"),
  #("MH", "Marshall Islands"),
  #("MR", "Mauritania"),
  #("MU", "Mauritius"),
  #("MX", "Mexico"),
  #("FM", "Micronesia"),
  #("MD", "Moldova"),
  #("MC", "Monaco"),
  #("MN", "Mongolia"),
  #("ME", "Montenegro"),
  #("MA", "Morocco"),
  #("MZ", "Mozambique"),
  #("MM", "Myanmar"),
  #("NA", "Namibia"),
  #("NR", "Nauru"),
  #("NP", "Nepal"),
  #("NL", "Netherlands"),
  #("NZ", "New Zealand"),
  #("NI", "Nicaragua"),
  #("NE", "Niger"),
  #("NG", "Nigeria"),
  #("KP", "North Korea"),
  #("MK", "North Macedonia"),
  #("NO", "Norway"),
  #("OM", "Oman"),
  #("PK", "Pakistan"),
  #("PW", "Palau"),
  #("PS", "Palestine"),
  #("PA", "Panama"),
  #("PG", "Papua New Guinea"),
  #("PY", "Paraguay"),
  #("PE", "Peru"),
  #("PH", "Philippines"),
  #("PL", "Poland"),
  #("PT", "Portugal"),
  #("PR", "Puerto Rico"),
  #("QA", "Qatar"),
  #("CG", "Republic of the Congo"),
  #("RO", "Romania"),
  #("RU", "Russia"),
  #("RW", "Rwanda"),
  #("KN", "Saint Kitts and Nevis"),
  #("LC", "Saint Lucia"),
  #("VC", "Saint Vincent and the Grenadines"),
  #("WS", "Samoa"),
  #("SM", "San Marino"),
  #("SA", "Saudi Arabia"),
  #("SN", "Senegal"),
  #("RS", "Serbia"),
  #("SC", "Seychelles"),
  #("SL", "Sierra Leone"),
  #("SG", "Singapore"),
  #("SK", "Slovakia"),
  #("SI", "Slovenia"),
  #("SB", "Solomon Islands"),
  #("SO", "Somalia"),
  #("ZA", "South Africa"),
  #("KR", "South Korea"),
  #("SS", "South Sudan"),
  #("ES", "Spain"),
  #("LK", "Sri Lanka"),
  #("SD", "Sudan"),
  #("SR", "Suriname"),
  #("SE", "Sweden"),
  #("CH", "Switzerland"),
  #("SY", "Syria"),
  #("TW", "Taiwan"),
  #("TJ", "Tajikistan"),
  #("TZ", "Tanzania"),
  #("TH", "Thailand"),
  #("TL", "Timor-Leste"),
  #("TG", "Togo"),
  #("TO", "Tonga"),
  #("TT", "Trinidad and Tobago"),
  #("TN", "Tunisia"),
  #("TR", "Turkey"),
  #("TM", "Turkmenistan"),
  #("TV", "Tuvalu"),
  #("UG", "Uganda"),
  #("UA", "Ukraine"),
  #("AE", "United Arab Emirates"),
  #("GB", "United Kingdom"),
  #("US", "United States"),
  #("UY", "Uruguay"),
  #("UZ", "Uzbekistan"),
  #("VU", "Vanuatu"),
  #("VA", "Vatican City"),
  #("VE", "Venezuela"),
  #("VN", "Vietnam"),
  #("YE", "Yemen"),
  #("ZM", "Zambia"),
  #("ZW", "Zimbabwe"),
]

fn iso_to_country(code: String) -> String {
  let upper = string.uppercase(string.trim(code))
  case list.key_find(countries, upper) {
    Ok(name) -> name
    _ -> upper
  }
}

// --- Form helpers ---

pub const input_class = "w-full px-3 py-2 border border-stone-300 rounded-lg text-stone-900 focus:outline-none focus:ring-2 focus:ring-rose-800/20 focus:border-rose-800"

pub fn form_field(label: String, required: Bool, children: List(Node)) -> Node {
  html.div([], [
    html.Element(
      "label",
      [attr.class("block text-sm font-medium text-stone-700 mb-1")],
      [
        html.Text(label),
        case required {
          False -> html.Nothing
          True ->
            html.span([attr.class("text-rose-600 ml-0.5")], [html.Text("*")])
        },
      ],
    ),
    ..children
  ])
}

pub fn country_input(
  name: String,
  selected: Option(String),
  class: String,
) -> Node {
  let sel = case selected {
    Some(c) -> string.uppercase(string.trim(c))
    None -> ""
  }
  html.Element("select", [attr.name(name), attr.class(class)], [
    html.Element("option", [attr.value("")], [html.Text("\u{2014}")]),
    ..list.map(countries, fn(entry) {
      let #(code, label) = entry
      let attrs = [attr.value(code)]
      let attrs = case code == sel {
        True -> [attr.Attr("selected", ""), ..attrs]
        False -> attrs
      }
      html.Element("option", attrs, [html.Text(label)])
    })
  ])
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
          attr.style("color: " <> rating_ink(r)),
        ],
        [html.Text(float.to_string(r))],
      )
    }
  }
}

/// Two rating distributions over shared buckets, growing outward from a
/// centred rating axis. Colour already encodes the rating, so the two sides
/// are told apart by direction and weight rather than hue: the left side is
/// solid, the right ghosted. Both share one scale — normalising each side to
/// its own maximum would flatter the comparison and lie about the shape.
pub fn rating_butterfly(
  title: String,
  unit: String,
  left_label: String,
  right_label: String,
  rows: List(db.BucketPair),
) -> Node {
  case rows {
    [] -> html.Nothing
    _ -> {
      let max =
        list.fold(rows, 0, fn(acc, row) { int.max(acc, int.max(row.1, row.2)) })
      let left_total = list.fold(rows, 0, fn(acc, row) { acc + row.1 })

      html.div([attr.class("bg-white rounded-lg border border-stone-200 p-4")], [
        html.div([attr.class("text-xs text-stone-500")], [
          html.Text(title),
          html.span([attr.class("text-stone-400 ml-1")], [
            html.Text("(" <> int.to_string(left_total) <> " " <> unit <> ")"),
          ]),
        ]),
        butterfly_legend(left_label, right_label),
        html.div(
          [attr.class("space-y-1.5")],
          list.map(rows, fn(row) { butterfly_row(row, max) }),
        ),
      ])
    }
  }
}

fn butterfly_legend(left_label: String, right_label: String) -> Node {
  let swatch = fn(class) {
    html.span([attr.class("w-3 h-2.5 rounded-sm bg-stone-400 " <> class)], [])
  }
  html.div([attr.class("flex gap-4 text-[11px] text-stone-500 mt-2 mb-3")], [
    html.span([attr.class("flex items-center gap-1.5")], [
      swatch(""),
      html.Text(left_label),
    ]),
    html.span([attr.class("flex items-center gap-1.5")], [
      swatch("opacity-40"),
      html.Text(right_label),
    ]),
  ])
}

fn butterfly_row(row: db.BucketPair, max: Int) -> Node {
  let #(bucket, left, right) = row
  let #(label, label_class, fill) = case bucket {
    Some(rating) -> #(
      float.to_string(rating),
      "text-stone-800",
      rating_fill(rating),
    )
    None -> #("\u{2014}", "text-stone-400", stone_300)
  }
  let label_style = case bucket {
    Some(rating) -> attr.style("color: " <> rating_ink(rating))
    None -> attr.class("")
  }
  let separated = case bucket {
    None -> "border-t border-stone-100 pt-1.5 mt-1.5"
    Some(_) -> ""
  }

  html.div([attr.class("flex items-center gap-1.5 " <> separated)], [
    butterfly_count(left, "text-right"),
    butterfly_track(left, max, fill, "justify-end", ""),
    html.span(
      [
        attr.class(
          "text-xs font-medium tabular-nums w-7 text-center shrink-0 "
          <> label_class,
        ),
        label_style,
      ],
      [html.Text(label)],
    ),
    butterfly_track(right, max, fill, "", "opacity-40"),
    butterfly_count(right, "text-left"),
  ])
}

/// Bottles and wines nobody has scored get the one neutral fill on the chart
const stone_300 = "#d6d3d1"

fn butterfly_track(
  count: Int,
  max: Int,
  fill: String,
  align: String,
  weight: String,
) -> Node {
  let pct = case max {
    0 -> 0
    _ -> { count * 100 } / max
  }
  let width = case count {
    0 -> "0"
    _ -> int.to_string(int.max(pct, 2)) <> "%"
  }
  html.div([attr.class("flex-1 h-4 bg-stone-50 rounded-sm flex " <> align)], [
    html.div(
      [
        attr.class("h-full rounded-sm " <> weight),
        attr.style("width: " <> width <> "; background-color: " <> fill <> ";"),
      ],
      [],
    ),
  ])
}

fn butterfly_count(count: Int, align: String) -> Node {
  html.span(
    [
      attr.class(
        "text-[11px] text-stone-400 tabular-nums w-7 shrink-0 " <> align,
      ),
    ],
    [
      html.Text(case count {
        0 -> ""
        _ -> int.to_string(count)
      }),
    ],
  )
}

/// Stops along the rating axis as `#(rating, lightness, chroma, hue)` in OKLCH.
///
/// Ratings crowd into 3.0-5.0 and anything below 3.5 is a wine you would not
/// buy again, so the warm half of the sweep is spent under 4.0 and everything
/// above it reads green. The jump from 4.0 to 4.5 vaults the 90-120 degree
/// band, where sRGB holds no bright colour at these lightnesses and yellow
/// collapses into khaki.
const rating_stops = [
  #(3.0, 0.8, 0.14, 25.0),
  #(3.5, 0.81, 0.15, 50.0),
  #(4.0, 0.85, 0.16, 120.0),
  #(4.5, 0.8, 0.15, 145.0),
  #(5.0, 0.72, 0.17, 155.0),
]

/// Bar and badge fills, pale enough to sit under dark text
pub fn rating_fill(rating: Float) -> String {
  let #(lightness, chroma, hue) = rating_stop(rating)
  oklch(lightness, chroma, hue)
}

/// The same hue held dark enough to read as text
pub fn rating_ink(rating: Float) -> String {
  let #(_, _, hue) = rating_stop(rating)
  oklch(0.48, 0.13, hue)
}

fn rating_stop(rating: Float) -> #(Float, Float, Float) {
  interpolate_stops(rating_stops, float.clamp(rating, min: 3.0, max: 5.0))
}

fn interpolate_stops(
  stops: List(#(Float, Float, Float, Float)),
  rating: Float,
) -> #(Float, Float, Float) {
  case stops {
    [from, to, ..rest] -> {
      let #(low, lightness, chroma, hue) = from
      let #(high, next_lightness, next_chroma, next_hue) = to
      case rating <=. high {
        True -> {
          let t = { rating -. low } /. { high -. low }
          #(
            lerp(lightness, next_lightness, t),
            lerp(chroma, next_chroma, t),
            lerp(hue, next_hue, t),
          )
        }
        False -> interpolate_stops([to, ..rest], rating)
      }
    }
    _ -> #(0.72, 0.17, 155.0)
  }
}

fn lerp(from: Float, to: Float, t: Float) -> Float {
  from +. { to -. from } *. t
}

fn oklch(lightness: Float, chroma: Float, hue: Float) -> String {
  "oklch("
  <> decimals(lightness, 3)
  <> " "
  <> decimals(chroma, 3)
  <> " "
  <> decimals(hue, 1)
  <> ")"
}

fn decimals(value: Float, places: Int) -> String {
  float.to_string(float.to_precision(value, places))
}

// --- Image helpers ---

pub fn wine_image(wine_id: String, class: String) -> Node {
  html.div([attr.class(class <> " relative overflow-hidden")], [
    html.img([
      attr.src("/images/bottles/" <> wine_id <> ".jpg"),
      attr.Attr("alt", ""),
      attr.class("w-full h-full object-contain"),
      attr.Attr(
        "onerror",
        "this.style.display='none';this.nextElementSibling.style.display='flex'",
      ),
    ]),
    html.div(
      [
        attr.class(
          "hidden items-center justify-center w-full h-full bg-stone-100 border border-stone-200 rounded-lg p-1",
        ),
      ],
      [
        html.UnsafeInlineHtml(
          "<svg class=\"w-full h-full\" viewBox=\"0 0 80 220\" fill=\"#2d5a27\" xmlns=\"http://www.w3.org/2000/svg\">"
          <> "<path d=\"M30,0 L30,4 L26,4 L26,8 L30,8 L30,38 C30,52 10,62 10,80 L10,206 C10,214 16,220 24,220 L56,220 C64,220 70,214 70,206 L70,80 C70,62 50,52 50,38 L50,8 L54,8 L54,4 L50,4 L50,0 Z\"/>"
          <> "</svg>",
        ),
      ],
    ),
  ])
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

/// Client-side text filter input for the table inside `#target_id`.
/// Hides rows whose text does not contain the query.
pub fn table_filter(target_id: String, placeholder: String) -> Node {
  html.Element(
    "input",
    [
      attr.type_("search"),
      attr.Attr("placeholder", placeholder),
      attr.class(
        "w-full sm:w-72 border border-stone-300 rounded-lg px-3 py-2 text-sm mb-4",
      ),
      attr.Attr(
        "oninput",
        "var q=this.value.toLowerCase();var i=0;document.querySelectorAll('#"
          <> target_id
          <> " tbody tr').forEach(function(r){var show=r.textContent.toLowerCase().indexOf(q)!==-1;r.style.display=show?'':'none';if(show){r.classList.remove('bg-white','bg-stone-50/30');r.classList.add(i%2?'bg-stone-50/30':'bg-white');i++}})",
      ),
    ],
    [],
  )
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

/// Navigate on row click; ctrl/cmd/middle click opens a new tab like
/// a regular link would.
pub fn row_onclick(url: String) -> attr.Attr {
  attr.Attr(
    "onclick",
    "if(event.ctrlKey||event.metaKey){window.open('"
      <> url
      <> "','_blank')}else{window.location='"
      <> url
      <> "'}",
  )
}

pub fn row_onauxclick(url: String) -> attr.Attr {
  attr.Attr(
    "onauxclick",
    "if(event.button===1){window.open('" <> url <> "','_blank')}",
  )
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

pub fn page(
  title: String,
  user: User,
  conn: sqlight.Connection,
  content: List(Node),
) -> Response {
  layout(title, [
    site_header(user, conn),
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
        attr.href(
          "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🍇</text></svg>",
        ),
      ]),
      html.Element("script", [attr.src("/static/js/htmx.min.js")], []),
      html.Element("script", [], [
        html.Text(
          "document.addEventListener('click',function(e){document.querySelectorAll('details[open]').forEach(function(d){if(!d.contains(e.target))d.removeAttribute('open')})})",
        ),
      ]),
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

pub fn render_fragment(node: Node) -> Response {
  node
  |> nakai.to_inline_string
  |> wisp.html_response(200)
}

pub fn not_found(user: User, conn: sqlight.Connection) -> Response {
  layout("Not Found", [
    site_header(user, conn),
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

fn site_header(user: User, conn: sqlight.Connection) -> Node {
  let subtitle = case db.count_wines(conn) {
    0 -> None
    _ -> {
      let wines = int.to_string(db.count_wines(conn))
      let wineries = int.to_string(db.count_wineries(conn))
      let num_users = db.count_users(conn)
      Some(
        wines
        <> " wines from "
        <> wineries
        <> " wineries"
        <> case num_users > 1 {
          True -> ", " <> int.to_string(num_users) <> " users"
          False -> ""
        },
      )
    }
  }
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
          html.a([attr.href("/"), attr.class("flex items-center gap-2 group")], [
            html.span([attr.class("text-2xl")], [html.Text("\u{1f347}")]),
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
          html.nav([attr.class("flex items-center gap-4 text-sm")], [
            nav_link("Wines", "/wines"),
            nav_link("Wineries", "/wineries"),
            html.span([attr.class("text-stone-300")], [
              html.Text("\u{2502}"),
            ]),
            nav_link("Cellar", "/~" <> user.username <> "/cellar"),
            nav_link("Wishlist", "/~" <> user.username <> "/wishlist"),
            nav_link("Ratings", "/~" <> user.username <> "/ratings"),
            nav_link("Lists", "/~" <> user.username <> "/lists"),
            html.span([attr.class("text-stone-300")], [
              html.Text("\u{2502}"),
            ]),
            html.Element("details", [attr.class("relative user-menu")], [
              html.Element(
                "summary",
                [
                  attr.class(
                    "cursor-pointer text-stone-500 hover:text-rose-800 transition-colors list-none",
                  ),
                ],
                [html.Text("~" <> user.username)],
              ),
              html.div(
                [
                  attr.class(
                    "absolute right-0 top-8 bg-white border border-stone-200 rounded-lg shadow-lg py-1 min-w-[140px] z-20",
                  ),
                ],
                [
                  html.a(
                    [
                      attr.href("/~" <> user.username <> "/import"),
                      attr.class(
                        "block px-4 py-2 text-sm text-stone-600 hover:bg-amber-50 hover:text-stone-800 transition-colors",
                      ),
                    ],
                    [html.Text("Import")],
                  ),
                ],
              ),
            ]),
          ]),
        ],
      ),
    ],
  )
}
