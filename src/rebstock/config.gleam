import argv
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option.{None, Some}
import simplifile

import rebstock/auth.{type AuthMode, Forward, Single}
import wisp

pub type Config {
  Config(port: Int, database_uri: String, auth: AuthMode)
}

pub fn default() -> Config {
  Config(port: 3000, database_uri: "file:rebstock.db", auth: Single("admin"))
}

pub fn parse_args() -> String {
  parse_args_loop(argv.load().arguments)
}

fn parse_args_loop(args: List(String)) -> String {
  case args {
    ["--config", path, ..] -> path
    [_, ..rest] -> parse_args_loop(rest)
    [] -> "config.json"
  }
}

pub fn load(path: String) -> Config {
  let #(source, config) = case simplifile.read(path) {
    Error(_) -> #(path <> " (not found, using defaults)", default())
    Ok(content) -> #(path, parse(content))
  }
  let auth_desc = case config.auth {
    Single(user) -> "single (user: " <> user <> ")"
    Forward(header_user:, header_name:, header_email:, header_groups:) ->
      "forward (user: "
      <> header_user
      <> ", name: "
      <> header_name
      <> ", email: "
      <> header_email
      <> ", groups: "
      <> header_groups
      <> ")"
  }
  wisp.log_info(
    "Config: "
    <> source
    <> " | port: "
    <> int.to_string(config.port)
    <> " | db: "
    <> config.database_uri
    <> " | auth: "
    <> auth_desc,
  )
  config
}

pub fn parse(content: String) -> Config {
  let d = default()
  let assert Ok(config) = json.parse(content, config_decoder(d))
  config
}

fn config_decoder(d: Config) -> decode.Decoder(Config) {
  use port <- decode.optional_field("port", d.port, decode.int)
  use database_uri <- decode.optional_field(
    "database_uri",
    d.database_uri,
    decode.string,
  )
  use auth <- decode.field("auth", auth_decoder())
  decode.success(Config(port:, database_uri:, auth:))
}

fn auth_decoder() -> decode.Decoder(AuthMode) {
  use single <- decode.optional_field(
    "single",
    None,
    decode.optional(single_decoder()),
  )
  use forward <- decode.optional_field(
    "forward",
    None,
    decode.optional(forward_decoder()),
  )
  case single, forward {
    Some(s), None -> decode.success(s)
    None, Some(f) -> decode.success(f)
    _, _ -> decode.success(Single("admin"))
  }
}

fn single_decoder() -> decode.Decoder(AuthMode) {
  use user <- decode.optional_field("user", "admin", decode.string)
  decode.success(Single(user))
}

fn forward_decoder() -> decode.Decoder(AuthMode) {
  use header_user <- decode.optional_field(
    "header_user",
    "x-webauth-user",
    decode.string,
  )
  use header_name <- decode.optional_field(
    "header_name",
    "x-webauth-name",
    decode.string,
  )
  use header_email <- decode.optional_field(
    "header_email",
    "x-webauth-email",
    decode.string,
  )
  use header_groups <- decode.optional_field(
    "header_groups",
    "x-webauth-groups",
    decode.string,
  )
  decode.success(Forward(
    header_user:,
    header_name:,
    header_email:,
    header_groups:,
  ))
}
