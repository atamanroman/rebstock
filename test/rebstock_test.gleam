import gleam/http
import gleam/string
import gleeunit
import wisp/simulate

import rebstock/router

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn home_returns_200_test() {
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request

  let assert 200 = response.status
}

pub fn home_returns_html_test() {
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request

  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Rebstock")
}

pub fn not_found_test() {
  let response =
    simulate.request(http.Get, "/nope")
    |> router.handle_request

  let assert 404 = response.status
}
