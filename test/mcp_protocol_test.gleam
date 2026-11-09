import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import wisp/simulate

import rebstock/mcp/protocol

fn call(
  name: String,
  _arguments: dynamic.Dynamic,
) -> Result(protocol.ToolResult, protocol.ToolError) {
  case name {
    "example" ->
      Ok(protocol.ToolResult(json.object([#("answer", json.int(42))]), False))
    _ -> Error(protocol.ExecutionError("Invalid source record"))
  }
}

fn respond(body: String) {
  protocol.respond(body, Some("2025-11-25"), [], call)
}

pub fn mcp_initializes_and_negotiates_supported_version_test() {
  let response =
    respond(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"future\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1\"}}}",
    )
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "2025-11-25")
  let assert True = string.contains(body, "\"tools\"")
}

pub fn mcp_tool_calls_return_structured_and_text_results_test() {
  let response =
    respond(
      "{\"jsonrpc\":\"2.0\",\"id\":\"request\",\"method\":\"tools/call\",\"params\":{\"name\":\"example\",\"arguments\":{}}}",
    )
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True =
    string.contains(body, "\"structuredContent\":{\"answer\":42}")
  let assert True = string.contains(body, "\"isError\":false")
  let assert True = string.contains(body, "\"id\":\"request\"")
}

pub fn mcp_tool_failure_is_not_reported_as_success_test() {
  let response =
    respond(
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"bad\",\"arguments\":{}}}",
    )
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "\"isError\":true")
  let assert True = string.contains(body, "Invalid source record")
  let assert Ok("Invalid source record") =
    json.parse(
      body,
      decode.at(
        ["result", "structuredContent", "error", "message"],
        decode.string,
      ),
    )
}

pub fn mcp_valid_notifications_are_accepted_without_dispatch_test() {
  let response =
    protocol.respond(
      "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
      None,
      [],
      fn(_, _) { panic as "Notifications must not call tools" },
    )
  let assert 202 = response.status
  let assert "" = simulate.read_body(response)
}

pub fn mcp_missing_request_id_cannot_execute_a_mutation_test() {
  let response =
    protocol.respond(
      "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"example\"}}",
      None,
      [],
      fn(_, _) { panic as "A notification must not run mutations" },
    )
  let assert 400 = response.status
}

pub fn mcp_malformed_json_and_batch_requests_have_protocol_errors_test() {
  let parse_error = respond("{") |> simulate.read_body
  let invalid_request = respond("[]") |> simulate.read_body
  let invalid_id =
    respond("{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":\"ping\"}")
    |> simulate.read_body
  let assert True = string.contains(parse_error, "-32700")
  let assert True = string.contains(invalid_request, "-32600")
  let assert True = string.contains(invalid_id, "-32600")
}

pub fn mcp_unknown_methods_and_invalid_parameters_have_protocol_errors_test() {
  let unknown =
    respond("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"sql\"}")
    |> simulate.read_body
  let invalid =
    respond(
      "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{}}",
    )
    |> simulate.read_body
  let assert True = string.contains(unknown, "-32601")
  let assert True = string.contains(invalid, "-32602")
}

pub fn mcp_rejects_unsupported_version_on_noninitialization_requests_test() {
  let response =
    protocol.respond(
      "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"ping\"}",
      Some("future"),
      [],
      call,
    )
  let assert 400 = response.status
}
