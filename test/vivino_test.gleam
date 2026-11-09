import gleam/json
import gleam/list
import gleeunit
import rebstock/vivino.{parse_vivino_id, wine_detail_mobile_decoder}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn decode_mobile_wine_detail_test() {
  let mock_json =
    "{\"id\":23337,\"name\":\"Aalto\",\"type_id\":1,\"winery\":{\"id\":7999,\"name\":\"Aalto\"},\"region\":{\"name\":\"Ribera del Duero\",\"country\":\"es\"},\"statistics\":{\"ratings_average\":4.4,\"ratings_count\":50020},\"image\":{\"location\":\"//images.vivino.com/thumbs/aalto.png\"},\"vintages\":[{\"year\":\"2020\",\"statistics\":{\"ratings_average\":4.4,\"ratings_count\":3835}},{\"year\":\"2021\",\"statistics\":{\"ratings_average\":4.4,\"ratings_count\":3347}},{\"year\":\"2025\",\"statistics\":{\"ratings_average\":0,\"ratings_count\":2}},{\"year\":\"\",\"statistics\":{\"ratings_average\":4.4,\"ratings_count\":50020}}]}"

  let assert Ok(result) = json.parse(mock_json, wine_detail_mobile_decoder())
  let assert "Aalto" = result.wine_name
  let assert "Aalto" = result.winery_name
  let assert 7999 = result.winery_id
  let assert 23_337 = result.wine_id
  let assert "Ribera del Duero" = result.region
  let assert "es" = result.country
  let assert "Red" = result.wine_type
  // Empty year is filtered, vintages with 0.0 rating are kept (imported without rating)
  let assert 3 = list.length(result.vintages)
  let assert [first, second, third] = result.vintages
  let assert "2020" = first.year
  let assert 3835 = first.rating_count
  let assert "2021" = second.year
  let assert "2025" = third.year
  let assert 0.0 = third.rating
  Nil
}

pub fn parse_vivino_id_plain_test() {
  let assert Ok("6184388") = parse_vivino_id("6184388")
  Nil
}

pub fn parse_vivino_id_url_test() {
  let assert Ok("6184388") =
    parse_vivino_id(
      "https://www.vivino.com/en/buglioni-teste-dure-amarone-riserva/w/6184388",
    )
  Nil
}

pub fn parse_vivino_id_url_with_query_test() {
  let assert Ok("6184388") =
    parse_vivino_id(
      "https://www.vivino.com/en/buglioni-teste-dure-amarone-riserva/w/6184388?year=2015&price_id=34701637",
    )
  Nil
}

pub fn parse_vivino_id_vintage_url_test() {
  // CSV-style /wines/ URLs carry vintage IDs, returned with the
  // unresolved-vintage prefix.
  let assert Ok("v3269106") =
    parse_vivino_id("https://www.vivino.com/wines/3269106?year=2015")
  Nil
}

pub fn parse_vivino_id_invalid_test() {
  let assert Error(Nil) = parse_vivino_id("not-a-url")
  Nil
}

pub fn parse_vivino_id_rejects_nonpositive_ids_and_unrelated_hosts_test() {
  let assert Error(Nil) = parse_vivino_id("0")
  let assert Error(Nil) = parse_vivino_id("-123")
  let assert Error(Nil) = parse_vivino_id("https://example.com/w/123")
  let assert Error(Nil) =
    parse_vivino_id("https://vivino.com.evil.example/w/123")
  let assert Error(Nil) =
    parse_vivino_id("https://www.vivino.com/w/123/../../w/456")
  Nil
}

pub fn decode_vivino_country_objects_and_absolute_images_test() {
  let source =
    "{\"id\":123,\"name\":\"Wine\",\"type_id\":999,\"winery\":{\"id\":7,\"name\":\"Winery\"},\"region\":{\"name\":\"Mosel\",\"country\":{\"code\":\"de\",\"name\":\"Germany\"}},\"image\":{\"location\":\"https://images.vivino.com/label.png\"}}"
  let assert Ok(wine) = json.parse(source, wine_detail_mobile_decoder())
  let assert "de" = wine.country
  let assert "Other" = wine.wine_type
  let assert "https://images.vivino.com/label.png" = wine.thumb_url
  Nil
}

pub fn decode_mobile_no_vintages_test() {
  let mock_json =
    "{\"id\":99999,\"name\":\"Test Wine\",\"type_id\":2,\"winery\":{\"id\":1,\"name\":\"Test Winery\"},\"statistics\":{\"ratings_average\":3.5,\"ratings_count\":100},\"image\":{\"location\":\"//images.vivino.com/thumbs/test.png\"}}"

  let assert Ok(result) = json.parse(mock_json, wine_detail_mobile_decoder())
  let assert "Test Wine" = result.wine_name
  let assert "White" = result.wine_type
  let assert [] = result.vintages
  Nil
}
