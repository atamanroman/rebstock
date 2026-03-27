import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri
import migrant
import sqlight.{type Connection}

pub type Wine {
  Wine(
    id: Int,
    created_by: String,
    winery_id: Int,
    winery_name: String,
    name: String,
    vintage: Option(Int),
    region: Option(String),
    country: Option(String),
    style: Option(String),
    avg_rating: Option(Float),
    rating_count: Option(Int),
    personal_note: Option(String),
    wine_type: String,
    vivino_link: Option(String),
    wishlisted: Bool,
  )
}

pub type Rating {
  Rating(
    id: Int,
    username: String,
    wine_id: Int,
    rating: Option(Float),
    tasting_notes: Option(String),
    rated_at: Option(String),
    created_at: String,
  )
}

pub type CellarEntry {
  CellarEntry(
    id: Int,
    username: String,
    wine_id: Int,
    quantity: Int,
    notes: Option(String),
    dated_at: Option(String),
    created_at: String,
  )
}

pub type Winery {
  Winery(id: Int, name: String, wine_count: Int, country: Option(String))
}

pub fn migrate(conn: Connection) -> Nil {
  let assert Ok(Nil) = sqlight.exec("PRAGMA journal_mode=WAL", conn)
  let assert Ok(Nil) = migrant.migrate(conn, "priv/migrations")
  Nil
}

// Columns: wines fields + winery name from JOIN
const wine_cols = "w.id, w.created_by, w.winery_id, wy.name, w.name, w.vintage,
        w.region, w.country, w.style, w.avg_rating, w.rating_count,
        w.personal_note, w.wine_type,
        w.vivino_link, w.wishlisted"

const wine_join = "FROM wines w JOIN wineries wy ON w.winery_id = wy.id"

fn wine_decoder() -> decode.Decoder(Wine) {
  use id <- decode.field(0, decode.int)
  use created_by <- decode.field(1, decode.string)
  use winery_id <- decode.field(2, decode.int)
  use winery_name <- decode.field(3, decode.string)
  use name <- decode.field(4, decode.string)
  use vintage <- decode.field(5, decode.optional(decode.int))
  use region <- decode.field(6, decode.optional(decode.string))
  use country <- decode.field(7, decode.optional(decode.string))
  use style <- decode.field(8, decode.optional(decode.string))
  use avg_rating <- decode.field(9, decode.optional(decode.float))
  use rating_count <- decode.field(10, decode.optional(decode.int))
  use personal_note <- decode.field(11, decode.optional(decode.string))
  use wine_type <- decode.field(12, decode.string)
  use vivino_link <- decode.field(13, decode.optional(decode.string))
  use wishlisted_int <- decode.field(14, decode.int)
  decode.success(Wine(
    id:, created_by:, winery_id:, winery_name:, name:, vintage:,
    region:, country:, style:, avg_rating:, rating_count:,
    personal_note:, wine_type:,
    vivino_link:, wishlisted: wishlisted_int != 0,
  ))
}

fn rating_decoder() -> decode.Decoder(Rating) {
  use id <- decode.field(0, decode.int)
  use username <- decode.field(1, decode.string)
  use wine_id <- decode.field(2, decode.int)
  use rating <- decode.field(3, decode.optional(decode.float))
  use tasting_notes <- decode.field(4, decode.optional(decode.string))
  use rated_at <- decode.field(5, decode.optional(decode.string))
  use created_at <- decode.field(6, decode.string)
  decode.success(Rating(id:, username:, wine_id:, rating:, tasting_notes:, rated_at:, created_at:))
}

fn cellar_entry_decoder() -> decode.Decoder(CellarEntry) {
  use id <- decode.field(0, decode.int)
  use username <- decode.field(1, decode.string)
  use wine_id <- decode.field(2, decode.int)
  use quantity <- decode.field(3, decode.int)
  use notes <- decode.field(4, decode.optional(decode.string))
  use dated_at <- decode.field(5, decode.optional(decode.string))
  use created_at <- decode.field(6, decode.string)
  decode.success(CellarEntry(id:, username:, wine_id:, quantity:, notes:, dated_at:, created_at:))
}

pub fn list_wines(conn: Connection, created_by: String) -> List(Wine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT " <> wine_cols <> " " <> wine_join
        <> " WHERE w.created_by = ? ORDER BY wy.name, w.name",
      on: conn,
      with: [sqlight.text(created_by)],
      expecting: wine_decoder(),
    )
  wines
}

pub fn get_wine_by_id(conn: Connection, id: Int) -> Result(Wine, Nil) {
  let result =
    sqlight.query(
      "SELECT " <> wine_cols <> " " <> wine_join <> " WHERE w.id = ?",
      on: conn,
      with: [sqlight.int(id)],
      expecting: wine_decoder(),
    )
  case result {
    Ok([wine]) -> Ok(wine)
    _ -> Error(Nil)
  }
}

pub fn get_wine(conn: Connection, created_by: String, id: Int) -> Result(Wine, Nil) {
  let result =
    sqlight.query(
      "SELECT " <> wine_cols <> " " <> wine_join
        <> " WHERE w.created_by = ? AND w.id = ?",
      on: conn,
      with: [sqlight.text(created_by), sqlight.int(id)],
      expecting: wine_decoder(),
    )
  case result {
    Ok([wine]) -> Ok(wine)
    _ -> Error(Nil)
  }
}

pub fn list_wineries(conn: Connection, created_by: String) -> List(Winery) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use wine_count <- decode.field(2, decode.int)
    use country <- decode.field(3, decode.optional(decode.string))
    decode.success(Winery(id:, name:, wine_count:, country:))
  }
  let assert Ok(wineries) =
    sqlight.query(
      "SELECT wy.id, wy.name, COUNT(w.id) as wine_count, wy.country
       FROM wineries wy LEFT JOIN wines w ON wy.id = w.winery_id
       WHERE wy.created_by = ?
       GROUP BY wy.id ORDER BY wy.name",
      on: conn,
      with: [sqlight.text(created_by)],
      expecting: decoder,
    )
  wineries
}

pub fn get_winery(conn: Connection, created_by: String, id: Int) -> Result(Winery, Nil) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use wine_count <- decode.field(2, decode.int)
    use country <- decode.field(3, decode.optional(decode.string))
    decode.success(Winery(id:, name:, wine_count:, country:))
  }
  let result =
    sqlight.query(
      "SELECT wy.id, wy.name, COUNT(w.id) as wine_count, wy.country
       FROM wineries wy LEFT JOIN wines w ON wy.id = w.winery_id
       WHERE wy.created_by = ? AND wy.id = ?
       GROUP BY wy.id",
      on: conn,
      with: [sqlight.text(created_by), sqlight.int(id)],
      expecting: decoder,
    )
  case result {
    Ok([winery]) -> Ok(winery)
    _ -> Error(Nil)
  }
}

pub fn wines_by_winery(conn: Connection, created_by: String, winery_id: Int) -> List(Wine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT " <> wine_cols <> " " <> wine_join
        <> " WHERE w.created_by = ? AND w.winery_id = ? ORDER BY w.name, w.vintage",
      on: conn,
      with: [sqlight.text(created_by), sqlight.int(winery_id)],
      expecting: wine_decoder(),
    )
  wines
}

pub fn wishlist_wines(conn: Connection, created_by: String) -> List(Wine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT " <> wine_cols <> " " <> wine_join
        <> " WHERE w.created_by = ? AND w.wishlisted = 1 ORDER BY wy.name, w.name",
      on: conn,
      with: [sqlight.text(created_by)],
      expecting: wine_decoder(),
    )
  wines
}

/// Wine + bottle count for cellar views
pub type CellarWine {
  CellarWine(wine: Wine, bottles: Int)
}

const cellar_wine_cols = "w.id, w.created_by, w.winery_id, wy.name, w.name, w.vintage,
        w.region, w.country, w.style, w.avg_rating, w.rating_count,
        w.personal_note, w.wine_type,
        w.vivino_link, w.wishlisted, COALESCE(SUM(c.quantity), 0) as bottles"

const cellar_wine_join = "FROM wines w
        JOIN wineries wy ON w.winery_id = wy.id
        JOIN cellar c ON c.wine_id = w.id"

fn cellar_wine_decoder() -> decode.Decoder(CellarWine) {
  use id <- decode.field(0, decode.int)
  use created_by <- decode.field(1, decode.string)
  use winery_id <- decode.field(2, decode.int)
  use winery_name <- decode.field(3, decode.string)
  use name <- decode.field(4, decode.string)
  use vintage <- decode.field(5, decode.optional(decode.int))
  use region <- decode.field(6, decode.optional(decode.string))
  use country <- decode.field(7, decode.optional(decode.string))
  use style <- decode.field(8, decode.optional(decode.string))
  use avg_rating <- decode.field(9, decode.optional(decode.float))
  use rating_count <- decode.field(10, decode.optional(decode.int))
  use personal_note <- decode.field(11, decode.optional(decode.string))
  use wine_type <- decode.field(12, decode.string)
  use vivino_link <- decode.field(13, decode.optional(decode.string))
  use wishlisted_int <- decode.field(14, decode.int)
  use bottles <- decode.field(15, decode.int)
  decode.success(CellarWine(
    wine: Wine(
      id:, created_by:, winery_id:, winery_name:, name:, vintage:,
      region:, country:, style:, avg_rating:, rating_count:,
      personal_note:, wine_type:, vivino_link:,
      wishlisted: wishlisted_int != 0,
    ),
    bottles:,
  ))
}

pub fn cellar_wines(conn: Connection, username: String) -> List(CellarWine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT " <> cellar_wine_cols <> " " <> cellar_wine_join
        <> " WHERE c.username = ?
       GROUP BY w.id HAVING bottles > 0
       ORDER BY wy.name, w.name",
      on: conn,
      with: [sqlight.text(username)],
      expecting: cellar_wine_decoder(),
    )
  wines
}

pub fn cellar_wines_by_type(conn: Connection, username: String) -> List(CellarWine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT " <> cellar_wine_cols <> " " <> cellar_wine_join
        <> " WHERE c.username = ?
       GROUP BY w.id HAVING bottles > 0
       ORDER BY w.wine_type, w.region, wy.name, w.name",
      on: conn,
      with: [sqlight.text(username)],
      expecting: cellar_wine_decoder(),
    )
  wines
}

pub fn top_cellar(conn: Connection, username: String, limit: Int) -> List(CellarWine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT " <> cellar_wine_cols <> " " <> cellar_wine_join
        <> " WHERE c.username = ?
       GROUP BY w.id HAVING bottles > 0
       ORDER BY w.avg_rating DESC, bottles DESC LIMIT ?",
      on: conn,
      with: [sqlight.text(username), sqlight.int(limit)],
      expecting: cellar_wine_decoder(),
    )
  wines
}

pub fn cellar_entries_for_wine(conn: Connection, wine_id: Int) -> List(CellarEntry) {
  let assert Ok(entries) =
    sqlight.query(
      "SELECT id, username, wine_id, quantity, notes, dated_at, created_at
       FROM cellar WHERE wine_id = ? ORDER BY created_at DESC",
      on: conn,
      with: [sqlight.int(wine_id)],
      expecting: cellar_entry_decoder(),
    )
  entries
}

pub fn cellar_bottle_count(conn: Connection, username: String, wine_id: Int) -> Int {
  let count_decoder = {
    use count <- decode.field(0, decode.int)
    decode.success(count)
  }
  let assert Ok([count]) =
    sqlight.query(
      "SELECT COALESCE(SUM(quantity), 0) FROM cellar
       WHERE username = ? AND wine_id = ?",
      on: conn,
      with: [sqlight.text(username), sqlight.int(wine_id)],
      expecting: count_decoder,
    )
  count
}

pub fn insert_cellar_entry(
  conn: Connection,
  username username: String,
  wine_id wine_id: Int,
  quantity quantity: Int,
  notes notes: Option(String),
  dated_at dated_at: Option(String),
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO cellar (username, wine_id, quantity, notes, dated_at)
       VALUES (?, ?, ?, ?, ?)",
      on: conn,
      with: [
        sqlight.text(username),
        sqlight.int(wine_id),
        sqlight.int(quantity),
        nullable_text(notes),
        nullable_text(dated_at),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn ratings_by_user(conn: Connection, username: String) -> List(Rating) {
  let assert Ok(ratings) =
    sqlight.query(
      "SELECT id, username, wine_id, rating, tasting_notes, rated_at, created_at
       FROM ratings WHERE username = ? ORDER BY rating DESC, rated_at DESC",
      on: conn,
      with: [sqlight.text(username)],
      expecting: rating_decoder(),
    )
  ratings
}

pub fn top_ratings_by_user(conn: Connection, username: String, limit: Int) -> List(Rating) {
  let assert Ok(ratings) =
    sqlight.query(
      "SELECT id, username, wine_id, rating, tasting_notes, rated_at, created_at
       FROM ratings WHERE username = ? AND rating IS NOT NULL
       ORDER BY rating DESC, rated_at DESC LIMIT ?",
      on: conn,
      with: [sqlight.text(username), sqlight.int(limit)],
      expecting: rating_decoder(),
    )
  ratings
}

pub fn latest_ratings(conn: Connection, username: String, limit: Int) -> List(Rating) {
  let assert Ok(ratings) =
    sqlight.query(
      "SELECT id, username, wine_id, rating, tasting_notes, rated_at, created_at
       FROM ratings WHERE username = ?
       ORDER BY rated_at DESC, created_at DESC LIMIT ?",
      on: conn,
      with: [sqlight.text(username), sqlight.int(limit)],
      expecting: rating_decoder(),
    )
  ratings
}

pub fn ratings_for_wine(conn: Connection, wine_id: Int) -> List(Rating) {
  let assert Ok(ratings) =
    sqlight.query(
      "SELECT id, username, wine_id, rating, tasting_notes, rated_at, created_at
       FROM ratings WHERE wine_id = ? ORDER BY rated_at DESC",
      on: conn,
      with: [sqlight.int(wine_id)],
      expecting: rating_decoder(),
    )
  ratings
}

pub fn latest_cellar_entries(conn: Connection, username: String, limit: Int) -> List(CellarEntry) {
  let assert Ok(entries) =
    sqlight.query(
      "SELECT id, username, wine_id, quantity, notes, dated_at, created_at
       FROM cellar WHERE username = ? AND quantity > 0
       ORDER BY created_at DESC LIMIT ?",
      on: conn,
      with: [sqlight.text(username), sqlight.int(limit)],
      expecting: cellar_entry_decoder(),
    )
  entries
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

fn upsert_winery(conn: Connection, created_by: String, name: String, country: Option(String)) -> Int {
  let id_decoder = {
    use id <- decode.field(0, decode.int)
    decode.success(id)
  }
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO wineries (created_by, name, country) VALUES (?, ?, ?)
       ON CONFLICT(created_by, name) DO UPDATE SET
         country = COALESCE(excluded.country, wineries.country)",
      on: conn,
      with: [sqlight.text(created_by), sqlight.text(name), nullable_text(country)],
      expecting: decode.success(Nil),
    )
  let assert Ok([id]) =
    sqlight.query(
      "SELECT id FROM wineries WHERE created_by = ? AND name = ?",
      on: conn,
      with: [sqlight.text(created_by), sqlight.text(name)],
      expecting: id_decoder,
    )
  id
}

pub fn upsert_wine(
  conn: Connection,
  created_by created_by: String,
  winery winery: String,
  name name: String,
  vintage vintage: Option(Int),
  region region: Option(String),
  country country: Option(String),
  style style: Option(String),
  avg_rating avg_rating: Option(Float),
  rating_count rating_count: Option(Int),
  personal_note personal_note: Option(String),
  wine_type wine_type: String,
  vivino_link vivino_link: Option(String),
  wishlisted wishlisted: Bool,
) -> Int {
  let winery_id = upsert_winery(conn, created_by, winery, country)

  let sql =
    "INSERT INTO wines (created_by, winery_id, name, vintage, region, country, style,
                        avg_rating, rating_count,
                        personal_note, wine_type, vivino_link, wishlisted)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(created_by, winery_id, name, vivino_link) DO UPDATE SET
       vintage = COALESCE(excluded.vintage, wines.vintage),
       region = COALESCE(excluded.region, wines.region),
       country = COALESCE(excluded.country, wines.country),
       style = COALESCE(excluded.style, wines.style),
       avg_rating = COALESCE(excluded.avg_rating, wines.avg_rating),
       rating_count = COALESCE(excluded.rating_count, wines.rating_count),
       personal_note = COALESCE(excluded.personal_note, wines.personal_note),
       wine_type = COALESCE(excluded.wine_type, wines.wine_type),
       vivino_link = COALESCE(excluded.vivino_link, wines.vivino_link),
       wishlisted = CASE WHEN excluded.wishlisted = 1 THEN 1 ELSE wines.wishlisted END
     RETURNING id"

  let id_decoder = {
    use id <- decode.field(0, decode.int)
    decode.success(id)
  }
  let assert Ok([id]) =
    sqlight.query(
      sql,
      on: conn,
      with: [
        sqlight.text(created_by),
        sqlight.int(winery_id),
        sqlight.text(name),
        nullable_int(vintage),
        nullable_text(region),
        nullable_text(country),
        nullable_text(style),
        nullable_float(avg_rating),
        nullable_int(rating_count),
        nullable_text(personal_note),
        sqlight.text(wine_type),
        nullable_text(vivino_link),
        sqlight.bool(wishlisted),
      ],
      expecting: id_decoder,
    )
  id
}

pub fn insert_rating(
  conn: Connection,
  username username: String,
  wine_id wine_id: Int,
  rating rating: Option(Float),
  tasting_notes tasting_notes: Option(String),
  rated_at rated_at: Option(String),
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO ratings (username, wine_id, rating, tasting_notes, rated_at)
       VALUES (?, ?, ?, ?, ?)",
      on: conn,
      with: [
        sqlight.text(username),
        sqlight.int(wine_id),
        nullable_float(rating),
        nullable_text(tasting_notes),
        nullable_text(rated_at),
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

fn nullable_text(val: Option(String)) -> sqlight.Value {
  case val {
    Some(v) -> sqlight.text(v)
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

pub fn parse_vintage(s: String) -> Option(Int) {
  case string.trim(s) {
    "" -> None
    trimmed ->
      case int.parse(trimmed) {
        Ok(v) -> Some(v)
        Error(_) -> None
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

pub fn optional_non_empty(s: String) -> Option(String) {
  case string.trim(s) {
    "" -> None
    trimmed -> Some(trimmed)
  }
}

pub fn slugify(text: String) -> String {
  text
  |> string.lowercase
  |> string.replace(" ", "-")
  |> string.replace("'", "")
  |> string.replace("\"", "")
  |> string.replace("&", "and")
  |> string.replace("/", "-")
  |> string.replace(",", "")
  |> string.replace(".", "")
  |> uri.percent_encode
}
