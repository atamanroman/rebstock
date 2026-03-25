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
