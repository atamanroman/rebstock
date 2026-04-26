import gleam/bit_array
import gleam/dynamic
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
import gsv
import simplifile
import sqlight.{type Connection}

import rebstock/db
import wisp

pub type ImportResult {
  ImportResult(
    wineries_created: Int,
    wineries_updated: Int,
    wines_created: Int,
    wines_updated: Int,
    cellar_created: Int,
    wishlist_created: Int,
  )
}

pub const vivino_user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

pub const vivino_mobile_user_agent = "Vivino/8.18.11 (Android; SDK 30)"

pub type VivinoSearchResult {
  VivinoSearchResult(
    wine_id: Int,
    wine_name: String,
    winery_name: String,
    vintage: String,
    rating: Float,
    rating_count: Int,
    region: String,
    country: String,
    wine_type: String,
    thumb_url: String,
  )
}

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
    _ -> "Red"
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

fn stats_decoder() -> decode.Decoder(#(Float, Int)) {
  use rating <- decode.optional_field(
    "wine_ratings_average",
    0.0,
    float_or_int_decoder(),
  )
  use rating_count <- decode.optional_field("wine_ratings_count", 0, decode.int)
  decode.success(#(rating, rating_count))
}

pub fn search_results_decoder() -> decode.Decoder(List(VivinoSearchResult)) {
  let wine_decoder = {
    use id <- decode.field("id", decode.int)
    use name <- decode.field("name", decode.string)
    use type_id <- decode.field("type_id", decode.int)
    use winery_name <- decode.field("winery", {
      use name <- decode.field("name", decode.string)
      decode.success(name)
    })
    use region_pair <- decode.field("region", {
      use name <- decode.field("name", decode.string)
      use country <- decode.field("country", {
        use name <- decode.field("native_name", decode.string)
        decode.success(name)
      })
      decode.success(#(name, country))
    })
    let #(region, country) = region_pair
    decode.success(#(id, name, type_id, winery_name, region, country))
  }

  let match_decoder = {
    use year <- decode.field("year", year_decoder())
    use stats <- decode.optional_field("statistics", #(0.0, 0), stats_decoder())
    use thumb <- decode.field("image", {
      use location <- decode.field("location", decode.string)
      decode.success(location)
    })
    use wine_tuple <- decode.field("wine", wine_decoder)
    let #(id, name, type_id, winery_name, region, country) = wine_tuple
    let #(rating, rating_count) = stats
    decode.success(VivinoSearchResult(
      wine_id: id,
      wine_name: name,
      winery_name: winery_name,
      vintage: year,
      rating: rating,
      rating_count: rating_count,
      region: region,
      country: country,
      wine_type: wine_type_from_id(type_id),
      thumb_url: "https:" <> thumb,
    ))
  }

  let vintage_decoder = {
    use result <- decode.field("vintage", match_decoder)
    decode.success(result)
  }

  use matches <- decode.field("explore_vintage", {
    use matches <- decode.field("matches", decode.list(vintage_decoder))
    decode.success(matches)
  })
  decode.success(matches)
}

pub fn search_url(query: String) -> String {
  let encoded = uri.percent_encode(query)
  "https://www.vivino.com/api/explore/explore?search_term="
  <> encoded
  <> "&min_rating=1"
}

fn vivino_get(url: String) -> Result(String, String) {
  vivino_http(url, vivino_user_agent)
}

fn vivino_mobile_get(url: String) -> Result(String, String) {
  vivino_http(url, vivino_mobile_user_agent)
}

fn vivino_http(url: String, user_agent: String) -> Result(String, String) {
  wisp.log_info("Vivino API: " <> url)
  case request.to(url) {
    Error(_) -> Error("Invalid URL")
    Ok(req) -> {
      let req =
        req
        |> request.set_header("user-agent", user_agent)
        |> request.set_header("accept", "application/json")
      case httpc.send(req) {
        Error(e) -> {
          wisp.log_error("Vivino HTTP error: " <> string.inspect(e))
          Error("HTTP request failed")
        }
        Ok(resp) ->
          case resp.status {
            200 -> Ok(resp.body)
            status -> {
              wisp.log_warning(
                "Vivino API status "
                <> int.to_string(status)
                <> ": "
                <> string.slice(resp.body, 0, 200),
              )
              Error("Vivino API returned status " <> int.to_string(status))
            }
          }
      }
    }
  }
}

pub fn search(query: String) -> Result(List(VivinoSearchResult), String) {
  let url = search_url(query)
  case vivino_get(url) {
    Error(e) -> Error(e)
    Ok(body) ->
      case json.parse(body, search_results_decoder()) {
        Ok(results) -> {
          wisp.log_info(
            "Vivino search returned "
            <> int.to_string(list.length(results))
            <> " results",
          )
          Ok(results)
        }
        Error(e) -> {
          wisp.log_error("Vivino parse error: " <> string.inspect(e))
          Error("Failed to parse search results")
        }
      }
  }
}

pub fn wine_detail_decoder() -> decode.Decoder(VivinoSearchResult) {
  use year <- decode.field("year", decode.int)
  use stats <- decode.optional_field("statistics", #(0.0, 0), stats_decoder())
  use wine_tuple <- decode.field("wine", {
    use id <- decode.field("id", decode.int)
    use name <- decode.field("name", decode.string)
    use type_id <- decode.field("type_id", decode.int)
    use winery_name <- decode.field("winery", {
      use name <- decode.field("name", decode.string)
      decode.success(name)
    })
    use region_pair <- decode.field("region", {
      use name <- decode.field("name", decode.string)
      use country <- decode.field("country", {
        use name <- decode.field("native_name", decode.string)
        decode.success(name)
      })
      decode.success(#(name, country))
    })
    decode.success(#(id, name, type_id, winery_name, region_pair))
  })
  use thumb <- decode.field("image", {
    use location <- decode.field("location", decode.string)
    decode.success(location)
  })
  let #(id, name, type_id, winery_name, region_pair) = wine_tuple
  let #(region, country) = region_pair
  let #(rating, rating_count) = stats
  decode.success(VivinoSearchResult(
    wine_id: id,
    wine_name: name,
    winery_name: winery_name,
    vintage: int.to_string(year),
    rating: rating,
    rating_count: rating_count,
    region: region,
    country: country,
    wine_type: wine_type_from_id(type_id),
    thumb_url: "https:" <> thumb,
  ))
}

pub fn fetch_wine_detail(
  wine_id: Int,
  vintage_year: String,
) -> Result(VivinoSearchResult, String) {
  let url =
    "https://www.vivino.com/api/wines/"
    <> int.to_string(wine_id)
    <> "/years/"
    <> vintage_year
  case vivino_get(url) {
    Error(e) -> Error(e)
    Ok(body) ->
      case json.parse(body, wine_detail_decoder()) {
        Ok(result) -> Ok(result)
        Error(e) -> {
          wisp.log_error("Vivino parse error: " <> string.inspect(e))
          Error("Failed to parse wine details")
        }
      }
  }
}

pub fn fetch_wine_by_id(wine_id: String) -> Result(VivinoSearchResult, String) {
  let url =
    "https://www.vivino.com/api/wines/" <> wine_id <> "/reviews?per_page=1"
  case vivino_get(url) {
    Error(e) -> Error(e)
    Ok(body) -> {
      let decoder = {
        use reviews <- decode.field(
          "reviews",
          decode.list(wine_from_review_decoder()),
        )
        decode.success(reviews)
      }
      case json.parse(body, decoder) {
        Ok([result, ..]) -> Ok(result)
        Ok([]) -> Error("No reviews found for this wine")
        Error(e) -> {
          wisp.log_error("Vivino parse error: " <> string.inspect(e))
          Error("Failed to parse wine data")
        }
      }
    }
  }
}

fn wine_from_review_decoder() -> decode.Decoder(VivinoSearchResult) {
  use vintage <- decode.field("vintage", {
    use stats_pair <- decode.field("statistics", {
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
    use wine_tuple <- decode.field("wine", {
      use id <- decode.field("id", decode.int)
      use name <- decode.field("name", decode.string)
      use type_id <- decode.field("type_id", decode.int)
      use winery_name <- decode.optional_field("winery", "", {
        use n <- decode.field("name", decode.string)
        decode.success(n)
      })
      use region_pair <- decode.optional_field("region", #("", ""), {
        use rname <- decode.field("name", decode.string)
        use country <- decode.optional_field("country", "", {
          use n <- decode.field("native_name", decode.string)
          decode.success(n)
        })
        decode.success(#(rname, country))
      })
      decode.success(#(id, name, type_id, winery_name, region_pair))
    })
    let #(id, name, type_id, winery_name, region_pair) = wine_tuple
    let #(region, country) = region_pair
    let #(rating, rating_count) = stats_pair
    let thumb_url = case thumb {
      "" -> ""
      loc -> "https:" <> loc
    }
    decode.success(VivinoSearchResult(
      wine_id: id,
      wine_name: name,
      winery_name: winery_name,
      vintage: "N.V.",
      rating: rating,
      rating_count: rating_count,
      region: region,
      country: country,
      wine_type: wine_type_from_id(type_id),
      thumb_url: thumb_url,
    ))
  })
  decode.success(vintage)
}

pub fn parse_vivino_id(input: String) -> Result(String, Nil) {
  let trimmed = string.trim(input)
  case int.parse(trimmed) {
    Ok(_) -> Ok(trimmed)
    Error(_) ->
      case string.split(trimmed, "/w/") {
        [_, id_part, ..] -> {
          let id =
            id_part
            |> string.split("/")
            |> list.first
            |> result.unwrap("")
            |> string.split("?")
            |> list.first
            |> result.unwrap("")
          case int.parse(id) {
            Ok(_) -> Ok(id)
            Error(_) -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
  }
}

pub fn fetch_wine_with_vintages(
  wine_id: String,
) -> Result(VivinoWineDetail, String) {
  let url = "https://api.vivino.com/wines/" <> wine_id
  case vivino_mobile_get(url) {
    Error(e) -> Error(e)
    Ok(body) ->
      case json.parse(body, wine_detail_mobile_decoder()) {
        Ok(result) -> Ok(result)
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
    use country <- decode.optional_field("country", "", decode.string)
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
    loc -> "https:" <> loc
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

pub fn empty_result() -> ImportResult {
  ImportResult(
    wineries_created: 0,
    wineries_updated: 0,
    wines_created: 0,
    wines_updated: 0,
    cellar_created: 0,
    wishlist_created: 0,
  )
}

pub fn merge_results(a: ImportResult, b: ImportResult) -> ImportResult {
  ImportResult(
    wineries_created: a.wineries_created + b.wineries_created,
    wineries_updated: a.wineries_updated + b.wineries_updated,
    wines_created: a.wines_created + b.wines_created,
    wines_updated: a.wines_updated + b.wines_updated,
    cellar_created: a.cellar_created + b.cellar_created,
    wishlist_created: a.wishlist_created + b.wishlist_created,
  )
}

pub fn import_data(
  conn: Connection,
  data_dir: String,
  created_by: String,
) -> Nil {
  db.ensure_user(conn, created_by)
  let assert Ok(cellar_csv) = simplifile.read(data_dir <> "/cellar.csv")
  let assert Ok(wine_list_csv) =
    simplifile.read(data_dir <> "/full_wine_list.csv")
  let assert Ok(wishlist_csv) = simplifile.read(data_dir <> "/wishlisted.csv")
  import_cellar(conn, cellar_csv, created_by)
  import_full_wine_list(conn, wine_list_csv, created_by)
  import_wishlisted(conn, wishlist_csv, created_by)
  let count = db.count_wines(conn)
  wisp.log_info(
    "Imported " <> int.to_string(count) <> " wines for " <> created_by,
  )
}

fn is_blank(s: String) -> Bool {
  string.trim(s) == ""
}

fn extract_vivino_id(url: String) -> Option(String) {
  case db.optional_non_empty(url) {
    None -> None
    Some(u) ->
      case string.split(u, "/wines/") {
        [_, id_part] ->
          case string.split(id_part, "?") {
            [id, ..] -> db.optional_non_empty(id)
            _ -> None
          }
        _ -> None
      }
  }
}

pub fn import_cellar(
  conn: Connection,
  content: String,
  created_by: String,
) -> ImportResult {
  let assert Ok(rows) = gsv.to_lists(content, ",")
  case rows {
    [_header, ..data] ->
      list.fold(data, empty_result(), fn(acc, row) {
        case row {
          [
            winery,
            name,
            vintage_str,
            region,
            country,
            style,
            avg_rating,
            _rating_count,
            wine_type,
            vivino_link,
            cellar_count,
          ] ->
            case is_blank(name) {
              True -> acc
              False -> {
                let vintage = db.parse_vintage(vintage_str)
                let wine_id =
                  db.upsert_wine(
                    conn,
                    created_by:,
                    winery:,
                    name:,
                    vintage:,
                    region: db.optional_non_empty(region),
                    country: db.country_to_iso(country),
                    style: db.optional_non_empty(style),
                    personal_note: None,
                    wine_type: db.wine_type_from_string(wine_type),
                    vivino_id: extract_vivino_id(vivino_link),
                  )
                let acc =
                  ImportResult(..acc, wines_created: acc.wines_created + 1)
                case db.parse_optional_float(avg_rating) {
                  Some(r) ->
                    db.upsert_vivino_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating: r,
                    )
                  None -> Nil
                }
                let bottles = db.parse_int_or_zero(cellar_count)
                case bottles > 0 {
                  True -> {
                    case vintage {
                      Some(v) -> db.upsert_vintage(conn, wine_id, v)
                      None -> Nil
                    }
                    db.insert_cellar_entry(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      quantity: bottles,
                      notes: None,
                      date: None,
                    )
                    ImportResult(..acc, cellar_created: acc.cellar_created + 1)
                  }
                  False -> acc
                }
              }
            }
          _ -> acc
        }
      })
    _ -> empty_result()
  }
}

pub fn import_full_wine_list(
  conn: Connection,
  content: String,
  created_by: String,
) -> ImportResult {
  let assert Ok(rows) = gsv.to_lists(content, ",")
  case rows {
    [_header, ..data] ->
      list.fold(data, empty_result(), fn(acc, row) {
        case row {
          [
            winery,
            name,
            vintage_str,
            region,
            country,
            style,
            avg_rating,
            _scan_date,
            _scan_location,
            user_rating,
            user_review,
            personal_note,
            wine_type,
            _drinking_window,
            vivino_link,
            ..
          ] ->
            case is_blank(name) {
              True -> acc
              False -> {
                let vintage = db.parse_vintage(vintage_str)
                let wine_id =
                  db.upsert_wine(
                    conn,
                    created_by:,
                    winery:,
                    name:,
                    vintage:,
                    region: db.optional_non_empty(region),
                    country: db.country_to_iso(country),
                    style: db.optional_non_empty(style),
                    personal_note: db.optional_non_empty(personal_note),
                    wine_type: db.wine_type_from_string(wine_type),
                    vivino_id: extract_vivino_id(vivino_link),
                  )
                let acc =
                  ImportResult(..acc, wines_created: acc.wines_created + 1)
                case db.parse_optional_float(avg_rating) {
                  Some(r) ->
                    db.upsert_vivino_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating: r,
                    )
                  None -> Nil
                }
                let rating = db.parse_optional_float(user_rating)
                let tasting_notes = db.optional_non_empty(user_review)
                case rating, tasting_notes {
                  None, None -> Nil
                  _, _ ->
                    db.insert_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating:,
                      tasting_notes:,
                      rated_at: None,
                      source: "user",
                    )
                }
                acc
              }
            }
          _ -> acc
        }
      })
    _ -> empty_result()
  }
}

pub fn import_wishlisted(
  conn: Connection,
  content: String,
  created_by: String,
) -> ImportResult {
  let assert Ok(rows) = gsv.to_lists(content, ",")
  case rows {
    [_header, ..data] ->
      list.fold(data, empty_result(), fn(acc, row) {
        case row {
          [
            winery,
            name,
            vintage_str,
            region,
            country,
            style,
            avg_rating,
            _scan_date,
            _scan_location,
            user_rating,
            user_review,
            personal_note,
            wine_type,
            _wishlisted_date,
            _drinking_window,
            vivino_link,
            ..
          ] ->
            case is_blank(name) {
              True -> acc
              False -> {
                let vintage = db.parse_vintage(vintage_str)
                let wine_id =
                  db.upsert_wine(
                    conn,
                    created_by:,
                    winery:,
                    name:,
                    vintage:,
                    region: db.optional_non_empty(region),
                    country: db.country_to_iso(country),
                    style: db.optional_non_empty(style),
                    personal_note: db.optional_non_empty(personal_note),
                    wine_type: db.wine_type_from_string(wine_type),
                    vivino_id: extract_vivino_id(vivino_link),
                  )
                let acc =
                  ImportResult(..acc, wines_created: acc.wines_created + 1)
                case db.parse_optional_float(avg_rating) {
                  Some(r) ->
                    db.upsert_vivino_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating: r,
                    )
                  None -> Nil
                }
                let wishlist = db.get_user_wishlist(conn, created_by)
                db.add_wine_to_list(conn, wishlist.id, wine_id, vintage, None)
                let acc =
                  ImportResult(
                    ..acc,
                    wishlist_created: acc.wishlist_created + 1,
                  )
                let rating = db.parse_optional_float(user_rating)
                let tasting_notes = db.optional_non_empty(user_review)
                case rating, tasting_notes {
                  None, None -> Nil
                  _, _ ->
                    db.insert_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating:,
                      tasting_notes:,
                      rated_at: None,
                      source: "user",
                    )
                }
                acc
              }
            }
          _ -> acc
        }
      })
    _ -> empty_result()
  }
}

@external(erlang, "zip_ffi", "unzip_memory")
fn unzip_memory(
  archive: BitArray,
) -> Result(List(#(String, BitArray)), dynamic.Dynamic)

pub fn import_from_zip(
  conn: Connection,
  zip_bytes: BitArray,
  created_by: String,
) -> Result(ImportResult, String) {
  db.ensure_user(conn, created_by)
  case unzip_memory(zip_bytes) {
    Error(_) -> Error("Invalid zip file")
    Ok(entries) -> {
      let files =
        list.filter_map(entries, fn(entry) {
          let #(name, data) = entry
          let filename = case string.split(name, "/") |> list.last {
            Ok(f) -> f
            Error(_) -> name
          }
          case bit_array.to_string(data) {
            Ok(content) -> Ok(#(filename, content))
            Error(_) -> Error(Nil)
          }
        })
      case find_file(files, "full_wine_list.csv") {
        Error(_) -> Error("Zip must contain full_wine_list.csv")
        Ok(wine_list_csv) -> {
          let result = import_full_wine_list(conn, wine_list_csv, created_by)
          let result = case find_file(files, "cellar.csv") {
            Ok(cellar_csv) ->
              merge_results(result, import_cellar(conn, cellar_csv, created_by))
            Error(_) -> result
          }
          let result = case find_file(files, "wishlisted.csv") {
            Ok(wishlist_csv) ->
              merge_results(
                result,
                import_wishlisted(conn, wishlist_csv, created_by),
              )
            Error(_) -> result
          }
          Ok(result)
        }
      }
    }
  }
}

fn find_file(
  files: List(#(String, String)),
  name: String,
) -> Result(String, Nil) {
  list.find_map(files, fn(entry) {
    case entry.0 == name {
      True -> Ok(entry.1)
      False -> Error(Nil)
    }
  })
}
