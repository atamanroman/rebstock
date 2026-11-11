import gleam/bit_array
import gleam/http
import gleam/http/response
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import nakai/attr
import nakai/html.{type Node}
import simplifile
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type User}
import rebstock/db
import rebstock/ulid
import rebstock/web/components as c

const max_picture_bytes = 2_000_000

type PictureError {
  InvalidPicture(String)
  StorageError
}

pub fn display_name(profile: db.Profile) -> String {
  option.unwrap(profile.display_name, profile.username)
}

pub fn heading(profile: db.Profile) -> Node {
  html.header([attr.class("profile-heading page-heading")], [
    picture(profile, False),
    html.div([], [
      html.h1([], [html.Text(display_name(profile))]),
      html.p([], [html.Text("~" <> profile.username)]),
    ]),
  ])
}

fn picture(profile: db.Profile, preview: Bool) -> Node {
  let #(src, class) = case profile.picture {
    Some(file) -> #("/images/profiles/" <> file, "profile-picture")
    None -> #(
      "/static/grapevine.svg",
      "profile-picture profile-picture-placeholder",
    )
  }
  html.img([
    attr.src(src),
    attr.class(class),
    attr.Attr("alt", case preview {
      True -> "Current profile picture"
      False -> ""
    }),
    attr.Attr("width", "96"),
    attr.Attr("height", "96"),
  ])
}

pub fn settings(
  req: Request,
  conn: Connection,
  user: User,
  image_dir: String,
) -> Response {
  let assert Ok(profile) = db.get_profile(conn, user.username)
  case req.method {
    http.Get -> {
      let saved = list.key_find(wisp.get_query(req), "saved") == Ok("1")
      c.page("Settings — Rebstock", user, conn, [
        settings_form(user, profile, saved),
      ])
    }
    http.Post -> save(req, conn, user, profile, image_dir)
    _ -> wisp.method_not_allowed([http.Get, http.Post])
  }
}

fn settings_form(user: User, profile: db.Profile, saved: Bool) -> Node {
  let name =
    option.unwrap(
      profile.display_name,
      option.unwrap(user.display_name, user.username),
    )
  html.div([attr.class("form-card")], [
    c.page_header("Settings", "Your public profile."),
    case saved {
      True ->
        html.p([attr.class("settings-saved"), attr.Attr("role", "status")], [
          html.Text("Profile saved."),
        ])
      False -> html.Nothing
    },
    html.form(
      [
        attr.method("post"),
        attr.Attr("action", "/settings"),
        attr.Attr("enctype", "multipart/form-data"),
        attr.class("space-y-4"),
      ],
      [
        c.form_field("profile-name", "Name", True, [
          html.input([
            attr.type_("text"),
            attr.id("profile-name"),
            attr.name("display_name"),
            attr.value(name),
            attr.Attr("required", ""),
            attr.Attr("maxlength", "100"),
            attr.Attr("autocomplete", "name"),
            attr.class(c.input_class),
          ]),
        ]),
        html.div([attr.class("profile-picture-field")], [
          picture(profile, True),
          html.div([], [
            c.form_field("profile-picture", "Picture", False, [
              html.input([
                attr.type_("file"),
                attr.id("profile-picture"),
                attr.name("picture"),
                attr.Attr("accept", "image/png,image/jpeg,image/webp"),
                attr.Attr("aria-describedby", "profile-picture-help"),
                attr.class("profile-picture-input"),
              ]),
            ]),
            html.p(
              [
                attr.id("profile-picture-help"),
                attr.class("text-sm text-stone-500"),
              ],
              [
                html.Text(
                  "PNG, JPEG or WebP, up to 2 MB. Shown as a square on your public profile, not your home dashboard. Without a picture, the grapevine logo is used.",
                ),
              ],
            ),
          ]),
        ]),
        case profile.picture {
          None -> html.Nothing
          Some(_) ->
            html.label([attr.class("flex items-center gap-2")], [
              html.input([
                attr.type_("checkbox"),
                attr.name("remove_picture"),
                attr.value("1"),
              ]),
              html.Text("Remove picture"),
            ])
        },
        html.div([attr.class("flex items-center flex-wrap gap-3")], [
          html.button([attr.type_("submit"), attr.class("primary-action")], [
            html.Text("Save profile"),
          ]),
          html.a(
            [
              attr.href(c.profile_url(user.username)),
              attr.class("text-sm text-rose-800"),
            ],
            [html.Text("View your public profile")],
          ),
        ]),
      ],
    ),
  ])
}

fn save(
  req: Request,
  conn: Connection,
  user: User,
  profile: db.Profile,
  image_dir: String,
) -> Response {
  // Bound streaming uploads as well as checking the individual picture below.
  use form <- wisp.require_form(wisp.set_max_files_size(req, 4_000_000))
  let name =
    list.key_find(form.values, "display_name")
    |> result.unwrap("")
    |> string.trim
  case name == "" || string.length(name) > 100 {
    True ->
      c.form_error(
        req,
        conn,
        user,
        settings_form(user, profile, False),
        form.values,
        ["display_name"],
        "Enter a name between 1 and 100 characters.",
      )
    False ->
      case save_picture(form, image_dir, profile.picture) {
        Error(InvalidPicture(message)) ->
          c.form_error(
            req,
            conn,
            user,
            settings_form(user, profile, False),
            form.values,
            ["picture"],
            message,
          )
        Error(StorageError) -> {
          let rendered =
            c.form_error(
              req,
              conn,
              user,
              settings_form(user, profile, False),
              form.values,
              [],
              "The picture could not be saved. Your profile has not changed; please try again.",
            )
          response.Response(..rendered, status: 500)
        }
        Ok(picture) -> {
          db.update_profile(conn, user.username, name, picture)
          remove_replaced_picture(image_dir, profile.picture, picture)
          c.redirect(req, "/settings?saved=1")
        }
      }
  }
}

fn save_picture(
  form: wisp.FormData,
  image_dir: String,
  existing: Option(String),
) -> Result(Option(String), PictureError) {
  let remove = list.key_find(form.values, "remove_picture") == Ok("1")
  let upload = list.key_find(form.files, "picture") |> option.from_result
  case upload {
    Some(file) if file.file_name != "" -> {
      case remove {
        True ->
          Error(InvalidPicture(
            "Choose a new picture or remove the current one, not both.",
          ))
        False -> {
          use extension <- result.try(validate_picture(file.path))
          let name = ulid.generate() <> "." <> extension
          use _ <- result.try(
            simplifile.create_directory_all(image_dir <> "/profiles")
            |> result.map_error(fn(_) { StorageError }),
          )
          use _ <- result.try(
            simplifile.copy_file(file.path, image_dir <> "/profiles/" <> name)
            |> result.map_error(fn(_) { StorageError }),
          )
          Ok(Some(name))
        }
      }
    }
    _ ->
      Ok(case remove {
        True -> None
        False -> existing
      })
  }
}

fn validate_picture(path: String) -> Result(String, PictureError) {
  use info <- result.try(
    simplifile.file_info(path) |> result.map_error(fn(_) { StorageError }),
  )
  case info.size > max_picture_bytes {
    True -> Error(InvalidPicture("Choose a picture no larger than 2 MB."))
    False -> {
      use bits <- result.try(
        simplifile.read_bits(path) |> result.map_error(fn(_) { StorageError }),
      )
      // Determine the safe file extension from bytes, never the supplied filename.
      case
        bit_array.starts_with(bits, <<137, 80, 78, 71, 13, 10, 26, 10>>),
        bit_array.starts_with(bits, <<255, 216, 255>>),
        bit_array.starts_with(bits, <<"RIFF":utf8>>)
        && bit_array.slice(bits, 8, 4) == Ok(<<"WEBP":utf8>>)
      {
        True, _, _ -> Ok("png")
        _, True, _ -> Ok("jpg")
        _, _, True -> Ok("webp")
        _, _, _ -> Error(InvalidPicture("Choose a PNG, JPEG or WebP picture."))
      }
    }
  }
}

fn remove_replaced_picture(
  image_dir: String,
  old: Option(String),
  new: Option(String),
) -> Nil {
  case old {
    Some(file) if old != new -> {
      case simplifile.delete_file(image_dir <> "/profiles/" <> file) {
        Ok(_) -> Nil
        Error(_) ->
          wisp.log_warning("An old profile picture could not be removed.")
      }
    }
    _ -> Nil
  }
}
