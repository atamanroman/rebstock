# Bottle illustration studies

Open [`index.html`](index.html) directly in a browser. No server, npm build, network
request or app database is needed.

## Scope

- The wine-page and placeholder starting point was committed **before** these
  studies: `bf82e95` (`Rework wine details and add illustrated bottle placeholders`).
- Eight types, ten original SVG candidates each: **80 choices**, not 80 app changes.
- IDs are stable: `RED-01` … `RED-10`, `WHITE-01` … `WHITE-10`, `ROSE-01` …,
  `ORANGE-01` …, `SPARKLING-01` …, `DESSERT-01` …, `SAKE-01` …, `OTHER-01` ….
- Red, white and orange have additional color exploration. The other types keep
  burgundy ink, sometimes with low-opacity washes of the same hue.
- Sake labels use vector strokes for 酒, not a font glyph.

## Independent generation

Every candidate was created by a separate ephemeral `pi --print` process with
`--no-session --no-context-files --no-skills --no-extensions --no-mcp
--no-prompt-templates --no-themes --no-tools` and a custom illustrator system prompt.
It saw only:

1. The common reference image's hand-drawn visual family (not permission to trace).
2. Its own type's SVG path baseline from the committed code.
3. Its own anatomical brief, palette constraints and a distinct art-direction brief.

No candidate saw any other candidate or the long redesign conversation. The ten
art directions deliberately explore different mark-making, silhouette, labels and
composition, rather than successively tweaking a closure. Original per-candidate
briefs are in `briefs/`; titles and provenance are in `manifest.json`.

The ten briefs cover bistro contour, continuous gesture, cellar engraving, dry
brush, cut-paper, ink/wash, geometric atelier, botanical field note, linocut and
naive folk sketch. These are independent interpretations, not a requirement to
pick a matched set. Pick any one candidate per type.

## Review

- Filter to one type or use the navigation links.
- Click a drawing to inspect it at larger size; Escape closes the preview.
- Switch **Actual app size** on to check whether the illustration survives at
  88 × 220 px.
- Choose a radio option per type. Picks persist only in local browser storage.
- **Copy selections** produces an ID list; **Download selections** exports JSON.
- Each card also downloads its standalone SVG.
- `previews/` contains the eight visual contact sheets.

`candidates.js` is the same manifest as a static JavaScript assignment so the
review page works from a `file://` URL without fetch/CORS restrictions. No external
libraries, fonts, images or services are used by the gallery or its SVG assets.

The original reference is not embedded or redistributed. All SVG candidates were
checked for valid XML, a common viewBox and the absence of scripts, external
resources, images, fonts, filters and foreignObject.

## Verification

From the repository root:

```sh
node docs/bottle-studies/verify.cjs
```

This validates all SVGs and checks rendering, selection persistence, filtering,
preview keyboard behavior, mobile overflow and axe accessibility in Chromium and
WebKit. It also refreshes the Chromium contact-sheet images in `previews/`.

## Selected set

All eight **cut-paper (#05)** options were selected. Production assets are in
`priv/static/bottles/`. Red, white, rosé and orange are unchanged copies of #05.
Sparkling is a cut-paper derivative with dark-green champagne glass, an elongated
neck, seated cork with a rounder visible head, glass lip and heavy heel. Dessert,
sake and other were harmonized with the approved four: two-tone filled paper
shapes, simple highlights and fully inset labels (amber, ivory and neutral olive).
Dessert is a tall, slender half-bottle with a long gold capsule, Other has a
question mark on its label, and
Sake retains the drawn 酒 label. The gallery originals remain unchanged.

`selection.json` records the chosen IDs and their production assets. Uploaded
label photos continue to take precedence over placeholders.
