import gleam/erlang/process
import mist
import wisp
import wisp/wisp_mist

import rebstock/router

pub fn main() -> Nil {
  wisp.configure_logger()

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request, "secret-signing-key")
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
