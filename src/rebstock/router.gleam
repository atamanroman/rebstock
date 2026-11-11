import gleam/erlang/application
import gleam/http
import gleam/http/request
import gleam/string
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth
import rebstock/config.{type Config}
import rebstock/db
import rebstock/mcp
import rebstock/web/cellar
import rebstock/web/components as c
import rebstock/web/home
import rebstock/web/lists
import rebstock/web/profiles
import rebstock/web/ratings
import rebstock/web/shared
import rebstock/web/wineries
import rebstock/web/wines
import rebstock/web/wishlist

/// CSRF protection: browsers send Origin (and Sec-Fetch-Site) on
/// form posts, so reject POSTs whose origin does not match the Host.
/// Requests without either header (curl, htmx same-origin GET) pass.
fn require_same_origin(req: Request, next: fn() -> Response) -> Response {
  case req.method {
    http.Post ->
      case same_origin(req) {
        True -> next()
        False -> wisp.response(403)
      }
    _ -> next()
  }
}

fn same_origin(req: Request) -> Bool {
  case request.get_header(req, "origin") {
    Ok(origin) -> {
      let host = case request.get_header(req, "host") {
        Ok(h) -> h
        Error(_) -> ""
      }
      string.ends_with(origin, "://" <> host)
    }
    Error(_) ->
      case request.get_header(req, "sec-fetch-site") {
        Ok("cross-site") -> False
        _ -> True
      }
  }
}

pub fn handle_request(
  req: Request,
  conn: Connection,
  config: Config,
) -> Response {
  case wisp.path_segments(req) {
    ["mcp"] -> mcp.handle(req, conn, config)
    [".well-known", "oauth-protected-resource"]
    | [".well-known", "oauth-protected-resource", "mcp"] ->
      mcp.metadata(req, config)
    _ -> handle_web_request(req, conn, config)
  }
}

fn handle_web_request(
  req: Request,
  conn: Connection,
  config: Config,
) -> Response {
  use req <- wisp.handle_head(req)
  use <- require_same_origin(req)
  let assert Ok(priv) = application.priv_directory("rebstock")
  use <- wisp.serve_static(req, under: "/static", from: priv <> "/static")
  use <- wisp.serve_static(
    req,
    under: "/images/profiles",
    from: config.image_dir <> "/profiles",
  )
  use <- wisp.serve_static(
    req,
    under: "/images/bottles",
    from: config.image_dir,
  )

  // Public routes (no auth required)
  let response = case wisp.path_segments(req) {
    ["shared", id, _slug] -> shared.shared_list(conn, id)
    _ -> {
      let user = auth.get_user(req, config.auth)
      db.ensure_user(conn, user.username)
      db.ensure_system_lists(conn, user.username)

      case req.method {
        http.Post ->
          wisp.log_info(
            user.username
            <> " POST /"
            <> string.join(wisp.path_segments(req), "/"),
          )
        _ -> Nil
      }

      case wisp.path_segments(req) {
        [] -> home.home(conn, user)
        ["settings"] -> profiles.settings(req, conn, user, config.image_dir)
        ["wines"] ->
          case req.method {
            http.Post -> wines.create_wine(req, conn, user, config.image_dir)
            _ -> wines.wines(conn, user)
          }
        ["wines", "new"] -> wines.new_wine_form(req, conn, user)
        ["wines", id, _, "edit"] ->
          case req.method {
            http.Post ->
              wines.handle_edit_wine(req, conn, id, user, config.image_dir)
            _ -> wines.edit_wine_form(req, conn, id, user)
          }
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
        ["wineries"] ->
          case req.method {
            http.Post -> wineries.create_winery(req, conn, user)
            _ -> wineries.wineries(conn, user)
          }
        ["wineries", "new"] -> wineries.new_winery_form(conn, user)
        ["wineries", id, "edit"] ->
          case req.method {
            http.Post -> wineries.handle_edit_winery(req, conn, id, user)
            _ -> wineries.edit_winery_form(conn, id, user)
          }
        ["wineries", id] | ["wineries", id, _slug] ->
          wineries.winery_detail(conn, id, user)
        ["~" <> username] ->
          case req.method {
            http.Get -> home.profile(conn, user, username)
            _ -> wisp.method_not_allowed([http.Get])
          }
        ["~" <> username, "cellar"] -> cellar.cellar(req, conn, user, username)
        ["~" <> username, "cellar", "public"] ->
          cellar.cellar_set_public(req, conn, user, username)
        ["~" <> username, "cellar", "export.csv"] ->
          cellar.cellar_csv(conn, user, username)
        ["~" <> username, "wishlist"] -> wishlist.wishlist(conn, user, username)
        ["~" <> username, "ratings"] ->
          ratings.my_ratings(req, conn, user, username)
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
        ["~" <> username, "lists", id, "wines", "toggle"] ->
          lists.toggle_wine(req, conn, user, username, id)
        ["~" <> username, "lists", id, "wines"] ->
          lists.add_wine(req, conn, user, username, id)
        ["~" <> username, "lists", id, "wines", wine_id] ->
          case req.method {
            http.Post -> lists.remove_wine(conn, user, username, id, wine_id)
            _ -> wisp.method_not_allowed([http.Post])
          }
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
  response
  |> wisp.set_header(
    "Vary",
    "HX-Request, HX-Request-Type, HX-History-Restore-Request",
  )
}
