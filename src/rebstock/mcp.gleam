import gleam/http
import gleam/http/request
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth
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

/// Only the development router calls this; production never bypasses OAuth.
pub fn handle_local(
  req: Request,
  conn: Connection,
  config: Config,
) -> Response {
  case config.mcp, config.auth, config.host {
    None, auth.Single(username), "127.0.0.1"
    | None, auth.Single(username), "::1"
    -> {
      case valid_local_request(req, config.port) {
        False -> wisp.response(403)
        True ->
          case req.method {
            http.Post -> post_as_user(req, conn, config, username)
            _ -> wisp.method_not_allowed([http.Post])
          }
      }
    }
    _, _, _ -> wisp.not_found()
  }
}

fn valid_local_request(req: Request, port: Int) -> Bool {
  let suffix = case port {
    80 -> ""
    _ -> ":" <> int.to_string(port)
  }
  let hosts =
    list.map(["localhost", "127.0.0.1", "[::1]"], fn(host) { host <> suffix })
  let headers = fn(name) {
    req.headers
    |> list.filter_map(fn(header) {
      case string.lowercase(header.0) == name {
        True -> Ok(header.1)
        False -> Error(Nil)
      }
    })
  }
  let fetch_site_ok = case headers("sec-fetch-site") {
    [] | ["same-origin"] | ["same-site"] | ["none"] -> True
    _ -> False
  }
  case headers("host") {
    [host] -> {
      let host = string.lowercase(host)
      fetch_site_ok
      && list.contains(hosts, host)
      && case headers("origin") {
        [] -> True
        [origin] -> origin == "http://" <> host
        _ -> False
      }
    }
    _ -> False
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
    Ok(user) -> post_as_user(req, conn, config, user.username)
  }
}

fn post_as_user(
  req: Request,
  conn: Connection,
  config: Config,
  username: String,
) -> Response {
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
          protocol.respond(body, version, tools.catalog(), fn(name, arguments) {
            tools.dispatch(conn, config.database_uri, username, name, arguments)
          })
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
