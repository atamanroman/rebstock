import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gsv
import simplifile
import sqlight.{type Connection}

import rebstock/db
import wisp

pub fn import_data(conn: Connection, data_dir: String, created_by: String) -> Nil {
  import_cellar(conn, data_dir <> "/cellar.csv", created_by)
  import_full_wine_list(conn, data_dir <> "/full_wine_list.csv", created_by)
  import_wishlisted(conn, data_dir <> "/wishlisted.csv", created_by)
  let count = db.count_wines(conn)
  wisp.log_info("Imported " <> int.to_string(count) <> " wines for " <> created_by)
}

fn is_blank(s: String) -> Bool {
  string.trim(s) == ""
}

fn vintage_to_vintages(v: Option(Int)) -> Option(String) {
  case v {
    None -> None
    Some(year) -> Some(int.to_string(year))
  }
}

fn vintage_or_zero(v: Option(Int)) -> Int {
  case v {
    None -> 0
    Some(year) -> year
  }
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

fn import_cellar(conn: Connection, path: String, created_by: String) -> Nil {
  let assert Ok(content) = simplifile.read(path)
  let assert Ok(rows) = gsv.to_lists(content, ",")
  case rows {
    [_header, ..data] ->
      list.each(data, fn(row) {
        case row {
          [winery, name, vintage, region, country, style, avg_rating, rating_count, wine_type, vivino_link, cellar_count] ->
            case is_blank(name) {
              True -> Nil
              False -> {
                let parsed_vintage = db.parse_vintage(vintage)
                let wine_id = db.upsert_wine(
                  conn,
                  created_by:,
                  winery:,
                  name:,
                  vintages: vintage_to_vintages(parsed_vintage),
                  region: db.optional_non_empty(region),
                  country: db.optional_non_empty(country),
                  style: db.optional_non_empty(style),
                  avg_rating: db.parse_optional_float(avg_rating),
                  rating_count: db.parse_optional_int(rating_count),
                  personal_note: None,
                  wine_type:,
                  vivino_id: extract_vivino_id(vivino_link),
                )
                let bottles = db.parse_int_or_zero(cellar_count)
                case bottles > 0 {
                  True ->
                    db.insert_cellar_entry(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage: vintage_or_zero(parsed_vintage),
                      quantity: bottles,
                      notes: None,
                      dated_at: None,
                    )
                  False -> Nil
                }
              }
            }
          _ -> Nil
        }
      })
    _ -> Nil
  }
}

fn import_full_wine_list(conn: Connection, path: String, created_by: String) -> Nil {
  let assert Ok(content) = simplifile.read(path)
  let assert Ok(rows) = gsv.to_lists(content, ",")
  case rows {
    [_header, ..data] ->
      list.each(data, fn(row) {
        case row {
          [winery, name, vintage, region, country, style, avg_rating, _scan_date, _scan_location, user_rating, user_review, personal_note, wine_type, _drinking_window, vivino_link, ..] ->
            case is_blank(name) {
              True -> Nil
              False -> {
                let parsed_vintage = db.parse_vintage(vintage)
                let wine_id = db.upsert_wine(
                  conn,
                  created_by:,
                  winery:,
                  name:,
                  vintages: vintage_to_vintages(parsed_vintage),
                  region: db.optional_non_empty(region),
                  country: db.optional_non_empty(country),
                  style: db.optional_non_empty(style),
                  avg_rating: db.parse_optional_float(avg_rating),
                  rating_count: None,
                  personal_note: db.optional_non_empty(personal_note),
                  wine_type:,
                  vivino_id: extract_vivino_id(vivino_link),
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
                      vintage: parsed_vintage,
                      rating:,
                      tasting_notes:,
                      rated_at: None,
                    )
                }
              }
            }
          _ -> Nil
        }
      })
    _ -> Nil
  }
}

fn import_wishlisted(conn: Connection, path: String, created_by: String) -> Nil {
  let assert Ok(content) = simplifile.read(path)
  let assert Ok(rows) = gsv.to_lists(content, ",")
  case rows {
    [_header, ..data] ->
      list.each(data, fn(row) {
        case row {
          [winery, name, vintage, region, country, style, avg_rating, _scan_date, _scan_location, user_rating, user_review, personal_note, wine_type, _wishlisted_date, _drinking_window, vivino_link, ..] ->
            case is_blank(name) {
              True -> Nil
              False -> {
                let parsed_vintage = db.parse_vintage(vintage)
                let wine_id = db.upsert_wine(
                  conn,
                  created_by:,
                  winery:,
                  name:,
                  vintages: vintage_to_vintages(parsed_vintage),
                  region: db.optional_non_empty(region),
                  country: db.optional_non_empty(country),
                  style: db.optional_non_empty(style),
                  avg_rating: db.parse_optional_float(avg_rating),
                  rating_count: None,
                  personal_note: db.optional_non_empty(personal_note),
                  wine_type:,
                  vivino_id: extract_vivino_id(vivino_link),
                )
                db.upsert_wishlist(
                  conn,
                  username: created_by,
                  wine_id:,
                  vintage: parsed_vintage,
                  notes: None,
                  dated_at: None,
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
                      vintage: parsed_vintage,
                      rating:,
                      tasting_notes:,
                      rated_at: None,
                    )
                }
              }
            }
          _ -> Nil
        }
      })
    _ -> Nil
  }
}
