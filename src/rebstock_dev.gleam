import envoy
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
import rebstock/vivino

pub fn main() -> Nil {
  wisp.configure_logger()
  wisp.set_logger_level(wisp.DebugLevel)

  let skip_import = envoy.get("SKIP_IMPORT") == Ok("1")
  let cfg = config.load(config.parse_args())

  let assert Ok(_) = simplifile.create_directory_all(cfg.image_dir)

  let assert Ok(conn) = sqlight.open(cfg.database_uri)
  db.migrate(conn)

  let username = case cfg.auth {
    auth.Single(u) -> u
    auth.Forward(..) -> "admin"
  }

  case skip_import, db.count_wines(conn) {
    True, _ -> wisp.log_info("Skipping Vivino import (--skip-import)")
    _, 0 -> {
      vivino.import_data(conn, "vivino_data", username)
      seed.seed_alice(conn, username)
    }
    _, n ->
      wisp.log_info(
        "DB already has " <> int.to_string(n) <> " wines, skipping seed",
      )
  }

  let assert Ok(_) =
    wisp_mist.handler(
      router.handle_request(_, conn, cfg),
      config.secret_key_base(cfg),
    )
    |> mist.new
    |> mist.port(cfg.port)
    |> mist.start

  process.sleep_forever()
}
