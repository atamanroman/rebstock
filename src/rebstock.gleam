import gleam/erlang/process
import mist
import sqlight
import wisp
import wisp/wisp_mist

import rebstock/db
import rebstock/vivino
import rebstock/router

pub fn main() -> Nil {
  wisp.configure_logger()

  let assert Ok(conn) = sqlight.open("rebstock.db")
  db.migrate(conn)
  vivino.import_data(conn, "vivino_data")

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, conn), "secret-signing-key")
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
