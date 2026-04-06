import gleam/bit_array
import gleam/dynamic
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
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
                    db.insert_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating: Some(r),
                      tasting_notes: None,
                      rated_at: None,
                      source: "vivino",
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
                    db.insert_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating: Some(r),
                      tasting_notes: None,
                      rated_at: None,
                      source: "vivino",
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
                    db.insert_rating(
                      conn,
                      username: created_by,
                      wine_id:,
                      vintage:,
                      rating: Some(r),
                      tasting_notes: None,
                      rated_at: None,
                      source: "vivino",
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
