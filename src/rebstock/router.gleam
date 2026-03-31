import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type AuthMode}
import rebstock/web/cellar
import rebstock/web/home
import rebstock/web/ratings
import rebstock/web/wineries
import rebstock/web/wines
import rebstock/web/wishlist

pub fn handle_request(
  req: Request,
  conn: Connection,
  auth: AuthMode,
) -> Response {
  use req <- wisp.handle_head(req)
  use <- wisp.serve_static(req, under: "/static", from: "priv/static")

  let user = auth.get_user(req, auth)

  case wisp.path_segments(req) {
    [] -> home.home(conn, user)
    ["wines"] -> wines.wines(conn, user)
    ["wines", id, _, "ratings", "new"] ->
      ratings.handle_new(req, conn, id, user)
    ["wines", _id, _, "ratings", rid, "edit"] ->
      ratings.handle_edit(req, conn, rid, user)
    ["wines", _id, _, "ratings", rid] -> ratings.rating_detail(conn, rid, user)
    ["wines", id] | ["wines", id, _slug] ->
      wines.wine_detail(req, conn, id, user)
    ["wineries"] -> wineries.wineries(conn, user)
    ["wineries", id] | ["wineries", id, _slug] ->
      wineries.winery_detail(conn, id, user)
    ["~" <> username, "cellar"] -> cellar.cellar(conn, user, username)
    ["~" <> username, "cellar", "print"] ->
      cellar.cellar_print(conn, user, username)
    ["~" <> username, "cellar", "export.csv"] ->
      cellar.cellar_csv(conn, user, username)
    ["~" <> username, "wishlist"] -> wishlist.wishlist(conn, user, username)
    ["~" <> username, "ratings"] -> ratings.my_ratings(conn, user, username)
    ["ratings", id, "overlay"] -> ratings.rating_overlay(conn, id)
    ["ratings", id] -> ratings.rating_detail(conn, id, user)
    ["cellar", id, "overlay"] -> cellar.cellar_entry_overlay(conn, id)
    ["cellar", id] -> cellar.cellar_entry_detail(conn, id, user)
    ["wishlist", id, "overlay"] -> wishlist.wishlist_entry_overlay(conn, id)
    ["wishlist", id] -> wishlist.wishlist_entry_detail(conn, id, user)
    _ -> wisp.not_found()
  }
}
