import gleam/http
import gleam/http/request
import gleam/list
import gleam/option.{Some}
import gleam/string
import rebstock/auth
import rebstock/config
import rebstock/mcp/oauth
import rebstock/router
import test_helpers.{test_config, with_empty_db}
import wisp/simulate

fn local_request() {
  simulate.request(http.Post, "/mcp")
  |> simulate.header("host", "127.0.0.1:3000")
  |> simulate.header("accept", "application/json")
  |> simulate.string_body(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}",
  )
  |> simulate.header("content-type", "application/json")
}

pub fn local_mcp_is_dev_only_test() {
  use conn <- with_empty_db
  let req = local_request()
  let prod = router.handle_request(req, conn, test_config)
  let dev = router.handle_dev_request(req, conn, test_config)
  let assert 404 = prod.status
  let assert 200 = dev.status
  let assert True = string.contains(simulate.read_body(dev), "import_batch")
  Nil
}

pub fn local_mcp_rejects_non_loopback_bindings_and_forward_auth_test() {
  use conn <- with_empty_db
  list.each(["0.0.0.0", "::", "192.168.1.1", "example.com"], fn(host) {
    let res =
      router.handle_dev_request(
        local_request(),
        conn,
        config.Config(..test_config, host: host),
      )
    let assert 404 = res.status
    Nil
  })
  let forward =
    config.Config(
      ..test_config,
      auth: auth.Forward("x-user", "x-name", "x-email", "x-groups"),
    )
  let res = router.handle_dev_request(local_request(), conn, forward)
  let assert 404 = res.status
  Nil
}

pub fn local_mcp_guards_host_origin_and_fetch_site_test() {
  use conn <- with_empty_db
  list.each(
    [
      #("host", "evil.example:3000"),
      #("host", "127.0.0.1:3001"),
      #("host", "localhost.evil.example:3000"),
      #("origin", "https://evil.example"),
      #("origin", "null"),
      #("origin", "http://127.0.0.1:3001"),
      #("sec-fetch-site", "cross-site"),
    ],
    fn(header) {
      let res =
        local_request()
        |> simulate.header(header.0, header.1)
        |> router.handle_dev_request(conn, test_config)
      let assert 403 = res.status
      Nil
    },
  )
  let req = local_request()
  list.each(
    [#("host", "127.0.0.1:3000"), #("origin", "http://127.0.0.1:3000")],
    fn(header) {
      let req =
        request.Request(..req, headers: [
          header,
          header,
          ..list.filter(req.headers, fn(h) { h.0 != header.0 })
        ])
      let res = router.handle_dev_request(req, conn, test_config)
      let assert 403 = res.status
      Nil
    },
  )
  list.each(["127.0.0.1:3000", "localhost:3000", "[::1]:3000"], fn(host) {
    let req =
      local_request()
      |> simulate.header("host", host)
      |> simulate.header("origin", "http://" <> host)
    let res = router.handle_dev_request(req, conn, test_config)
    let assert 200 = res.status
    Nil
  })
  Nil
}

pub fn configured_oauth_is_never_bypassed_in_dev_test() {
  use conn <- with_empty_db
  let cfg =
    config.Config(
      ..test_config,
      mcp: Some(oauth.Config(
        resource: "https://rebstock.example.com/mcp",
        issuer: "https://id.example.com",
        jwks_uri: "https://id.example.com/jwks",
        client_id: "codex",
        scope: "rebstock:mcp",
        username_claim: "preferred_username",
      )),
    )
  let res = router.handle_dev_request(local_request(), conn, cfg)
  let assert 401 = res.status
  Nil
}

pub fn local_mcp_retains_post_only_and_json_contract_test() {
  use conn <- with_empty_db
  let req = local_request()
  list.each([http.Get, http.Delete, http.Put, http.Options], fn(method) {
    let res =
      request.Request(..req, method: method)
      |> router.handle_dev_request(conn, test_config)
    let assert 405 = res.status
    Nil
  })
  let res =
    req
    |> simulate.header("content-type", "text/plain")
    |> router.handle_dev_request(conn, test_config)
  let assert 415 = res.status
  let res =
    req
    |> simulate.header("accept", "text/event-stream")
    |> router.handle_dev_request(conn, test_config)
  let assert 406 = res.status
  Nil
}
