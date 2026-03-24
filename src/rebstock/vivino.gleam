import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}
import gsv
import simplifile
import sqlight.{type Connection}

import rebstock/db

pub fn import_data(conn: Connection, data_dir: String, username: String) -> Nil {
  import_cellar(conn, data_dir <> "/cellar.csv", username)
  import_full_wine_list(conn, data_dir <> "/full_wine_list.csv", username)
  import_wishlisted(conn, data_dir <> "/wishlisted.csv", username)
  let count = db.count_wines(conn, username)
  io.println("Imported " <> int.to_string(count) <> " wines for " <> username)
}

fn import_cellar(conn: Connection, path: String, username: String) -> Nil {
  let assert Ok(content) = simplifile.read(path)
  let assert Ok(rows) = gsv.to_lists(content, ",")
  case rows {
    [_header, ..data] ->
      list.each(data, fn(row) {
        case row {
          [winery, name, vintage, region, country, style, avg_rating, rating_count, wine_type, vivino_link, cellar_count] ->
            db.upsert_wine(
              conn,
              username:,
              winery:,
              name:,
              vintage: db.parse_vintage(vintage),
              region:,
              country:,
              style:,
              avg_rating: db.parse_optional_float(avg_rating),
              rating_count: db.parse_optional_int(rating_count),
              user_rating: None,
              user_review: "",
              personal_note: "",
              wine_type:,
              vivino_link:,
              in_cellar: db.parse_int_or_zero(cellar_count),
              wishlisted: False,
            )
          _ -> Nil
        }
      })
    _ -> Nil
  }
}

fn import_full_wine_list(conn: Connection, path: String, username: String) -> Nil {
  let assert Ok(content) = simplifile.read(path)
  let assert Ok(rows) = gsv.to_lists(content, ",")
  case rows {
    [_header, ..data] ->
      list.each(data, fn(row) {
        case row {
          [winery, name, vintage, region, country, style, avg_rating, _scan_date, _scan_location, user_rating, user_review, personal_note, wine_type, _drinking_window, vivino_link, ..] ->
            db.upsert_wine(
              conn,
              username:,
              winery:,
              name:,
              vintage: db.parse_vintage(vintage),
              region:,
              country:,
              style:,
              avg_rating: db.parse_optional_float(avg_rating),
              rating_count: None,
              user_rating: db.parse_optional_float(user_rating),
              user_review:,
              personal_note:,
              wine_type:,
              vivino_link:,
              in_cellar: 0,
              wishlisted: False,
            )
          _ -> Nil
        }
      })
    _ -> Nil
  }
}

fn import_wishlisted(conn: Connection, path: String, username: String) -> Nil {
  let assert Ok(content) = simplifile.read(path)
  let assert Ok(rows) = gsv.to_lists(content, ",")
  case rows {
    [_header, ..data] ->
      list.each(data, fn(row) {
        case row {
          [winery, name, vintage, region, country, style, avg_rating, _scan_date, _scan_location, user_rating, user_review, personal_note, wine_type, _wishlisted_date, _drinking_window, vivino_link, ..] ->
            db.upsert_wine(
              conn,
              username:,
              winery:,
              name:,
              vintage: db.parse_vintage(vintage),
              region:,
              country:,
              style:,
              avg_rating: db.parse_optional_float(avg_rating),
              rating_count: None,
              user_rating: db.parse_optional_float(user_rating),
              user_review:,
              personal_note:,
              wine_type:,
              vivino_link:,
              in_cellar: 0,
              wishlisted: True,
            )
          _ -> Nil
        }
      })
    _ -> Nil
  }
}
