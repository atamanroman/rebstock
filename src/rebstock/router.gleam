import gleam/int
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type AuthMode}
import rebstock/web/pages

pub fn handle_request(
  req: Request,
  conn: Connection,
  auth: AuthMode,
) -> Response {
  use _req <- wisp.handle_head(req)
  use <- wisp.serve_static(req, under: "/static", from: "priv/static")

  let user = auth.get_user(req, auth)

  case wisp.path_segments(req) {
    [] -> pages.home(conn, user)
    ["wines"] -> pages.wines(conn, user)
    ["wines", id_str] ->
      case int.parse(id_str) {
        Ok(id) -> pages.wine_detail(conn, id, user)
        Error(_) -> wisp.not_found()
      }
    ["wineries"] -> pages.wineries(conn, user)
    ["wineries", name] -> pages.winery_detail(conn, name, user)
    ["cellar"] -> pages.cellar(conn, user)
    ["cellar", "print"] -> pages.cellar_print(conn, user)
    ["cellar", "export.csv"] -> pages.cellar_csv(conn, user)
    _ -> wisp.not_found()
  }
}
