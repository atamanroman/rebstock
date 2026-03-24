import gleam/erlang/process
import gleam/int
import gleam/io
import mist
import sqlight
import wisp
import wisp/wisp_mist

import rebstock/auth
import rebstock/db
import rebstock/vivino
import rebstock/router

pub fn main() -> Nil {
  wisp.configure_logger()

  let assert Ok(conn) = sqlight.open("rebstock.db")
  db.migrate(conn)

  let auth_config = auth.config_from_env()
  let username = case auth_config {
    auth.Single(u) -> u
    auth.Forward(..) -> "admin"
  }

  case db.count_wines(conn, username) {
    0 -> vivino.import_data(conn, "vivino_data", username)
    n -> io.println("DB already has " <> int.to_string(n) <> " wines, skipping seed")
  }

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, conn, auth_config), "secret-signing-key")
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
