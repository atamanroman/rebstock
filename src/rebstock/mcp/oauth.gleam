import gleam/dynamic/decode
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import rebstock/auth
import wisp

pub type Config {
  Config(
    resource: String,
    issuer: String,
    jwks_uri: String,
    client_id: String,
    scope: String,
    username_claim: String,
  )
}

pub type Failure {
  Unauthorized
  Forbidden
  Unavailable
}

@external(erlang, "mcp_oauth_ffi", "verify")
fn verify(token: String, config: Config) -> Result(String, Failure)

@external(erlang, "mcp_oauth_ffi", "valid_config")
fn valid_config(config: Config) -> Bool

@external(erlang, "mcp_oauth_ffi", "resource_origin")
fn resource_origin(resource: String) -> String

@external(erlang, "mcp_oauth_ffi", "metadata_uri")
fn metadata_uri(resource: String) -> String

pub fn authenticate(
  req: wisp.Request,
  config: Config,
) -> Result(auth.User, Failure) {
  case header_values(req, "authorization") {
    [authorization] -> {
      case string.split(authorization, " ") {
        [scheme, token] if token != "" -> {
          case string.lowercase(scheme) == "bearer" {
            False -> Error(Unauthorized)
            True -> {
              case verify(token, config) {
                Ok(username) -> Ok(auth.User(username, None, None, []))
                Error(failure) -> Error(failure)
              }
            }
          }
        }
        _ -> Error(Unauthorized)
      }
    }
    _ -> Error(Unauthorized)
  }
}

pub fn challenge(config: Config, failure: Failure) -> wisp.Response {
  let #(status, error) = case failure {
    Unauthorized -> #(401, "invalid_token")
    Forbidden -> #(403, "insufficient_scope")
    Unavailable -> #(503, "temporarily_unavailable")
  }
  let challenge =
    "Bearer resource_metadata=\""
    <> metadata_uri(config.resource)
    <> "\", scope=\""
    <> config.scope
    <> "\", error=\""
    <> error
    <> "\""
  let result =
    wisp.response(status)
    |> response.set_header("cache-control", "no-store")
  case failure {
    Unavailable -> result |> response.set_header("retry-after", "5")
    _ -> result |> response.set_header("www-authenticate", challenge)
  }
}

pub fn metadata(config: Config) -> wisp.Response {
  json.object([
    #("resource", json.string(config.resource)),
    #("authorization_servers", json.array([config.issuer], json.string)),
    #("scopes_supported", json.array([config.scope], json.string)),
    #("bearer_methods_supported", json.array(["header"], json.string)),
    #("resource_name", json.string("Rebstock MCP")),
  ])
  |> json.to_string
  |> wisp.json_response(200)
  |> response.set_header("cache-control", "no-store")
}

pub fn valid_origin(req: wisp.Request, config: Config) -> Bool {
  case header_values(req, "origin") {
    [] -> True
    [origin] -> origin == resource_origin(config.resource)
    _ -> False
  }
}

fn header_values(req: wisp.Request, name: String) -> List(String) {
  req.headers
  |> list.filter_map(fn(header) {
    case string.lowercase(header.0) == name {
      True -> Ok(header.1)
      False -> Error(Nil)
    }
  })
}

pub fn decoder() -> decode.Decoder(Config) {
  use resource <- decode.field("resource", decode.string)
  use issuer <- decode.field("issuer", decode.string)
  use jwks_uri <- decode.field("jwks_uri", decode.string)
  use client_id <- decode.field("client_id", decode.string)
  use scope <- decode.field("scope", decode.string)
  use username_claim <- decode.field("username_claim", decode.string)
  let config =
    Config(resource:, issuer:, jwks_uri:, client_id:, scope:, username_claim:)
  case valid_config(config) {
    True -> decode.success(config)
    False -> decode.failure(config, "complete HTTPS MCP OAuth configuration")
  }
}
