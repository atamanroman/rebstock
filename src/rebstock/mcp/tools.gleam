import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/result
import sqlight.{type Connection}

import rebstock/mcp/imports
import rebstock/mcp/protocol
import rebstock/mcp/read
import rebstock/mcp/sync
import rebstock/vivino

pub fn catalog() -> List(Json) {
  let pagination = [
    #(
      "limit",
      json.object([
        #("type", json.string("integer")),
        #("minimum", json.int(1)),
        #("maximum", json.int(100)),
        #("default", json.int(50)),
      ]),
    ),
    #(
      "offset",
      json.object([
        #("type", json.string("integer")),
        #("minimum", json.int(0)),
        #("maximum", json.int(1_000_000)),
        #("default", json.int(0)),
      ]),
    ),
  ]
  let wine_id = #("wine_id", string_schema("Owned Rebstock wine ID"))
  [
    tool(
      "search_wines",
      "Find your wines by name, winery, or stored Vivino ID. Follow next_offset until null.",
      object_schema(
        [
          #("q", string_schema("Name, winery, or exact stored Vivino ID")),
          ..pagination
        ],
        [],
      ),
      True,
    ),
    tool(
      "get_wine",
      "Read an owned wine and its exact vintages, cached community ratings, and personal note.",
      object_schema([wine_id], ["wine_id"]),
      True,
    ),
    tool(
      "get_cellar",
      "Read your purchases and consumption entries, including dates, notes, and unit prices in cents.",
      object_schema([wine_id, ..pagination], []),
      True,
    ),
    tool(
      "get_ratings",
      "Read your personal ratings and tasting notes. These are separate from community ratings.",
      object_schema([wine_id, ..pagination], []),
      True,
    ),
    tool(
      "get_wishlist",
      "Read your wishlist with selected vintages and notes.",
      object_schema(pagination, []),
      True,
    ),
    tool(
      "import_batch",
      "Preview or apply structured wine, purchase, personal-rating, and wishlist records. Preview first. Keep source and per-record ref stable across retries; changed content under an applied ref is rejected. Maximum 100 records total.",
      imports.schema(),
      False,
    ),
    tool(
      "lookup_vivino_wine",
      "Fetch metadata and vintage ratings for an explicit Vivino URL, wine ID, or legacy v-prefixed vintage ID. Review the identity before linking; this tool makes no cellar changes.",
      object_schema(
        [
          #(
            "vivino_id",
            string_schema("Verified Vivino public URL or positive wine ID"),
          ),
        ],
        ["vivino_id"],
      ),
      True,
    ),
    tool(
      "sync_vivino_ratings",
      "Refresh community ratings and counts for 1..20 selected owned wines using stored Vivino links. Updates only overall and already-known vintage ratings; preserves metadata, personal ratings, and bottles. A partial failure is reported as an error with per-wine outcomes.",
      object_schema(
        [
          #(
            "wine_ids",
            json.object([
              #("type", json.string("array")),
              #("items", string_schema("Owned Rebstock wine ID")),
              #("minItems", json.int(1)),
              #("maxItems", json.int(20)),
              #("uniqueItems", json.bool(True)),
            ]),
          ),
        ],
        ["wine_ids"],
      ),
      False,
    ),
  ]
}

pub fn dispatch(
  conn: Connection,
  database_uri: String,
  username: String,
  name: String,
  arguments: Dynamic,
) -> Result(protocol.ToolResult, protocol.ToolError) {
  case name {
    "search_wines" -> success(read.search(conn, username, arguments))
    "get_wine" -> success(read.wine(conn, username, arguments))
    "get_cellar" -> success(read.cellar(conn, username, arguments))
    "get_ratings" -> success(read.ratings(conn, username, arguments))
    "get_wishlist" -> success(read.wishlist(conn, username, arguments))
    "import_batch" -> success(imports.run(database_uri, username, arguments))
    "lookup_vivino_wine" -> success(lookup(arguments))
    "sync_vivino_ratings" ->
      sync.run(database_uri, username, arguments, vivino.lookup)
      |> result.map(fn(outcome) {
        protocol.ToolResult(outcome.data, outcome.failed)
      })
      |> result.map_error(protocol.ExecutionError)
    _ -> Error(protocol.UnknownTool)
  }
}

fn success(
  outcome: Result(Json, String),
) -> Result(protocol.ToolResult, protocol.ToolError) {
  outcome
  |> result.map(fn(data) { protocol.ToolResult(data, False) })
  |> result.map_error(protocol.ExecutionError)
}

fn lookup(arguments: Dynamic) -> Result(Json, String) {
  use _ <- result.try(read.only(arguments, ["vivino_id"]))
  let decoder = {
    use id <- decode.field("vivino_id", decode.string)
    decode.success(id)
  }
  use id <- result.try(
    decode.run(arguments, decoder)
    |> result.map_error(fn(_) { "vivino_id is required" }),
  )
  use detail <- result.try(vivino.lookup(id))
  Ok(
    json.object([
      #("vivino_id", json.string(int.to_string(detail.wine_id))),
      #("winery", json.string(detail.winery_name)),
      #("winery_id", json.int(detail.winery_id)),
      #("name", json.string(detail.wine_name)),
      #("region", json.string(detail.region)),
      #("country", json.string(detail.country)),
      #("wine_type", json.string(detail.wine_type)),
      #("vivino_rating", case detail.rating >. 0.0 {
        True -> json.float(detail.rating)
        False -> json.null()
      }),
      #("vivino_rating_count", json.int(detail.rating_count)),
      #("label_url", json.string(detail.thumb_url)),
      #(
        "vintages",
        json.array(detail.vintages, fn(vintage) {
          json.object([
            #("year", json.string(vintage.year)),
            #("vivino_rating", case vintage.rating >. 0.0 {
              True -> json.float(vintage.rating)
              False -> json.null()
            }),
            #("vivino_rating_count", json.int(vintage.rating_count)),
          ])
        }),
      ),
    ]),
  )
}

fn tool(
  name: String,
  description: String,
  schema: Json,
  read_only: Bool,
) -> Json {
  json.object([
    #("name", json.string(name)),
    #("description", json.string(description)),
    #("inputSchema", schema),
    #(
      "annotations",
      json.object([
        #("readOnlyHint", json.bool(read_only)),
        #("destructiveHint", json.bool(False)),
        #("idempotentHint", json.bool(True)),
        #(
          "openWorldHint",
          json.bool(
            name == "lookup_vivino_wine" || name == "sync_vivino_ratings",
          ),
        ),
      ]),
    ),
  ])
}

fn object_schema(
  properties: List(#(String, Json)),
  required: List(String),
) -> Json {
  json.object([
    #("type", json.string("object")),
    #("properties", json.object(properties)),
    #("required", json.array(required, json.string)),
    #("additionalProperties", json.bool(False)),
  ])
}

fn string_schema(description: String) -> Json {
  json.object([
    #("type", json.string("string")),
    #("description", json.string(description)),
  ])
}
