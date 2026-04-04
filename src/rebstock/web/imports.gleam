import gleam/http
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import nakai/attr
import nakai/html
import simplifile
import sqlight.{type Connection}
import wisp.{type Request, type Response}

import rebstock/auth.{type User}
import rebstock/vivino.{type ImportResult}
import rebstock/web/components as c

pub fn import_page(
  req: Request,
  conn: Connection,
  user: User,
  username: String,
) -> Response {
  case username == user.username {
    False -> wisp.response(403)
    True ->
      case req.method {
        http.Get -> render_upload_page(user, None, None)
        http.Post -> handle_upload(req, conn, user)
        _ -> wisp.method_not_allowed([http.Get, http.Post])
      }
  }
}

fn handle_upload(req: Request, conn: Connection, user: User) -> Response {
  use form <- wisp.require_form(req)
  case list.key_find(form.files, "zipfile") {
    Error(_) -> render_upload_page(user, Some("No file uploaded"), None)
    Ok(uploaded) -> {
      case simplifile.read_bits(uploaded.path) {
        Error(_) ->
          render_upload_page(user, Some("Failed to read uploaded file"), None)
        Ok(zip_bytes) ->
          case vivino.import_from_zip(conn, zip_bytes, user.username) {
            Error(msg) -> render_upload_page(user, Some(msg), None)
            Ok(result) -> render_upload_page(user, None, Some(result))
          }
      }
    }
  }
}

fn render_upload_page(
  user: User,
  error: Option(String),
  result: Option(ImportResult),
) -> Response {
  let content = case error, result {
    Some(err), _ -> [
      c.back_link("/~" <> user.username, user.username),
      html.h1([attr.class("text-2xl font-bold text-stone-800 mb-6")], [
        html.Text("Import Vivino Data"),
      ]),
      html.div(
        [
          attr.class(
            "mb-6 p-4 rounded-lg border bg-red-50 border-red-200 text-red-700",
          ),
        ],
        [html.Text(err)],
      ),
      upload_form(),
    ]
    _, Some(r) -> [
      c.back_link("/~" <> user.username, user.username),
      html.h1([attr.class("text-2xl font-bold text-stone-800 mb-6")], [
        html.Text("Import Vivino Data"),
      ]),
      result_card(r, user.username),
    ]
    _, _ -> [
      c.back_link("/~" <> user.username, user.username),
      html.h1([attr.class("text-2xl font-bold text-stone-800 mb-6")], [
        html.Text("Import Vivino Data"),
      ]),
      upload_form(),
    ]
  }

  c.page("Import — Rebstock", user, content)
}

fn upload_form() -> html.Node {
  html.Element(
    "form",
    [
      attr.method("POST"),
      attr.enctype("multipart/form-data"),
      attr.id("upload-form"),
    ],
    [
      html.div(
        [
          attr.id("drop-zone"),
          attr.class(
            "border-2 border-dashed border-stone-300 rounded-lg p-12 text-center cursor-pointer hover:border-amber-400 hover:bg-amber-50/30",
          ),
        ],
        [
          html.UnsafeInlineHtml(upload_icon_svg()),
          html.p([attr.class("mt-4 text-stone-600 font-medium")], [
            html.Text("Drop your Vivino export zip here"),
          ]),
          html.p([attr.class("mt-1 text-sm text-stone-400")], [
            html.Text("or click to select a file"),
          ]),
          html.Element(
            "input",
            [
              attr.type_("file"),
              attr.name("zipfile"),
              attr.id("file-input"),
              attr.Attr("accept", ".zip"),
              attr.class("hidden"),
            ],
            [],
          ),
        ],
      ),
      html.p(
        [attr.id("file-name"), attr.class("text-sm text-stone-500 hidden mt-3")],
        [],
      ),
      html.div([attr.class("mt-4")], [
        html.Element(
          "button",
          [
            attr.type_("submit"),
            attr.id("submit-btn"),
            attr.Attr("disabled", ""),
            attr.class(
              "px-4 py-2 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors disabled:opacity-50 disabled:cursor-not-allowed",
            ),
          ],
          [
            html.Text("Import"),
          ],
        ),
      ]),
      html.Element("script", [], [html.Text(drop_zone_js())]),
    ],
  )
}

fn result_card(r: ImportResult, username: String) -> html.Node {
  c.card([
    html.h2([attr.class("text-lg font-semibold text-stone-800 mb-4")], [
      html.Text("Import Complete"),
    ]),
    result_row("Wines", r.wines_created),
    result_row("Cellar entries", r.cellar_created),
    result_row("Wishlist items", r.wishlist_created),
    html.div([attr.class("flex gap-3 mt-6")], [
      html.a(
        [
          attr.href("/~" <> username <> "/cellar"),
          attr.class(
            "px-4 py-2 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors",
          ),
        ],
        [html.Text("View Cellar")],
      ),
      html.a(
        [
          attr.href("/~" <> username <> "/import"),
          attr.class(
            "px-4 py-2 border border-stone-300 text-stone-700 rounded-lg hover:bg-stone-50 transition-colors",
          ),
        ],
        [html.Text("Import Again")],
      ),
    ]),
  ])
}

fn result_row(label: String, count: Int) -> html.Node {
  html.div([attr.class("flex justify-between py-1 border-b border-stone-100")], [
    html.span([attr.class("text-stone-600")], [html.Text(label)]),
    html.span([attr.class("font-medium text-stone-800 tabular-nums")], [
      html.Text(int.to_string(count)),
    ]),
  ])
}

fn upload_icon_svg() -> String {
  "<svg class=\"mx-auto\" width=\"48\" height=\"48\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4\"/><polyline points=\"17 8 12 3 7 8\"/><line x1=\"12\" y1=\"3\" x2=\"12\" y2=\"15\"/></svg>"
}

fn drop_zone_js() -> String {
  "(function() {
  var dz = document.getElementById('drop-zone');
  var fi = document.getElementById('file-input');
  var fn_ = document.getElementById('file-name');
  var btn = document.getElementById('submit-btn');

  dz.addEventListener('click', function() { fi.click(); });

  fi.addEventListener('change', function() {
    if (fi.files.length > 0) {
      fn_.textContent = fi.files[0].name;
      fn_.classList.remove('hidden');
      btn.removeAttribute('disabled');
    }
  });

  dz.addEventListener('dragover', function(e) {
    e.preventDefault();
    dz.classList.add('border-amber-400', 'bg-amber-50/30');
  });

  dz.addEventListener('dragleave', function(e) {
    e.preventDefault();
    dz.classList.remove('border-amber-400', 'bg-amber-50/30');
  });

  dz.addEventListener('drop', function(e) {
    e.preventDefault();
    dz.classList.remove('border-amber-400', 'bg-amber-50/30');
    if (e.dataTransfer.files.length > 0) {
      fi.files = e.dataTransfer.files;
      fn_.textContent = e.dataTransfer.files[0].name;
      fn_.classList.remove('hidden');
      btn.removeAttribute('disabled');
    }
  });
})();"
}
