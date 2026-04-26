# Vivino API Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Vivino API search and detail fetching to the existing vivino module, enabling wine lookup by name via Vivino's explore API.

**Architecture:** HTTP client (`gleam_httpc`) calls Vivino's explore API, decodes nested JSON responses into `VivinoSearchResult` records. Tests use mock JSON data (no live API calls). Search functions return `Result` types for error handling.

**Tech Stack:** gleam_httpc (HTTP client), gleam/json + gleam/dynamic/decode (JSON parsing), existing vivino.gleam module

---

### Task 1: Add gleam_httpc Dependency

**Files:**
- Modify: `gleam.toml`

- [ ] **Step 1: Add gleam_httpc to dependencies**

Add to `[dependencies]` in `gleam.toml`:

```toml
gleam_httpc = "~> 5.0"
```

- [ ] **Step 2: Build to fetch and verify**

Run: `gleam build`
Expected: Compiles successfully, httpc package downloaded

- [ ] **Step 3: Commit**

```bash
git add gleam.toml manifest.toml
git commit -m "chore: add gleam_httpc dependency"
```

---

### Task 2: Add VivinoSearchResult Type and User Agent

**Files:**
- Modify: `src/rebstock/vivino.gleam`

- [ ] **Step 1: Write test for search result type construction**

Create `test/vivino_test.gleam`:

```gleam
import gleeunit
import rebstock/vivino.{VivinoSearchResult}

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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL — `VivinoSearchResult` not exported from vivino module

- [ ] **Step 3: Add type and constant to vivino.gleam**

Add after existing `ImportResult` type in `src/rebstock/vivino.gleam`:

```gleam
pub const vivino_user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

pub type VivinoSearchResult {
  VivinoSearchResult(
    wine_id: Int,
    wine_name: String,
    winery_name: String,
    vintage: String,
    rating: Float,
    rating_count: Int,
    region: String,
    country: String,
    wine_type: String,
    thumb_url: String,
  )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `gleam test`
Expected: PASS

- [ ] **Step 5: Build with warnings check**

Run: `gleam build --warnings-as-errors`
Expected: Compiles with no warnings

- [ ] **Step 6: Commit**

```bash
gleam format .
git add src/rebstock/vivino.gleam test/vivino_test.gleam
git commit -m "feat: add VivinoSearchResult type and user agent constant"
```

---

### Task 3: Add JSON Decoder for Vivino Search Results

**Files:**
- Modify: `src/rebstock/vivino.gleam`
- Modify: `test/vivino_test.gleam`

The Vivino explore API returns nested JSON like:

```json
{
  "explore_vintage": {
    "matches": [
      {
        "vintage": {
          "year": "2016",
          "wine": {
            "id": 12345,
            "name": "Barolo Riserva",
            "type_id": 1,
            "winery": { "name": "Giacomo Conterno" },
            "region": {
              "name": "Barolo",
              "country": { "name": "Italy" }
            },
            "statistics": {
              "ratings_average": 4.6,
              "ratings_count": 2891
            }
          },
          "image": {
            "location": "//images.vivino.com/thumbs/wine.png"
          }
        }
      }
    ]
  }
}
```

- [ ] **Step 1: Write test for decoder with mock JSON**

Add to `test/vivino_test.gleam`:

```gleam
import gleam/json
import gleam/list
import rebstock/vivino.{VivinoSearchResult, search_results_decoder}

pub fn decode_search_results_test() {
  let mock_json =
    "{\"explore_vintage\":{\"matches\":[{\"vintage\":{\"year\":\"2016\",\"wine\":{\"id\":12345,\"name\":\"Barolo Riserva\",\"type_id\":1,\"winery\":{\"name\":\"Giacomo Conterno\"},\"region\":{\"name\":\"Barolo\",\"country\":{\"name\":\"Italy\"}},\"statistics\":{\"ratings_average\":4.6,\"ratings_count\":2891}},\"image\":{\"location\":\"//images.vivino.com/thumbs/wine.png\"}}}]}}"

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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL — `search_results_decoder` not found

- [ ] **Step 3: Implement the decoder**

Add to `src/rebstock/vivino.gleam` (new imports and decoder function):

Add imports:
```gleam
import gleam/dynamic/decode
import gleam/json
```

Add decoder function:
```gleam
fn wine_type_from_id(id: Int) -> String {
  case id {
    1 -> "Red"
    2 -> "White"
    3 -> "Sparkling"
    4 -> "Rosé"
    7 -> "Dessert"
    24 -> "Fortified"
    _ -> "Red"
  }
}

pub fn search_results_decoder() -> decode.Decoder(List(VivinoSearchResult)) {
  let image_decoder = {
    use location <- decode.field("location", decode.string)
    decode.success(location)
  }

  let stats_decoder = {
    use avg <- decode.field("ratings_average", decode.float)
    use count <- decode.field("ratings_count", decode.int)
    decode.success(#(avg, count))
  }

  let country_decoder = {
    use name <- decode.field("name", decode.string)
    decode.success(name)
  }

  let region_decoder = {
    use name <- decode.field("name", decode.string)
    use country <- decode.field("country", country_decoder)
    decode.success(#(name, country))
  }

  let winery_decoder = {
    use name <- decode.field("name", decode.string)
    decode.success(name)
  }

  let wine_decoder = {
    use id <- decode.field("id", decode.int)
    use name <- decode.field("name", decode.string)
    use type_id <- decode.field("type_id", decode.int)
    use winery_name <- decode.field("winery", winery_decoder)
    use region_pair <- decode.field("region", region_decoder)
    use stats <- decode.field("statistics", stats_decoder)
    let #(region, country) = region_pair
    let #(rating, rating_count) = stats
    decode.success(#(id, name, type_id, winery_name, region, country, rating, rating_count))
  }

  let match_decoder = {
    use year <- decode.field("year", decode.string)
    use wine_tuple <- decode.field("wine", wine_decoder)
    use thumb <- decode.field("image", image_decoder)
    let #(id, name, type_id, winery_name, region, country, rating, rating_count) = wine_tuple
    decode.success(VivinoSearchResult(
      wine_id: id,
      wine_name: name,
      winery_name: winery_name,
      vintage: year,
      rating: rating,
      rating_count: rating_count,
      region: region,
      country: country,
      wine_type: wine_type_from_id(type_id),
      thumb_url: "https:" <> thumb,
    ))
  }

  let vintage_decoder = {
    use result <- decode.field("vintage", match_decoder)
    decode.success(result)
  }

  use matches <- decode.field("explore_vintage", {
    use matches <- decode.field("matches", decode.list(vintage_decoder))
    decode.success(matches)
  })
  decode.success(matches)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `gleam test`
Expected: PASS

- [ ] **Step 5: Build with warnings check**

Run: `gleam build --warnings-as-errors`
Expected: No warnings

- [ ] **Step 6: Commit**

```bash
gleam format .
git add src/rebstock/vivino.gleam test/vivino_test.gleam
git commit -m "feat: add Vivino API search results JSON decoder"
```

---

### Task 4: Add HTTP Search Function

**Files:**
- Modify: `src/rebstock/vivino.gleam`
- Modify: `test/vivino_test.gleam`

- [ ] **Step 1: Write test for search URL construction**

Add to `test/vivino_test.gleam`:

```gleam
import rebstock/vivino.{search_url}

pub fn search_url_test() {
  let url = search_url("barolo")
  let assert True =
    string.contains(url, "vivino.com/api/explore/explore")
  let assert True = string.contains(url, "q=barolo")
  Nil
}

pub fn search_url_encoding_test() {
  let url = search_url("château margaux")
  let assert True = string.contains(url, "q=ch%C3%A2teau%20margaux")
  Nil
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL — `search_url` not found

- [ ] **Step 3: Implement search URL and search function**

Add imports to `src/rebstock/vivino.gleam`:

```gleam
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/uri
```

Add functions:

```gleam
pub fn search_url(query: String) -> String {
  let encoded = uri.percent_encode(query)
  "https://www.vivino.com/api/explore/explore?q="
  <> encoded
  <> "&language=en"
}

pub fn search(query: String) -> Result(List(VivinoSearchResult), String) {
  let url = search_url(query)
  case request.to(url) {
    Error(_) -> Error("Invalid search URL")
    Ok(req) -> {
      let req =
        req
        |> request.set_header("user-agent", vivino_user_agent)
        |> request.set_header("accept", "application/json")
      case httpc.send(req) {
        Error(_) -> Error("HTTP request failed")
        Ok(resp) ->
          case resp.status {
            200 ->
              case json.parse(resp.body, search_results_decoder()) {
                Ok(results) -> Ok(results)
                Error(_) -> Error("Failed to parse search results")
              }
            status -> Error("Vivino API returned status " <> int.to_string(status))
          }
      }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `gleam test`
Expected: PASS (URL tests pass, search function compiles)

- [ ] **Step 5: Build with warnings check**

Run: `gleam build --warnings-as-errors`
Expected: No warnings

- [ ] **Step 6: Commit**

```bash
gleam format .
git add src/rebstock/vivino.gleam test/vivino_test.gleam
git commit -m "feat: add Vivino API search function with HTTP client"
```

---

### Task 5: Add Wine Detail Fetching

**Files:**
- Modify: `src/rebstock/vivino.gleam`
- Modify: `test/vivino_test.gleam`

The Vivino wine detail endpoint returns data at `https://www.vivino.com/api/wines/{id}`.

- [ ] **Step 1: Write test for detail decoder**

Add to `test/vivino_test.gleam`:

```gleam
import rebstock/vivino.{VivinoSearchResult, wine_detail_decoder}

pub fn decode_wine_detail_test() {
  let mock_json =
    "{\"vintage\":{\"year\":\"2018\",\"wine\":{\"id\":67890,\"name\":\"Sassicaia\",\"type_id\":1,\"winery\":{\"name\":\"Tenuta San Guido\"},\"region\":{\"name\":\"Bolgheri\",\"country\":{\"name\":\"Italy\"}},\"statistics\":{\"ratings_average\":4.5,\"ratings_count\":15432}},\"image\":{\"location\":\"//images.vivino.com/thumbs/sass.png\"}}}"

  let assert Ok(result) = json.parse(mock_json, wine_detail_decoder())
  let assert "Sassicaia" = result.wine_name
  let assert "Tenuta San Guido" = result.winery_name
  let assert 67_890 = result.wine_id
  let assert "2018" = result.vintage
  Nil
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL — `wine_detail_decoder` not found

- [ ] **Step 3: Implement detail decoder and fetch function**

Add to `src/rebstock/vivino.gleam`:

```gleam
pub fn wine_detail_decoder() -> decode.Decoder(VivinoSearchResult) {
  use year <- decode.field("year", decode.string)
  use wine_tuple <- decode.field("wine", {
    use id <- decode.field("id", decode.int)
    use name <- decode.field("name", decode.string)
    use type_id <- decode.field("type_id", decode.int)
    use winery_name <- decode.field("winery", {
      use name <- decode.field("name", decode.string)
      decode.success(name)
    })
    use region_pair <- decode.field("region", {
      use name <- decode.field("name", decode.string)
      use country <- decode.field("country", {
        use name <- decode.field("name", decode.string)
        decode.success(name)
      })
      decode.success(#(name, country))
    })
    use stats <- decode.field("statistics", {
      use avg <- decode.field("ratings_average", decode.float)
      use count <- decode.field("ratings_count", decode.int)
      decode.success(#(avg, count))
    })
    decode.success(#(id, name, type_id, winery_name, region_pair, stats))
  })
  use thumb <- decode.field("image", {
    use location <- decode.field("location", decode.string)
    decode.success(location)
  })
  let #(id, name, type_id, winery_name, region_pair, stats) = wine_tuple
  let #(region, country) = region_pair
  let #(rating, rating_count) = stats
  decode.success(VivinoSearchResult(
    wine_id: id,
    wine_name: name,
    winery_name: winery_name,
    vintage: year,
    rating: rating,
    rating_count: rating_count,
    region: region,
    country: country,
    wine_type: wine_type_from_id(type_id),
    thumb_url: "https:" <> thumb,
  ))
}

pub fn fetch_wine_detail(
  wine_id: Int,
  vintage_year: String,
) -> Result(VivinoSearchResult, String) {
  let url =
    "https://www.vivino.com/api/wines/"
    <> int.to_string(wine_id)
    <> "/years/"
    <> vintage_year
  case request.to(url) {
    Error(_) -> Error("Invalid detail URL")
    Ok(req) -> {
      let req =
        req
        |> request.set_header("user-agent", vivino_user_agent)
        |> request.set_header("accept", "application/json")
      case httpc.send(req) {
        Error(_) -> Error("HTTP request failed")
        Ok(resp) ->
          case resp.status {
            200 ->
              case json.parse(resp.body, wine_detail_decoder()) {
                Ok(result) -> Ok(result)
                Error(_) -> Error("Failed to parse wine details")
              }
            status ->
              Error("Vivino API returned status " <> int.to_string(status))
          }
      }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `gleam test`
Expected: PASS

- [ ] **Step 5: Build with warnings check**

Run: `gleam build --warnings-as-errors`
Expected: No warnings

- [ ] **Step 6: Commit**

```bash
gleam format .
git add src/rebstock/vivino.gleam test/vivino_test.gleam
git commit -m "feat: add Vivino wine detail fetching and decoder"
```

---

### Task 6: Additional Test Coverage

**Files:**
- Modify: `test/vivino_test.gleam`

- [ ] **Step 1: Add edge case tests**

Add to `test/vivino_test.gleam`:

```gleam
pub fn decode_multiple_results_test() {
  let mock_json =
    "{\"explore_vintage\":{\"matches\":[{\"vintage\":{\"year\":\"2016\",\"wine\":{\"id\":111,\"name\":\"Wine A\",\"type_id\":1,\"winery\":{\"name\":\"Winery A\"},\"region\":{\"name\":\"Region A\",\"country\":{\"name\":\"France\"}},\"statistics\":{\"ratings_average\":3.8,\"ratings_count\":500}},\"image\":{\"location\":\"//img.vivino.com/a.png\"}}},{\"vintage\":{\"year\":\"2020\",\"wine\":{\"id\":222,\"name\":\"Wine B\",\"type_id\":2,\"winery\":{\"name\":\"Winery B\"},\"region\":{\"name\":\"Region B\",\"country\":{\"name\":\"Spain\"}},\"statistics\":{\"ratings_average\":4.2,\"ratings_count\":1200}},\"image\":{\"location\":\"//img.vivino.com/b.png\"}}}]}}"

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
  // Sparkling wine (type_id 3)
  let mock_json =
    "{\"explore_vintage\":{\"matches\":[{\"vintage\":{\"year\":\"NV\",\"wine\":{\"id\":333,\"name\":\"Dom Pérignon\",\"type_id\":3,\"winery\":{\"name\":\"Moët & Chandon\"},\"region\":{\"name\":\"Champagne\",\"country\":{\"name\":\"France\"}},\"statistics\":{\"ratings_average\":4.4,\"ratings_count\":8000}},\"image\":{\"location\":\"//img.vivino.com/dp.png\"}}}]}}"

  let assert Ok([result]) = json.parse(mock_json, search_results_decoder())
  let assert "Sparkling" = result.wine_type
  let assert "Dom Pérignon" = result.wine_name
  Nil
}

pub fn decode_invalid_json_test() {
  let bad_json = "{\"not_valid\": true}"
  let assert Error(_) = json.parse(bad_json, search_results_decoder())
  Nil
}
```

- [ ] **Step 2: Run all tests**

Run: `gleam test`
Expected: All PASS

- [ ] **Step 3: Final warnings check**

Run: `gleam build --warnings-as-errors`
Expected: No warnings

- [ ] **Step 4: Format and commit**

```bash
gleam format .
git add test/vivino_test.gleam
git commit -m "test: add comprehensive Vivino decoder test coverage"
```
