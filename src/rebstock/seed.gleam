import gleam/list
import gleam/option.{None, Some}
import sqlight.{type Connection}

import rebstock/db

pub fn seed_alice(conn: Connection, main_user: String) -> Nil {
  db.ensure_user(conn, "alice")

  let wines = db.list_wines(conn, main_user)

  // Rate some of the main user's wines as alice
  case wines {
    [w1, w2, w3, w4, w5, ..] -> {
      db.insert_rating(
        conn,
        username: "alice",
        wine_id: w1.id,
        vintage: w1.vintages,
        rating: Some(4.2),
        tasting_notes: Some(
          "Rich and complex, dark fruit with a hint of leather. Long finish.",
        ),
        rated_at: Some("2025-11-15"),
        source: "user",
      )
      db.insert_rating(
        conn,
        username: "alice",
        wine_id: w2.id,
        vintage: w2.vintages,
        rating: Some(3.8),
        tasting_notes: Some("Pleasant but not outstanding. Good acidity."),
        rated_at: Some("2025-12-01"),
        source: "user",
      )
      db.insert_rating(
        conn,
        username: "alice",
        wine_id: w3.id,
        vintage: w3.vintages,
        rating: Some(4.7),
        tasting_notes: Some(
          "Exceptional. Layers of blackberry, cedar, and spice. One of the best I've had this year.",
        ),
        rated_at: Some("2026-01-10"),
        source: "user",
      )
      db.insert_rating(
        conn,
        username: "alice",
        wine_id: w4.id,
        vintage: None,
        rating: Some(3.5),
        tasting_notes: None,
        rated_at: Some("2026-02-20"),
        source: "user",
      )
      db.insert_rating(
        conn,
        username: "alice",
        wine_id: w5.id,
        vintage: w5.vintages,
        rating: Some(4.0),
        tasting_notes: Some("Solid everyday wine. Cherry and vanilla notes."),
        rated_at: Some("2026-03-05"),
        source: "user",
      )

      // Cellar entries for alice
      db.insert_cellar_entry(
        conn,
        username: "alice",
        wine_id: w1.id,
        vintage: w1.vintages,
        quantity: 3,
        notes: Some("Picked up at the winery"),
        date: Some("2025-10-01"),
      )
      db.insert_cellar_entry(
        conn,
        username: "alice",
        wine_id: w3.id,
        vintage: w3.vintages,
        quantity: 6,
        notes: None,
        date: Some("2026-01-05"),
      )

      // Wishlist for alice
      db.upsert_wishlist(
        conn,
        username: "alice",
        wine_id: w4.id,
        vintage: None,
        notes: Some("Recommended by a friend"),
      )
      db.upsert_wishlist(
        conn,
        username: "alice",
        wine_id: w5.id,
        vintage: w5.vintages,
        notes: None,
      )
    }
    _ -> {
      // Not enough wines to seed, add a few ratings on whatever exists
      list.each(wines, fn(w) {
        db.insert_rating(
          conn,
          username: "alice",
          wine_id: w.id,
          vintage: w.vintages,
          rating: Some(4.0),
          tasting_notes: Some("Nice wine."),
          rated_at: Some("2026-01-01"),
          source: "user",
        )
      })
    }
  }

  Nil
}
