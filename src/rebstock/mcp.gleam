import gleam/http
import gleam/http/request
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/config.{type Config}
import rebstock/mcp/oauth
import rebstock/mcp/protocol
import rebstock/mcp/tools

pub fn handle(req: Request, conn: Connection, config: Config) -> Response {
  case config.mcp {
    None -> wisp.not_found()
    Some(auth_config) ->
      case oauth.valid_origin(req, auth_config) {
        False -> wisp.response(403)
        True ->
          case req.method {
            http.Post -> post(req, conn, config, auth_config)
            _ -> wisp.method_not_allowed([http.Post])
          }
      }
  }
}

pub fn metadata(req: Request, config: Config) -> Response {
  use req <- wisp.handle_head(req)
  case config.mcp, req.method {
    None, _ -> wisp.not_found()
    Some(auth_config), http.Get -> oauth.metadata(auth_config)
    Some(_), _ -> wisp.method_not_allowed([http.Get, http.Head])
  }
}

fn post(
  req: Request,
  conn: Connection,
  config: Config,
  auth_config: oauth.Config,
) -> Response {
  case oauth.authenticate(req, auth_config) {
    Error(failure) -> oauth.challenge(auth_config, failure)
    Ok(user) ->
      case
        media_type(request.get_header(req, "content-type") |> result.unwrap(""))
        == "application/json"
      {
        False -> wisp.unsupported_media_type(["application/json"])
        True ->
          case accepts_json(req) {
            False -> wisp.response(406)
            True -> {
              let req = wisp.set_max_body_size(req, 1_048_576)
              use body <- wisp.require_string_body(req)
              let version =
                request.get_header(req, "mcp-protocol-version")
                |> option.from_result
              protocol.respond(
                body,
                version,
                tools.catalog(),
                fn(name, arguments) {
                  tools.dispatch(
                    conn,
                    config.database_uri,
                    user.username,
                    name,
                    arguments,
                  )
                },
              )
            }
          }
      }
  }
}

fn media_type(value: String) -> String {
  value |> string.split(";") |> list_first |> string.trim |> string.lowercase
}

fn accepts_json(req: Request) -> Bool {
  req
  |> request.get_header("accept")
  |> result.unwrap("")
  |> string.split(",")
  |> contains_json
}

fn contains_json(types: List(String)) -> Bool {
  case types {
    [] -> False
    [first, ..rest] ->
      media_type(first) == "application/json" || contains_json(rest)
  }
}

fn list_first(values: List(String)) -> String {
  case values {
    [value, ..] -> value
    [] -> ""
  }
}
