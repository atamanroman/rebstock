import gleam/dynamic/decode
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

import wisp

pub const vivino_mobile_user_agent = "Vivino/8.18.11 (Android; SDK 30)"

pub type VivinoVintage {
  VivinoVintage(year: String, rating: Float, rating_count: Int)
}

pub type VivinoWineDetail {
  VivinoWineDetail(
    wine_id: Int,
    wine_name: String,
    winery_name: String,
    winery_id: Int,
    region: String,
    country: String,
    wine_type: String,
    rating: Float,
    rating_count: Int,
    thumb_url: String,
    vintages: List(VivinoVintage),
  )
}

fn wine_type_from_id(id: Int) -> String {
  case id {
    1 -> "Red"
    2 -> "White"
    3 -> "Sparkling"
    4 -> "Rosé"
    7 -> "Dessert"
    24 -> "Fortified"
    _ -> "Other"
  }
}

fn year_decoder() -> decode.Decoder(String) {
  decode.one_of(decode.string, [
    {
      use n <- decode.then(decode.int)
      decode.success(int.to_string(n))
    },
  ])
}

fn float_or_int_decoder() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [
    {
      use n <- decode.then(decode.int)
      decode.success(int.to_float(n))
    },
  ])
}

fn vivino_mobile_get(url: String) -> Result(String, String) {
  vivino_http(url, vivino_mobile_user_agent)
}

fn vivino_http(url: String, user_agent: String) -> Result(String, String) {
  case request.to(url) {
    Error(_) -> Error("Invalid URL")
    Ok(req) -> {
      let req =
        req
        |> request.set_header("user-agent", user_agent)
        |> request.set_header("accept", "application/json")
      case httpc.configure() |> httpc.timeout(5000) |> httpc.dispatch(req) {
        Error(e) -> {
          wisp.log_error("Vivino HTTP error: " <> string.inspect(e))
          Error("HTTP request failed")
        }
        Ok(resp) ->
          case resp.status {
            200 ->
              case string.byte_size(resp.body) <= 1_048_576 {
                True -> Ok(resp.body)
                False -> Error("Vivino response exceeded the size limit")
              }
            status -> {
              wisp.log_warning("Vivino API status " <> int.to_string(status))
              Error("Vivino API returned status " <> int.to_string(status))
            }
          }
      }
    }
  }
}

pub fn parse_vivino_id(input: String) -> Result(String, Nil) {
  let trimmed = string.trim(input)
  case positive_id(trimmed) {
    Ok(id) -> Ok(id)
    Error(_) -> {
      use url <- result.try(uri.parse(trimmed))
      let segments =
        string.split(url.path, "/") |> list.filter(fn(part) { part != "" })
      case
        url.scheme == Some("https")
        && {
          url.host == Some("www.vivino.com") || url.host == Some("vivino.com")
        }
        && !list.contains(segments, "..")
        && !list.contains(segments, ".")
      {
        True -> path_id(segments)
        False -> Error(Nil)
      }
    }
  }
}

fn positive_id(input: String) -> Result(String, Nil) {
  case int.parse(input) {
    Ok(id) if id > 0 && id <= 9_223_372_036_854_775_807 -> Ok(int.to_string(id))
    _ -> Error(Nil)
  }
}

fn path_id(segments: List(String)) -> Result(String, Nil) {
  case segments {
    ["w", id] -> positive_id(id)
    ["wines", id] ->
      positive_id(id) |> result.map(fn(id) { vintage_id_prefix <> id })
    ["w", ..] | ["wines", ..] -> Error(Nil)
    [_, ..rest] -> path_id(rest)
    [] -> Error(Nil)
  }
}

pub fn lookup(input: String) -> Result(VivinoWineDetail, String) {
  let stored = case unresolved_vintage_id(string.trim(input)) {
    Some(id) -> Ok(vintage_id_prefix <> id)
    None -> parse_vivino_id(input)
  }
  use id <- result.try(
    stored
    |> result.map_error(fn(_) {
      "Enter a positive Vivino wine ID or public Vivino URL"
    }),
  )
  use id <- result.try(ensure_wine_id(id))
  fetch_wine_with_vintages(id)
}

pub fn validate_identity(
  wine_id: String,
  detail: VivinoWineDetail,
) -> Result(VivinoWineDetail, String) {
  let returned_id = int.to_string(detail.wine_id)
  case positive_id(wine_id) {
    Ok(id) if id == returned_id -> Ok(detail)
    Ok(_) -> Error("Vivino returned a different wine identity")
    Error(_) -> Error("Invalid Vivino wine ID")
  }
}

pub fn fetch_wine_with_vintages(
  wine_id: String,
) -> Result(VivinoWineDetail, String) {
  use wine_id <- result.try(
    positive_id(wine_id) |> result.map_error(fn(_) { "Invalid Vivino wine ID" }),
  )
  let url = "https://api.vivino.com/wines/" <> wine_id
  case vivino_mobile_get(url) {
    Error(e) -> Error(e)
    Ok(body) ->
      case json.parse(body, wine_detail_mobile_decoder()) {
        Ok(result) -> validate_identity(wine_id, result)
        Error(e) -> {
          wisp.log_error("Vivino parse error: " <> string.inspect(e))
          Error("Failed to parse wine data")
        }
      }
  }
}

pub fn wine_detail_mobile_decoder() -> decode.Decoder(VivinoWineDetail) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use type_id <- decode.field("type_id", decode.int)
  use winery <- decode.field("winery", {
    use winery_id <- decode.field("id", decode.int)
    use winery_name <- decode.field("name", decode.string)
    decode.success(#(winery_id, winery_name))
  })
  use region_pair <- decode.optional_field("region", #("", ""), {
    use rname <- decode.field("name", decode.string)
    use country <- decode.optional_field(
      "country",
      "",
      decode.one_of(decode.string, [
        {
          use code <- decode.field("code", decode.string)
          decode.success(code)
        },
      ]),
    )
    decode.success(#(rname, country))
  })
  use stats <- decode.optional_field("statistics", #(0.0, 0), {
    use avg <- decode.optional_field(
      "ratings_average",
      0.0,
      float_or_int_decoder(),
    )
    use count <- decode.optional_field("ratings_count", 0, decode.int)
    decode.success(#(avg, count))
  })
  use thumb <- decode.optional_field("image", "", {
    use loc <- decode.field("location", decode.string)
    decode.success(loc)
  })
  use vintages <- decode.optional_field(
    "vintages",
    [],
    decode.list(vintage_decoder()),
  )
  let #(winery_id, winery_name) = winery
  let #(region, country) = region_pair
  let #(rating, rating_count) = stats
  let thumb_url = case thumb {
    "" -> ""
    loc ->
      case string.starts_with(loc, "//") {
        True -> "https:" <> loc
        False -> loc
      }
  }
  let vintages = list.filter(vintages, fn(v) { v.year != "" })
  decode.success(VivinoWineDetail(
    wine_id: id,
    wine_name: name,
    winery_name: winery_name,
    winery_id: winery_id,
    region: region,
    country: country,
    wine_type: wine_type_from_id(type_id),
    rating: rating,
    rating_count: rating_count,
    thumb_url: thumb_url,
    vintages: vintages,
  ))
}

fn vintage_decoder() -> decode.Decoder(VivinoVintage) {
  use year <- decode.optional_field("year", "", year_decoder())
  use stats <- decode.optional_field("statistics", #(0.0, 0), {
    use avg <- decode.optional_field(
      "ratings_average",
      0.0,
      float_or_int_decoder(),
    )
    use count <- decode.optional_field("ratings_count", 0, decode.int)
    decode.success(#(avg, count))
  })
  let #(rating, rating_count) = stats
  decode.success(VivinoVintage(
    year: year,
    rating: rating,
    rating_count: rating_count,
  ))
}

const vintage_id_prefix = "v"

/// Public Vivino URL for a stored ID (resolved wine ID or
/// prefixed vintage ID).
pub fn vivino_url(vivino_id: String) -> String {
  case unresolved_vintage_id(vivino_id) {
    Some(vintage_id) -> "https://www.vivino.com/wines/" <> vintage_id
    None -> "https://www.vivino.com/w/" <> vivino_id
  }
}

fn unresolved_vintage_id(vivino_id: String) -> Option(String) {
  case string.split_once(vivino_id, vintage_id_prefix) {
    Ok(#("", rest)) ->
      case positive_id(rest) {
        Ok(id) -> Some(id)
        Error(_) -> None
      }
    _ -> None
  }
}

/// Turn a stored ID into an API wine ID, resolving prefixed
/// vintage IDs via the vintages endpoint on demand.
pub fn ensure_wine_id(vivino_id: String) -> Result(String, String) {
  case unresolved_vintage_id(vivino_id) {
    None ->
      positive_id(vivino_id)
      |> result.map_error(fn(_) { "Invalid Vivino wine ID" })
    Some(vintage_id) -> resolve_vintage_to_wine_id(vintage_id)
  }
}

fn resolve_vintage_to_wine_id(vintage_id: String) -> Result(String, String) {
  let url = "https://api.vivino.com/vintages/" <> vintage_id
  wisp.log_debug("Resolving vintage ID " <> vintage_id)
  case vivino_mobile_get(url) {
    Error(e) -> Error(e)
    Ok(body) -> {
      let decoder = {
        use wine_id <- decode.field("wine", {
          use id <- decode.field("id", decode.int)
          decode.success(id)
        })
        decode.success(wine_id)
      }
      case json.parse(body, decoder) {
        Ok(wine_id) -> Ok(int.to_string(wine_id))
        Error(_) -> Error("Failed to resolve Vivino vintage ID")
      }
    }
  }
}
