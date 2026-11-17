# Cut-paper wine companions

**Shelved:** these custom avatar studies are not in use. The app uses a separate,
licensed Unsplash illustration as its fallback. These studies are retained only for later reference.

**Latest refinement:** [three softer paper studies](soft/index.html), with a
rounded lounging cat and two new dog-reference interpretations. The original
12 studies below are preserved for comparison.

Open [index.html](index.html) directly in a browser. Twelve standalone SVG avatar
studies, in three groups of four:

| Numbers | Animal | Directions |
| --- | --- | --- |
| 01–04 | Cats | Cream bottle-and-glass lounger; patch-eared table supervisor; burgundy lounger; amber cat tasting |
| 05–08 | Dachshunds | Amber long-back toast; black-and-tan table regular; reclining burgundy dog; pale bottle-and-glass dog |
| 09–12 | Whippets / greyhounds | Charcoal lounger; pale table regular; curled fawn whippet; patch-coated reverse-facing toast |

## References and treatment

The user supplied two references, both of which were downloaded temporarily and
viewed:

1. [Lounging cat holding a bottle and glass](https://i.pinimg.com/originals/36/88/7c/36887c101fde6287c00d58d7c180b51f.jpg)
2. [Patch-eared cat with a paw over a table edge](https://i.pinimg.com/736x/88/f1/ca/88f1ca2f9a486fa77f5709a3e114b971.jpg)

The studies are newly drawn SVG interpretations of these poses, using angular
filled paper shapes, restrained two-tone shading, small facial marks, thin
charcoal wine glasses and Rebstock's burgundy/cream/amber palette. Dachshund and
sighthound versions adapt the gestures to their long backs, short legs, folded
ears, narrow muzzles, deep chests and long limbs. The source JPEGs are linked for
context but are not embedded or redistributed in the repository.

## Review

- Each card shows an enlarged drawing, a true **96px profile** sample and a true
  **28px account-menu** sample with the app's circular clipping and background.
- Filter by animal using the native select control.
- Click a drawing to enlarge it in a native dialog. Escape closes the dialog and
  returns focus to its trigger.
- Toggle the main previews to actual 96px size.
- Pick a number or copy its stable ID. Selection persists only in local browser
  storage and never modifies the app.
- Each card links to its standalone SVG download.
- Approved bottles and logo appear below for palette/context comparison.

All SVGs share `viewBox="0 0 120 120"`. They contain no fonts, scripts, raster
images, filters or external dependencies. `manifest.json` records references,
species, descriptions and the unchanged production avatar hash. `candidates.js`
provides the same study metadata without file-URL fetch/CORS issues.

**None is applied to the app.** Production artwork, uploaded-photo behavior and
the earlier [person studies](../avatar-studies/index.html) are unchanged.

## Verification

From the repository root:

```sh
node docs/animal-avatar-studies/verify.cjs
```

Validates 12 distinct SVGs, four per species, thin glass outlines, safe XML, image
loading, actual sample sizes, species filtering, the size toggle, saved picks,
modal keyboard/focus behavior, mobile overflow and axe accessibility in Chromium
and WebKit. Confirms the production avatar has not changed. Refreshes the contact
sheet and per-species previews in `previews/`.
