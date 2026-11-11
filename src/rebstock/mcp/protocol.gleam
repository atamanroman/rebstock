import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import wisp.{type Response}

const supported_versions = ["2025-11-25", "2025-06-18", "2025-03-26"]

pub const version = "2025-11-25"

pub type ToolResult {
  ToolResult(data: Json, is_error: Bool)
}

pub type ToolError {
  ExecutionError(message: String)
  UnknownTool
}

type Message {
  Message(id: Option(Json), method: String, params: Dynamic)
}

pub fn respond(
  body: String,
  protocol_version: Option(String),
  catalog: List(Json),
  dispatch: fn(String, Dynamic) -> Result(ToolResult, ToolError),
) -> Response {
  case json.parse(body, decode.dynamic) {
    Error(_) -> rpc_error(json.null(), -32_700, "Parse error", 400)
    Ok(data) ->
      case decode.run(data, message_decoder()) {
        Error(_) -> rpc_error(json.null(), -32_600, "Invalid request", 400)
        Ok(message) -> {
          case message.method, protocol_version {
            "initialize", _ -> handle(message, catalog, dispatch)
            _, None -> handle(message, catalog, dispatch)
            _, Some(v) ->
              case list.contains(supported_versions, v) {
                True -> handle(message, catalog, dispatch)
                False ->
                  rpc_error(
                    option.unwrap(message.id, json.null()),
                    -32_600,
                    "Unsupported MCP protocol version",
                    400,
                  )
              }
          }
        }
      }
  }
}

fn message_decoder() -> decode.Decoder(Message) {
  use jsonrpc <- decode.field("jsonrpc", decode.string)
  use method <- decode.field("method", decode.string)
  use id <- decode.optional_field(
    "id",
    None,
    decode.map(
      decode.one_of(decode.map(decode.int, json.int), [
        decode.map(decode.string, json.string),
      ]),
      Some,
    ),
  )
  use params <- decode.optional_field(
    "params",
    dynamic_empty_object(),
    decode.dynamic,
  )
  case jsonrpc == "2.0" && method != "" {
    True -> decode.success(Message(id:, method:, params:))
    False ->
      decode.failure(Message(id:, method:, params:), "JSON-RPC 2.0 request")
  }
}

fn handle(
  message: Message,
  catalog: List(Json),
  dispatch: fn(String, Dynamic) -> Result(ToolResult, ToolError),
) -> Response {
  case message.id, message.method {
    None, "notifications/initialized" | None, "notifications/cancelled" ->
      wisp.response(202)
    None, _ -> rpc_error(json.null(), -32_600, "Request ID required", 400)
    Some(id), "initialize" -> initialize(id, message.params)
    Some(id), "ping" -> rpc_success(id, json.object([]))
    Some(id), "tools/list" ->
      rpc_success(
        id,
        json.object([#("tools", json.preprocessed_array(catalog))]),
      )
    Some(id), "tools/call" ->
      case decode.run(message.params, call_decoder()) {
        Error(_) ->
          rpc_error(id, -32_602, "Expected tool name and object arguments", 200)
        Ok(#(name, arguments)) ->
          case dispatch(name, arguments) {
            Ok(outcome) -> rpc_success(id, tool_success(outcome))
            Error(ExecutionError(message)) ->
              rpc_success(id, tool_error(message))
            Error(UnknownTool) -> rpc_error(id, -32_602, "Unknown tool", 200)
          }
      }
    Some(id), _ -> rpc_error(id, -32_601, "Method not found", 200)
  }
}

fn initialize(id: Json, params: Dynamic) -> Response {
  let decoder = {
    use requested <- decode.field("protocolVersion", decode.string)
    use _capabilities <- decode.field(
      "capabilities",
      decode.dict(decode.string, decode.dynamic),
    )
    use _client <- decode.field("clientInfo", {
      use name <- decode.field("name", decode.string)
      use version <- decode.field("version", decode.string)
      decode.success(#(name, version))
    })
    decode.success(requested)
  }
  case decode.run(params, decoder) {
    Error(_) -> rpc_error(id, -32_602, "Invalid initialization parameters", 200)
    Ok(requested) -> {
      let negotiated = case list.contains(supported_versions, requested) {
        True -> requested
        False -> version
      }
      rpc_success(
        id,
        json.object([
          #("protocolVersion", json.string(negotiated)),
          #("capabilities", json.object([#("tools", json.object([]))])),
          #(
            "serverInfo",
            json.object([
              #("name", json.string("Rebstock")),
              #("version", json.string("0.4.0")),
            ]),
          ),
          #(
            "instructions",
            json.string(
              "Read before importing. Use stable source references and preview import_batch before applying it. Personal ratings and Vivino community ratings are separate.",
            ),
          ),
        ]),
      )
    }
  }
}

fn call_decoder() -> decode.Decoder(#(String, Dynamic)) {
  use name <- decode.field("name", decode.string)
  use arguments <- decode.optional_field(
    "arguments",
    dynamic_empty_object(),
    decode.dynamic,
  )
  use _ <- decode.then(
    case decode.run(arguments, decode.dict(decode.string, decode.dynamic)) {
      Ok(_) -> decode.success(Nil)
      Error(_) -> decode.failure(Nil, "Object arguments")
    },
  )
  decode.success(#(name, arguments))
}

fn dynamic_empty_object() -> Dynamic {
  dynamic.properties([])
}

fn rpc_success(id: Json, value: Json) -> Response {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", id),
    #("result", value),
  ])
  |> json.to_string
  |> wisp.json_response(200)
  |> wisp.set_header("cache-control", "no-store")
}

pub fn rpc_error(
  id: Json,
  code: Int,
  message: String,
  status: Int,
) -> Response {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", id),
    #(
      "error",
      json.object([
        #("code", json.int(code)),
        #("message", json.string(message)),
      ]),
    ),
  ])
  |> json.to_string
  |> wisp.json_response(status)
  |> wisp.set_header("cache-control", "no-store")
}

fn tool_success(outcome: ToolResult) -> Json {
  json.object([
    #(
      "content",
      json.preprocessed_array([
        json.object([
          #("type", json.string("text")),
          #("text", json.string(json.to_string(outcome.data))),
        ]),
      ]),
    ),
    #("structuredContent", outcome.data),
    #("isError", json.bool(outcome.is_error)),
  ])
}

fn tool_error(message: String) -> Json {
  json.object([
    #(
      "content",
      json.preprocessed_array([
        json.object([
          #("type", json.string("text")),
          #("text", json.string(message)),
        ]),
      ]),
    ),
    #(
      "structuredContent",
      json.object([
        #("error", json.object([#("message", json.string(message))])),
      ]),
    ),
    #("isError", json.bool(True)),
  ])
}
