# Artwork collection

Open [index.html](index.html) directly in a browser for production artwork,
concise [study summaries](studies.md), and current UI screenshots. The old study
artwork, galleries, briefs, metadata, and contact sheets have been removed.

## Current production artwork

- [All eight bottles](current-bottles.html): enlarged and actual-app-size views of
  red, white, rosé, orange, sparkling, dessert, sake, and other.
- [Logo and default avatar](current-logo.html): header, favicon, account-menu, and
  profile sizes alongside the complete bottle set.

The previews reference live files in [`priv/static/`](../../priv/static/), not
copies. Uploaded wine and profile photos take precedence in the app. The default
avatar is the unmodified Spacepixel Creative Unsplash illustration; see
[the license and attribution notice](../../LICENSE.md).

## Project screenshots

`assets/` contains fresh dashboard, wine-detail, desktop/mobile cellar, shared
wine-list, and print-view captures. All data is fictitious, including illustrative
community ratings. No personal cellar data or uploaded photographs are used.

The README uses these files directly. The project site publishes copies of
`dashboard.png` and `shared-list.png` as `site/static/images/dashboard.png` and
`site/static/images/cellar.png` respectively.

Refresh all six images and both site copies from the repository root:

```sh
npm run screenshots
```

Requires Gleam, the SQLite CLI, and the browser-test dependencies. The script
starts a separate server on a free local port, populates a temporary database,
checks the pages with axe, captures Chromium screenshots, and cleans up the
server and database. Requests outside the temporary app are blocked; the public
menu uses its native serif-font fallback. Existing running instances and real
cellar data are not touched.

## Verification

```sh
npm ci
npx playwright install chromium webkit
npm run test:artwork
```

Checks all local documentation/media links, the complete eight-bottle set,
mobile/desktop layout and axe in Chromium and WebKit, and matching project-site
screenshot copies. The checks and capture utility live in `test/artwork/`, not
alongside the documentation media. The app's HTTP/browser tests remain separate:
`npm run test:browser`. UI behavior is documented in [`docs/ui.md`](../ui.md).
