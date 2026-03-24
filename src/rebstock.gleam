import gleam/erlang/process
import mist
import sqlight
import wisp
import wisp/wisp_mist

import rebstock/auth
import rebstock/db
import rebstock/router

pub fn main() -> Nil {
  wisp.configure_logger()

  let assert Ok(conn) = sqlight.open("rebstock.db")
  db.migrate(conn)

  let auth_config = auth.config_from_env()

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, conn, auth_config), "secret-signing-key")
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
