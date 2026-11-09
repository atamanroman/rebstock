import gleam/list
import gleam/option.{type Option, None, Some}
import sqlight.{type Connection}

import rebstock/db

pub fn seed_collection(conn: Connection, username: String) -> Nil {
  db.ensure_user(conn, username)
  let wines = [
    #(
      "Ciclope",
      db.Red,
      "IT",
      ["2011", "2012", "2013"],
      Some(4.5),
      Some(4.2),
      3,
    ),
    #("Riesling", db.White, "DE", ["2020", "2021"], Some(3.2), Some(4.0), 6),
    #("Rosato", db.Rose, "IT", ["2022"], Some(4.0), Some(3.7), 2),
    #("Brut", db.Sparkling, "FR", [], None, None, 4),
    #("Late Harvest", db.Dessert, "DE", ["2019"], Some(4.7), Some(4.6), 1),
    #("Amber", db.Orange, "GE", ["2021"], Some(3.9), None, 2),
  ]
  list.each(wines, fn(wine) {
    let #(name, wine_type, country, vintages, rating, vivino_rating, bottles) =
      wine
    seed_wine(
      conn,
      username,
      name,
      wine_type,
      country,
      vintages,
      rating,
      vivino_rating,
      bottles,
    )
  })
}

fn seed_wine(
  conn: Connection,
  username: String,
  name: String,
  wine_type: db.WineType,
  country: String,
  vintages: List(String),
  rating: Option(Float),
  vivino_rating: Option(Float),
  bottles: Int,
) -> Nil {
  let vintage = vintages |> list.first |> option.from_result
  let wine_id =
    db.upsert_wine(
      conn,
      created_by: username,
      winery: "Demo " <> db.wine_type_label(wine_type) <> " Estate",
      name: name,
      vintage: vintage,
      region: None,
      country: Some(country),
      style: None,
      personal_note: None,
      wine_type: wine_type,
      vivino_id: None,
    )
  list.each(vintages, fn(year) { db.upsert_vintage(conn, wine_id, year) })
  case vivino_rating {
    Some(score) -> {
      db.set_wine_vivino_rating(conn, wine_id, score, Some(120))
      list.each(vintages, fn(year) {
        db.set_vintage_vivino_rating(conn, wine_id, year, score, Some(40))
      })
    }
    None -> Nil
  }
  db.insert_rating(
    conn,
    username: username,
    wine_id: wine_id,
    vintage: vintage,
    rating: rating,
    tasting_notes: Some("Sample tasting note"),
    rated_at: Some("2026-01-15"),
  )
  db.insert_cellar_entry(
    conn,
    username: username,
    wine_id: wine_id,
    vintage: vintage,
    quantity: bottles,
    notes: Some("Sample cellar purchase"),
    date: Some("2026-01-10"),
    price_cents: Some(1500),
  )
  case wine_type {
    db.White | db.Sparkling -> {
      let wishlist = db.get_user_wishlist(conn, username)
      db.add_wine_to_list(conn, wishlist.id, wine_id, vintage, None)
    }
    _ -> Nil
  }
}

pub fn seed_alice(conn: Connection, main_user: String) -> Nil {
  db.ensure_user(conn, "alice")

  let wines = db.list_wines(conn, main_user)
  let vintage_for = fn(wine: db.Wine) {
    db.vintages_for_wine(conn, wine.id) |> list.first |> option.from_result
  }

  // Rate some of the main user's wines as alice
  case wines {
    [w1, w2, w3, w4, w5, ..] -> {
      db.insert_rating(
        conn,
        username: "alice",
        wine_id: w1.id,
        vintage: vintage_for(w1),
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
        vintage: vintage_for(w2),
        rating: Some(3.8),
        tasting_notes: Some("Pleasant but not outstanding. Good acidity."),
        rated_at: Some("2025-12-01"),
      )
      db.insert_rating(
        conn,
        username: "alice",
        wine_id: w3.id,
        vintage: vintage_for(w3),
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
        vintage: vintage_for(w5),
        rating: Some(4.0),
        tasting_notes: Some("Solid everyday wine. Cherry and vanilla notes."),
        rated_at: Some("2026-03-05"),
      )

      // Cellar entries for alice
      db.insert_cellar_entry(
        conn,
        username: "alice",
        wine_id: w1.id,
        vintage: vintage_for(w1),
        quantity: 3,
        notes: Some("Picked up at the winery"),
        date: Some("2025-10-01"),
        price_cents: None,
      )
      db.insert_cellar_entry(
        conn,
        username: "alice",
        wine_id: w3.id,
        vintage: vintage_for(w3),
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
      db.add_wine_to_list(conn, alice_wishlist.id, w5.id, vintage_for(w5), None)
    }
    _ -> {
      // Not enough wines to seed, add a few ratings on whatever exists
      list.each(wines, fn(w) {
        db.insert_rating(
          conn,
          username: "alice",
          wine_id: w.id,
          vintage: vintage_for(w),
          rating: Some(4.0),
          tasting_notes: Some("Nice wine."),
          rated_at: Some("2026-01-01"),
        )
      })
    }
  }

  Nil
}
