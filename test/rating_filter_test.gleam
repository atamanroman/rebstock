import gleam/http
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import sqlight.{type Connection}
import wisp/simulate

import rebstock/db
import rebstock/router
import test_helpers.{test_config, with_empty_db, with_seeded_db}

/// Ratings, Vivino scores and bottles chosen so every case below is decided
/// by exactly one of them:
///
///   wine     own            vivino               bottles
///   Alpha    4.5            4.2                  3
///   Bravo    3.8            4.6                  2
///   Charlie  none           3.4                  5
///   Delta    3.5 and 4.0    none                 1
///   Echo     5.0            4.9                  none
///   Foxtrot  4.2            3.0, 4.7 on the 2019 2
fn with_rated_cellar(f: fn(Connection) -> Nil) -> Nil {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")

  let alpha = wine(conn, "Alpha", "2020", Some(4.2))
  rate(conn, alpha, "2020", 4.5)
  stock(conn, alpha, "2020", 3)

  let bravo = wine(conn, "Bravo", "2018", Some(4.6))
  rate(conn, bravo, "2018", 3.8)
  stock(conn, bravo, "2018", 2)

  let charlie = wine(conn, "Charlie", "2022", Some(3.4))
  stock(conn, charlie, "2022", 5)

  let delta = wine(conn, "Delta", "2019", None)
  db.upsert_vintage(conn, delta, "2020")
  rate(conn, delta, "2019", 3.5)
  rate(conn, delta, "2020", 4.0)
  stock(conn, delta, "2020", 1)

  let echo_wine = wine(conn, "Echo", "2021", Some(4.9))
  rate(conn, echo_wine, "2021", 5.0)

  let foxtrot = wine(conn, "Foxtrot", "2019", Some(3.0))
  db.set_vintage_vivino_rating(conn, foxtrot, "2019", 4.7, None)
  rate(conn, foxtrot, "2019", 4.2)
  stock(conn, foxtrot, "2019", 2)

  f(conn)
}

fn wine(
  conn: Connection,
  name: String,
  vintage: String,
  vivino: Option(Float),
) -> String {
  let id =
    db.upsert_wine(
      conn,
      created_by: "test",
      winery: "Test Winery",
      name: name,
      vintage: Some(vintage),
      region: None,
      country: None,
      style: None,
      personal_note: None,
      wine_type: db.Red,
      vivino_id: None,
    )
  db.upsert_vintage(conn, id, vintage)
  case vivino {
    Some(rating) -> db.set_wine_vivino_rating(conn, id, rating, None)
    None -> Nil
  }
  id
}

fn rate(
  conn: Connection,
  wine_id: String,
  vintage: String,
  rating: Float,
) -> Nil {
  db.insert_rating(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some(vintage),
    rating: Some(rating),
    tasting_notes: None,
    rated_at: None,
  )
}

fn stock(
  conn: Connection,
  wine_id: String,
  vintage: String,
  quantity: Int,
) -> Nil {
  db.insert_cellar_entry(
    conn,
    username: "test",
    wine_id: wine_id,
    vintage: Some(vintage),
    quantity: quantity,
    notes: None,
    date: None,
  )
}

fn mine(score: db.ScoreFilter) -> db.RatingFilter {
  db.RatingFilter(..db.unfiltered, mine: score)
}

fn vivino(score: db.ScoreFilter) -> db.RatingFilter {
  db.RatingFilter(..db.unfiltered, vivino: score)
}

fn rated_wines(conn: Connection, filter: db.RatingFilter) -> List(String) {
  db.ratings_by_user(conn, "test", filter)
  |> list.map(fn(rating) {
    let assert Ok(wine) = db.get_wine_by_id(conn, rating.wine_id)
    wine.name
  })
  |> list.sort(string.compare)
}

fn cellared_wines(conn: Connection, filter: db.RatingFilter) -> List(String) {
  db.cellar_wines(conn, "test", filter)
  |> list.map(fn(cw) { cw.wine.name })
  |> list.sort(string.compare)
}

fn bottles(conn: Connection, filter: db.RatingFilter) -> Int {
  db.cellar_wines(conn, "test", filter)
  |> list.fold(0, fn(acc, cw) { acc + cw.bottles })
}

// --- Ratings ---

pub fn unfiltered_keeps_every_rating_test() {
  use conn <- with_rated_cellar
  let assert ["Alpha", "Bravo", "Delta", "Delta", "Echo", "Foxtrot"] =
    rated_wines(conn, db.unfiltered)
  Nil
}

pub fn rating_range_includes_both_bounds_test() {
  use conn <- with_rated_cellar
  let assert ["Alpha", "Delta", "Echo", "Foxtrot"] =
    rated_wines(conn, mine(db.ScoreRange(Some(4.0), Some(5.0))))
  Nil
}

pub fn rating_range_leaves_an_end_open_test() {
  use conn <- with_rated_cellar
  let assert ["Alpha", "Echo"] =
    rated_wines(conn, mine(db.ScoreRange(Some(4.5), None)))
  let assert ["Bravo", "Delta"] =
    rated_wines(conn, mine(db.ScoreRange(None, Some(3.8))))
  Nil
}

/// The vintage's own Vivino score wins over the wine's, so Foxtrot answers
/// for its 2019 rather than the 3.0 on the wine
pub fn vivino_range_prefers_the_vintage_score_test() {
  use conn <- with_rated_cellar
  let assert ["Bravo", "Echo", "Foxtrot"] =
    rated_wines(conn, vivino(db.ScoreRange(Some(4.5), None)))
  Nil
}

pub fn no_score_finds_what_vivino_never_rated_test() {
  use conn <- with_rated_cellar
  let assert ["Delta", "Delta"] = rated_wines(conn, vivino(db.NoScore))
  Nil
}

/// Delta is rated 4.0 but has no Vivino score, so a Vivino bound drops it
pub fn halves_narrow_together_test() {
  use conn <- with_rated_cellar
  let filter =
    db.RatingFilter(
      mine: db.ScoreRange(Some(4.0), None),
      vivino: db.ScoreRange(Some(4.0), None),
    )
  let assert ["Alpha", "Echo", "Foxtrot"] = rated_wines(conn, filter)
  Nil
}

// --- Cellar ---

pub fn unfiltered_keeps_every_bottle_test() {
  use conn <- with_rated_cellar
  let assert ["Alpha", "Bravo", "Charlie", "Delta", "Foxtrot"] =
    cellared_wines(conn, db.unfiltered)
  let assert 13 = bottles(conn, db.unfiltered)
  Nil
}

/// Delta is rated 3.5 and 4.0; the cellar scores it as the better of the two
pub fn cellar_scores_a_wine_by_its_best_rating_test() {
  use conn <- with_rated_cellar
  let filter = mine(db.ScoreRange(Some(4.0), None))
  let assert ["Alpha", "Delta", "Foxtrot"] = cellared_wines(conn, filter)
  let assert 6 = bottles(conn, filter)
  Nil
}

pub fn cellar_no_score_finds_untasted_bottles_test() {
  use conn <- with_rated_cellar
  let assert ["Charlie"] = cellared_wines(conn, mine(db.NoScore))
  let assert 5 = bottles(conn, mine(db.NoScore))
  let assert ["Delta"] = cellared_wines(conn, vivino(db.NoScore))
  Nil
}

pub fn cellar_halves_narrow_together_test() {
  use conn <- with_rated_cellar
  let filter =
    db.RatingFilter(
      mine: db.ScoreRange(None, Some(4.0)),
      vivino: db.ScoreRange(Some(4.5), None),
    )
  let assert ["Bravo"] = cellared_wines(conn, filter)
  let assert 2 = bottles(conn, filter)
  Nil
}

// --- Query parameters ---

fn body_of(conn: Connection, path: String) -> String {
  simulate.request(http.Get, path)
  |> router.handle_request(conn, test_config)
  |> simulate.read_body
}

pub fn query_params_filter_the_ratings_page_test() {
  use conn <- with_rated_cellar
  let body = body_of(conn, "/~test/ratings?my_min=4&my_max=5")
  let assert True = string.contains(body, "Alpha")
  let assert True = string.contains(body, "Foxtrot")
  let assert False = string.contains(body, "Bravo")
  Nil
}

pub fn query_params_compose_on_the_cellar_page_test() {
  use conn <- with_rated_cellar
  let body = body_of(conn, "/~test/cellar?my_min=4&vivino_min=4.5")
  let assert True = string.contains(body, "Foxtrot")
  let assert False = string.contains(body, "Alpha")
  let assert False = string.contains(body, "Delta")
  Nil
}

pub fn none_selects_the_unrated_bar_test() {
  use conn <- with_rated_cellar
  let body = body_of(conn, "/~test/cellar?my=none")
  let assert True = string.contains(body, "Charlie")
  let assert False = string.contains(body, "Alpha")
  Nil
}

/// Each chip drops its own half of the filter and leaves the other standing
pub fn chips_clear_one_half_test() {
  use conn <- with_rated_cellar
  let body = body_of(conn, "/~test/cellar?my_min=4&vivino_min=4.5")
  let assert True =
    string.contains(body, "href=\"/~test/cellar?vivino_min=4.5\"")
  let assert True = string.contains(body, "href=\"/~test/cellar?my_min=4\"")
  Nil
}

pub fn unreadable_bounds_are_ignored_test() {
  use conn <- with_rated_cellar
  let body = body_of(conn, "/~test/ratings?my_min=abc")
  let assert True = string.contains(body, "Bravo")
  Nil
}

// --- Bars and the lists they link to ---

/// A bar's link asks for the window of raw scores that rounds to it, so the
/// list it opens has to be as long as the bar is.
pub fn every_rating_bar_leads_to_its_own_rows_test() {
  use conn <- with_seeded_db
  let bars = db.rating_distribution(conn, "test")
  let assert [_, _, ..] = bars
  bars
  |> list.each(fn(bar) {
    let #(bucket, count) = bar
    let found = db.ratings_by_user(conn, "test", mine(window(bucket)))
    let assert True = count == list.length(found)
  })
}

pub fn every_cellar_bar_leads_to_its_own_bottles_test() {
  use conn <- with_seeded_db
  let own = db.cellar_own_distribution(conn, "test")
  let assert [_, _, ..] = own
  own
  |> list.each(fn(bar) {
    let #(bucket, count) = bar
    let assert True = count == bottles_for(conn, mine(window(bucket)))
  })
  let by_vivino = db.cellar_vivino_distribution(conn, "test")
  let assert [_, _, ..] = by_vivino
  by_vivino
  |> list.each(fn(bar) {
    let #(bucket, count) = bar
    let assert True = count == bottles_for(conn, vivino(window(bucket)))
  })
}

fn bottles_for(conn: Connection, filter: db.RatingFilter) -> Int {
  db.cellar_wines(conn, "test", filter)
  |> list.fold(0, fn(acc, cw) { acc + cw.bottles })
}

/// The same window `bar_url` builds, kept in step with it by hand
fn window(bucket: Option(Float)) -> db.ScoreFilter {
  case bucket {
    None -> db.NoScore
    Some(rating) -> db.ScoreRange(Some(rating -. 0.25), Some(rating +. 0.25))
  }
}
