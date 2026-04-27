import gleam/http
import gleam/option.{None, Some}
import wisp/simulate

import rebstock/auth
import rebstock/config

pub fn auth_single_mode_test() {
  let mode = auth.Single("bob")
  let user = auth.get_user(simulate.request(http.Get, "/"), mode)
  let assert "bob" = user.username
  let assert None = user.display_name
  Nil
}

pub fn auth_forward_mode_test() {
  let mode =
    auth.Forward(
      header_user: "x-user",
      header_name: "x-name",
      header_email: "x-email",
      header_groups: "x-groups",
    )
  let req =
    simulate.request(http.Get, "/")
    |> simulate.header("x-user", "alice")
    |> simulate.header("x-name", "Alice W")
    |> simulate.header("x-email", "alice@example.com")
    |> simulate.header("x-groups", "admin, users")
  let user = auth.get_user(req, mode)
  let assert "alice" = user.username
  let assert Some("Alice W") = user.display_name
  let assert Some("alice@example.com") = user.email
  let assert ["admin", "users"] = user.groups
  Nil
}

pub fn auth_forward_mode_missing_headers_test() {
  let mode =
    auth.Forward(
      header_user: "x-user",
      header_name: "x-name",
      header_email: "x-email",
      header_groups: "x-groups",
    )
  let user = auth.get_user(simulate.request(http.Get, "/"), mode)
  let assert "anonymous" = user.username
  let assert None = user.display_name
  let assert [] = user.groups
  Nil
}

pub fn config_single_mode_test() {
  let cfg = config.parse("{\"auth\": {\"single\": {\"user\": \"bob\"}}}")
  let assert auth.Single("bob") = cfg.auth
  let assert 3000 = cfg.port
  let assert "file:./data/rebstock.db" = cfg.database_uri
  Nil
}

pub fn config_forward_mode_test() {
  let cfg =
    config.parse(
      "{\"port\": 8080, \"auth\": {\"forward\": {\"header_user\": \"x-user\"}}}",
    )
  let assert auth.Forward(
    header_user: "x-user",
    header_name: "x-webauth-name",
    ..,
  ) = cfg.auth
  let assert 8080 = cfg.port
  Nil
}

pub fn config_defaults_test() {
  let cfg = config.parse("{\"auth\": {\"single\": {}}}")
  let assert auth.Single("admin") = cfg.auth
  let assert 3000 = cfg.port
  let assert "file:./data/rebstock.db" = cfg.database_uri
  let assert "./data/images" = cfg.image_dir
  Nil
}

pub fn config_missing_file_test() {
  let cfg = config.load("/nonexistent/config.json")
  let assert auth.Single("admin") = cfg.auth
  Nil
}

pub fn config_forward_load_test() {
  let cfg =
    config.parse(
      "{\"host\": \"0.0.0.0\", \"database_uri\": \"file:test.db\", \"auth\": {\"forward\": {}}}",
    )
  let assert auth.Forward(
    header_user: "x-webauth-user",
    header_name: "x-webauth-name",
    ..,
  ) = cfg.auth
  let assert "0.0.0.0" = cfg.host
  let assert "file:test.db" = cfg.database_uri
  Nil
}

pub fn config_load_existing_file_test() {
  let cfg = config.load("config.example.json")
  let assert True = cfg.port > 0
  Nil
}
