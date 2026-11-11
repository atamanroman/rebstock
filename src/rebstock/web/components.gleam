import gleam/float
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
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

/// Standard entity link
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
      attr.class("nav-link"),
      attr.Attr("hx-boost", "true"),
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

pub fn profile_url(username: String) -> String {
  "/~" <> uri.percent_encode(username)
}

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

pub const input_class = "form-control"

pub fn form_field(
  id: String,
  label: String,
  required: Bool,
  children: List(Node),
) -> Node {
  html.div([], [
    html.Element("label", [attr.Attr("for", id), attr.class("field-label")], [
      html.Text(label),
      case required {
        False -> html.Nothing
        True ->
          html.span(
            [
              attr.class("text-rose-600 ml-0.5"),
              attr.Attr("aria-hidden", "true"),
            ],
            [html.Text("*")],
          )
      },
    ]),
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
  html.Element("select", [attr.id(name), attr.name(name), attr.class(class)], [
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
  case string.split(string.replace(iso, "T", " "), " ") {
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
  let date =
    iso
    |> string.replace("T", " ")
    |> string.split(" ")
    |> list.first
    |> result.unwrap(iso)
  html.time([attr.Attr("datetime", date)], [html.Text(format_date(iso))])
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
  let class = case wine_type {
    db.Red -> "wine-type wine-type-red"
    db.White -> "wine-type wine-type-white"
    db.Rose -> "wine-type wine-type-rose"
    db.Orange -> "wine-type wine-type-orange"
    db.Sparkling -> "wine-type wine-type-sparkling"
    db.Dessert -> "wine-type wine-type-dessert"
    db.Sake -> "wine-type wine-type-sake"
    db.Other -> "wine-type"
  }
  html.span([attr.class(class)], [html.Text(wine_type_label(wine_type))])
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

// --- Rating filters ---

/// Which half of a filter a parameter or a chart wing speaks for
pub type Rater {
  Mine
  Vivino
}

fn rater_prefix(rater: Rater) -> String {
  case rater {
    Mine -> "my"
    Vivino -> "vivino"
  }
}

/// `?my_min=4&my_max=5&vivino_min=3`, with `?my=none` for wines that side
/// never scored. Both halves narrow the list together.
pub fn rating_filter(req: Request) -> db.RatingFilter {
  let query = wisp.get_query(req)
  db.RatingFilter(
    mine: score_filter(query, Mine),
    vivino: score_filter(query, Vivino),
  )
}

fn score_filter(
  query: List(#(String, String)),
  rater: Rater,
) -> db.ScoreFilter {
  let prefix = rater_prefix(rater)
  let bound = fn(suffix) {
    case list.key_find(query, prefix <> suffix) {
      Ok(value) -> db.parse_optional_float(value)
      Error(_) -> None
    }
  }
  case list.key_find(query, prefix), bound("_min"), bound("_max") {
    Ok("none"), _, _ -> db.NoScore
    _, None, None -> db.AnyScore
    _, min, max -> db.ScoreRange(min, max)
  }
}

/// The query string that reproduces a filter, so a chip can drop its own half
/// and leave the rest standing
pub fn filter_url(base: String, filter: db.RatingFilter) -> String {
  case
    list.append(
      score_params(filter.mine, Mine),
      score_params(filter.vivino, Vivino),
    )
  {
    [] -> base
    params -> base <> "?" <> string.join(params, "&")
  }
}

fn score_params(filter: db.ScoreFilter, rater: Rater) -> List(String) {
  let prefix = rater_prefix(rater)
  case filter {
    db.AnyScore -> []
    db.NoScore -> [prefix <> "=none"]
    db.ScoreRange(min, max) ->
      [#("_min", min), #("_max", max)]
      |> list.filter_map(fn(bound) {
        case bound.1 {
          Some(value) -> Ok(prefix <> bound.0 <> "=" <> number(value))
          None -> Error(Nil)
        }
      })
  }
}

/// A bar holds every score that rounds to it, so its link asks for that
/// window on the raw score. Both ends are inclusive, which at the edge two
/// bars share (4.75 is drawn on the 5.0 bar) shows a row on both rather than
/// losing it from either.
pub fn bar_url(base: String, rater: Rater, bucket: Option(Float)) -> String {
  let score = case bucket {
    None -> db.NoScore
    Some(rating) -> db.ScoreRange(Some(rating -. 0.25), Some(rating +. 0.25))
  }
  let filter = case rater {
    Mine -> db.RatingFilter(..db.unfiltered, mine: score)
    Vivino -> db.RatingFilter(..db.unfiltered, vivino: score)
  }
  filter_url(base, filter)
}

/// Ratings are written the way people say them: 4, not 4.0
fn number(value: Float) -> String {
  let text = float.to_string(value)
  case string.ends_with(text, ".0") {
    True -> string.drop_end(text, 2)
    False -> text
  }
}

/// Names each half of the filter the list was narrowed by; clicking one drops
/// that half and keeps the other
pub fn filter_chips(filter: db.RatingFilter, base: String) -> Node {
  let chips =
    [
      #(filter.mine, Mine, db.RatingFilter(..filter, mine: db.AnyScore)),
      #(filter.vivino, Vivino, db.RatingFilter(..filter, vivino: db.AnyScore)),
    ]
    |> list.filter_map(fn(chip) {
      let #(score, rater, without) = chip
      case score {
        db.AnyScore -> Error(Nil)
        _ ->
          Ok(filter_chip(chip_label(score, rater), filter_url(base, without)))
      }
    })

  case chips {
    [] -> html.Nothing
    _ -> html.div([attr.class("flex flex-wrap gap-2 mb-4")], chips)
  }
}

fn chip_label(score: db.ScoreFilter, rater: Rater) -> String {
  let who = case rater {
    Mine -> "Rated"
    Vivino -> "Vivino"
  }
  case score {
    db.AnyScore -> who
    db.NoScore ->
      case rater {
        Mine -> "Unrated"
        Vivino -> "No Vivino score"
      }
    db.ScoreRange(Some(min), Some(max)) ->
      case min == max {
        True -> who <> " " <> number(min)
        False -> who <> " " <> number(min) <> "\u{2013}" <> number(max)
      }
    db.ScoreRange(Some(min), None) -> who <> " \u{2265}" <> number(min)
    db.ScoreRange(None, Some(max)) -> who <> " \u{2264}" <> number(max)
    db.ScoreRange(None, None) -> who
  }
}

fn filter_chip(label: String, clear_href: String) -> Node {
  html.a(
    [
      attr.href(clear_href),
      attr.class(
        "button inline-flex items-center gap-2 px-3 py-1 rounded-full text-sm bg-stone-100 text-stone-600 hover:bg-stone-200 transition-colors",
      ),
    ],
    [
      html.Text(label),
      html.span([attr.class("text-stone-500")], [html.Text("\u{00d7}")]),
    ],
  )
}

/// Two rating distributions over shared buckets, growing outward from a
/// centred rating axis. Colour already encodes the rating, so the two sides
/// are told apart by direction and weight rather than hue: the left side is
/// solid, the right ghosted. Both share one scale — normalising each side to
/// its own maximum would flatter the comparison and lie about the shape.
pub fn rating_butterfly(
  title: String,
  unit: String,
  left: ButterflySide,
  right: ButterflySide,
  rows: List(db.BucketPair),
) -> Node {
  case rows {
    [] -> html.Nothing
    _ -> {
      let max =
        list.fold(rows, 0, fn(acc, row) { int.max(acc, int.max(row.1, row.2)) })
      let left_total = list.fold(rows, 0, fn(acc, row) { acc + row.1 })

      html.figure([attr.class("rating-chart")], [
        html.figcaption([attr.class("text-xs text-stone-500")], [
          html.Text(title),
          html.span([attr.class("text-stone-500 ml-1")], [
            html.Text("(" <> int.to_string(left_total) <> " " <> unit <> ")"),
          ]),
        ]),
        butterfly_legend(left.label, right.label),
        html.div(
          [attr.class("space-y-1.5")],
          list.map(rows, fn(row) { butterfly_row(row, max, unit, left, right) }),
        ),
        butterfly_table(title, unit, left, right, rows),
      ])
    }
  }
}

fn butterfly_table(
  title: String,
  unit: String,
  left: ButterflySide,
  right: ButterflySide,
  rows: List(db.BucketPair),
) -> Node {
  html.table([attr.class("sr-only")], [
    html.caption([], [html.Text(title <> " — " <> unit)]),
    html.thead([], [
      html.tr(
        [],
        list.map(["Rating", left.label, right.label], fn(label) {
          html.th([attr.Attr("scope", "col")], [html.Text(label)])
        }),
      ),
    ]),
    html.tbody(
      [],
      list.map(rows, fn(row) {
        let #(bucket, left_count, right_count) = row
        let label = case bucket {
          Some(rating) -> float.to_string(rating)
          None -> "Unrated"
        }
        html.tr([], [
          html.th([attr.Attr("scope", "row")], [html.Text(label)]),
          html.td([], [html.Text(int.to_string(left_count))]),
          html.td([], [html.Text(int.to_string(right_count))]),
        ])
      }),
    ),
  ])
}

/// One wing of the butterfly: how it is named, and the filtered list a bar
/// of it leads to
pub type ButterflySide {
  ButterflySide(label: String, href: fn(Option(Float)) -> String)
}

fn butterfly_legend(left_label: String, right_label: String) -> Node {
  let swatch = fn(class) {
    html.span(
      [
        attr.class("w-3 h-2.5 rounded-sm bg-stone-400 " <> class),
        attr.Attr("aria-hidden", "true"),
      ],
      [],
    )
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

fn butterfly_row(
  row: db.BucketPair,
  max: Int,
  unit: String,
  left_side: ButterflySide,
  right_side: ButterflySide,
) -> Node {
  let #(bucket, left, right) = row
  let #(label, label_class, fill) = case bucket {
    Some(rating) -> #(
      float.to_string(rating),
      "text-stone-800",
      rating_fill(rating),
    )
    None -> #("\u{2014}", "text-stone-500", stone_300)
  }
  let label_style = case bucket {
    Some(rating) -> attr.style("color: " <> rating_ink(rating))
    None -> attr.class("")
  }
  let separated = case bucket {
    None -> "border-t border-stone-100 pt-1.5 mt-1.5"
    Some(_) -> ""
  }

  let spoken_bucket = case bucket {
    Some(rating) -> float.to_string(rating)
    None -> "unrated"
  }
  let title = fn(side: ButterflySide, count) {
    side.label
    <> " "
    <> spoken_bucket
    <> " \u{00b7} "
    <> int.to_string(count)
    <> " "
    <> pluralize(unit, count)
  }

  html.div([attr.class("flex items-center gap-1.5 " <> separated)], [
    butterfly_wing(left, left_side.href(bucket), title(left_side, left), [
      butterfly_count(left, "text-right"),
      butterfly_track(left, max, fill, "justify-end", ""),
    ]),
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
    butterfly_wing(right, right_side.href(bucket), title(right_side, right), [
      butterfly_track(right, max, fill, "", "opacity-40"),
      butterfly_count(right, "text-left"),
    ]),
  ])
}

fn pluralize(plural: String, count: Int) -> String {
  case count {
    1 -> string.drop_end(plural, 1)
    _ -> plural
  }
}

/// An empty bar leads to an empty list, so only bars with something in them
/// become links
fn butterfly_wing(
  count: Int,
  href: String,
  title: String,
  children: List(Node),
) -> Node {
  let layout = "flex items-center gap-1.5 flex-1"
  case count {
    0 -> html.div([attr.class(layout)], children)
    _ ->
      html.a(
        [
          attr.href(href),
          attr.Attr("title", title),
          attr.Attr("aria-label", title),
          attr.class(layout <> " hover:opacity-70 transition-opacity"),
        ],
        children,
      )
  }
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
        "text-[11px] text-stone-500 tabular-nums w-7 shrink-0 " <> align,
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
          "<svg aria-hidden=\"true\" class=\"w-full h-full\" viewBox=\"0 0 80 220\" fill=\"#2d5a27\" xmlns=\"http://www.w3.org/2000/svg\">"
          <> "<path d=\"M30,0 L30,4 L26,4 L26,8 L30,8 L30,38 C30,52 10,62 10,80 L10,206 C10,214 16,220 24,220 L56,220 C64,220 70,214 70,206 L70,80 C70,62 50,52 50,38 L50,8 L54,8 L54,4 L50,4 L50,0 Z\"/>"
          <> "</svg>",
        ),
      ],
    ),
  ])
}

// --- Card helpers ---

pub fn card(content: List(Node)) -> Node {
  html.div([attr.class("card")], content)
}

// --- Table helpers ---

pub fn table(headers: List(String), rows: List(Node)) -> Node {
  html.div(
    [
      attr.class("data-table"),
    ],
    [
      html.table([attr.class("w-full text-sm"), attr.Attr("role", "table")], [
        html.thead([attr.Attr("role", "rowgroup")], [
          html.tr(
            [
              attr.class("bg-stone-50 border-b border-stone-200"),
              attr.Attr("role", "row"),
            ],
            list.map(headers, th),
          ),
        ]),
        html.tbody(
          [attr.Attr("role", "rowgroup")],
          list.map(rows, fn(row) {
            case row {
              html.Element("tr", attrs, cells) ->
                html.tr(
                  [attr.Attr("role", "row"), ..attrs],
                  list.index_map(
                    list.filter(cells, fn(cell) { cell != html.Nothing }),
                    fn(cell, index) {
                      case cell {
                        html.Element("td", attrs, content) -> {
                          let label =
                            headers
                            |> list.drop(index)
                            |> list.first
                            |> result.unwrap("")
                          html.td(
                            [
                              attr.Attr("data-label", label),
                              attr.Attr("role", "cell"),
                              ..attrs
                            ],
                            content,
                          )
                        }
                        _ -> cell
                      }
                    },
                  ),
                )
              _ -> row
            }
          }),
        ),
      ]),
      html.p([attr.class("table-empty"), attr.Attr("role", "status")], [
        html.Text("No entries to show. Clear your filters or add an entry."),
      ]),
    ],
  )
}

/// Client-side text filter input for the table inside `#target_id`.
/// Hides rows whose text does not contain the query.
pub fn table_filter(target_id: String, placeholder: String) -> Node {
  html.Element(
    "input",
    [
      attr.type_("search"),
      attr.Attr("placeholder", placeholder),
      attr.Attr("aria-label", placeholder),
      attr.class("table-search"),
      attr.Attr("data-table-filter", target_id),
      attr.Attr("hidden", ""),
    ],
    [],
  )
}

fn th(label: String) -> Node {
  html.th(
    [
      attr.Attr("scope", "col"),
      attr.Attr("role", "columnheader"),
      attr.class(
        "px-4 py-3 text-left font-medium text-stone-600 text-xs uppercase tracking-wider",
      ),
    ],
    [
      case label {
        "" -> html.span([attr.class("sr-only")], [html.Text("Actions")])
        _ -> html.Text(label)
      },
    ],
  )
}

pub fn row_class(_idx: Int) -> String {
  "table-row"
}

pub fn clickable_row_class(idx: Int) -> String {
  row_class(idx) <> " clickable-row"
}

/// Navigate on row click; ctrl/cmd/middle click opens a new tab like
/// a regular link would.
pub fn row_onclick(url: String) -> attr.Attr {
  attr.Attr(
    "onclick",
    "if(!event.target.closest('a,button,input,select,textarea,label,summary,form')){if(event.ctrlKey||event.metaKey){window.open('"
      <> url
      <> "','_blank')}else{window.location='"
      <> url
      <> "'}}",
  )
}

pub fn row_onauxclick(url: String) -> attr.Attr {
  attr.Attr(
    "onauxclick",
    "if(event.button===1&&!event.target.closest('a,button,input,select,textarea,label,summary,form')){window.open('"
      <> url
      <> "','_blank')}",
  )
}

// --- Section helpers (home page cards) ---

pub fn section_header(title: String, link_href: String) -> Node {
  html.div(
    [attr.class("section-heading flex items-baseline justify-between mb-3")],
    [
      html.h2([attr.class("text-lg font-medium text-stone-800")], [
        html.Text(title),
      ]),
      html.a(
        [
          attr.href(link_href),
          attr.Attr("aria-label", "View all: " <> title),
          attr.class(
            "text-xs text-stone-500 hover:text-stone-600 transition-colors",
          ),
        ],
        [html.Text("View all \u{2192}")],
      ),
    ],
  )
}

pub fn stat_card(label: String, value: String, href: String) -> Node {
  html.div([attr.class("stat-card")], [
    html.dt([], [html.a([attr.href(href)], [html.Text(label)])]),
    html.dd([], [html.Text(value)]),
  ])
}

/// A collection with native list semantics, including in Safari with no markers.
pub fn item_list(class: String, items: List(Node)) -> Node {
  html.ul(
    [attr.class("item-list " <> class), attr.Attr("role", "list")],
    list.filter_map(items, fn(item) {
      case item {
        html.Nothing -> Error(Nil)
        _ -> Ok(html.li([], [item]))
      }
    }),
  )
}

pub fn page_header(title: String, subtitle: String) -> Node {
  html.div([attr.class("page-heading mb-6")], [
    html.h1([attr.class("text-3xl font-light text-stone-800 tracking-tight")], [
      html.Text(title),
    ]),
    html.p([attr.class("text-stone-500 mt-1")], [html.Text(subtitle)]),
  ])
}

pub fn detail_grid(items: List(#(String, String))) -> Node {
  html.dl(
    [attr.class("detail-grid")],
    list.filter_map(items, fn(item) {
      case item.1 {
        "" -> Error(Nil)
        val ->
          Ok(
            html.div([], [
              html.dt(
                [attr.class("text-xs uppercase tracking-wider text-stone-500")],
                [html.Text(item.0)],
              ),
              html.dd([attr.class("text-stone-700 mt-0.5")], [html.Text(val)]),
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
  _conn: sqlight.Connection,
  content: List(Node),
) -> Response {
  layout(title, [
    site_header(user),
    html.main(
      [attr.id("main"), attr.class("site-main"), attr.Attr("tabindex", "-1")],
      content,
    ),
  ])
  |> render
}

/// Form titles express their rendering context, independently of visual styles.
pub fn form_title(title: String, fragment: Bool) -> Node {
  let tag = case fragment {
    True -> "h2"
    False -> "h1"
  }
  html.Element(tag, [attr.class("text-xl font-light text-stone-800 mb-4")], [
    html.Text(title),
  ])
}

pub fn layout(title: String, content: List(Node)) -> Node {
  html.Html(
    [
      attr.lang("en"),
      attr.Attr("data-ui", "ledger"),
    ],
    [
      html.Head([
        html.meta([attr.charset("utf-8")]),
        html.meta([
          attr.name("viewport"),
          attr.content(
            "width=device-width, initial-scale=1, viewport-fit=cover",
          ),
        ]),
        html.title(title),
        html.link([
          attr.rel("stylesheet"),
          attr.href("/static/css/app.css"),
        ]),
        html.link([
          attr.rel("icon"),
          attr.href("/static/grapevine.svg"),
        ]),
        html.meta([
          attr.name("htmx-config"),
          attr.content("{\"noSwap\":[204,304,400,401,403,404,409,\"5xx\"]}"),
        ]),
        html.Element("script", [attr.src("/static/js/htmx.min.js")], []),
        html.Element("script", [attr.src("/static/js/ui.js")], []),
      ]),
      html.Body(
        [
          attr.class("app-body"),
        ],
        list.append(
          [
            html.a([attr.href("#main"), attr.class("skip-link")], [
              html.Text("Skip to content"),
            ]),
            ..content
          ],
          [
            html.footer(
              [
                attr.class("site-footer"),
              ],
              [
                html.hr([
                  attr.class("section-divider"),
                  attr.Attr("aria-hidden", "true"),
                ]),
                html.span([], [html.Text("© 2026 Roman Ataman")]),
                html.span([], [
                  html.a(
                    [
                      attr.href("https://rebstock.atamanroman.dev"),
                      attr.class("hover:text-rose-800 transition-colors"),
                    ],
                    [html.Text("rebstock.atamanroman.dev")],
                  ),
                  html.Text(" · "),
                  html.a(
                    [
                      attr.href(
                        "https://polyformproject.org/licenses/noncommercial/1.0.0/",
                      ),
                      attr.class("hover:text-rose-800 transition-colors"),
                    ],
                    [html.Text("PolyForm Noncommercial 1.0.0")],
                  ),
                ]),
              ],
            ),
            html.p(
              [
                attr.id("request-status"),
                attr.class("request-status"),
                attr.Attr("role", "alert"),
                attr.Attr("hidden", ""),
              ],
              [],
            ),
            html.div([attr.id("overlay"), attr.class("hidden")], []),
          ],
        ),
      ),
    ],
  )
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

pub fn not_found(user: User, _conn: sqlight.Connection) -> Response {
  layout("Not Found", [
    site_header(user),
    html.main(
      [
        attr.id("main"),
        attr.class("site-main text-center pt-24"),
        attr.Attr("tabindex", "-1"),
      ],
      [
        html.Element(
          "svg",
          [
            attr.class("mx-auto mb-6 text-stone-300"),
            attr.Attr("aria-hidden", "true"),
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
          html.Text(
            "The page you're looking for has been uncorked and consumed.",
          ),
        ]),
        html.a(
          [
            attr.href("/"),
            attr.class(
              "button inline-block px-5 py-2.5 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors",
            ),
          ],
          [html.Text("Back to your wines")],
        ),
      ],
    ),
  ])
  |> nakai.to_string
  |> wisp.html_response(404)
}

pub fn overlay_wrapper(content: Node) -> Response {
  html.div(
    [
      attr.id("overlay"),
      attr.class("overlay-backdrop"),
    ],
    [
      html.div(
        [
          attr.class("overlay-panel"),
          attr.Attr("role", "dialog"),
          attr.Attr("aria-modal", "true"),
          attr.Attr("aria-label", "Wine details or form"),
          attr.Attr("tabindex", "-1"),
        ],
        [
          html.button(
            [
              attr.class("overlay-close"),

              attr.Attr("aria-label", "Close dialog"),
              attr.type_("button"),
            ],
            [html.Text("\u{00d7}")],
          ),
          content,
        ],
      ),
    ],
  )
  |> nakai.to_inline_string
  |> wisp.html_response(200)
}

fn site_header(user: User) -> Node {
  html.header([attr.class("site-header")], [
    html.div([attr.class("masthead")], [
      html.a([attr.href("/"), attr.class("brand")], [
        html.img([
          attr.src("/static/grapevine.svg"),
          attr.class("brand-mark"),
          attr.Attr("alt", ""),
          attr.Attr("width", "32"),
          attr.Attr("height", "38"),
        ]),
        html.span([attr.class("brand-name")], [html.Text("Rebstock")]),
      ]),
      html.Element("details", [attr.class("user-menu")], [
        html.Element("summary", [], [html.Text("~" <> user.username)]),
        html.div([attr.class("user-dropdown")], [
          html.a([attr.href("/settings")], [html.Text("Settings")]),
          html.a([attr.href(profile_url(user.username))], [
            html.Text("Your profile"),
          ]),
        ]),
      ]),
    ]),
    html.nav(
      [attr.class("site-nav"), attr.Attr("aria-label", "Main navigation")],
      [
        nav_link("Home", "/"),
        nav_link("Cellar", "/~" <> user.username <> "/cellar"),
        nav_link("Wines", "/wines"),
        nav_link("Wineries", "/wineries"),
        nav_link("Ratings", "/~" <> user.username <> "/ratings"),
        nav_link("Wishlist", "/~" <> user.username <> "/wishlist"),
        nav_link("Lists", "/~" <> user.username <> "/lists"),
      ],
    ),
  ])
}

/// Full-page htmx navigation and history restoration must not receive an overlay.
pub fn is_fragment(req: Request) -> Bool {
  request.get_header(req, "hx-request") == Ok("true")
  && request.get_header(req, "hx-request-type") != Ok("full")
  && request.get_header(req, "hx-history-restore-request") != Ok("true")
}

/// htmx follows this with a page request; ordinary forms keep Post/Redirect/Get.
pub fn redirect(req: Request, url: String) -> Response {
  case request.get_header(req, "hx-request") {
    Ok("true") ->
      wisp.response(200)
      |> wisp.set_header(
        "HX-Location",
        json.object([
          #("path", json.string(url)),
          #("replace", json.string(url)),
        ])
          |> json.to_string,
      )
    _ -> wisp.redirect(url)
  }
}

/// Validation keeps the submitted fields, whether enhanced or posted as a page.
pub fn form_error(
  req: Request,
  conn: sqlight.Connection,
  user: User,
  form: Node,
  values: List(#(String, String)),
  invalid_fields: List(String),
  message: String,
) -> Response {
  let error_id =
    "validation-"
    <> case invalid_fields {
      [] -> "form"
      fields -> string.join(fields, "-")
    }
  let error =
    html.p(
      [
        attr.id(error_id),
        attr.class("form-error"),
        attr.Attr("role", "alert"),
        attr.Attr("tabindex", "-1"),
      ],
      [html.Text(message)],
    )
  let form =
    fill_form(form, values)
    |> associate_errors(invalid_fields, error_id)
  let content = case form {
    html.Element(tag, attrs, children) ->
      html.Element(tag, attrs, [error, ..children])
    node -> html.div([attr.class("form-card")], [error, node])
  }
  let rendered = case is_fragment(req) {
    True -> render_fragment(content)
    False -> page("Check your entry — Rebstock", user, conn, [content])
  }
  response.Response(..rendered, status: 422)
}

fn associate_errors(
  node: Node,
  fields: List(String),
  error_id: String,
) -> Node {
  case node {
    html.LeafElement(tag, attrs) -> {
      let assert html.Element(_, attrs, _) =
        associate_errors(html.Element(tag, attrs, []), fields, error_id)
      html.LeafElement(tag, attrs)
    }
    html.Element(tag, attrs, children) -> {
      let invalid =
        list.contains(["input", "select", "textarea"], tag)
        && list.any(attrs, fn(a) {
          a.name == "name" && list.contains(fields, a.value)
        })
      let attrs = case invalid || tag == "form" {
        False -> attrs
        True -> {
          let description =
            list.find(attrs, fn(a) { a.name == "aria-describedby" })
            |> result.map(fn(a) { a.value <> " " })
            |> result.unwrap("")
          let attrs = [
            attr.Attr("aria-describedby", description <> error_id),
            ..list.filter(attrs, fn(a) {
              a.name != "aria-describedby" && a.name != "aria-invalid"
            })
          ]
          case invalid {
            True -> [attr.Attr("aria-invalid", "true"), ..attrs]
            False -> attrs
          }
        }
      }
      html.Element(
        tag,
        attrs,
        list.map(children, associate_errors(_, fields, error_id)),
      )
    }
    _ -> node
  }
}

fn fill_form(node: Node, values: List(#(String, String))) -> Node {
  case node {
    html.LeafElement(tag, attrs) -> {
      let assert html.Element(_, attrs, _) =
        fill_form(html.Element(tag, attrs, []), values)
      html.LeafElement(tag, attrs)
    }
    html.Element(tag, attrs, children) -> {
      let submitted =
        list.find(attrs, fn(a) { a.name == "name" })
        |> result.try(fn(a) { list.key_find(values, a.value) })
      let children = list.map(children, fill_form(_, values))
      let checkbox =
        tag == "input"
        && list.any(attrs, fn(a) { a.name == "type" && a.value == "checkbox" })
      case tag, submitted, checkbox {
        "input", submitted, True ->
          html.Element(
            tag,
            list.append(
              case submitted {
                Ok(_) -> [attr.Attr("checked", "")]
                Error(_) -> []
              },
              list.filter(attrs, fn(a) { a.name != "checked" }),
            ),
            children,
          )
        "input", Ok(value), False ->
          html.Element(
            tag,
            [
              attr.value(value),
              ..list.filter(attrs, fn(a) { a.name != "value" })
            ],
            children,
          )
        "textarea", Ok(value), _ -> html.Element(tag, attrs, [html.Text(value)])
        "select", Ok(value), _ ->
          html.Element(
            tag,
            attrs,
            list.map(children, fn(child) {
              case child {
                html.Element("option", attrs, text) -> {
                  let matches =
                    list.any(attrs, fn(a) {
                      a.name == "value" && a.value == value
                    })
                  html.Element(
                    "option",
                    list.append(
                      case matches {
                        True -> [attr.Attr("selected", "")]
                        False -> []
                      },
                      list.filter(attrs, fn(a) { a.name != "selected" }),
                    ),
                    text,
                  )
                }
                _ -> child
              }
            }),
          )
        _, _, _ -> html.Element(tag, attrs, children)
      }
    }
    _ -> node
  }
}
