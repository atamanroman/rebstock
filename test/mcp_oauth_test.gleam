import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import rebstock/auth
import rebstock/config as app_config
import rebstock/mcp/oauth
import wisp/simulate

type Server

@external(erlang, "mcp_oauth_test_ffi", "start")
fn start() -> #(String, Server)

@external(erlang, "mcp_oauth_test_ffi", "stop")
fn stop(server: Server) -> Nil

@external(erlang, "mcp_oauth_test_ffi", "token")
fn token(server: Server, header: String, claims: String) -> String

@external(erlang, "mcp_oauth_test_ffi", "response")
fn upstream_response(server: Server, status: Int, body: String) -> Nil

@external(erlang, "mcp_oauth_test_ffi", "rotate")
fn rotate(server: Server) -> Nil

@external(erlang, "mcp_oauth_test_ffi", "requests")
fn requests(server: Server) -> Int

@external(erlang, "mcp_oauth_test_ffi", "delay")
fn delay(server: Server, milliseconds: Int) -> Nil

@external(erlang, "mcp_oauth_test_ffi", "chunked")
fn chunked(server: Server) -> Nil

const header = "{\"alg\":\"RS256\",\"typ\":\"at+jwt\",\"kid\":\"first\"}"

fn claims() -> String {
  "{\"iss\":\"https://auth.example.com\",\"aud\":[\"https://rebstock.example.com/mcp\"],\"client_id\":\"rebstock-codex\",\"exp\":4102444800,\"nbf\":0,\"scope\":\"openid rebstock:mcp\",\"preferred_username\":\"alice\"}"
}

fn config(jwks_uri: String) -> oauth.Config {
  oauth.Config(
    resource: "https://rebstock.example.com/mcp",
    issuer: "https://auth.example.com",
    jwks_uri:,
    client_id: "rebstock-codex",
    scope: "rebstock:mcp",
    username_claim: "preferred_username",
  )
}

fn with_server(check: fn(oauth.Config, Server) -> Nil) {
  let #(url, server) = start()
  check(config(url), server)
  stop(server)
}

fn authenticate(config: oauth.Config, bearer: String) {
  simulate.request(http.Post, "/mcp")
  |> simulate.header("authorization", "Bearer " <> bearer)
  |> oauth.authenticate(config)
}

pub fn signed_access_token_maps_only_verified_username_test() {
  use config, server <- with_server
  let assert Ok(user) = authenticate(config, token(server, header, claims()))
  user |> should.equal(auth.User("alice", None, None, []))
}

pub fn missing_and_ambiguous_bearer_credentials_are_unauthorized_test() {
  let req =
    simulate.request(http.Post, "/mcp")
    |> simulate.header("x-webauth-user", "admin")
  oauth.authenticate(req, config("https://auth.example.com/jwks"))
  |> should.equal(Error(oauth.Unauthorized))
  use config, server <- with_server
  let bearer = token(server, header, claims())
  req
  |> request.prepend_header("authorization", "Bearer " <> bearer)
  |> request.prepend_header("authorization", "Bearer " <> bearer)
  |> oauth.authenticate(config)
  |> should.equal(Error(oauth.Unauthorized))
}

pub fn forged_signature_is_unauthorized_test() {
  use config, _server <- with_server
  use _other_config, other <- with_server
  authenticate(config, token(other, header, claims()))
  |> should.equal(Error(oauth.Unauthorized))
}

pub fn invalid_access_token_claims_are_unauthorized_test() {
  use config, server <- with_server
  [
    #(config.issuer, "https://wrong.example.com"),
    #(config.resource, "https://other.example.com/mcp"),
    #(config.client_id, "other-client"),
    #("4102444800", "1"),
    #("\"nbf\":0", "\"nbf\":4102444800"),
    #("\"alice\"", "\"\""),
    #("\"alice\"", "null"),
  ]
  |> list.each(fn(replacement) {
    let #(from, to) = replacement
    let jwt = token(server, header, string.replace(claims(), from, to))
    authenticate(config, jwt) |> should.equal(Error(oauth.Unauthorized))
  })
}

pub fn missing_required_scope_is_forbidden_test() {
  use config, server <- with_server
  let jwt =
    token(server, header, string.replace(claims(), "rebstock:mcp", "other"))
  authenticate(config, jwt) |> should.equal(Error(oauth.Forbidden))
}

pub fn wrong_algorithm_and_id_token_type_are_unauthorized_test() {
  use config, server <- with_server
  [
    string.replace(header, "RS256", "none"),
    string.replace(header, "RS256", "HS256"),
    string.replace(header, "at+jwt", "JWT"),
    string.replace(header, "first", "unknown"),
  ]
  |> list.each(fn(h) {
    authenticate(config, token(server, h, claims()))
    |> should.equal(Error(oauth.Unauthorized))
  })
}

pub fn unavailable_signing_keys_return_unavailable_test() {
  use config, server <- with_server
  upstream_response(server, 503, "unavailable")
  authenticate(config, token(server, header, claims()))
  |> should.equal(Error(oauth.Unavailable))
}

pub fn malformed_and_oversized_jwks_are_unavailable_test() {
  ["not json", string.repeat("x", 262_145)]
  |> list.each(fn(body) {
    use config, server <- with_server
    upstream_response(server, 200, body)
    authenticate(config, token(server, header, claims()))
    |> should.equal(Error(oauth.Unavailable))
  })
}

pub fn signing_keys_are_cached_and_new_key_ids_refresh_test() {
  use config, server <- with_server
  let jwt = token(server, header, claims())
  let assert Ok(_) = authenticate(config, jwt)
  let assert Ok(_) = authenticate(config, jwt)
  requests(server) |> should.equal(1)
  rotate(server)
  let rotated_header = string.replace(header, "first", "second")
  let assert Ok(_) =
    authenticate(config, token(server, rotated_header, claims()))
  requests(server) |> should.equal(2)
}

pub fn origins_match_only_the_configured_resource_origin_test() {
  let config = config("https://auth.example.com/jwks")
  let req = simulate.request(http.Post, "/mcp")
  oauth.valid_origin(req, config) |> should.be_true
  req
  |> simulate.header("origin", "https://rebstock.example.com")
  |> oauth.valid_origin(config)
  |> should.be_true
  [
    "null",
    "https://evil.example.com",
    "https://rebstock.example.com.evil.example.com",
    "https://rebstock.example.com/",
    "https://rebstock.example.com/mcp",
    "http://rebstock.example.com",
    "https://rebstock.example.com:444",
    "https://user@rebstock.example.com",
  ]
  |> list.each(fn(origin) {
    req
    |> simulate.header("origin", origin)
    |> oauth.valid_origin(config)
    |> should.be_false
  })
  req
  |> request.prepend_header("origin", "https://rebstock.example.com")
  |> request.prepend_header("origin", "https://rebstock.example.com")
  |> oauth.valid_origin(config)
  |> should.be_false
}

pub fn metadata_and_challenges_advertise_resource_issuer_and_scope_test() {
  let config = config("https://auth.example.com/jwks")
  let metadata = oauth.metadata(config)
  metadata.status |> should.equal(200)
  let body = simulate.read_body(metadata)
  string.contains(body, config.resource) |> should.be_true
  string.contains(body, config.issuer) |> should.be_true
  string.contains(body, config.scope) |> should.be_true
  let unauthorized = oauth.challenge(config, oauth.Unauthorized)
  unauthorized.status |> should.equal(401)
  let assert Ok(challenge) =
    response.get_header(unauthorized, "www-authenticate")
  string.contains(
    challenge,
    "resource_metadata=\"https://rebstock.example.com/.well-known/oauth-protected-resource/mcp\"",
  )
  |> should.be_true
  oauth.challenge(config, oauth.Forbidden).status |> should.equal(403)
  oauth.challenge(config, oauth.Unavailable).status |> should.equal(503)
}

pub fn oauth_decoder_requires_complete_safe_configuration_test() {
  let source =
    "{\"resource\":\"https://rebstock.example.com/mcp\",\"issuer\":\"https://auth.example.com\",\"jwks_uri\":\"https://auth.example.com/jwks\",\"client_id\":\"rebstock-codex\",\"scope\":\"rebstock:mcp\",\"username_claim\":\"preferred_username\"}"
  let assert Ok(_) = json.parse(source, oauth.decoder())
  [
    "{}",
    string.replace(
      source,
      "https://auth.example.com/jwks",
      "http://remote.example.com/jwks",
    ),
    string.replace(source, "rebstock:mcp", ""),
    string.replace(source, "rebstock-codex", "bad\"client"),
  ]
  |> list.each(fn(invalid) {
    json.parse(invalid, oauth.decoder()) |> should.be_error
  })
}

pub fn malformed_tokens_and_missing_or_wrong_claim_types_are_unauthorized_test() {
  use config, server <- with_server
  ["", "opaque-token", "a.b.c", string.repeat("x", 16_385)]
  |> list.each(fn(value) {
    authenticate(config, value) |> should.equal(Error(oauth.Unauthorized))
  })
  [
    string.replace(claims(), ",\"exp\":4102444800", ""),
    string.replace(claims(), "4102444800", "\"4102444800\""),
    string.replace(claims(), "\"nbf\":0", "\"nbf\":null"),
    string.replace(claims(), "\"alice\"", "\" alice \""),
    string.replace(claims(), "\"openid rebstock:mcp\"", "[\"rebstock:mcp\"]"),
    string.replace(claims(), "\"iss\":", "\"iss\":\"forged\",\"iss\":"),
  ]
  |> list.each(fn(invalid) {
    authenticate(config, token(server, header, invalid))
    |> should.equal(Error(oauth.Unauthorized))
  })
}

pub fn string_audience_and_optional_not_before_are_supported_test() {
  use config, server <- with_server
  let valid =
    claims()
    |> string.replace(
      "[\"https://rebstock.example.com/mcp\"]",
      "\"https://rebstock.example.com/mcp\"",
    )
    |> string.replace(",\"nbf\":0", "")
  let assert Ok(user) = authenticate(config, token(server, header, valid))
  user.username |> should.equal("alice")
}

pub fn token_key_urls_are_ignored_and_critical_headers_rejected_test() {
  use config, server <- with_server
  let untrusted_url_header =
    string.replace(
      header,
      "\"kid\":",
      "\"jku\":\"http://127.0.0.1:1/evil\",\"kid\":",
    )
  let assert Ok(_) =
    authenticate(config, token(server, untrusted_url_header, claims()))
  requests(server) |> should.equal(1)
  let critical =
    string.replace(header, "\"kid\":", "\"crit\":[\"unknown\"],\"kid\":")
  authenticate(config, token(server, critical, claims()))
  |> should.equal(Error(oauth.Unauthorized))
}

pub fn redirects_empty_keys_and_wrong_key_types_fail_closed_test() {
  [
    #(302, "redirect"),
    #(200, "{\"keys\":[]}"),
    #(
      200,
      "{\"keys\":[{\"kty\":\"oct\",\"kid\":\"first\",\"k\":\"not-a-public-key\"}]}",
    ),
  ]
  |> list.each(fn(upstream) {
    use config, server <- with_server
    upstream_response(server, upstream.0, upstream.1)
    authenticate(config, token(server, header, claims()))
    |> should.equal(Error(oauth.Unavailable))
  })
}

pub fn slow_signing_key_response_is_unavailable_test() {
  use config, server <- with_server
  delay(server, 3000)
  authenticate(config, token(server, header, claims()))
  |> should.equal(Error(oauth.Unavailable))
}

pub fn mcp_is_disabled_by_default_and_explicit_null_test() {
  app_config.default().mcp |> should.equal(None)
  app_config.parse("{\"auth\":{\"single\":{}},\"mcp\":null}").mcp
  |> should.equal(None)
}

pub fn chunked_signing_key_response_is_supported_test() {
  use config, server <- with_server
  chunked(server)
  let assert Ok(user) = authenticate(config, token(server, header, claims()))
  user.username |> should.equal("alice")
}

pub fn signing_key_outages_are_cached_briefly_test() {
  use config, server <- with_server
  upstream_response(server, 503, "unavailable")
  let jwt = token(server, header, claims())
  authenticate(config, jwt) |> should.equal(Error(oauth.Unavailable))
  authenticate(config, jwt) |> should.equal(Error(oauth.Unavailable))
  requests(server) |> should.equal(1)
}

pub fn failed_key_rotation_keeps_unexpired_known_keys_test() {
  use config, server <- with_server
  let jwt = token(server, header, claims())
  let assert Ok(_) = authenticate(config, jwt)
  upstream_response(server, 503, "unavailable")
  let new_header = string.replace(header, "first", "second")
  let new_jwt = token(server, new_header, claims())
  authenticate(config, new_jwt) |> should.equal(Error(oauth.Unavailable))
  let assert Ok(user) = authenticate(config, jwt)
  user.username |> should.equal("alice")
  authenticate(config, new_jwt) |> should.equal(Error(oauth.Unavailable))
  requests(server) |> should.equal(2)
}
