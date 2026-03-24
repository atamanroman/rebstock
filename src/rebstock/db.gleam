import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import sqlight.{type Connection}

pub type Wine {
  Wine(
    id: Int,
    winery: String,
    name: String,
    vintage: Int,
    region: String,
    country: String,
    style: String,
    avg_rating: Option(Float),
    rating_count: Option(Int),
    user_rating: Option(Float),
    user_review: String,
    personal_note: String,
    wine_type: String,
    vivino_link: String,
    in_cellar: Int,
    wishlisted: Bool,
  )
}

pub fn migrate(conn: Connection) -> Nil {
  let sql =
    "CREATE TABLE IF NOT EXISTS wines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      winery TEXT NOT NULL DEFAULT '',
      name TEXT NOT NULL DEFAULT '',
      vintage INTEGER NOT NULL DEFAULT 0,
      region TEXT NOT NULL DEFAULT '',
      country TEXT NOT NULL DEFAULT '',
      style TEXT NOT NULL DEFAULT '',
      avg_rating REAL,
      rating_count INTEGER,
      user_rating REAL,
      user_review TEXT NOT NULL DEFAULT '',
      personal_note TEXT NOT NULL DEFAULT '',
      wine_type TEXT NOT NULL DEFAULT '',
      vivino_link TEXT NOT NULL DEFAULT '',
      in_cellar INTEGER NOT NULL DEFAULT 0,
      wishlisted INTEGER NOT NULL DEFAULT 0,
      UNIQUE(winery, name, vintage, vivino_link)
    );"
  let assert Ok(Nil) = sqlight.exec(sql, conn)
  Nil
}

pub fn wine_decoder() -> decode.Decoder(Wine) {
  use id <- decode.field(0, decode.int)
  use winery <- decode.field(1, decode.string)
  use name <- decode.field(2, decode.string)
  use vintage <- decode.field(3, decode.int)
  use region <- decode.field(4, decode.string)
  use country <- decode.field(5, decode.string)
  use style <- decode.field(6, decode.string)
  use avg_rating <- decode.field(7, decode.optional(decode.float))
  use rating_count <- decode.field(8, decode.optional(decode.int))
  use user_rating <- decode.field(9, decode.optional(decode.float))
  use user_review <- decode.field(10, decode.string)
  use personal_note <- decode.field(11, decode.string)
  use wine_type <- decode.field(12, decode.string)
  use vivino_link <- decode.field(13, decode.string)
  use in_cellar <- decode.field(14, decode.int)
  use wishlisted_int <- decode.field(15, decode.int)
  decode.success(Wine(
    id:,
    winery:,
    name:,
    vintage:,
    region:,
    country:,
    style:,
    avg_rating:,
    rating_count:,
    user_rating:,
    user_review:,
    personal_note:,
    wine_type:,
    vivino_link:,
    in_cellar:,
    wishlisted: wishlisted_int != 0,
  ))
}

pub fn list_wines(conn: Connection) -> List(Wine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT id, winery, name, vintage, region, country, style,
              avg_rating, rating_count, user_rating, user_review,
              personal_note, wine_type, vivino_link, in_cellar, wishlisted
       FROM wines ORDER BY winery, name",
      on: conn,
      with: [],
      expecting: wine_decoder(),
    )
  wines
}

pub type Winery {
  Winery(name: String, wine_count: Int, country: String)
}

pub fn list_wineries(conn: Connection) -> List(Winery) {
  let decoder = {
    use name <- decode.field(0, decode.string)
    use wine_count <- decode.field(1, decode.int)
    use country <- decode.field(2, decode.string)
    decode.success(Winery(name:, wine_count:, country:))
  }
  let assert Ok(wineries) =
    sqlight.query(
      "SELECT winery, COUNT(*) as wine_count, country
       FROM wines WHERE winery != ''
       GROUP BY winery ORDER BY winery",
      on: conn,
      with: [],
      expecting: decoder,
    )
  wineries
}

pub fn wines_by_winery(conn: Connection, winery: String) -> List(Wine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT id, winery, name, vintage, region, country, style,
              avg_rating, rating_count, user_rating, user_review,
              personal_note, wine_type, vivino_link, in_cellar, wishlisted
       FROM wines WHERE winery = ? ORDER BY name, vintage",
      on: conn,
      with: [sqlight.text(winery)],
      expecting: wine_decoder(),
    )
  wines
}

pub fn get_wine(conn: Connection, id: Int) -> Result(Wine, Nil) {
  let result =
    sqlight.query(
      "SELECT id, winery, name, vintage, region, country, style,
              avg_rating, rating_count, user_rating, user_review,
              personal_note, wine_type, vivino_link, in_cellar, wishlisted
       FROM wines WHERE id = ?",
      on: conn,
      with: [sqlight.int(id)],
      expecting: wine_decoder(),
    )
  case result {
    Ok([wine]) -> Ok(wine)
    _ -> Error(Nil)
  }
}

pub fn cellar_wines(conn: Connection) -> List(Wine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT id, winery, name, vintage, region, country, style,
              avg_rating, rating_count, user_rating, user_review,
              personal_note, wine_type, vivino_link, in_cellar, wishlisted
       FROM wines WHERE in_cellar > 0 ORDER BY winery, name",
      on: conn,
      with: [],
      expecting: wine_decoder(),
    )
  wines
}

pub fn count_wines(conn: Connection) -> Int {
  let count_decoder = {
    use count <- decode.field(0, decode.int)
    decode.success(count)
  }
  let assert Ok([count]) =
    sqlight.query(
      "SELECT COUNT(*) FROM wines",
      on: conn,
      with: [],
      expecting: count_decoder,
    )
  count
}

pub fn upsert_wine(
  conn: Connection,
  winery winery: String,
  name name: String,
  vintage vintage: Int,
  region region: String,
  country country: String,
  style style: String,
  avg_rating avg_rating: Option(Float),
  rating_count rating_count: Option(Int),
  user_rating user_rating: Option(Float),
  user_review user_review: String,
  personal_note personal_note: String,
  wine_type wine_type: String,
  vivino_link vivino_link: String,
  in_cellar in_cellar: Int,
  wishlisted wishlisted: Bool,
) -> Nil {
  let sql =
    "INSERT INTO wines (winery, name, vintage, region, country, style,
                        avg_rating, rating_count, user_rating, user_review,
                        personal_note, wine_type, vivino_link, in_cellar, wishlisted)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(winery, name, vintage, vivino_link) DO UPDATE SET
       region = excluded.region,
       country = excluded.country,
       style = excluded.style,
       avg_rating = excluded.avg_rating,
       rating_count = COALESCE(excluded.rating_count, wines.rating_count),
       user_rating = COALESCE(excluded.user_rating, wines.user_rating),
       user_review = CASE WHEN excluded.user_review = '' THEN wines.user_review ELSE excluded.user_review END,
       personal_note = CASE WHEN excluded.personal_note = '' THEN wines.personal_note ELSE excluded.personal_note END,
       wine_type = excluded.wine_type,
       vivino_link = excluded.vivino_link,
       in_cellar = CASE WHEN excluded.in_cellar > wines.in_cellar THEN excluded.in_cellar ELSE wines.in_cellar END,
       wishlisted = CASE WHEN excluded.wishlisted = 1 THEN 1 ELSE wines.wishlisted END"

  let assert Ok(_) =
    sqlight.query(
      sql,
      on: conn,
      with: [
        sqlight.text(winery),
        sqlight.text(name),
        sqlight.int(vintage),
        sqlight.text(region),
        sqlight.text(country),
        sqlight.text(style),
        nullable_float(avg_rating),
        nullable_int(rating_count),
        nullable_float(user_rating),
        sqlight.text(user_review),
        sqlight.text(personal_note),
        sqlight.text(wine_type),
        sqlight.text(vivino_link),
        sqlight.int(in_cellar),
        sqlight.bool(wishlisted),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

fn nullable_int(val: Option(Int)) -> sqlight.Value {
  case val {
    Some(v) -> sqlight.int(v)
    None -> sqlight.null()
  }
}

fn nullable_float(val: Option(Float)) -> sqlight.Value {
  case val {
    Some(v) -> sqlight.float(v)
    None -> sqlight.null()
  }
}

pub fn parse_optional_int(s: String) -> Option(Int) {
  case string.trim(s) {
    "" -> None
    trimmed ->
      case int.parse(trimmed) {
        Ok(v) -> Some(v)
        Error(_) -> None
      }
  }
}

pub fn parse_int_or_zero(s: String) -> Int {
  case string.trim(s) {
    "" -> 0
    trimmed ->
      case int.parse(trimmed) {
        Ok(v) -> v
        Error(_) -> 0
      }
  }
}

pub fn parse_optional_float(s: String) -> Option(Float) {
  case string.trim(s) {
    "" -> None
    trimmed ->
      case float.parse(trimmed) {
        Ok(v) -> Some(v)
        Error(_) ->
          case int.parse(trimmed) {
            Ok(v) -> Some(int.to_float(v))
            Error(_) -> None
          }
      }
  }
}
