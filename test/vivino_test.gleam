import gleam/json
import gleam/list
import gleam/string
import gleeunit
import rebstock/vivino.{
  VivinoSearchResult, parse_vivino_id, search_results_decoder, search_url,
  wine_detail_decoder, wine_detail_mobile_decoder,
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn search_result_construction_test() {
  let result =
    VivinoSearchResult(
      wine_id: 12_345,
      wine_name: "Barolo Riserva",
      winery_name: "Giacomo Conterno",
      vintage: "2016",
      rating: 4.6,
      rating_count: 2891,
      region: "Barolo",
      country: "Italy",
      wine_type: "Red",
      thumb_url: "https://images.vivino.com/thumbs/wine.png",
    )
  let assert "Barolo Riserva" = result.wine_name
  let assert 12_345 = result.wine_id
  Nil
}

pub fn decode_search_results_test() {
  let mock_json =
    "{\"explore_vintage\":{\"matches\":[{\"vintage\":{\"year\":2016,\"statistics\":{\"wine_ratings_average\":4.6,\"wine_ratings_count\":2891},\"wine\":{\"id\":12345,\"name\":\"Barolo Riserva\",\"type_id\":1,\"winery\":{\"name\":\"Giacomo Conterno\"},\"region\":{\"name\":\"Barolo\",\"country\":{\"native_name\":\"Italy\"}}},\"image\":{\"location\":\"//images.vivino.com/thumbs/wine.png\"}}}]}}"

  let assert Ok(results) = json.parse(mock_json, search_results_decoder())
  let assert [first, ..] = results
  let assert "Barolo Riserva" = first.wine_name
  let assert "Giacomo Conterno" = first.winery_name
  let assert 12_345 = first.wine_id
  let assert "2016" = first.vintage
  let assert "Barolo" = first.region
  let assert "Italy" = first.country
  let assert 2891 = first.rating_count
  Nil
}

pub fn decode_empty_results_test() {
  let mock_json = "{\"explore_vintage\":{\"matches\":[]}}"
  let assert Ok(results) = json.parse(mock_json, search_results_decoder())
  let assert [] = results
  Nil
}

pub fn search_url_test() {
  let url = search_url("barolo")
  let assert True = string.contains(url, "vivino.com/api/explore/explore")
  let assert True = string.contains(url, "search_term=barolo")
  let assert True = string.contains(url, "min_rating=1")
  Nil
}

pub fn search_url_encoding_test() {
  let url = search_url("château margaux")
  let assert True = string.contains(url, "ch%C3%A2teau%20margaux")
  Nil
}

pub fn decode_wine_detail_test() {
  let mock_json =
    "{\"year\":2018,\"statistics\":{\"wine_ratings_average\":4.5,\"wine_ratings_count\":15432},\"wine\":{\"id\":67890,\"name\":\"Sassicaia\",\"type_id\":1,\"winery\":{\"name\":\"Tenuta San Guido\"},\"region\":{\"name\":\"Bolgheri\",\"country\":{\"native_name\":\"Italy\"}}},\"image\":{\"location\":\"//images.vivino.com/thumbs/sass.png\"}}"

  let assert Ok(result) = json.parse(mock_json, wine_detail_decoder())
  let assert "Sassicaia" = result.wine_name
  let assert "Tenuta San Guido" = result.winery_name
  let assert 67_890 = result.wine_id
  let assert "2018" = result.vintage
  Nil
}

pub fn decode_multiple_results_test() {
  let mock_json =
    "{\"explore_vintage\":{\"matches\":[{\"vintage\":{\"year\":2016,\"statistics\":{\"wine_ratings_average\":3.8,\"wine_ratings_count\":500},\"wine\":{\"id\":111,\"name\":\"Wine A\",\"type_id\":1,\"winery\":{\"name\":\"Winery A\"},\"region\":{\"name\":\"Region A\",\"country\":{\"native_name\":\"France\"}}},\"image\":{\"location\":\"//img.vivino.com/a.png\"}}},{\"vintage\":{\"year\":2020,\"statistics\":{\"wine_ratings_average\":4.2,\"wine_ratings_count\":1200},\"wine\":{\"id\":222,\"name\":\"Wine B\",\"type_id\":2,\"winery\":{\"name\":\"Winery B\"},\"region\":{\"name\":\"Region B\",\"country\":{\"native_name\":\"Spain\"}}},\"image\":{\"location\":\"//img.vivino.com/b.png\"}}}]}}"

  let assert Ok(results) = json.parse(mock_json, search_results_decoder())
  let assert 2 = list.length(results)
  let assert [first, second] = results
  let assert "Wine A" = first.wine_name
  let assert "Red" = first.wine_type
  let assert "Wine B" = second.wine_name
  let assert "White" = second.wine_type
  let assert "France" = first.country
  let assert "Spain" = second.country
  Nil
}

pub fn wine_type_mapping_test() {
  let mock_json =
    "{\"explore_vintage\":{\"matches\":[{\"vintage\":{\"year\":2015,\"statistics\":{\"wine_ratings_average\":4.4,\"wine_ratings_count\":8000},\"wine\":{\"id\":333,\"name\":\"Dom Pérignon\",\"type_id\":3,\"winery\":{\"name\":\"Moët & Chandon\"},\"region\":{\"name\":\"Champagne\",\"country\":{\"native_name\":\"France\"}}},\"image\":{\"location\":\"//img.vivino.com/dp.png\"}}}]}}"

  let assert Ok([result]) = json.parse(mock_json, search_results_decoder())
  let assert "Sparkling" = result.wine_type
  let assert "Dom Pérignon" = result.wine_name
  let assert "2015" = result.vintage
  Nil
}

pub fn decode_nv_year_test() {
  let mock_json =
    "{\"explore_vintage\":{\"matches\":[{\"vintage\":{\"year\":\"N.V.\",\"statistics\":{\"wine_ratings_average\":4.4,\"wine_ratings_count\":5000},\"wine\":{\"id\":555,\"name\":\"Brut Champagne\",\"type_id\":3,\"winery\":{\"name\":\"Krug\"},\"region\":{\"name\":\"Champagne\",\"country\":{\"native_name\":\"France\"}}},\"image\":{\"location\":\"//img.vivino.com/krug.png\"}}}]}}"

  let assert Ok([result]) = json.parse(mock_json, search_results_decoder())
  let assert "N.V." = result.vintage
  Nil
}

pub fn decode_missing_stats_test() {
  let mock_json =
    "{\"explore_vintage\":{\"matches\":[{\"vintage\":{\"year\":2020,\"wine\":{\"id\":444,\"name\":\"Unknown Wine\",\"type_id\":1,\"winery\":{\"name\":\"Small Winery\"},\"region\":{\"name\":\"Somewhere\",\"country\":{\"native_name\":\"France\"}}},\"image\":{\"location\":\"//img.vivino.com/x.png\"}}}]}}"

  let assert Ok([result]) = json.parse(mock_json, search_results_decoder())
  let assert 0.0 = result.rating
  let assert 0 = result.rating_count
  Nil
}

pub fn decode_invalid_json_test() {
  let bad_json = "{\"not_valid\": true}"
  let assert Error(_) = json.parse(bad_json, search_results_decoder())
  Nil
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

pub fn parse_vivino_id_invalid_test() {
  let assert Error(Nil) = parse_vivino_id("not-a-url")
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
