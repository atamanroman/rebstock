import argv
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option.{None, Some}
import simplifile

import rebstock/auth.{type AuthMode, Forward, Single}
import wisp

pub type Config {
  Config(
    host: String,
    port: Int,
    database_uri: String,
    image_dir: String,
    auth: AuthMode,
    secret_key_base: String,
  )
}

pub fn default() -> Config {
  Config(
    host: "127.0.0.1",
    port: 3000,
    database_uri: "file:./data/rebstock.db",
    image_dir: "./data/images",
    auth: Single("admin"),
    secret_key_base: "",
  )
}

/// Signing secret for the wisp handler. Configured value wins;
/// otherwise a random one is generated at boot (fine as long as
/// nothing signed needs to survive restarts).
pub fn secret_key_base(config: Config) -> String {
  case config.secret_key_base {
    "" ->
      crypto.strong_random_bytes(32)
      |> bit_array.base64_encode(False)
    key -> key
  }
}

pub fn parse_args() -> String {
  parse_args_loop(argv.load().arguments)
}

fn parse_args_loop(args: List(String)) -> String {
  case args {
    ["--config", path, ..] -> path
    [_, ..rest] -> parse_args_loop(rest)
    [] -> "config.example.json"
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
    <> " | host: "
    <> config.host
    <> " | port: "
    <> int.to_string(config.port)
    <> " | db: "
    <> config.database_uri
    <> " | images: "
    <> config.image_dir
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
  use host <- decode.optional_field("host", d.host, decode.string)
  use port <- decode.optional_field("port", d.port, decode.int)
  use database_uri <- decode.optional_field(
    "database_uri",
    d.database_uri,
    decode.string,
  )
  use image_dir <- decode.optional_field(
    "image_dir",
    d.image_dir,
    decode.string,
  )
  use secret_key_base <- decode.optional_field(
    "secret_key_base",
    d.secret_key_base,
    decode.string,
  )
  use auth <- decode.field("auth", auth_decoder())
  decode.success(Config(
    host:,
    port:,
    database_uri:,
    image_dir:,
    auth:,
    secret_key_base:,
  ))
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
