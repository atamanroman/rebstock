import gleam/list
import gleam/option.{None, Some}
import sqlight

import rebstock/auth
import rebstock/config.{type Config}
import rebstock/db
import rebstock/vivino

pub const test_config: Config = config.Config(
  host: "127.0.0.1",
  port: 3000,
  database_uri: ":memory:",
  image_dir: "/tmp/rebstock-test-images",
  auth: auth.Single("test"),
)

pub fn with_seeded_db(f: fn(sqlight.Connection) -> Nil) -> Nil {
  use conn <- sqlight.with_connection(":memory:")
  db.migrate(conn)
  vivino.import_data(conn, "vivino_data", "test", False)
  f(conn)
}

pub fn with_empty_db(f: fn(sqlight.Connection) -> Nil) -> Nil {
  use conn <- sqlight.with_connection(":memory:")
  db.migrate(conn)
  f(conn)
}

pub fn create_test_wine(
  conn: sqlight.Connection,
  name: String,
  wine_type: db.WineType,
) -> String {
  db.upsert_wine(
    conn,
    created_by: "test",
    winery: "Test Winery",
    name: name,
    vintage: None,
    region: None,
    country: None,
    style: None,
    personal_note: None,
    wine_type: wine_type,
    vivino_id: None,
  )
}

pub fn create_test_cellar_wine(
  conn: sqlight.Connection,
  name: String,
  vintage: String,
  quantity: Int,
) -> #(String, String) {
  let wine_id = create_test_wine(conn, name, db.Red)
  db.upsert_vintage(conn, wine_id, vintage)
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some(vintage),
    quantity: quantity,
    notes: None,
    date: None,
  )
  let entries = db.cellar_entries_for_wine(conn, wine_id)
  let assert [entry, ..] = entries
  #(wine_id, entry.id)
}

pub fn wine_path(wine_id: String, wine_name: String) -> String {
  "/wines/" <> wine_id <> "/" <> db.slugify(wine_name)
}

pub fn user_ratings(
  ratings: List(db.Rating),
  username: String,
) -> List(db.Rating) {
  list.filter(ratings, fn(r) { r.username == username && r.source == "user" })
}

pub fn seed_two_users(conn: sqlight.Connection) -> #(String, String) {
  db.ensure_user(conn, "alice")
  db.ensure_user(conn, "bob")
  let wine_a =
    db.upsert_wine(
      conn,
      created_by: "alice",
      winery: "Domaine Alice",
      name: "Pinot Noir Reserve",
      vintage: Some("2020"),
      region: Some("Burgundy"),
      country: Some("FR"),
      style: None,
      personal_note: None,
      wine_type: db.Red,
      vivino_id: None,
    )
  let wine_b =
    db.upsert_wine(
      conn,
      created_by: "bob",
      winery: "Bodega Bob",
      name: "Tempranillo Gran Reserva",
      vintage: Some("2018"),
      region: Some("Rioja"),
      country: Some("ES"),
      style: None,
      personal_note: None,
      wine_type: db.Red,
      vivino_id: None,
    )
  db.upsert_vintage(conn, wine_a, "2020")
  db.upsert_vintage(conn, wine_b, "2018")
  db.insert_cellar_entry(
    conn,
    username: "alice",
    wine_id: wine_a,
    vintage: Some("2020"),
    quantity: 6,
    notes: None,
    date: None,
  )
  db.insert_cellar_entry(
    conn,
    username: "bob",
    wine_id: wine_b,
    vintage: Some("2018"),
    quantity: 3,
    notes: None,
    date: None,
  )
  db.insert_rating(
    conn,
    username: "alice",
    wine_id: wine_a,
    vintage: Some("2020"),
    rating: Some(4.5),
    tasting_notes: Some("Excellent"),
    rated_at: None,
    source: "user",
  )
  db.insert_rating(
    conn,
    username: "bob",
    wine_id: wine_b,
    vintage: Some("2018"),
    rating: Some(3.8),
    tasting_notes: None,
    rated_at: None,
    source: "user",
  )
  let alice_wl = db.get_user_wishlist(conn, "alice")
  db.add_wine_to_list(
    conn,
    alice_wl.id,
    wine_b,
    Some("2018"),
    Some("Want to try"),
  )
  #(wine_a, wine_b)
}
