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
      )
      db.insert_rating(
        conn,
        username: "alice",
        wine_id: w2.id,
        vintage: w2.vintages,
        rating: Some(3.8),
        tasting_notes: Some("Pleasant but not outstanding. Good acidity."),
        rated_at: Some("2025-12-01"),
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
      )
      db.insert_rating(
        conn,
        username: "alice",
        wine_id: w4.id,
        vintage: None,
        rating: Some(3.5),
        tasting_notes: None,
        rated_at: Some("2026-02-20"),
      )
      db.insert_rating(
        conn,
        username: "alice",
        wine_id: w5.id,
        vintage: w5.vintages,
        rating: Some(4.0),
        tasting_notes: Some("Solid everyday wine. Cherry and vanilla notes."),
        rated_at: Some("2026-03-05"),
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
        price_cents: None,
      )
      db.insert_cellar_entry(
        conn,
        username: "alice",
        wine_id: w3.id,
        vintage: w3.vintages,
        quantity: 6,
        notes: None,
        date: Some("2026-01-05"),
        price_cents: None,
      )

      // Rate all Ciclope vintages
      case list.find(wines, fn(w) { w.name == "Ciclope" }) {
        Ok(ciclope) -> {
          let vtgs = db.vintages_for_wine(conn, ciclope.id)
          list.each(vtgs, fn(v) {
            let #(rating, notes, date) = case v {
              "2011" -> #(
                Some(4.3),
                Some("First vintage, raw and powerful. Impressive structure."),
                "2026-01-10",
              )
              "2012" -> #(
                Some(4.5),
                Some(
                  "Best vintage so far. Polished tannins, deep fruit, elegant.",
                ),
                "2026-02-14",
              )
              "2013" -> #(
                Some(4.1),
                Some(
                  "Lighter year but still characterful. Dried herbs and cherry.",
                ),
                "2026-03-20",
              )
              _ -> #(Some(4.0), None, "2026-03-01")
            }
            db.insert_rating(
              conn,
              username: "alice",
              wine_id: ciclope.id,
              vintage: Some(v),
              rating: rating,
              tasting_notes: notes,
              rated_at: Some(date),
            )
          })
        }
        Error(_) -> Nil
      }

      // Wishlist for alice
      let alice_wishlist = db.get_user_wishlist(conn, "alice")
      db.add_wine_to_list(
        conn,
        alice_wishlist.id,
        w4.id,
        None,
        Some("Recommended by a friend"),
      )
      db.add_wine_to_list(conn, alice_wishlist.id, w5.id, w5.vintages, None)
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
        )
      })
    }
  }

  Nil
}
