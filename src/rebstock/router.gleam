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
    ["wines", id] | ["wines", id, _slug] ->
      pages.wine_detail(conn, id, user)
    ["wineries"] -> pages.wineries(conn, user)
    ["wineries", id] | ["wineries", id, _slug] ->
      pages.winery_detail(conn, id, user)
    ["~" <> username, "cellar"] -> pages.cellar(conn, user, username)
    ["~" <> username, "cellar", "print"] -> pages.cellar_print(conn, user, username)
    ["~" <> username, "cellar", "export.csv"] -> pages.cellar_csv(conn, user, username)
    ["~" <> username, "wishlist"] -> pages.wishlist(conn, user, username)
    ["~" <> username, "ratings"] -> pages.my_ratings(conn, user, username)
    ["ratings", id] -> pages.rating_detail(conn, id, user)
    _ -> wisp.not_found()
  }
}
