import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/web/pages

pub fn handle_request(req: Request, conn: Connection) -> Response {
  use _req <- wisp.handle_head(req)

  case wisp.path_segments(req) {
    [] -> pages.home(conn)
    _ -> wisp.not_found()
  }
}
