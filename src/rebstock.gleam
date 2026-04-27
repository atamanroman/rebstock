import gleam/erlang/process
import mist
import simplifile
import sqlight
import wisp
import wisp/wisp_mist

import rebstock/config
import rebstock/db
import rebstock/router

pub fn main() -> Nil {
  wisp.configure_logger()

  let cfg = config.load(config.parse_args())

  let assert Ok(_) = simplifile.create_directory_all(cfg.image_dir)

  let assert Ok(conn) = sqlight.open(cfg.database_uri)
  db.migrate(conn)

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, conn, cfg), "secret")
    |> mist.new
    |> mist.port(cfg.port)
    |> mist.bind(cfg.host)
    |> mist.start

  process.sleep_forever()
}
