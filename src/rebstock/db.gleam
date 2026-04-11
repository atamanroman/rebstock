import gleam/dynamic/decode
import gleam/erlang/application
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri
import migrant
import sqlight.{type Connection}

import rebstock/ulid

pub type WineType {
  Red
  White
  Rose
  Orange
  Sparkling
  Dessert
  Sake
  Other
}

pub type ListType {
  CellarList
  RatedList
  WishlistList
  CustomList
}

pub type WineList {
  WineList(
    id: String,
    username: String,
    name: String,
    description: Option(String),
    slug: String,
    list_type: ListType,
    public: Bool,
    show_bottles: Bool,
    created_at: String,
  )
}

pub fn wine_type_to_string(wt: WineType) -> String {
  case wt {
    Red -> "RED"
    White -> "WHITE"
    Rose -> "ROSE"
    Orange -> "ORANGE"
    Sparkling -> "SPARKLING"
    Dessert -> "DESSERT"
    Sake -> "SAKE"
    Other -> "OTHER"
  }
}

pub const all_wine_types = [
  Red,
  White,
  Rose,
  Orange,
  Sparkling,
  Dessert,
  Sake,
  Other,
]

pub fn wine_type_from_string(s: String) -> WineType {
  case string.uppercase(s) {
    "RED" | "RED WINE" -> Red
    "WHITE" | "WHITE WINE" -> White
    "ROSE" | "ROSÉ" | "ROSÉ WINE" -> Rose
    "ORANGE" -> Orange
    "SPARKLING" -> Sparkling
    "DESSERT" | "DESSERT WINE" -> Dessert
    "SAKE" -> Sake
    _ -> Other
  }
}

pub fn wine_type_label(wt: WineType) -> String {
  case wt {
    Red -> "Red"
    White -> "White"
    Rose -> "Rosé"
    Orange -> "Orange"
    Sparkling -> "Sparkling"
    Dessert -> "Dessert"
    Sake -> "Sake"
    Other -> "Other"
  }
}

pub fn list_type_to_string(lt: ListType) -> String {
  case lt {
    CellarList -> "cellar"
    RatedList -> "rated"
    WishlistList -> "wishlist"
    CustomList -> "custom"
  }
}

pub fn list_type_from_string(s: String) -> ListType {
  case s {
    "cellar" -> CellarList
    "rated" -> RatedList
    "wishlist" -> WishlistList
    _ -> CustomList
  }
}

pub type Wine {
  Wine(
    id: String,
    created_by: String,
    winery_id: String,
    winery_name: String,
    name: String,
    vintages: Option(String),
    region: Option(String),
    country: Option(String),
    style: Option(String),
    personal_note: Option(String),
    wine_type: WineType,
    vivino_id: Option(String),
  )
}

pub type Rating {
  Rating(
    id: String,
    username: String,
    wine_id: String,
    vintage: Option(String),
    rating: Option(Float),
    tasting_notes: Option(String),
    rated_at: Option(String),
    source: String,
    created_at: String,
  )
}

pub type CellarEntry {
  CellarEntry(
    id: String,
    username: String,
    wine_id: String,
    vintage: Option(String),
    quantity: Int,
    notes: Option(String),
    date: Option(String),
    parent_id: Option(String),
    created_at: String,
  )
}

pub type Winery {
  Winery(
    id: String,
    name: String,
    wine_count: Int,
    country: Option(String),
    vivino_id: Option(String),
  )
}

pub fn migrate(conn: Connection) -> Nil {
  let assert Ok(Nil) = sqlight.exec("PRAGMA journal_mode=WAL", conn)
  let assert Ok(Nil) = sqlight.exec("PRAGMA foreign_keys=ON", conn)
  let assert Ok(priv) = application.priv_directory("rebstock")
  let assert Ok(Nil) = migrant.migrate(conn, priv <> "/migrations")
  Nil
}

// Columns: wines fields + winery name from JOIN + vintages subquery
const wine_cols = "w.id, w.created_by, w.winery_id, wy.name, w.name,
        (SELECT GROUP_CONCAT(v.year) FROM wines_vintages v WHERE v.wine_id = w.id ORDER BY v.year) AS vintages,
        w.region, w.country, w.style,
        w.personal_note, w.wine_type,
        w.vivino_id"

const wine_join = "FROM wines w JOIN wineries wy ON w.winery_id = wy.id"

fn wine_decoder() -> decode.Decoder(Wine) {
  use id <- decode.field(0, decode.string)
  use created_by <- decode.field(1, decode.string)
  use winery_id <- decode.field(2, decode.string)
  use winery_name <- decode.field(3, decode.string)
  use name <- decode.field(4, decode.string)
  use vintages <- decode.field(5, decode.optional(decode.string))
  use region <- decode.field(6, decode.optional(decode.string))
  use country <- decode.field(7, decode.optional(decode.string))
  use style <- decode.field(8, decode.optional(decode.string))
  use personal_note <- decode.field(9, decode.optional(decode.string))
  use wine_type_str <- decode.field(10, decode.string)
  use vivino_id <- decode.field(11, decode.optional(decode.string))
  decode.success(Wine(
    id:,
    created_by:,
    winery_id:,
    winery_name:,
    name:,
    vintages:,
    region:,
    country:,
    style:,
    personal_note:,
    wine_type: wine_type_from_string(wine_type_str),
    vivino_id:,
  ))
}

fn rating_decoder() -> decode.Decoder(Rating) {
  use id <- decode.field(0, decode.string)
  use username <- decode.field(1, decode.string)
  use wine_id <- decode.field(2, decode.string)
  use vintage <- decode.field(3, decode.optional(decode.string))
  use rating <- decode.field(4, decode.optional(decode.float))
  use tasting_notes <- decode.field(5, decode.optional(decode.string))
  use rated_at <- decode.field(6, decode.optional(decode.string))
  use source <- decode.field(7, decode.string)
  use created_at <- decode.field(8, decode.string)
  decode.success(Rating(
    id:,
    username:,
    wine_id:,
    vintage:,
    rating:,
    tasting_notes:,
    rated_at:,
    source:,
    created_at:,
  ))
}

fn cellar_entry_decoder() -> decode.Decoder(CellarEntry) {
  use id <- decode.field(0, decode.string)
  use username <- decode.field(1, decode.string)
  use wine_id <- decode.field(2, decode.string)
  use vintage <- decode.field(3, decode.optional(decode.string))
  use quantity <- decode.field(4, decode.int)
  use notes <- decode.field(5, decode.optional(decode.string))
  use date <- decode.field(6, decode.optional(decode.string))
  use parent_id <- decode.field(7, decode.optional(decode.string))
  use created_at <- decode.field(8, decode.string)
  decode.success(CellarEntry(
    id:,
    username:,
    wine_id:,
    vintage:,
    quantity:,
    notes:,
    date:,
    parent_id:,
    created_at:,
  ))
}

pub fn ensure_user(conn: Connection, username: String) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "INSERT OR IGNORE INTO users (username) VALUES (?)",
      on: conn,
      with: [sqlight.text(username)],
      expecting: decode.success(Nil),
    )
  Nil
}

fn list_decoder() -> decode.Decoder(WineList) {
  use id <- decode.field(0, decode.string)
  use username <- decode.field(1, decode.string)
  use name <- decode.field(2, decode.string)
  use description <- decode.field(3, decode.optional(decode.string))
  use slug <- decode.field(4, decode.string)
  use list_type_str <- decode.field(5, decode.string)
  use public_int <- decode.field(6, decode.int)
  use show_bottles_int <- decode.field(7, decode.int)
  use created_at <- decode.field(8, decode.string)
  decode.success(WineList(
    id:,
    username:,
    name:,
    description:,
    slug:,
    list_type: list_type_from_string(list_type_str),
    public: public_int == 1,
    show_bottles: show_bottles_int == 1,
    created_at:,
  ))
}

pub fn ensure_system_lists(conn: Connection, username: String) -> Nil {
  let system = [
    #("Cellar", "cellar", "cellar", True),
    #("Rated", "rated", "rated", False),
    #("Wishlist", "wishlist", "wishlist", False),
  ]
  list.each(system, fn(item) {
    let #(name, slug, list_type, show_bottles) = item
    let assert Ok(_) =
      sqlight.query(
        "INSERT OR IGNORE INTO lists (id, username, name, slug, list_type, show_bottles)
         VALUES (?, ?, ?, ?, ?, ?)",
        on: conn,
        with: [
          sqlight.text(ulid.generate()),
          sqlight.text(username),
          sqlight.text(name),
          sqlight.text(slug),
          sqlight.text(list_type),
          sqlight.int(case show_bottles {
            True -> 1
            False -> 0
          }),
        ],
        expecting: decode.success(Nil),
      )
    Nil
  })
}

pub fn get_list(conn: Connection, id: String) -> Result(WineList, Nil) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT id, username, name, description, slug, list_type, public, show_bottles, created_at
       FROM lists WHERE id = ?",
      on: conn,
      with: [sqlight.text(id)],
      expecting: list_decoder(),
    )
  case rows {
    [row] -> Ok(row)
    _ -> Error(Nil)
  }
}

pub fn get_list_by_slug(
  conn: Connection,
  username: String,
  slug: String,
) -> Result(WineList, Nil) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT id, username, name, description, slug, list_type, public, show_bottles, created_at
       FROM lists WHERE username = ? AND slug = ?",
      on: conn,
      with: [sqlight.text(username), sqlight.text(slug)],
      expecting: list_decoder(),
    )
  case rows {
    [row] -> Ok(row)
    _ -> Error(Nil)
  }
}

pub fn lists_for_user(conn: Connection, username: String) -> List(WineList) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT id, username, name, description, slug, list_type, public, show_bottles, created_at
       FROM lists WHERE username = ?
       ORDER BY CASE list_type
         WHEN 'cellar' THEN 1
         WHEN 'rated' THEN 2
         WHEN 'wishlist' THEN 3
         ELSE 4
       END, name",
      on: conn,
      with: [sqlight.text(username)],
      expecting: list_decoder(),
    )
  rows
}

pub fn create_list(
  conn: Connection,
  username: String,
  name: String,
  description: Option(String),
  show_bottles: Bool,
) -> String {
  let id = ulid.generate()
  let slug = slugify(name)
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO lists (id, username, name, description, slug, list_type, show_bottles)
       VALUES (?, ?, ?, ?, ?, 'custom', ?)",
      on: conn,
      with: [
        sqlight.text(id),
        sqlight.text(username),
        sqlight.text(name),
        nullable_text(description),
        sqlight.text(slug),
        sqlight.int(case show_bottles {
          True -> 1
          False -> 0
        }),
      ],
      expecting: decode.success(Nil),
    )
  id
}

pub fn update_list(
  conn: Connection,
  id: String,
  name: String,
  description: Option(String),
  show_bottles: Bool,
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "UPDATE lists SET name = ?, description = ?, slug = ?, show_bottles = ?
       WHERE id = ? AND list_type = 'custom'",
      on: conn,
      with: [
        sqlight.text(name),
        nullable_text(description),
        sqlight.text(slugify(name)),
        sqlight.int(case show_bottles {
          True -> 1
          False -> 0
        }),
        sqlight.text(id),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn delete_list(conn: Connection, id: String) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "DELETE FROM lists WHERE id = ? AND list_type = 'custom'",
      on: conn,
      with: [sqlight.text(id)],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn set_list_public(conn: Connection, id: String, public: Bool) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "UPDATE lists SET public = ? WHERE id = ?",
      on: conn,
      with: [
        sqlight.int(case public {
          True -> 1
          False -> 0
        }),
        sqlight.text(id),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn set_list_show_bottles(
  conn: Connection,
  id: String,
  show_bottles: Bool,
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "UPDATE lists SET show_bottles = ? WHERE id = ?",
      on: conn,
      with: [
        sqlight.int(case show_bottles {
          True -> 1
          False -> 0
        }),
        sqlight.text(id),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn bottle_counts_for_user(
  conn: Connection,
  username: String,
) -> List(#(String, Int)) {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT wine_id, COALESCE(SUM(quantity), 0)
       FROM cellar WHERE username = ?
       GROUP BY wine_id HAVING COALESCE(SUM(quantity), 0) > 0",
      on: conn,
      with: [sqlight.text(username)],
      expecting: {
        use wine_id <- decode.field(0, decode.string)
        use count <- decode.field(1, decode.int)
        decode.success(#(wine_id, count))
      },
    )
  rows
}

pub type ListWine {
  ListWine(wine: Wine, vintage: Option(String), notes: Option(String))
}

pub fn list_wines_for_list(conn: Connection, list_id: String) -> List(ListWine) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use created_by <- decode.field(1, decode.string)
    use winery_id <- decode.field(2, decode.string)
    use winery_name <- decode.field(3, decode.string)
    use name <- decode.field(4, decode.string)
    use vintages <- decode.field(5, decode.optional(decode.string))
    use region <- decode.field(6, decode.optional(decode.string))
    use country <- decode.field(7, decode.optional(decode.string))
    use style <- decode.field(8, decode.optional(decode.string))
    use personal_note <- decode.field(9, decode.optional(decode.string))
    use wine_type_str <- decode.field(10, decode.string)
    use vivino_id <- decode.field(11, decode.optional(decode.string))
    use vintage <- decode.field(12, decode.optional(decode.string))
    use notes <- decode.field(13, decode.optional(decode.string))
    decode.success(ListWine(
      wine: Wine(
        id:,
        created_by:,
        winery_id:,
        winery_name:,
        name:,
        vintages:,
        region:,
        country:,
        style:,
        personal_note:,
        wine_type: wine_type_from_string(wine_type_str),
        vivino_id:,
      ),
      vintage:,
      notes:,
    ))
  }
  let assert Ok(wines) =
    sqlight.query(
      "SELECT " <> wine_cols <> ", NULLIF(lw.vintage, '') as vintage, lw.notes
       " <> wine_join <> "
       JOIN lists_wines lw ON lw.wine_id = w.id
       WHERE lw.list_id = ?
       ORDER BY w.wine_type, w.region, wy.name, w.name",
      on: conn,
      with: [sqlight.text(list_id)],
      expecting: decoder,
    )
  wines
}

pub fn add_wine_to_list(
  conn: Connection,
  list_id: String,
  wine_id: String,
  vintage: Option(String),
  notes: Option(String),
) -> Nil {
  let vintage_str = option.unwrap(vintage, "")
  let assert Ok(_) =
    sqlight.query(
      "INSERT OR IGNORE INTO lists_wines (list_id, wine_id, vintage, notes)
       VALUES (?, ?, ?, ?)",
      on: conn,
      with: [
        sqlight.text(list_id),
        sqlight.text(wine_id),
        sqlight.text(vintage_str),
        nullable_text(notes),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn remove_wine_from_list(
  conn: Connection,
  list_id: String,
  wine_id: String,
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "DELETE FROM lists_wines WHERE list_id = ? AND wine_id = ?",
      on: conn,
      with: [sqlight.text(list_id), sqlight.text(wine_id)],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn count_list_wines(conn: Connection, list_id: String) -> Int {
  let count_decoder = {
    use count <- decode.field(0, decode.int)
    decode.success(count)
  }
  let assert Ok([count]) =
    sqlight.query(
      "SELECT COUNT(*) FROM lists_wines WHERE list_id = ?",
      on: conn,
      with: [sqlight.text(list_id)],
      expecting: count_decoder,
    )
  count
}

pub fn is_wine_in_list(
  conn: Connection,
  list_id: String,
  wine_id: String,
) -> Bool {
  let count_decoder = {
    use count <- decode.field(0, decode.int)
    decode.success(count)
  }
  let assert Ok([count]) =
    sqlight.query(
      "SELECT COUNT(*) FROM lists_wines WHERE list_id = ? AND wine_id = ?",
      on: conn,
      with: [sqlight.text(list_id), sqlight.text(wine_id)],
      expecting: count_decoder,
    )
  count > 0
}

pub fn get_user_wishlist(conn: Connection, username: String) -> WineList {
  ensure_system_lists(conn, username)
  let assert Ok(wl) = get_list_by_slug(conn, username, "wishlist")
  wl
}

pub fn list_wines(conn: Connection, created_by: String) -> List(Wine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT "
        <> wine_cols
        <> " "
        <> wine_join
        <> " WHERE w.created_by = ? ORDER BY wy.name, w.name",
      on: conn,
      with: [sqlight.text(created_by)],
      expecting: wine_decoder(),
    )
  wines
}

pub fn get_wine_by_id(conn: Connection, id: String) -> Result(Wine, Nil) {
  let result =
    sqlight.query(
      "SELECT " <> wine_cols <> " " <> wine_join <> " WHERE w.id = ?",
      on: conn,
      with: [sqlight.text(id)],
      expecting: wine_decoder(),
    )
  case result {
    Ok([wine]) -> Ok(wine)
    _ -> Error(Nil)
  }
}

pub fn get_wine(
  conn: Connection,
  created_by: String,
  id: String,
) -> Result(Wine, Nil) {
  let result =
    sqlight.query(
      "SELECT "
        <> wine_cols
        <> " "
        <> wine_join
        <> " WHERE w.created_by = ? AND w.id = ?",
      on: conn,
      with: [sqlight.text(created_by), sqlight.text(id)],
      expecting: wine_decoder(),
    )
  case result {
    Ok([wine]) -> Ok(wine)
    _ -> Error(Nil)
  }
}

pub fn list_wineries(conn: Connection) -> List(Winery) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use name <- decode.field(1, decode.string)
    use wine_count <- decode.field(2, decode.int)
    use country <- decode.field(3, decode.optional(decode.string))
    use vivino_id <- decode.field(4, decode.optional(decode.string))
    decode.success(Winery(id:, name:, wine_count:, country:, vivino_id:))
  }
  let assert Ok(wineries) =
    sqlight.query(
      "SELECT wy.id, wy.name, COUNT(w.id) as wine_count, wy.country, wy.vivino_id
       FROM wineries wy LEFT JOIN wines w ON wy.id = w.winery_id
       GROUP BY wy.id ORDER BY wy.name",
      on: conn,
      with: [],
      expecting: decoder,
    )
  wineries
}

pub fn get_winery(conn: Connection, id: String) -> Result(Winery, Nil) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use name <- decode.field(1, decode.string)
    use wine_count <- decode.field(2, decode.int)
    use country <- decode.field(3, decode.optional(decode.string))
    use vivino_id <- decode.field(4, decode.optional(decode.string))
    decode.success(Winery(id:, name:, wine_count:, country:, vivino_id:))
  }
  let result =
    sqlight.query(
      "SELECT wy.id, wy.name, COUNT(w.id) as wine_count, wy.country, wy.vivino_id
       FROM wineries wy LEFT JOIN wines w ON wy.id = w.winery_id
       WHERE wy.id = ?
       GROUP BY wy.id",
      on: conn,
      with: [sqlight.text(id)],
      expecting: decoder,
    )
  case result {
    Ok([winery]) -> Ok(winery)
    _ -> Error(Nil)
  }
}

pub fn wines_by_winery(
  conn: Connection,
  created_by: String,
  winery_id: String,
) -> List(Wine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT "
        <> wine_cols
        <> " "
        <> wine_join
        <> " WHERE w.created_by = ? AND w.winery_id = ? ORDER BY w.name",
      on: conn,
      with: [sqlight.text(created_by), sqlight.text(winery_id)],
      expecting: wine_decoder(),
    )
  wines
}

/// Wine + vintage + bottle count for cellar views
pub type CellarWine {
  CellarWine(wine: Wine, vintage: Option(String), bottles: Int)
}

const cellar_wine_cols = "w.id, w.created_by, w.winery_id, wy.name, w.name,
        (SELECT GROUP_CONCAT(v.year) FROM wines_vintages v WHERE v.wine_id = w.id ORDER BY v.year) AS vintages,
        w.region, w.country, w.style,
        w.personal_note, w.wine_type,
        w.vivino_id, c.vintage, COALESCE(SUM(c.quantity), 0) AS bottles"

const cellar_wine_join = "FROM wines w
        JOIN wineries wy ON w.winery_id = wy.id
        JOIN cellar c ON c.wine_id = w.id"

fn cellar_wine_decoder() -> decode.Decoder(CellarWine) {
  use id <- decode.field(0, decode.string)
  use created_by <- decode.field(1, decode.string)
  use winery_id <- decode.field(2, decode.string)
  use winery_name <- decode.field(3, decode.string)
  use name <- decode.field(4, decode.string)
  use vintages <- decode.field(5, decode.optional(decode.string))
  use region <- decode.field(6, decode.optional(decode.string))
  use country <- decode.field(7, decode.optional(decode.string))
  use style <- decode.field(8, decode.optional(decode.string))
  use personal_note <- decode.field(9, decode.optional(decode.string))
  use wine_type_str <- decode.field(10, decode.string)
  use vivino_id <- decode.field(11, decode.optional(decode.string))
  use vintage <- decode.field(12, decode.optional(decode.string))
  use bottles <- decode.field(13, decode.int)
  decode.success(CellarWine(
    wine: Wine(
      id:,
      created_by:,
      winery_id:,
      winery_name:,
      name:,
      vintages:,
      region:,
      country:,
      style:,
      personal_note:,
      wine_type: wine_type_from_string(wine_type_str),
      vivino_id:,
    ),
    vintage:,
    bottles:,
  ))
}

pub fn cellar_wines(conn: Connection, username: String) -> List(CellarWine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT "
        <> cellar_wine_cols
        <> " "
        <> cellar_wine_join
        <> " WHERE c.username = ?
       GROUP BY w.id, c.vintage HAVING bottles > 0
       ORDER BY wy.name, w.name",
      on: conn,
      with: [sqlight.text(username)],
      expecting: cellar_wine_decoder(),
    )
  wines
}

pub fn cellar_wines_by_type(
  conn: Connection,
  username: String,
) -> List(CellarWine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT "
        <> cellar_wine_cols
        <> " "
        <> cellar_wine_join
        <> " WHERE c.username = ?
       GROUP BY w.id, c.vintage HAVING bottles > 0
       ORDER BY w.wine_type, w.region, wy.name, w.name",
      on: conn,
      with: [sqlight.text(username)],
      expecting: cellar_wine_decoder(),
    )
  wines
}

pub fn top_cellar(
  conn: Connection,
  username: String,
  limit: Int,
) -> List(CellarWine) {
  let assert Ok(wines) =
    sqlight.query(
      "SELECT "
        <> cellar_wine_cols
        <> " "
        <> cellar_wine_join
        <> " WHERE c.username = ?
       GROUP BY w.id, c.vintage HAVING bottles > 0
       ORDER BY (SELECT AVG(r.rating) FROM ratings r WHERE r.wine_id = w.id AND r.source = 'vivino') DESC, bottles DESC LIMIT ?",
      on: conn,
      with: [sqlight.text(username), sqlight.int(limit)],
      expecting: cellar_wine_decoder(),
    )
  wines
}

pub fn cellar_entries_for_wine(
  conn: Connection,
  wine_id: String,
) -> List(CellarEntry) {
  let assert Ok(entries) =
    sqlight.query(
      "SELECT c.id, c.username, c.wine_id, c.vintage, c.quantity, c.notes, c.date, c.parent_id, c.created_at
       FROM cellar c WHERE c.wine_id = ? ORDER BY c.created_at DESC",
      on: conn,
      with: [sqlight.text(wine_id)],
      expecting: cellar_entry_decoder(),
    )
  entries
}

pub fn cellar_bottle_count(
  conn: Connection,
  username: String,
  wine_id: String,
) -> Int {
  let count_decoder = {
    use count <- decode.field(0, decode.int)
    decode.success(count)
  }
  let assert Ok([count]) =
    sqlight.query(
      "SELECT COALESCE(SUM(quantity), 0) FROM cellar
       WHERE username = ? AND wine_id = ?",
      on: conn,
      with: [sqlight.text(username), sqlight.text(wine_id)],
      expecting: count_decoder,
    )
  count
}

pub fn get_cellar_entry_by_id(
  conn: Connection,
  id: String,
) -> Result(CellarEntry, Nil) {
  let result =
    sqlight.query(
      "SELECT c.id, c.username, c.wine_id, c.vintage, c.quantity, c.notes, c.date, c.parent_id, c.created_at
       FROM cellar c WHERE c.id = ?",
      on: conn,
      with: [sqlight.text(id)],
      expecting: cellar_entry_decoder(),
    )
  case result {
    Ok([entry]) -> Ok(entry)
    _ -> Error(Nil)
  }
}

pub fn insert_cellar_entry(
  conn: Connection,
  username username: String,
  wine_id wine_id: String,
  vintage vintage: Option(String),
  quantity quantity: Int,
  notes notes: Option(String),
  date date: Option(String),
) -> Nil {
  let id = ulid.generate()
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO cellar (id, username, wine_id, vintage, quantity, notes, date)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      on: conn,
      with: [
        sqlight.text(id),
        sqlight.text(username),
        sqlight.text(wine_id),
        nullable_text(vintage),
        sqlight.int(quantity),
        nullable_text(notes),
        nullable_text(date),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn insert_cellar_drink(
  conn: Connection,
  parent_id parent_id: String,
  username username: String,
  wine_id wine_id: String,
  vintage vintage: Option(String),
  notes notes: Option(String),
  date date: Option(String),
) -> Nil {
  let id = ulid.generate()
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO cellar (id, username, wine_id, vintage, quantity, notes, date, parent_id)
       VALUES (?, ?, ?, ?, -1, ?, ?, ?)",
      on: conn,
      with: [
        sqlight.text(id),
        sqlight.text(username),
        sqlight.text(wine_id),
        nullable_text(vintage),
        nullable_text(notes),
        nullable_text(date),
        sqlight.text(parent_id),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn update_cellar_entry(
  conn: Connection,
  id id: String,
  vintage vintage: Option(String),
  quantity quantity: Int,
  notes notes: Option(String),
  date date: Option(String),
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "UPDATE cellar SET vintage = ?, quantity = ?, notes = ?, date = ?
       WHERE id = ?",
      on: conn,
      with: [
        nullable_text(vintage),
        sqlight.int(quantity),
        nullable_text(notes),
        nullable_text(date),
        sqlight.text(id),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn delete_cellar_entry(conn: Connection, id: String) -> Nil {
  // Delete children (drink events) first, then the entry itself
  let assert Ok(_) =
    sqlight.query(
      "DELETE FROM cellar WHERE parent_id = ?",
      on: conn,
      with: [sqlight.text(id)],
      expecting: decode.success(Nil),
    )
  let assert Ok(_) =
    sqlight.query(
      "DELETE FROM cellar WHERE id = ?",
      on: conn,
      with: [sqlight.text(id)],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn ratings_by_user(conn: Connection, username: String) -> List(Rating) {
  let assert Ok(ratings) =
    sqlight.query(
      "SELECT r.id, r.username, r.wine_id, r.vintage, r.rating, r.tasting_notes, r.rated_at, r.source, r.created_at
       FROM ratings r
       WHERE r.username = ? AND r.source = 'user' ORDER BY r.rating DESC, r.rated_at DESC",
      on: conn,
      with: [sqlight.text(username)],
      expecting: rating_decoder(),
    )
  ratings
}

pub fn top_ratings_by_user(
  conn: Connection,
  username: String,
  limit: Int,
) -> List(Rating) {
  let assert Ok(ratings) =
    sqlight.query(
      "SELECT r.id, r.username, r.wine_id, r.vintage, r.rating, r.tasting_notes, r.rated_at, r.source, r.created_at
       FROM ratings r
       WHERE r.username = ? AND r.source = 'user' AND r.rating IS NOT NULL
       ORDER BY r.rating DESC, r.rated_at DESC LIMIT ?",
      on: conn,
      with: [sqlight.text(username), sqlight.int(limit)],
      expecting: rating_decoder(),
    )
  ratings
}

pub fn latest_ratings(
  conn: Connection,
  username: String,
  limit: Int,
) -> List(Rating) {
  let assert Ok(ratings) =
    sqlight.query(
      "SELECT r.id, r.username, r.wine_id, r.vintage, r.rating, r.tasting_notes, r.rated_at, r.source, r.created_at
       FROM ratings r
       WHERE r.username = ? AND r.source = 'user'
       ORDER BY r.rated_at DESC, r.created_at DESC LIMIT ?",
      on: conn,
      with: [sqlight.text(username), sqlight.int(limit)],
      expecting: rating_decoder(),
    )
  ratings
}

pub fn rated_wines(conn: Connection, username: String) -> List(Wine) {
  let assert Ok(wines) = sqlight.query("SELECT DISTINCT " <> wine_cols <> "
       " <> wine_join <> "
       JOIN ratings r ON r.wine_id = w.id AND r.username = ?
       ORDER BY w.wine_type, w.region, wy.name, w.name", on: conn, with: [
      sqlight.text(username),
    ], expecting: wine_decoder())
  wines
}

pub fn get_rating_by_id(conn: Connection, id: String) -> Result(Rating, Nil) {
  let result =
    sqlight.query(
      "SELECT r.id, r.username, r.wine_id, r.vintage, r.rating, r.tasting_notes, r.rated_at, r.source, r.created_at
       FROM ratings r
       WHERE r.id = ?",
      on: conn,
      with: [sqlight.text(id)],
      expecting: rating_decoder(),
    )
  case result {
    Ok([rating]) -> Ok(rating)
    _ -> Error(Nil)
  }
}

pub fn ratings_for_wine(conn: Connection, wine_id: String) -> List(Rating) {
  let assert Ok(ratings) =
    sqlight.query(
      "SELECT r.id, r.username, r.wine_id, r.vintage, r.rating, r.tasting_notes, r.rated_at, r.source, r.created_at
       FROM ratings r
       WHERE r.wine_id = ? ORDER BY r.source, r.rated_at DESC",
      on: conn,
      with: [sqlight.text(wine_id)],
      expecting: rating_decoder(),
    )
  ratings
}

pub fn latest_cellar_entries(
  conn: Connection,
  username: String,
  limit: Int,
) -> List(CellarEntry) {
  let assert Ok(entries) =
    sqlight.query(
      "SELECT c.id, c.username, c.wine_id, c.vintage, c.quantity, c.notes, c.date, c.parent_id, c.created_at
       FROM cellar c WHERE c.username = ?
       ORDER BY c.created_at DESC LIMIT ?",
      on: conn,
      with: [sqlight.text(username), sqlight.int(limit)],
      expecting: cellar_entry_decoder(),
    )
  entries
}

pub fn vivino_rating(conn: Connection, wine_id: String) -> Option(Float) {
  let decoder = {
    use rating <- decode.field(0, decode.optional(decode.float))
    decode.success(rating)
  }
  let assert Ok([rating]) =
    sqlight.query(
      "SELECT AVG(rating) FROM ratings WHERE wine_id = ? AND source = 'vivino'",
      on: conn,
      with: [sqlight.text(wine_id)],
      expecting: decoder,
    )
  rating
}

pub fn count_wines(conn: Connection) -> Int {
  count_query(conn, "SELECT COUNT(*) FROM wines", [])
}

pub fn count_wineries(conn: Connection) -> Int {
  count_query(conn, "SELECT COUNT(DISTINCT id) FROM wineries", [])
}

pub fn count_users(conn: Connection) -> Int {
  count_query(conn, "SELECT COUNT(*) FROM users", [])
}

/// Number of distinct wines the user has rated
pub fn count_rated_wines(conn: Connection, username: String) -> Int {
  count_query(
    conn,
    "SELECT COUNT(DISTINCT wine_id) FROM ratings WHERE username = ? AND source = 'user'",
    [sqlight.text(username)],
  )
}

/// Number of distinct wineries the user has tasted from (via ratings)
pub fn count_rated_wineries(conn: Connection, username: String) -> Int {
  count_query(
    conn,
    "SELECT COUNT(DISTINCT w.winery_id) FROM ratings r JOIN wines w ON w.id = r.wine_id WHERE r.username = ? AND r.source = 'user'",
    [sqlight.text(username)],
  )
}

/// Number of distinct wines in cellar (with bottles > 0)
pub fn count_cellar_wines(conn: Connection, username: String) -> Int {
  count_query(
    conn,
    "SELECT COUNT(*) FROM (SELECT wine_id FROM cellar WHERE username = ? GROUP BY wine_id HAVING SUM(quantity) > 0)",
    [sqlight.text(username)],
  )
}

/// Number of distinct wineries in cellar
pub fn count_cellar_wineries(conn: Connection, username: String) -> Int {
  count_query(
    conn,
    "SELECT COUNT(*) FROM (SELECT DISTINCT w.winery_id FROM cellar c JOIN wines w ON w.id = c.wine_id WHERE c.username = ? GROUP BY c.wine_id HAVING SUM(c.quantity) > 0)",
    [sqlight.text(username)],
  )
}

/// Rating distribution: count of ratings per integer bucket (1-5)
pub fn rating_distribution(
  conn: Connection,
  username: String,
) -> List(#(Int, Int)) {
  let decoder = {
    use bucket <- decode.field(0, decode.int)
    use count <- decode.field(1, decode.int)
    decode.success(#(bucket, count))
  }
  let assert Ok(rows) =
    sqlight.query(
      "SELECT CAST(rating AS INTEGER) AS bucket, COUNT(*) FROM ratings WHERE username = ? AND source = 'user' AND rating IS NOT NULL GROUP BY bucket ORDER BY bucket",
      on: conn,
      with: [sqlight.text(username)],
      expecting: decoder,
    )
  rows
}

fn count_query(
  conn: Connection,
  sql: String,
  params: List(sqlight.Value),
) -> Int {
  let count_decoder = {
    use count <- decode.field(0, decode.int)
    decode.success(count)
  }
  let assert Ok([count]) =
    sqlight.query(sql, on: conn, with: params, expecting: count_decoder)
  count
}

pub fn upsert_vintage(conn: Connection, wine_id: String, year: String) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "INSERT OR IGNORE INTO wines_vintages (wine_id, year) VALUES (?, ?)",
      on: conn,
      with: [sqlight.text(wine_id), sqlight.text(year)],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn vintages_for_wine(conn: Connection, wine_id: String) -> List(String) {
  let decoder = {
    use year <- decode.field(0, decode.string)
    decode.success(year)
  }
  let assert Ok(vintages) =
    sqlight.query(
      "SELECT year FROM wines_vintages WHERE wine_id = ? ORDER BY year",
      on: conn,
      with: [sqlight.text(wine_id)],
      expecting: decoder,
    )
  vintages
}

pub fn all_winery_names(conn: Connection) -> List(String) {
  let decoder = {
    use name <- decode.field(0, decode.string)
    decode.success(name)
  }
  let assert Ok(names) =
    sqlight.query(
      "SELECT name FROM wineries ORDER BY name",
      on: conn,
      with: [],
      expecting: decoder,
    )
  names
}

pub fn update_winery(
  conn: Connection,
  id: String,
  name: String,
  country: Option(String),
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "UPDATE wineries SET name = ?, country = ? WHERE id = ?",
      on: conn,
      with: [sqlight.text(name), nullable_text(country), sqlight.text(id)],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn update_wine(
  conn: Connection,
  id: String,
  name: String,
  winery: String,
  created_by: String,
  region: Option(String),
  country: Option(String),
  style: Option(String),
  personal_note: Option(String),
  wine_type: WineType,
) -> Nil {
  let winery_id = upsert_winery(conn, created_by, winery, country, None)
  let assert Ok(_) =
    sqlight.query(
      "UPDATE wines SET name = ?, winery_id = ?, region = ?, country = ?,
       style = ?, personal_note = ?, wine_type = ? WHERE id = ?",
      on: conn,
      with: [
        sqlight.text(name),
        sqlight.text(winery_id),
        nullable_text(region),
        nullable_text(country),
        nullable_text(style),
        nullable_text(personal_note),
        sqlight.text(wine_type_to_string(wine_type)),
        sqlight.text(id),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn upsert_winery(
  conn: Connection,
  created_by: String,
  name: String,
  country: Option(String),
  vivino_id: Option(String),
) -> String {
  let id_decoder = {
    use id <- decode.field(0, decode.string)
    decode.success(id)
  }
  // Check if winery exists (global, not per-user)
  let result =
    sqlight.query(
      "SELECT id FROM wineries WHERE name = ?",
      on: conn,
      with: [sqlight.text(name)],
      expecting: id_decoder,
    )
  case result {
    Ok([id]) -> {
      // Update fields if provided
      let assert Ok(_) =
        sqlight.query(
          "UPDATE wineries SET
             country = COALESCE(?, wineries.country),
             vivino_id = COALESCE(?, wineries.vivino_id)
           WHERE id = ?",
          on: conn,
          with: [
            nullable_text(country),
            nullable_text(vivino_id),
            sqlight.text(id),
          ],
          expecting: decode.success(Nil),
        )
      id
    }
    _ -> {
      let id = ulid.generate()
      let assert Ok(_) =
        sqlight.query(
          "INSERT INTO wineries (id, created_by, name, country, vivino_id) VALUES (?, ?, ?, ?, ?)",
          on: conn,
          with: [
            sqlight.text(id),
            sqlight.text(created_by),
            sqlight.text(name),
            nullable_text(country),
            nullable_text(vivino_id),
          ],
          expecting: decode.success(Nil),
        )
      id
    }
  }
}

pub fn upsert_wine(
  conn: Connection,
  created_by created_by: String,
  winery winery: String,
  name name: String,
  vintage vintage: Option(String),
  region region: Option(String),
  country country: Option(String),
  style style: Option(String),
  personal_note personal_note: Option(String),
  wine_type wine_type: WineType,
  vivino_id vivino_id: Option(String),
) -> String {
  let winery_id = upsert_winery(conn, created_by, winery, country, None)

  let id_decoder = {
    use id <- decode.field(0, decode.string)
    decode.success(id)
  }

  // Check if wine exists
  let result =
    sqlight.query(
      "SELECT id FROM wines WHERE created_by = ? AND winery_id = ? AND name = ?",
      on: conn,
      with: [
        sqlight.text(created_by),
        sqlight.text(winery_id),
        sqlight.text(name),
      ],
      expecting: id_decoder,
    )

  let wine_id = case result {
    Ok([id]) -> {
      // Update fields if provided
      let assert Ok(_) =
        sqlight.query(
          "UPDATE wines SET
             region = COALESCE(?, wines.region),
             country = COALESCE(?, wines.country),
             style = COALESCE(?, wines.style),
             personal_note = COALESCE(?, wines.personal_note),
             wine_type = COALESCE(?, wines.wine_type),
             vivino_id = COALESCE(?, wines.vivino_id)
           WHERE id = ?",
          on: conn,
          with: [
            nullable_text(region),
            nullable_text(country),
            nullable_text(style),
            nullable_text(personal_note),
            sqlight.text(wine_type_to_string(wine_type)),
            nullable_text(vivino_id),
            sqlight.text(id),
          ],
          expecting: decode.success(Nil),
        )
      id
    }
    _ -> {
      let id = ulid.generate()
      let assert Ok(_) =
        sqlight.query(
          "INSERT INTO wines (id, created_by, winery_id, name, region, country, style,
                              personal_note, wine_type, vivino_id)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          on: conn,
          with: [
            sqlight.text(id),
            sqlight.text(created_by),
            sqlight.text(winery_id),
            sqlight.text(name),
            nullable_text(region),
            nullable_text(country),
            nullable_text(style),
            nullable_text(personal_note),
            sqlight.text(wine_type_to_string(wine_type)),
            nullable_text(vivino_id),
          ],
          expecting: decode.success(Nil),
        )
      id
    }
  }

  // Upsert vintage if provided
  case vintage {
    Some(year) -> upsert_vintage(conn, wine_id, year)
    None -> Nil
  }

  wine_id
}

pub fn insert_rating(
  conn: Connection,
  username username: String,
  wine_id wine_id: String,
  vintage vintage: Option(String),
  rating rating: Option(Float),
  tasting_notes tasting_notes: Option(String),
  rated_at rated_at: Option(String),
  source source: String,
) -> Nil {
  let id = ulid.generate()
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO ratings (id, username, wine_id, vintage, rating, tasting_notes, rated_at, source)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      on: conn,
      with: [
        sqlight.text(id),
        sqlight.text(username),
        sqlight.text(wine_id),
        nullable_text(vintage),
        nullable_float(rating),
        nullable_text(tasting_notes),
        nullable_text(rated_at),
        sqlight.text(source),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn update_rating(
  conn: Connection,
  id id: String,
  vintage vintage: Option(String),
  rating rating: Option(Float),
  tasting_notes tasting_notes: Option(String),
  rated_at rated_at: Option(String),
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "UPDATE ratings SET vintage = ?, rating = ?, tasting_notes = ?, rated_at = ?
       WHERE id = ?",
      on: conn,
      with: [
        nullable_text(vintage),
        nullable_float(rating),
        nullable_text(tasting_notes),
        nullable_text(rated_at),
        sqlight.text(id),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn delete_rating(conn: Connection, id: String) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "DELETE FROM ratings WHERE id = ?",
      on: conn,
      with: [sqlight.text(id)],
      expecting: decode.success(Nil),
    )
  Nil
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

pub fn parse_vintage(s: String) -> Option(String) {
  case string.trim(s) {
    "" -> None
    "N.V." | "NV" | "n.v." | "nv" -> Some("NV")
    trimmed ->
      case int.parse(trimmed) {
        Ok(_) -> Some(trimmed)
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

pub fn country_to_iso(name: String) -> Option(String) {
  case string.lowercase(string.trim(name)) {
    "" -> None
    "france" -> Some("FR")
    "italy" -> Some("IT")
    "spain" -> Some("ES")
    "germany" | "de" -> Some("DE")
    "portugal" -> Some("PT")
    "austria" | "at" -> Some("AT")
    "united states" | "usa" | "us" -> Some("US")
    "argentina" -> Some("AR")
    "chile" -> Some("CL")
    "australia" -> Some("AU")
    "new zealand" -> Some("NZ")
    "south africa" -> Some("ZA")
    "greece" -> Some("GR")
    "hungary" -> Some("HU")
    "georgia" -> Some("GE")
    "lebanon" -> Some("LB")
    "israel" -> Some("IL")
    "croatia" -> Some("HR")
    "slovenia" -> Some("SI")
    "switzerland" -> Some("CH")
    "romania" -> Some("RO")
    "bulgaria" -> Some("BG")
    "moldova" -> Some("MD")
    "turkey" | "türkiye" -> Some("TR")
    "uruguay" -> Some("UY")
    "brazil" -> Some("BR")
    "mexico" -> Some("MX")
    "canada" -> Some("CA")
    "united kingdom" | "uk" -> Some("GB")
    "japan" -> Some("JP")
    "china" -> Some("CN")
    "czech republic" | "czechia" -> Some("CZ")
    "ukraine" -> Some("UA")
    _ -> None
  }
}
