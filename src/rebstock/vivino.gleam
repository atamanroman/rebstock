import gleam/int
import gleam/list
import gleam/option.{None}
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
                db.upsert_wine(
                  conn,
                  created_by:,
                  winery:,
                  name:,
                  vintage: db.parse_vintage(vintage),
                  region: db.optional_non_empty(region),
                  country: db.optional_non_empty(country),
                  style: db.optional_non_empty(style),
                  avg_rating: db.parse_optional_float(avg_rating),
                  rating_count: db.parse_optional_int(rating_count),
                  personal_note: None,
                  wine_type:,
                  vivino_link: db.optional_non_empty(vivino_link),
                  in_cellar: db.parse_int_or_zero(cellar_count),
                  wishlisted: False,
                )
                Nil
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
                let wine_id = db.upsert_wine(
                  conn,
                  created_by:,
                  winery:,
                  name:,
                  vintage: db.parse_vintage(vintage),
                  region: db.optional_non_empty(region),
                  country: db.optional_non_empty(country),
                  style: db.optional_non_empty(style),
                  avg_rating: db.parse_optional_float(avg_rating),
                  rating_count: None,
                  personal_note: db.optional_non_empty(personal_note),
                  wine_type:,
                  vivino_link: db.optional_non_empty(vivino_link),
                  in_cellar: 0,
                  wishlisted: False,
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
                let wine_id = db.upsert_wine(
                  conn,
                  created_by:,
                  winery:,
                  name:,
                  vintage: db.parse_vintage(vintage),
                  region: db.optional_non_empty(region),
                  country: db.optional_non_empty(country),
                  style: db.optional_non_empty(style),
                  avg_rating: db.parse_optional_float(avg_rating),
                  rating_count: None,
                  personal_note: db.optional_non_empty(personal_note),
                  wine_type:,
                  vivino_link: db.optional_non_empty(vivino_link),
                  in_cellar: 0,
                  wishlisted: True,
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
