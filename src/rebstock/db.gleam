import gleam/dynamic/decode
import gleam/erlang/application
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
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
    vivino_rating: Option(Float),
    vivino_rating_count: Option(Int),
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
    price_cents: Option(Int),
  )
}

pub type Winery {
  Winery(
    id: String,
    created_by: String,
    name: String,
    wine_count: Int,
    country: Option(String),
    vivino_id: Option(String),
  )
}

fn winery_decoder() -> decode.Decoder(Winery) {
  use id <- decode.field(0, decode.string)
  use created_by <- decode.field(1, decode.string)
  use name <- decode.field(2, decode.string)
  use wine_count <- decode.field(3, decode.int)
  use country <- decode.field(4, decode.optional(decode.string))
  use vivino_id <- decode.field(5, decode.optional(decode.string))
  decode.success(Winery(
    id:,
    created_by:,
    name:,
    wine_count:,
    country:,
    vivino_id:,
  ))
}

pub fn migrate(conn: Connection) -> Nil {
  let assert Ok(Nil) = sqlight.exec("PRAGMA journal_mode=WAL", conn)
  let assert Ok(Nil) = sqlight.exec("PRAGMA foreign_keys=ON", conn)
  let assert Ok(priv) = application.priv_directory("rebstock")
  let assert Ok(Nil) = migrant.migrate(conn, priv <> "/migrations")
  Nil
}

// Columns: wines fields + winery name/country from JOIN + vintages subquery
const wine_cols =
  "w.id, w.created_by, w.winery_id, wy.name, w.name,
        (SELECT GROUP_CONCAT(v.year) FROM wines_vintages v WHERE v.wine_id = w.id ORDER BY v.year) AS vintages,
        w.region, wy.country, w.style,
        w.personal_note, w.wine_type,
        w.vivino_id, w.vivino_rating, w.vivino_rating_count"

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
  use vivino_rating <- decode.field(12, decode.optional(decode.float))
  use vivino_rating_count <- decode.field(13, decode.optional(decode.int))
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
    vivino_rating:,
    vivino_rating_count:,
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
  use created_at <- decode.field(7, decode.string)
  decode.success(Rating(
    id:,
    username:,
    wine_id:,
    vintage:,
    rating:,
    tasting_notes:,
    rated_at:,
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
  use price_cents <- decode.field(9, decode.optional(decode.int))
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
    price_cents:,
  ))
}

/// Runs on every request, so check with a read first and only write
/// when the user is missing.
pub fn ensure_user(conn: Connection, username: String) -> Nil {
  let assert Ok(rows) =
    sqlight.query(
      "SELECT 1 FROM users WHERE username = ?",
      on: conn,
      with: [sqlight.text(username)],
      expecting: decode.success(Nil),
    )
  case rows {
    [_, ..] -> Nil
    [] -> {
      let assert Ok(_) =
        sqlight.query(
          "INSERT OR IGNORE INTO users (username) VALUES (?)",
          on: conn,
          with: [sqlight.text(username)],
          expecting: decode.success(Nil),
        )
      Nil
    }
  }
}

pub type Profile {
  Profile(
    username: String,
    display_name: Option(String),
    picture: Option(String),
  )
}

pub fn get_profile(conn: Connection, username: String) -> Result(Profile, Nil) {
  let decoder = {
    use username <- decode.field(0, decode.string)
    use display_name <- decode.field(1, decode.optional(decode.string))
    use picture <- decode.field(2, decode.optional(decode.string))
    decode.success(Profile(username:, display_name:, picture:))
  }
  case
    sqlight.query(
      "SELECT username, display_name, picture FROM users WHERE username = ?",
      on: conn,
      with: [sqlight.text(username)],
      expecting: decoder,
    )
  {
    Ok([profile]) -> Ok(profile)
    _ -> Error(Nil)
  }
}

pub fn update_profile(
  conn: Connection,
  username: String,
  display_name: String,
  picture: Option(String),
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "UPDATE users SET display_name = ?, picture = ? WHERE username = ?",
      on: conn,
      with: [
        sqlight.text(display_name),
        nullable_text(picture),
        sqlight.text(username),
      ],
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

/// Runs on every request, so skip the writes when the three system
/// lists already exist.
pub fn ensure_system_lists(conn: Connection, username: String) -> Nil {
  let existing =
    count_query(
      conn,
      "SELECT COUNT(*) FROM lists WHERE username = ? AND list_type IN ('cellar', 'rated', 'wishlist')",
      [sqlight.text(username)],
    )
  case existing >= 3 {
    True -> Nil
    False -> create_system_lists(conn, username)
  }
}

fn create_system_lists(conn: Connection, username: String) -> Nil {
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

pub fn list_wines_for_list(
  conn: Connection,
  list_id: String,
) -> List(ListWine) {
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
    use vivino_rating <- decode.field(12, decode.optional(decode.float))
    use vivino_rating_count <- decode.field(13, decode.optional(decode.int))
    use vintage <- decode.field(14, decode.optional(decode.string))
    use notes <- decode.field(15, decode.optional(decode.string))
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
        vivino_rating:,
        vivino_rating_count:,
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

pub fn list_ids_containing_wine(
  conn: Connection,
  username: String,
  wine_id: String,
) -> List(String) {
  let id_decoder = {
    use id <- decode.field(0, decode.string)
    decode.success(id)
  }
  let assert Ok(ids) =
    sqlight.query(
      "SELECT lw.list_id FROM lists_wines lw
       JOIN lists l ON l.id = lw.list_id
       WHERE lw.wine_id = ? AND l.username = ?",
      on: conn,
      with: [sqlight.text(wine_id), sqlight.text(username)],
      expecting: id_decoder,
    )
  ids
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

pub fn find_wine_by_vivino_id(
  conn: Connection,
  created_by: String,
  vivino_id: String,
) -> Result(Wine, Nil) {
  let result =
    sqlight.query(
      "SELECT "
        <> wine_cols
        <> " "
        <> wine_join
        <> " WHERE w.created_by = ? AND w.vivino_id = ?",
      on: conn,
      with: [sqlight.text(created_by), sqlight.text(vivino_id)],
      expecting: wine_decoder(),
    )
  case result {
    Ok([wine]) -> Ok(wine)
    _ -> Error(Nil)
  }
}

pub fn find_wine_by_name(
  conn: Connection,
  created_by: String,
  winery_name: String,
  wine_name: String,
) -> Result(Wine, Nil) {
  let result =
    sqlight.query(
      "SELECT "
        <> wine_cols
        <> " "
        <> wine_join
        <> " WHERE w.created_by = ? AND wy.name = ? AND w.name = ?",
      on: conn,
      with: [
        sqlight.text(created_by),
        sqlight.text(winery_name),
        sqlight.text(wine_name),
      ],
      expecting: wine_decoder(),
    )
  case result {
    Ok([wine]) -> Ok(wine)
    _ -> Error(Nil)
  }
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
  let assert Ok(wineries) =
    sqlight.query(
      "SELECT wy.id, wy.created_by, wy.name, COUNT(w.id) as wine_count, wy.country, wy.vivino_id
       FROM wineries wy LEFT JOIN wines w ON wy.id = w.winery_id
       GROUP BY wy.id ORDER BY wy.name",
      on: conn,
      with: [],
      expecting: winery_decoder(),
    )
  wineries
}

pub fn get_winery(conn: Connection, id: String) -> Result(Winery, Nil) {
  let result =
    sqlight.query(
      "SELECT wy.id, wy.created_by, wy.name, COUNT(w.id) as wine_count, wy.country, wy.vivino_id
       FROM wineries wy LEFT JOIN wines w ON wy.id = w.winery_id
       WHERE wy.id = ?
       GROUP BY wy.id",
      on: conn,
      with: [sqlight.text(id)],
      expecting: winery_decoder(),
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
  CellarWine(
    wine: Wine,
    vintage: Option(String),
    bottles: Int,
    price_breakdown: List(#(Int, Int)),
  )
}

const cellar_wine_cols =
  "w.id, w.created_by, w.winery_id, wy.name, w.name,
        (SELECT GROUP_CONCAT(v.year) FROM wines_vintages v WHERE v.wine_id = w.id ORDER BY v.year) AS vintages,
        w.region, wy.country, w.style,
        w.personal_note, w.wine_type,
        w.vivino_id, w.vivino_rating, w.vivino_rating_count,
        c.vintage, COALESCE(SUM(c.quantity), 0) AS bottles,
        (SELECT GROUP_CONCAT(pb.bottles || 'x' || pb.price)
         FROM (SELECT COALESCE(c2.price_cents, p2.price_cents) AS price,
                      SUM(c2.quantity) AS bottles
               FROM cellar c2 LEFT JOIN cellar p2 ON c2.parent_id = p2.id
               WHERE c2.username = c.username AND c2.wine_id = w.id
                 AND c2.vintage IS c.vintage
                 AND COALESCE(c2.price_cents, p2.price_cents) IS NOT NULL
               GROUP BY price HAVING bottles > 0) pb) AS price_breakdown"

const cellar_wine_join =
  "FROM wines w
        JOIN wineries wy ON w.winery_id = wy.id
        JOIN cellar c ON c.wine_id = w.id"

/// `"2x1370,1x1420"` from GROUP_CONCAT, whose order is not guaranteed,
/// into pairs of held bottles and unit price sorted by price
fn parse_price_breakdown(raw: Option(String)) -> List(#(Int, Int)) {
  case raw {
    None -> []
    Some(concatenated) ->
      concatenated
      |> string.split(",")
      |> list.filter_map(fn(pair) {
        case string.split(pair, "x") {
          [bottles, price] ->
            case int.parse(bottles), int.parse(price) {
              Ok(b), Ok(p) -> Ok(#(b, p))
              _, _ -> Error(Nil)
            }
          _ -> Error(Nil)
        }
      })
      |> list.sort(fn(a, b) { int.compare(a.1, b.1) })
  }
}

/// What the bottles still in the rack cost, `None` when none of them are priced
pub fn held_value(breakdown: List(#(Int, Int))) -> Option(Int) {
  case breakdown {
    [] -> None
    _ -> Some(list.fold(breakdown, 0, fn(acc, pair) { acc + pair.0 * pair.1 }))
  }
}

/// The same held value for entries already in hand, so a wine page that lists
/// every entry does not ask the database a second time. A drink is charged to
/// the purchase it draws from and a price whose bottles are all gone drops out,
/// exactly as the breakdown subquery does it.
pub fn entries_held_value(entries: List(CellarEntry)) -> Option(Int) {
  held_value(entries_price_breakdown(entries))
}

fn entries_price_breakdown(entries: List(CellarEntry)) -> List(#(Int, Int)) {
  let purchase_prices =
    list.filter_map(entries, fn(entry) {
      case entry.parent_id, entry.price_cents {
        None, Some(cents) -> Ok(#(entry.id, cents))
        _, _ -> Error(Nil)
      }
    })
  let priced =
    list.filter_map(entries, fn(entry) {
      let source = option.unwrap(entry.parent_id, entry.id)
      case list.key_find(purchase_prices, source) {
        Ok(cents) -> Ok(#(cents, entry.quantity))
        Error(_) -> Error(Nil)
      }
    })
  priced
  |> list.map(fn(pair) { pair.0 })
  |> list.unique
  |> list.sort(int.compare)
  |> list.filter_map(fn(price) {
    let bottles =
      priced
      |> list.filter(fn(pair) { pair.0 == price })
      |> list.map(fn(pair) { pair.1 })
      |> int.sum
    case bottles > 0 {
      True -> Ok(#(bottles, price))
      False -> Error(Nil)
    }
  })
}

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
  use vivino_rating <- decode.field(12, decode.optional(decode.float))
  use vivino_rating_count <- decode.field(13, decode.optional(decode.int))
  use vintage <- decode.field(14, decode.optional(decode.string))
  use bottles <- decode.field(15, decode.int)
  use price_breakdown <- decode.field(16, decode.optional(decode.string))
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
      vivino_rating:,
      vivino_rating_count:,
    ),
    vintage:,
    bottles:,
    price_breakdown: parse_price_breakdown(price_breakdown),
  ))
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
       ORDER BY w.vivino_rating DESC, bottles DESC LIMIT ?",
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
      "SELECT c.id, c.username, c.wine_id, c.vintage, c.quantity, c.notes, c.date, c.parent_id, c.created_at, c.price_cents
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
      "SELECT c.id, c.username, c.wine_id, c.vintage, c.quantity, c.notes, c.date, c.parent_id, c.created_at, c.price_cents
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
  price_cents price_cents: Option(Int),
) -> Nil {
  let id = ulid.generate()
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO cellar (id, username, wine_id, vintage, quantity, notes, date, price_cents)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      on: conn,
      with: [
        sqlight.text(id),
        sqlight.text(username),
        sqlight.text(wine_id),
        nullable_text(vintage),
        sqlight.int(quantity),
        nullable_text(notes),
        nullable_text(date),
        nullable_int(price_cents),
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
  price_cents price_cents: Option(Int),
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "UPDATE cellar SET vintage = ?, quantity = ?, notes = ?, date = ?, price_cents = ?
       WHERE id = ?",
      on: conn,
      with: [
        nullable_text(vintage),
        sqlight.int(quantity),
        nullable_text(notes),
        nullable_text(date),
        nullable_int(price_cents),
        sqlight.text(id),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn delete_cellar_entry(conn: Connection, id: String) -> Nil {
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

const rating_cols =
  "r.id, r.username, r.wine_id, r.vintage, r.rating,
        r.tasting_notes, r.rated_at, r.created_at"

const rating_order = " ORDER BY r.rating DESC, r.rated_at DESC"

pub fn top_ratings_by_user(
  conn: Connection,
  username: String,
  limit: Int,
) -> List(Rating) {
  let assert Ok(ratings) =
    sqlight.query(
      "SELECT r.id, r.username, r.wine_id, r.vintage, r.rating, r.tasting_notes, r.rated_at, r.created_at
       FROM ratings r
       WHERE r.username = ? AND r.rating IS NOT NULL
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
      "SELECT r.id, r.username, r.wine_id, r.vintage, r.rating, r.tasting_notes, r.rated_at, r.created_at
       FROM ratings r
       WHERE r.username = ?
       ORDER BY r.rated_at DESC, r.created_at DESC LIMIT ?",
      on: conn,
      with: [sqlight.text(username), sqlight.int(limit)],
      expecting: rating_decoder(),
    )
  ratings
}

pub fn rated_wines(conn: Connection, username: String) -> List(Wine) {
  let assert Ok(wines) =
    sqlight.query("SELECT DISTINCT " <> wine_cols <> " " <> wine_join <> "
       JOIN ratings r ON r.wine_id = w.id AND r.username = ?
       ORDER BY w.wine_type, w.region, wy.name, w.name", on: conn, with: [
      sqlight.text(username),
    ], expecting: wine_decoder())
  wines
}

pub fn get_rating_by_id(conn: Connection, id: String) -> Result(Rating, Nil) {
  let result =
    sqlight.query(
      "SELECT r.id, r.username, r.wine_id, r.vintage, r.rating, r.tasting_notes, r.rated_at, r.created_at
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
      "SELECT r.id, r.username, r.wine_id, r.vintage, r.rating, r.tasting_notes, r.rated_at, r.created_at
       FROM ratings r
       WHERE r.wine_id = ? ORDER BY r.rated_at DESC",
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
      "SELECT c.id, c.username, c.wine_id, c.vintage, c.quantity, c.notes, c.date, c.parent_id, c.created_at, c.price_cents
       FROM cellar c WHERE c.username = ?
       ORDER BY c.created_at DESC LIMIT ?",
      on: conn,
      with: [sqlight.text(username), sqlight.int(limit)],
      expecting: cellar_entry_decoder(),
    )
  entries
}

pub fn set_wine_vivino_rating(
  conn: Connection,
  wine_id: String,
  rating: Float,
  rating_count: Option(Int),
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "UPDATE wines SET vivino_rating = ?,
       vivino_rating_count = COALESCE(?, vivino_rating_count)
       WHERE id = ?",
      on: conn,
      with: [
        sqlight.float(rating),
        nullable_int(rating_count),
        sqlight.text(wine_id),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

pub fn set_vintage_vivino_rating(
  conn: Connection,
  wine_id: String,
  year: String,
  rating: Float,
  rating_count: Option(Int),
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "UPDATE wines_vintages SET vivino_rating = ?,
       vivino_rating_count = COALESCE(?, vivino_rating_count)
       WHERE wine_id = ? AND year = ?",
      on: conn,
      with: [
        sqlight.float(rating),
        nullable_int(rating_count),
        sqlight.text(wine_id),
        sqlight.text(year),
      ],
      expecting: decode.success(Nil),
    )
  Nil
}

/// Vintage year + cached Vivino community rating
pub type VintageRating {
  VintageRating(year: String, rating: Option(Float), rating_count: Option(Int))
}

pub fn vintage_ratings_for_wine(
  conn: Connection,
  wine_id: String,
) -> List(VintageRating) {
  let decoder = {
    use year <- decode.field(0, decode.string)
    use rating <- decode.field(1, decode.optional(decode.float))
    use rating_count <- decode.field(2, decode.optional(decode.int))
    decode.success(VintageRating(year:, rating:, rating_count:))
  }
  let assert Ok(rows) =
    sqlight.query(
      "SELECT year, vivino_rating, vivino_rating_count
       FROM wines_vintages WHERE wine_id = ? ORDER BY year",
      on: conn,
      with: [sqlight.text(wine_id)],
      expecting: decoder,
    )
  rows
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
    "SELECT COUNT(DISTINCT wine_id) FROM ratings WHERE username = ?",
    [sqlight.text(username)],
  )
}

/// Number of distinct wineries the user has tasted from (via ratings)
pub fn count_rated_wineries(conn: Connection, username: String) -> Int {
  count_query(
    conn,
    "SELECT COUNT(DISTINCT w.winery_id) FROM ratings r JOIN wines w ON w.id = r.wine_id WHERE r.username = ?",
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

/// One half-step bucket and its count. A `None` bucket holds everything with
/// no rating on that side — bottles never tasted, wines Vivino has no score
/// for — which is information in its own right, not a row to drop.
pub type Bucket =
  #(Option(Float), Int)

/// The same bucket counted on two sides, for comparing one rater to another
pub type BucketPair =
  #(Option(Float), Int, Int)

fn bucket_decoder() -> decode.Decoder(Bucket) {
  use bucket <- decode.field(0, decode.optional(decode.float))
  use count <- decode.field(1, decode.int)
  decode.success(#(bucket, count))
}

/// Half steps because that is how people rate — folding 3.5 in with 3.0
/// flattens the only part of the range that varies.
fn half_step(rating: String) -> String {
  "ROUND(" <> rating <> " * 2) / 2.0"
}

/// Bottles currently held, one row per wine and vintage
const held_bottles =
  "SELECT wine_id, vintage, SUM(quantity) AS bottles
   FROM cellar WHERE username = ?
   GROUP BY wine_id, vintage HAVING bottles > 0"

/// A vintage's own Vivino score beats the wine's overall one where both exist
const vivino_rating = "COALESCE(v.vivino_rating, w.vivino_rating)"

const vivino_join =
  "JOIN wines w ON w.id = held.wine_id
   LEFT JOIN wines_vintages v
     ON v.wine_id = held.wine_id AND v.year = held.vintage"

/// Unrated last rather than first, which is where SQLite would put NULL
const bucket_order = "GROUP BY bucket ORDER BY bucket IS NULL, bucket"

fn bucket_query(
  conn: Connection,
  sql: String,
  params: List(sqlight.Value),
) -> List(Bucket) {
  let assert Ok(rows) =
    sqlight.query(sql, on: conn, with: params, expecting: bucket_decoder())
  rows
}

/// How the user spreads their own ratings
pub fn rating_distribution(conn: Connection, username: String) -> List(Bucket) {
  bucket_query(conn, "SELECT " <> half_step("rating") <> " AS bucket, COUNT(*)
     FROM ratings WHERE username = ? AND rating IS NOT NULL " <> bucket_order, [
    sqlight.text(username),
  ])
}

/// What Vivino's crowd made of those same wines, so the two are comparable
pub fn vivino_distribution_of_rated(
  conn: Connection,
  username: String,
) -> List(Bucket) {
  bucket_query(
    conn,
    "SELECT " <> half_step(vivino_rating) <> " AS bucket, COUNT(*)
     FROM ratings held
     JOIN wines w ON w.id = held.wine_id
     LEFT JOIN wines_vintages v
       ON v.wine_id = held.wine_id AND v.year = held.vintage
     WHERE held.username = ? AND held.rating IS NOT NULL " <> bucket_order,
    [sqlight.text(username)],
  )
}

/// Cellar bottles by the user's own rating, counted in bottles so a case
/// weighs what it actually occupies. A wine rated across several vintages
/// takes its best score; bottles never tasted fall into the `None` bucket.
pub fn cellar_own_distribution(
  conn: Connection,
  username: String,
) -> List(Bucket) {
  bucket_query(conn, "WITH held AS (" <> held_bottles <> "), scored AS (
       SELECT held.bottles,
         (SELECT MAX(r.rating) FROM ratings r
          WHERE r.wine_id = held.wine_id AND r.username = ?
            AND r.rating IS NOT NULL) AS rating
       FROM held
     )
     SELECT " <> half_step("rating") <> " AS bucket, SUM(bottles) FROM scored " <> bucket_order, [
    sqlight.text(username),
    sqlight.text(username),
  ])
}

/// Cellar bottles by Vivino's rating
pub fn cellar_vivino_distribution(
  conn: Connection,
  username: String,
) -> List(Bucket) {
  bucket_query(
    conn,
    "WITH held AS ("
      <> held_bottles
      <> ") SELECT "
      <> half_step(vivino_rating)
      <> " AS bucket, SUM(held.bottles)
     FROM held "
      <> vivino_join
      <> " "
      <> bucket_order,
    [sqlight.text(username)],
  )
}

/// Line two distributions up on a shared set of buckets, unrated last
pub fn pair_distributions(
  left: List(Bucket),
  right: List(Bucket),
) -> List(BucketPair) {
  let buckets =
    list.append(left, right)
    |> list.map(fn(b) { b.0 })
    |> list.unique
    |> list.sort(compare_buckets)

  list.map(buckets, fn(bucket) {
    #(bucket, count_in(left, bucket), count_in(right, bucket))
  })
}

fn count_in(buckets: List(Bucket), bucket: Option(Float)) -> Int {
  case list.find(buckets, fn(b) { b.0 == bucket }) {
    Ok(#(_, count)) -> count
    Error(_) -> 0
  }
}

fn compare_buckets(a: Option(Float), b: Option(Float)) -> order.Order {
  case a, b {
    None, None -> order.Eq
    None, Some(_) -> order.Gt
    Some(_), None -> order.Lt
    Some(x), Some(y) -> float.compare(x, y)
  }
}

/// What one rater's score has to be for a row to survive. Bounds are on the
/// score itself, both inclusive, and either end may be left open.
pub type ScoreFilter {
  AnyScore
  NoScore
  ScoreRange(min: Option(Float), max: Option(Float))
}

/// The two raters filter independently and both have to agree
pub type RatingFilter {
  RatingFilter(mine: ScoreFilter, vivino: ScoreFilter)
}

pub const unfiltered = RatingFilter(AnyScore, AnyScore)

fn score_condition(
  score: String,
  filter: ScoreFilter,
) -> #(String, List(sqlight.Value)) {
  case filter {
    AnyScore -> #("", [])
    NoScore -> #(" AND " <> score <> " IS NULL", [])
    ScoreRange(min, max) -> {
      let #(low, low_params) = bound(score, ">=", min)
      let #(high, high_params) = bound(score, "<=", max)
      #(low <> high, list.append(low_params, high_params))
    }
  }
}

fn bound(
  score: String,
  operator: String,
  value: Option(Float),
) -> #(String, List(sqlight.Value)) {
  case value {
    None -> #("", [])
    Some(v) -> #(" AND " <> score <> " " <> operator <> " ?", [sqlight.float(v)])
  }
}

/// A user's ratings, narrowed to those where their own score and Vivino's
/// both fall where the filter asks
pub fn ratings_by_user(
  conn: Connection,
  username: String,
  filter: RatingFilter,
) -> List(Rating) {
  let #(mine, mine_params) = score_condition("r.rating", filter.mine)
  let #(vivino, vivino_params) = score_condition(vivino_rating, filter.vivino)
  let assert Ok(ratings) =
    sqlight.query("SELECT " <> rating_cols <> " FROM ratings r
       LEFT JOIN wines w ON w.id = r.wine_id
       LEFT JOIN wines_vintages v
         ON v.wine_id = r.wine_id AND v.year = r.vintage
       WHERE r.username = ?" <> mine <> vivino <> rating_order, on: conn, with: [
      sqlight.text(username),
      ..list.append(mine_params, vivino_params)
    ], expecting: rating_decoder())
  ratings
}

/// A wine the user rated across several vintages scores as its best, the same
/// way the cellar quality chart counts it
const own_rating_join =
  "LEFT JOIN (
     SELECT wine_id, MAX(rating) AS rating FROM ratings
     WHERE username = ? AND rating IS NOT NULL GROUP BY wine_id
   ) mine ON mine.wine_id = w.id"

/// Bottles held, narrowed the same way as `ratings_by_user`
pub fn cellar_wines(
  conn: Connection,
  username: String,
  filter: RatingFilter,
) -> List(CellarWine) {
  let #(mine, mine_params) = score_condition("mine.rating", filter.mine)
  let #(vivino, vivino_params) = score_condition(vivino_rating, filter.vivino)
  let assert Ok(wines) =
    sqlight.query(
      "SELECT "
        <> cellar_wine_cols
        <> " "
        <> cellar_wine_join
        <> " LEFT JOIN wines_vintages v ON v.wine_id = w.id AND v.year = c.vintage "
        <> own_rating_join
        <> " WHERE c.username = ?"
        <> mine
        <> vivino
        <> " GROUP BY w.id, c.vintage HAVING bottles > 0
       ORDER BY wy.name, w.name",
      on: conn,
      with: [
        sqlight.text(username),
        sqlight.text(username),
        ..list.append(mine_params, vivino_params)
      ],
      expecting: cellar_wine_decoder(),
    )
  wines
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
  vivino_id: Option(String),
) -> Nil {
  let assert Ok(_) =
    sqlight.query(
      "UPDATE wineries SET name = ?, country = ?,
       vivino_id = COALESCE(?, vivino_id) WHERE id = ?",
      on: conn,
      with: [
        sqlight.text(name),
        nullable_text(country),
        nullable_text(vivino_id),
        sqlight.text(id),
      ],
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
  vivino_id: Option(String),
) -> Nil {
  let winery_id = upsert_winery(conn, created_by, winery, country, None)
  let assert Ok(_) =
    sqlight.query(
      "UPDATE wines SET name = ?, winery_id = ?, region = ?,
       style = ?, personal_note = ?, wine_type = ?,
       vivino_id = COALESCE(?, vivino_id) WHERE id = ?",
      on: conn,
      with: [
        sqlight.text(name),
        sqlight.text(winery_id),
        nullable_text(region),
        nullable_text(style),
        nullable_text(personal_note),
        sqlight.text(wine_type_to_string(wine_type)),
        nullable_text(vivino_id),
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
             style = COALESCE(?, wines.style),
             personal_note = COALESCE(?, wines.personal_note),
             wine_type = COALESCE(?, wines.wine_type),
             vivino_id = COALESCE(?, wines.vivino_id)
           WHERE id = ?",
          on: conn,
          with: [
            nullable_text(region),
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
          "INSERT INTO wines (id, created_by, winery_id, name, region, style,
                              personal_note, wine_type, vivino_id)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
          on: conn,
          with: [
            sqlight.text(id),
            sqlight.text(created_by),
            sqlight.text(winery_id),
            sqlight.text(name),
            nullable_text(region),
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
) -> Nil {
  let id = ulid.generate()
  let assert Ok(_) =
    sqlight.query(
      "INSERT INTO ratings (id, username, wine_id, vintage, rating, tasting_notes, rated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)",
      on: conn,
      with: [
        sqlight.text(id),
        sqlight.text(username),
        sqlight.text(wine_id),
        nullable_text(vintage),
        nullable_float(rating),
        nullable_text(tasting_notes),
        nullable_text(rated_at),
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

fn nullable_int(val: Option(Int)) -> sqlight.Value {
  case val {
    Some(v) -> sqlight.int(v)
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

pub fn parse_price_cents(s: String) -> Option(Int) {
  case parse_optional_float(s) {
    None -> None
    Some(euros) -> Some(float.round(euros *. 100.0))
  }
}

/// Euro amount, for the CSV export and number inputs.
/// `int./` truncates toward zero and `int.%` keeps the dividend's sign, so a
/// negative amount is split into its sign and its absolute value first —
/// otherwise both halves would carry the minus, e.g. "-5.-50".
pub fn format_price_plain(cents: Int) -> String {
  let sign = case cents < 0 {
    True -> "-"
    False -> ""
  }
  let whole = int.absolute_value(cents)
  sign
  <> int.to_string(whole / 100)
  <> "."
  <> string.pad_start(int.to_string(whole % 100), to: 2, with: "0")
}

pub fn format_price(cents: Int) -> String {
  "\u{20ac}" <> format_price_plain(cents)
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
    "france" | "fr" | "francia" -> Some("FR")
    "italy" | "it" | "italia" -> Some("IT")
    "spain" | "es" | "españa" -> Some("ES")
    "germany" | "de" | "deutschland" -> Some("DE")
    "portugal" | "pt" -> Some("PT")
    "austria" | "at" | "österreich" -> Some("AT")
    "united states" | "usa" | "us" -> Some("US")
    "argentina" | "ar" -> Some("AR")
    "chile" | "cl" -> Some("CL")
    "australia" | "au" -> Some("AU")
    "new zealand" | "nz" -> Some("NZ")
    "south africa" | "za" -> Some("ZA")
    "greece" | "gr" | "ελλάδα" -> Some("GR")
    "hungary" | "hu" | "magyarország" -> Some("HU")
    "georgia" | "ge" | "საქართველო" -> Some("GE")
    "lebanon" | "lb" | "لبنان" -> Some("LB")
    "israel" | "il" | "ישראל" -> Some("IL")
    "croatia" | "hr" | "hrvatska" -> Some("HR")
    "slovenia" | "si" | "slovenija" -> Some("SI")
    "switzerland" | "ch" | "schweiz" | "suisse" | "svizzera" -> Some("CH")
    "romania" | "ro" | "românia" -> Some("RO")
    "bulgaria" | "bg" | "българия" -> Some("BG")
    "moldova" | "md" -> Some("MD")
    "turkey" | "tr" | "türkiye" -> Some("TR")
    "uruguay" | "uy" -> Some("UY")
    "brazil" | "br" | "brasil" -> Some("BR")
    "mexico" | "mx" | "méxico" -> Some("MX")
    "canada" | "ca" -> Some("CA")
    "united kingdom" | "uk" | "gb" -> Some("GB")
    "japan" | "jp" | "日本" -> Some("JP")
    "china" | "cn" | "中国" -> Some("CN")
    "czech republic" | "czechia" | "cz" | "česko" -> Some("CZ")
    "ukraine" | "ua" | "україна" -> Some("UA")
    _ -> None
  }
}
