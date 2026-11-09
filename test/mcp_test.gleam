import gleam/http
import gleam/option.{Some}
import gleam/string
import wisp/simulate

import rebstock/config
import rebstock/db
import rebstock/mcp/oauth
import rebstock/router
import test_helpers.{test_config, with_empty_db}

fn enabled() {
  config.Config(
    ..test_config,
    mcp: Some(oauth.Config(
      resource: "https://rebstock.example.com/mcp",
      issuer: "https://id.example.com",
      jwks_uri: "https://id.example.com/jwks.json",
      client_id: "rebstock-codex",
      scope: "rebstock:mcp",
      username_claim: "preferred_username",
    )),
  )
}

pub fn mcp_is_disabled_by_default_without_creating_web_users_test() {
  use conn <- with_empty_db
  let response =
    router.handle_request(
      simulate.request(http.Post, "/mcp"),
      conn,
      test_config,
    )
  let assert 404 = response.status
  let assert 0 = db.count_users(conn)
  Nil
}

pub fn mcp_missing_token_cannot_inherit_single_or_forward_auth_test() {
  use conn <- with_empty_db
  let req =
    simulate.request(http.Post, "/mcp")
    |> simulate.header("x-webauth-user", "test")
  let response = router.handle_request(req, conn, enabled())
  let assert 401 = response.status
  let assert "" = simulate.read_body(response)
  let assert 0 = db.count_users(conn)
  Nil
}

pub fn mcp_metadata_is_public_and_does_not_create_users_test() {
  use conn <- with_empty_db
  let response =
    router.handle_request(
      simulate.request(http.Get, "/.well-known/oauth-protected-resource/mcp"),
      conn,
      enabled(),
    )
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "https://rebstock.example.com/mcp")
  let assert True = string.contains(body, "https://id.example.com")
  let assert 0 = db.count_users(conn)
  Nil
}

pub fn mcp_rejects_hostile_origins_before_parsing_or_authentication_test() {
  use conn <- with_empty_db
  let req =
    simulate.request(http.Post, "/mcp")
    |> simulate.header("origin", "https://rebstock.example.com.evil.invalid")
  let response = router.handle_request(req, conn, enabled())
  let assert 403 = response.status
  let assert 0 = db.count_users(conn)
  Nil
}

pub fn mcp_does_not_advertise_unsupported_streams_or_sessions_test() {
  use conn <- with_empty_db
  let get =
    router.handle_request(simulate.request(http.Get, "/mcp"), conn, enabled())
  let delete =
    router.handle_request(
      simulate.request(http.Delete, "/mcp"),
      conn,
      enabled(),
    )
  let assert 405 = get.status
  let assert 405 = delete.status
  Nil
}
