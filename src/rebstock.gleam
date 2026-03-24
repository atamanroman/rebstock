import envoy
import gleam/erlang/process
import gleam/int
import gleam/io
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

  case envoy.get("REBSTOCK_SEED") {
    Ok("1") | Ok("true") ->
      case db.count_wines(conn) {
        0 -> vivino.import_data(conn, "vivino_data")
        n -> io.println("DB already has " <> int.to_string(n) <> " wines, skipping seed")
      }
    _ -> Nil
  }

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, conn), "secret-signing-key")
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
