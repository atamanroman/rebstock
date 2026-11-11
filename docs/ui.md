# Ledger UI

Ledger is the selected design, not a theme switcher. It uses a white background,
system typography, compact collection summaries, thin rules and one muted
burgundy accent. The compact masthead pairs the name with a flat grapevine mark
(`priv/static/grapevine.svg`, also used as the favicon); there is no tagline.
Wine types use a small colored dot with a text label rather than a badge.
Rating colors remain meaningful.

The standalone comparison in `docs/design-explorations.html` records the three
options; Ledger (A) was selected. Screenshots of the implemented cellar with
illustrative data: [desktop](assets/ledger-cellar.png) and
[mobile](assets/ledger-cellar-mobile.png).

## Responsive and accessible behavior

- Navigation wraps; mobile tables become labeled records without hiding columns
  or truncating names. Search has empty-result feedback and appears only when
  JavaScript is available.
- Dashboard summaries are compact inline links, not stat cards. Rating insights
  follow the collection summary, above recent activity and highlights; all remain
  visible without disclosure panels. Detail pages sit directly on white; forms and dialogs retain clear
  boundaries. Wine summary scores stay compact; entry actions do not overlap
  tasting notes.
- Thematic breaks between dashboard sections, before notes, and above the footer
  use native `<hr>` elements with shared `section-divider` spacing (a compact
  variant for notes). Borders remain on tables, controls and container edges.
- Primary controls have 44px heights, inputs use 16px text on mobile, and dialogs
  scroll independently in short viewports with safe-area padding.
- Labels are associated with controls.
  Vintage and precise 1–5 ratings use native inputs.
  Image uploads and mutation forms work without JavaScript.
- Dialogs are named, focus-trapped and dismissible with Escape; background content
  is inert. Closing restores focus and history; direct links render full pages.
- Validation returns 422, retains submitted values and focuses the error.
  Transport errors keep the form and show an inline, retry-safe message. Pending
  mutations are disabled and synchronized to prevent double submission.
- Public wine menus keep their separate print layout, with readable secondary
  text and narrower mobile margins.

## Profiles and settings

The account menu links **Settings** to `/settings` and **Your profile** to
`/~username`, the existing public collection dashboard. Settings has a native
multipart form for a display name (1–100 characters) and an optional picture;
only the authenticated user's profile can be edited. The username stays unchanged.
Names and pictures are visible to other viewers of that profile; auth email and
groups are not included.

User dashboards show the name and a 96px square picture above the collection
summary, with the grapevine logo when no picture is set. `/` keeps its collection
heading and never includes the profile picture. Pictures use `object-fit: cover`
for square presentation; the uploaded original is not resized or cropped on disk.

PNG, JPEG and WebP pictures up to 2 MB are accepted. File signatures determine
extensions, not the submitted filename or MIME type; SVG and other active content
are rejected. Files have generated names under `image_dir/profiles/` and are served
at `/images/profiles/…`. Replacing or removing a picture deletes the previous file.
Back up the image directory along with SQLite. Validation retains the submitted
name and current picture, and the whole workflow works without JavaScript.

`test/profile_test.gleam` and `test/browser/profiles.spec.cjs` cover profile
ownership, menu destinations, native uploads/removal, square rendering, logo
fallback, home-page exclusion, rejected files, safe extensions, and axe checks.

## Semantic HTML contracts

- Collections use `ul`/`li` (`item_list` preserves list semantics in Safari when
  markers are removed). Metadata and score summaries use `dl`/`dt`/`dd`.
- Wine detail sections use `h2`, with `h3` for You/Others within Ratings.
  Reused forms explicitly render an `h1` on a page and an `h2` in a dialog;
  heading levels do not depend on CSS classes.
- Dates use `time` with a machine-readable date; quoted notes use `blockquote`
  with attribution outside the quotation.
- Rating charts are figures with captions, contextual link names, and an
  equivalent visually hidden data table including zero/unrated counts.
- Vintage filters remain links in a labeled navigation group; the selected
  filter has `aria-current`. They are not ARIA tabs.
- Table rows remain rows. Pointer enhancements ignore links and other
  interactive descendants, including auxiliary clicks. Native links retain
  their default actions; do not make rows into ARIA links.
- Repeated actions have contextual accessible names, and action columns have a
  visually hidden header. Membership buttons are changing-name submit actions,
  not simultaneously pressed-state toggles.
- Server field errors identify the invalid controls with `aria-invalid` and
  `aria-describedby`, preserve existing help associations, and name the form's
  error summary. General form errors do not mark unrelated fields invalid.
- Shared/print menus have a main landmark, a header, headed wine-type sections,
  wine lists, and a footer. Shared 404 pages also have a main landmark.

`test/semantic_test.gleam` and `test/browser/semantics.spec.cjs` cover these
contracts alongside the broader browser/axe suite. Actual native middle-click
popup behavior is tested in Chromium; both engines test the row-handler guard
(WebKit's headless macOS build does not open native middle-click tabs).

## htmx version and contract

The previous vendored file was **2.0.4**. The next-generation release used here is
**4.0.0**, not a release called “3”. It is pinned from upstream; npm's default
`latest` remains on the 2.x line while 4.x uses `next`.

- [Release](https://github.com/bigskysoftware/htmx/releases/tag/v4.0.0)
- [Migration notes](https://htmx.org/docs/whats-new-in-htmx-4)
- [Vendored source](https://raw.githubusercontent.com/bigskysoftware/htmx/v4.0.0/dist/htmx.min.js)
- SHA-256: `e484d9171a9db30a39c8f16e3d709d4137f3211c659f8e6125816635033d593f`
- License: `priv/static/js/htmx.LICENSE` (Zero-Clause BSD).

Enhanced forms declare `hx-action`, target, swap, disable and synchronization
explicitly; they do not depend on 2.x implicit inheritance. Navigation is
boosted; ordinary links, form actions and native 303 Post/Redirect/Get remain
usable fallbacks.

`components.is_fragment` excludes full navigation and history restoration.
Dynamic responses vary on the htmx request headers. Successful enhanced mutations
use `HX-Location`; its `replace` option is the actual URL, not boolean `true`
(which 4.0.0 interpreted as a relative `/true` URL in browser verification).
Drink → rate uses `HX-Replace-Url`, so cancel cannot return to a stale drink form.
The configured `noSwap` policy preserves forms for unexpected HTTP errors while
allowing expected 422 validation fragments.

`ui.js` uses 4.x lifecycle events and `event.detail.ctx`, without a compatibility
extension or client-side history cache.

## Plain CSS, no build step

Tailwind has been removed from npm, Nix and the dev/build tasks. All styles are
version-controlled source in `priv/static/css/` and are served directly:

- `app.css`: imports, a small browser baseline, and print styles.
- `ui.css`: Ledger's shared navigation, tables, forms, summaries and dialogs.
- `layout.css`: local layout/text helpers for the existing Gleam templates.
  These preserve template layout without carrying generated Tailwind output;
  new shared styling should use named components in `ui.css`.
- `colors.css`: palette shared with the separate public wine menu.

No CSS compiler, npm install, runtime framework or utility-substring selectors
are required to build or run Rebstock. npm is only needed for the browser/MCP
test tools. Edit the files above directly; do not regenerate `app.css`.

## Verification

```sh
npm ci
npx playwright install chromium webkit
npm run test:browser
just lint
just test
```

The browser runner creates and cleans a temporary database and image directory
on port 4101; it refuses to reuse an existing server. Test-only forwarded auth
allows checking another user's empty profile without touching real accounts.

The suite covers populated page variants at 320, 375, 390, 768 and 1440px in Chromium and WebKit, with axe WCAG A/AA checks at 375px: home/profile, settings, collection indexes, wine/winery details and create/edit forms, cellar/rating details and forms, and lists/edit/share/print.
Additional tests exercise empty and filtered states, add/edit/drink/rate/delete, list membership and sharing, canonical URLs, back/forward/reload, short-height dialogs, keyboard focus, 422/403/500/network errors, pending submissions, native no-JavaScript forms, image uploads, CSV export, and retired import routes.
Gleam tests cover response contracts, field preservation, optional table columns and membership ownership/method guards.
MCP discovery, authorization, and tool calls have a separate [official-client socket suite](mcp.md#verification).

A separate read-only screenshot/axe pass used a copy of a populated cellar, including dashboard charts.
These checks use viewport/browser emulation and do not constitute a physical iPhone or complete screen-reader conformance audit.
The browser suite does not contact live Vivino services.
