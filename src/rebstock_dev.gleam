import gleam/erlang/process
import gleam/int
import mist
import simplifile
import sqlight
import wisp
import wisp/wisp_mist

import rebstock/auth
import rebstock/config
import rebstock/db
import rebstock/router
import rebstock/seed

pub fn main() -> Nil {
  wisp.configure_logger()
  wisp.set_logger_level(wisp.DebugLevel)

  let cfg = config.load(config.parse_args())

  let assert Ok(_) = simplifile.create_directory_all(cfg.image_dir)

  let assert Ok(conn) = sqlight.open(cfg.database_uri)
  db.migrate(conn)

  let username = case cfg.auth {
    auth.Single(u) -> u
    auth.Forward(..) -> "admin"
  }

  case db.count_wines(conn) {
    0 -> {
      seed.seed_collection(conn, username)
      seed.seed_alice(conn, username)
    }
    n ->
      wisp.log_info(
        "DB already has " <> int.to_string(n) <> " wines, skipping seed",
      )
  }

  let assert Ok(_) =
    wisp_mist.handler(
      router.handle_dev_request(_, conn, cfg),
      config.secret_key_base(cfg),
    )
    |> mist.new
    |> mist.port(cfg.port)
    |> mist.bind(cfg.host)
    |> mist.start

  process.sleep_forever()
}
