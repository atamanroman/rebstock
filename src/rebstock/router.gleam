import wisp.{type Request, type Response}

import rebstock/web/pages

pub fn handle_request(req: Request) -> Response {
  use _req <- wisp.handle_head(req)

  case wisp.path_segments(req) {
    [] -> pages.home()
    _ -> wisp.not_found()
  }
}
