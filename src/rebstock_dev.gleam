import gleam/erlang/process
import gleam/int
import mist
import sqlight
import wisp
import wisp/wisp_mist

import rebstock/auth
import rebstock/config
import rebstock/db
import rebstock/vivino
import rebstock/router

pub fn main() -> Nil {
  wisp.configure_logger()

  let cfg = config.load(config.parse_args())

  let assert Ok(conn) = sqlight.open(cfg.database_uri)
  db.migrate(conn)

  let username = case cfg.auth {
    auth.Single(u) -> u
    auth.Forward(..) -> "admin"
  }

  case db.count_wines(conn) {
    0 -> vivino.import_data(conn, "vivino_data", username)
    n -> wisp.log_info("DB already has " <> int.to_string(n) <> " wines, skipping seed")
  }

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, conn, cfg.auth), "secret")
    |> mist.new
    |> mist.port(cfg.port)
    |> mist.start

  process.sleep_forever()
}
