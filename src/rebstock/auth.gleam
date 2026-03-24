import envoy
import gleam/http/request.{type Request}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type User {
  User(
    username: String,
    display_name: Option(String),
    email: Option(String),
    groups: List(String),
  )
}

pub type AuthMode {
  Single(default_user: String)
  Forward(
    header_user: String,
    header_name: String,
    header_email: String,
    header_groups: String,
  )
}

pub fn config_from_env() -> AuthMode {
  case envoy.get("REBSTOCK_AUTH_MODE") {
    Ok("forward") ->
      Forward(
        header_user: env_or("REBSTOCK_HEADER_USER", "x-webauth-user"),
        header_name: env_or("REBSTOCK_HEADER_NAME", "x-webauth-name"),
        header_email: env_or("REBSTOCK_HEADER_EMAIL", "x-webauth-email"),
        header_groups: env_or("REBSTOCK_HEADER_GROUPS", "x-webauth-groups"),
      )
    _ -> Single(default_user: env_or("REBSTOCK_DEFAULT_USER", "admin"))
  }
}

pub fn get_user(req: Request(a), auth: AuthMode) -> User {
  case auth {
    Single(default_user) ->
      User(
        username: default_user,
        display_name: None,
        email: None,
        groups: [],
      )
    Forward(header_user:, header_name:, header_email:, header_groups:) -> {
      let username = case request.get_header(req, header_user) {
        Ok(v) -> v
        Error(_) -> "anonymous"
      }
      let display_name = case request.get_header(req, header_name) {
        Ok(v) -> Some(v)
        Error(_) -> None
      }
      let email = case request.get_header(req, header_email) {
        Ok(v) -> Some(v)
        Error(_) -> None
      }
      let groups = case request.get_header(req, header_groups) {
        Ok(v) ->
          string.split(v, ",")
          |> list.map(string.trim)
        Error(_) -> []
      }
      User(username:, display_name:, email:, groups:)
    }
  }
}

fn env_or(key: String, default: String) -> String {
  case envoy.get(key) {
    Ok(v) -> v
    Error(_) -> default
  }
}
