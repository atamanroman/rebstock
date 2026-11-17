# Wine avatar studies

**Shelved:** these custom avatar studies are not in use. The app uses a separate,
licensed Unsplash illustration as its fallback. These studies and [the shelved experimental silhouette](shelved-avatar.svg)
are retained only for later reference.

Open [index.html](index.html) directly in a browser. No server, database, build,
network connection or installation is needed once the project dependencies exist
for the optional verification script.

## Ten original directions

| ID | Name | Gesture | Drawing direction |
| --- | --- | --- | --- |
| AVATAR-01 | The quiet sip | Drinking | Fluid ink line |
| AVATAR-02 | A little toast | Holding | Loose paper shapes |
| AVATAR-03 | Savor the aroma | Enjoying | Soft editorial silhouette |
| AVATAR-04 | The generous pour | Pouring | Angular cut-paper scene |
| AVATAR-05 | A café moment | Enjoying | Relaxed bistro sketch |
| AVATAR-06 | Lean back | Holding | Playful abstract figure |
| AVATAR-07 | The swirl | Enjoying | Bold cropped graphic |
| AVATAR-08 | The welcoming host | Holding | Warm minimal portrait |
| AVATAR-09 | A ribbon of a toast | Holding | Expressive brush gesture |
| AVATAR-10 | The cellar signet | Drinking | Negative-space emblem |

These are different compositions and drawing approaches, not recolors or edits of
the current production pictogram. All are standalone SVGs with a shared
`0 0 120 120` viewBox, using Rebstock's burgundy, warm charcoal, cream and muted
rose. They do not rely on fonts, scripts, raster images or external resources.

The suggested [Vecteezy search](https://www.vecteezy.com/free-vector/people-wine)
returned HTTP 403 / Cloudflare, including in Chromium. Its examples could not be
viewed. No reference artwork was copied, traced, embedded or redistributed.

## Review

- Every card shows an enlarged drawing plus actual **96px profile** and **28px
  menu** samples, with the app's circular crop and light background.
- Click the large drawing for a bigger native-dialog preview; Escape closes it.
- The size checkbox changes the main previews to actual 96px size.
- Choose one numbered radio option. The pick persists only in local browser
  storage; **Copy selection** copies its stable ID.
- Each card links to its downloadable SVG.
- The approved grapevine and bottles remain alongside for visual context.

`manifest.json` records IDs, descriptions and the production avatar's unchanged
SHA-256. `candidates.js` provides the same candidate metadata for a `file://`
gallery without fetch/CORS restrictions.

**None is applied to the app yet.** The production `priv/static/avatar.svg` fallback, uploaded
photo priority, logo and bottles are unchanged by these studies.

## Verify

From the repository root:

```sh
node docs/avatar-studies/verify.cjs
```

Checks SVG validity and safety, ten distinct drawings, image loading, exact sample
sizes, the size toggle, persisted selection, modal keyboard/focus behavior, mobile
overflow and axe accessibility in Chromium and WebKit. It also confirms that the
production avatar still matches the recorded hash and saves a Chromium contact
sheet in `previews/contact-sheet.png`.
