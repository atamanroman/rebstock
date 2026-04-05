# Nav Reorganization + Empty Home State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the site header nav into clear global/user/tools zones, replace SVG logo with grape emoji, add username dropdown for tools, and show a welcome CTA when the database is empty.

**Architecture:** Modify `site_header` in components.gleam to restructure nav with separators and a CSS-only `details`/`summary` dropdown. Add empty state check in home.gleam. Remove duplicate `logo_svg` from cellar.gleam.

**Tech Stack:** Gleam, nakai (HTML), Tailwind CSS, CSS-only dropdown via `details`/`summary`

---

### Task 1: Restructure site header navigation

**Files:**
- Modify: `src/rebstock/web/components.gleam` (lines 549-615)
- Modify: `src/css/app.css`

- [ ] **Step 1: Replace `logo_svg` function with grape emoji in `site_header`**

In `src/rebstock/web/components.gleam`, replace the logo area (lines 564-583) from:

```gleam
          html.a([attr.href("/"), attr.class("flex items-center gap-3 group")], [
            html.UnsafeInlineHtml(logo_svg()),
            html.div([], [
              html.span(
                [
                  attr.class(
                    "text-xl font-light tracking-tight text-stone-800 group-hover:text-rose-800 transition-colors",
                  ),
                ],
                [html.Text("Rebstock")],
              ),
              case subtitle {
                None -> html.Nothing
                Some(s) ->
                  html.div([attr.class("text-xs text-stone-400 -mt-0.5")], [
                    html.Text(s),
                  ])
              },
            ]),
          ]),
```

To:

```gleam
          html.a([attr.href("/"), attr.class("flex items-center gap-2 group")], [
            html.span([attr.class("text-2xl")], [html.Text("\u{1f347}")]),
            html.div([], [
              html.span(
                [
                  attr.class(
                    "text-xl font-light tracking-tight text-stone-800 group-hover:text-rose-800 transition-colors",
                  ),
                ],
                [html.Text("Rebstock")],
              ),
              case subtitle {
                None -> html.Nothing
                Some(s) ->
                  html.div([attr.class("text-xs text-stone-400 -mt-0.5")], [
                    html.Text(s),
                  ])
              },
            ]),
          ]),
```

- [ ] **Step 2: Replace the nav section with new layout**

Replace the nav div (lines 584-596) from:

```gleam
          html.div([attr.class("flex items-center gap-6")], [
            html.nav([attr.class("flex gap-6 text-sm")], [
              nav_link("All Wines", "/wines"),
              nav_link("All Wineries", "/wineries"),
              html.span([attr.class("text-stone-300")], [html.Text("//")]),
              html.span([attr.class("text-sm text-stone-400")], [
                html.Text("~" <> user.username <> ":"),
              ]),
              nav_link("Cellar", "/~" <> user.username <> "/cellar"),
              nav_link("Wishlist", "/~" <> user.username <> "/wishlist"),
              nav_link("Ratings", "/~" <> user.username <> "/ratings"),
            ]),
          ]),
```

To:

```gleam
          html.nav([attr.class("flex items-center gap-4 text-sm")], [
            nav_link("Wines", "/wines"),
            nav_link("Wineries", "/wineries"),
            html.span([attr.class("text-stone-300")], [
              html.Text("\u{2502}"),
            ]),
            nav_link("Cellar", "/~" <> user.username <> "/cellar"),
            nav_link("Wishlist", "/~" <> user.username <> "/wishlist"),
            nav_link("Ratings", "/~" <> user.username <> "/ratings"),
            html.span([attr.class("text-stone-300")], [
              html.Text("\u{2502}"),
            ]),
            html.Element("details", [attr.class("relative user-menu")], [
              html.Element(
                "summary",
                [
                  attr.class(
                    "cursor-pointer text-stone-500 hover:text-rose-800 transition-colors list-none select-none",
                  ),
                ],
                [html.Text("~" <> user.username)],
              ),
              html.div(
                [
                  attr.class(
                    "absolute right-0 top-8 bg-white border border-stone-200 rounded-lg shadow-lg py-1 min-w-[140px] z-20",
                  ),
                ],
                [
                  html.a(
                    [
                      attr.href("/~" <> user.username <> "/import"),
                      attr.class(
                        "block px-4 py-2 text-sm text-stone-600 hover:bg-amber-50 hover:text-stone-800 transition-colors",
                      ),
                    ],
                    [html.Text("Import")],
                  ),
                ],
              ),
            ]),
          ]),
```

- [ ] **Step 3: Add CSS for details/summary dropdown**

Add to `src/css/app.css` before the `@media print` block:

```css
/* User menu dropdown — pure CSS via details/summary */
details.user-menu > summary {
  list-style: none;
}

details.user-menu > summary::-webkit-details-marker {
  display: none;
}

details.user-menu > summary::after {
  content: ' \25BE';
  font-size: 0.7em;
}

details.user-menu[open] > summary::after {
  content: ' \25B4';
  font-size: 0.7em;
}
```

- [ ] **Step 4: Remove the now-unused `logo_svg` function from components.gleam**

Delete the `logo_svg` function (lines 603-615):

```gleam
fn logo_svg() -> String {
  "<svg width=\"32\" height=\"32\" viewBox=\"0 0 32 32\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">
    <circle cx=\"10\" cy=\"8\" r=\"4\" fill=\"#78180e\" opacity=\"0.8\"/>
    ...
  </svg>"
}
```

Keep `favicon_data_uri` — we'll leave the favicon as the SVG for now.

- [ ] **Step 5: Build and run tests**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: All 27 tests pass. No warnings.

- [ ] **Step 6: Commit**

```bash
git add src/rebstock/web/components.gleam src/css/app.css
git commit -m "Reorganize nav: emoji logo, separated zones, username dropdown"
```

### Task 2: Remove duplicate logo_svg from cellar.gleam

**Files:**
- Modify: `src/rebstock/web/cellar.gleam` (lines 781-793)

- [ ] **Step 1: Remove the `logo_svg` function from cellar.gleam**

Delete the `logo_svg` function at lines 781-793 in `src/rebstock/web/cellar.gleam`:

```gleam
fn logo_svg() -> String {
  "<svg width=\"32\" height=\"32\" viewBox=\"0 0 32 32\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">
    <circle cx=\"10\" cy=\"8\" r=\"4\" fill=\"#78180e\" opacity=\"0.8\"/>
    <circle cx=\"18\" cy=\"6\" r=\"3.5\" fill=\"#78180e\" opacity=\"0.65\"/>
    <circle cx=\"14\" cy=\"13\" r=\"3.5\" fill=\"#78180e\" opacity=\"0.75\"/>
    <circle cx=\"22\" cy=\"11\" r=\"3\" fill=\"#78180e\" opacity=\"0.5\"/>
    <path d=\"M14 18 C14 18 13 24 16 28\" stroke=\"#78716c\" stroke-width=\"1.5\" stroke-linecap=\"round\"/>
    <path d=\"M16 28 C16 28 12 29 10 28\" stroke=\"#78716c\" stroke-width=\"1\" stroke-linecap=\"round\" opacity=\"0.5\"/>
    <path d=\"M16 28 C16 28 20 29 22 28\" stroke=\"#78716c\" stroke-width=\"1\" stroke-linecap=\"round\" opacity=\"0.5\"/>
    <path d=\"M14 20 C11 19 8 20 7 18\" stroke=\"#78716c\" stroke-width=\"1\" stroke-linecap=\"round\" opacity=\"0.4\"/>
    <path d=\"M15 22 C18 21 20 22 22 20\" stroke=\"#78716c\" stroke-width=\"1\" stroke-linecap=\"round\" opacity=\"0.4\"/>
  </svg>"
}
```

- [ ] **Step 2: Update the cellar_print function to use grape emoji instead**

In `cellar_print` (line 79), replace:

```gleam
          html.UnsafeInlineHtml(logo_svg()),
```

With:

```gleam
          html.span([attr.class("text-2xl")], [html.Text("\u{1f347}")]),
```

- [ ] **Step 3: Build and run tests**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: All 27 tests pass. No warnings.

- [ ] **Step 4: Commit**

```bash
git add src/rebstock/web/cellar.gleam
git commit -m "Remove duplicate logo_svg from cellar, use grape emoji"
```

### Task 3: Add empty home page state with import CTA

**Files:**
- Modify: `src/rebstock/web/home.gleam` (lines 14-19)

- [ ] **Step 1: Modify the `home` function to check wine count**

Replace the `home` function (lines 14-19):

```gleam
pub fn home(conn: Connection, user: User) -> Response {
  c.page_with_subtitle("Rebstock", user, global_stats(conn), [
    user_section(conn, user.username, True),
    activity_grid(conn, user.username),
  ])
}
```

With:

```gleam
pub fn home(conn: Connection, user: User) -> Response {
  case db.count_wines(conn) {
    0 ->
      c.page("Rebstock", user, [
        welcome_empty_state(user.username),
      ])
    _ ->
      c.page_with_subtitle("Rebstock", user, global_stats(conn), [
        user_section(conn, user.username, True),
        activity_grid(conn, user.username),
      ])
  }
}
```

- [ ] **Step 2: Add the `welcome_empty_state` function**

Add this function to `home.gleam`:

```gleam
fn welcome_empty_state(username: String) -> Node {
  html.div([attr.class("text-center pt-16 pb-24")], [
    html.div([attr.class("text-6xl mb-6")], [html.Text("\u{1f347}")]),
    html.h1(
      [attr.class("text-3xl font-light text-stone-800 tracking-tight mb-3")],
      [html.Text("Welcome to Rebstock")],
    ),
    html.p([attr.class("text-stone-500 mb-8")], [
      html.Text("Import your Vivino data to get started"),
    ]),
    html.a(
      [
        attr.href("/~" <> username <> "/import"),
        attr.class(
          "inline-block px-6 py-3 bg-rose-800 text-white rounded-lg hover:bg-rose-900 transition-colors font-medium",
        ),
      ],
      [html.Text("Import Vivino Data")],
    ),
    html.p([attr.class("text-sm text-stone-400 mt-6")], [
      html.Text("You can also add wines manually later"),
    ]),
  ])
}
```

- [ ] **Step 3: Build and run tests**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: All 27 tests pass. No warnings. The existing `home_returns_200_test` and `home_contains_rebstock_test` tests use `with_empty_db` + `db.ensure_user` which means wine count is 0, so they'll now hit the welcome state — but they should still pass because the page still returns 200 and contains "Rebstock".

- [ ] **Step 4: Commit**

```bash
git add src/rebstock/web/home.gleam
git commit -m "Show welcome with import CTA when database is empty"
```

### Task 4: Add tests and final verification

**Files:**
- Modify: `test/rebstock_test.gleam`

- [ ] **Step 1: Add test for empty home page showing import CTA**

```gleam
pub fn home_empty_shows_import_cta_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Import Vivino Data")
  let assert True = string.contains(body, "/~test/import")
  Nil
}
```

- [ ] **Step 2: Add test for home page with data shows stats**

```gleam
pub fn home_with_data_shows_stats_test() {
  use conn <- with_seeded_db
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_auth)
  let assert 200 = response.status
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "Your Stats")
  let assert False = string.contains(body, "Welcome to Rebstock")
  Nil
}
```

- [ ] **Step 3: Add test for nav containing username dropdown**

```gleam
pub fn nav_contains_username_dropdown_test() {
  use conn <- with_empty_db
  db.ensure_user(conn, "test")
  let response =
    simulate.request(http.Get, "/")
    |> router.handle_request(conn, test_auth)
  let body = simulate.read_body(response)
  let assert True = string.contains(body, "~test")
  let assert True = string.contains(body, "/~test/import")
  Nil
}
```

- [ ] **Step 4: Run all tests**

Run: `gleam format . && gleam build --warnings-as-errors && gleam test`

Expected: All tests pass (27 existing + 3 new = 30).

- [ ] **Step 5: Commit**

```bash
git add test/rebstock_test.gleam
git commit -m "Add tests for nav dropdown and empty home state"
```
