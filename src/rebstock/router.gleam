import gleam/http
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type AuthMode}
import rebstock/db
import rebstock/web/cellar
import rebstock/web/components as c
import rebstock/web/home
import rebstock/web/imports
import rebstock/web/lists
import rebstock/web/ratings
import rebstock/web/shared
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

  // Public routes (no auth required)
  case wisp.path_segments(req) {
    ["shared", id, _slug] -> shared.shared_list(conn, id)
    _ -> {
      let user = auth.get_user(req, auth)
      db.ensure_user(conn, user.username)
      db.ensure_system_lists(conn, user.username)

      case wisp.path_segments(req) {
        [] -> home.home(conn, user)
        ["wines"] -> wines.wines(conn, user)
        ["wines", id, _, "ratings", "new"] ->
          ratings.handle_new(req, conn, id, user)
        ["wines", _id, _, "ratings", rid, "edit"] ->
          ratings.handle_edit(req, conn, rid, user)
        ["wines", _id, _, "ratings", rid, "delete"] ->
          ratings.handle_delete(req, conn, rid, user)
        ["wines", _id, _, "ratings", rid] ->
          ratings.rating_detail(conn, rid, user)
        ["wines", id, _, "cellar", "new"] ->
          cellar.handle_new(req, conn, id, user)
        ["wines", _id, _, "cellar", eid, "edit"] ->
          cellar.handle_edit(req, conn, eid, user)
        ["wines", _id, _, "cellar", eid, "drink"] ->
          cellar.handle_drink(req, conn, eid, user)
        ["wines", _id, _, "cellar", eid, "delete"] ->
          cellar.handle_delete(req, conn, eid, user)
        ["wines", id] | ["wines", id, _slug] ->
          wines.wine_detail(req, conn, id, user)
        ["wineries"] -> wineries.wineries(conn, user)
        ["wineries", id] | ["wineries", id, _slug] ->
          wineries.winery_detail(conn, id, user)
        ["~" <> username] -> home.profile(conn, user, username)
        ["~" <> username, "cellar"] -> cellar.cellar(conn, user, username)
        ["~" <> username, "cellar", "print"] ->
          cellar.cellar_print(conn, user, username)
        ["~" <> username, "cellar", "export.csv"] ->
          cellar.cellar_csv(conn, user, username)
        ["~" <> username, "wishlist"] -> wishlist.wishlist(conn, user, username)
        ["~" <> username, "import"] ->
          imports.import_page(req, conn, user, username)
        ["~" <> username, "ratings"] -> ratings.my_ratings(conn, user, username)
        ["~" <> username, "lists"] ->
          case req.method {
            http.Post -> lists.create_list(req, conn, user)
            _ -> lists.lists_index(conn, user, username)
          }
        ["~" <> _username, "lists", "new"] -> lists.new_list_form(conn, user)
        ["~" <> username, "lists", id, "edit"] ->
          lists.edit_list_form(conn, user, username, id)
        ["~" <> username, "lists", id, "print"] ->
          lists.print_view(conn, user, username, id)
        ["~" <> username, "lists", id, "public"] ->
          lists.set_public(req, conn, user, username, id)
        ["~" <> username, "lists", id, "show-bottles"] ->
          lists.set_show_bottles(req, conn, user, username, id)
        ["~" <> username, "lists", id, "wines"] ->
          lists.add_wine(req, conn, user, username, id)
        ["~" <> username, "lists", id, "wines", wine_id] ->
          lists.remove_wine(conn, user, username, id, wine_id)
        ["~" <> username, "lists", id] ->
          lists.list_detail(req, conn, user, username, id)
        ["ratings", id, "overlay"] -> ratings.rating_overlay(conn, id)
        ["ratings", id] -> ratings.rating_detail(conn, id, user)
        ["cellar", id, "overlay"] -> cellar.cellar_entry_overlay(conn, id)
        ["cellar", id] -> cellar.cellar_entry_detail(conn, id, user)
        ["wishlist", id, "overlay"] -> wishlist.wishlist_entry_overlay(conn, id)
        ["wishlist", id] -> wishlist.wishlist_entry_detail(conn, id, user)
        _ -> c.not_found(user, conn)
      }
    }
  }
}
