import gleam/int
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/web/pages

pub fn handle_request(req: Request, conn: Connection) -> Response {
  use _req <- wisp.handle_head(req)
  use <- wisp.serve_static(req, under: "/static", from: "priv/static")

  case wisp.path_segments(req) {
    [] -> pages.home(conn)
    ["wines"] -> pages.wines(conn)
    ["wines", id_str] ->
      case int.parse(id_str) {
        Ok(id) -> pages.wine_detail(conn, id)
        Error(_) -> wisp.not_found()
      }
    ["wineries"] -> pages.wineries(conn)
    ["wineries", name] -> pages.winery_detail(conn, name)
    ["cellar"] -> pages.cellar(conn)
    ["cellar", "export.csv"] -> pages.cellar_csv(conn)
    _ -> wisp.not_found()
  }
}
