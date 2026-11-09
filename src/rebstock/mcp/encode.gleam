import gleam/json.{type Json}
import rebstock/db
import rebstock/vivino

pub fn wine(wine: db.Wine) -> Json {
  json.object([
    #("id", json.string(wine.id)),
    #("winery", json.string(wine.winery_name)),
    #("name", json.string(wine.name)),
    #("region", json.nullable(wine.region, json.string)),
    #("country", json.nullable(wine.country, json.string)),
    #("wine_type", json.string(db.wine_type_to_string(wine.wine_type))),
    #("style", json.nullable(wine.style, json.string)),
    #("personal_note", json.nullable(wine.personal_note, json.string)),
    #("vivino_id", json.nullable(wine.vivino_id, json.string)),
    #(
      "vivino_url",
      json.nullable(wine.vivino_id, fn(id) {
        json.string(vivino.vivino_url(id))
      }),
    ),
    #("vivino_rating", json.nullable(wine.vivino_rating, json.float)),
    #("vivino_rating_count", json.nullable(wine.vivino_rating_count, json.int)),
  ])
}

pub fn vintage(vintage: db.VintageRating) -> Json {
  json.object([
    #("year", json.string(vintage.year)),
    #("vivino_rating", json.nullable(vintage.rating, json.float)),
    #("vivino_rating_count", json.nullable(vintage.rating_count, json.int)),
  ])
}

pub fn cellar(entry: db.CellarEntry) -> Json {
  json.object([
    #("id", json.string(entry.id)),
    #("wine_id", json.string(entry.wine_id)),
    #("vintage", json.nullable(entry.vintage, json.string)),
    #("quantity", json.int(entry.quantity)),
    #("notes", json.nullable(entry.notes, json.string)),
    #("date", json.nullable(entry.date, json.string)),
    #("parent_id", json.nullable(entry.parent_id, json.string)),
    #("price_cents", json.nullable(entry.price_cents, json.int)),
  ])
}

pub fn rating(rating: db.Rating) -> Json {
  json.object([
    #("id", json.string(rating.id)),
    #("wine_id", json.string(rating.wine_id)),
    #("vintage", json.nullable(rating.vintage, json.string)),
    #("rating", json.nullable(rating.rating, json.float)),
    #("tasting_notes", json.nullable(rating.tasting_notes, json.string)),
    #("rated_at", json.nullable(rating.rated_at, json.string)),
  ])
}
