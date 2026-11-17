# Softer paper studies

**Shelved:** these custom avatar studies are not in use. The app uses a separate,
licensed Unsplash illustration as its fallback. These studies are retained only for later reference.

Open [index.html](index.html). Three focused studies made after feedback that the
first animal set was too rigid and geometric:

- **A — One more glass:** a rounded lounging cat, closer to the original reference
  pose, with a contented tilted face, soft paws, curled feet and a wrapping tail.
- **B — The wine inspector:** a front-facing, long-muzzled dog investigating a large
  glass. The nose sits inside the bowl, just above the wine.
- **C — Steady now:** a front-facing long-nosed dog balancing a flute on its head.

Organic closed Bézier shapes and a few broad color layers replace the earlier
polygon construction. Thin glass edges and the established cream, charcoal,
burgundy and muted-gold palette keep them related to the bottle artwork. Tiny
facial details are limited to expression, rather than fur rendering.

## Reference handling

The first cat reference, the newly supplied Thortful card and the user's local
flute-balancing dog photograph were all viewed. The SVGs are newly drawn
interpretations of the poses and visual jokes. They do not embed the reference
images, the greeting-card wording or the user's local photograph. The public
reference URLs and a non-identifying note about the local photo are recorded in
`manifest.json`.

## Review and verification

The page shows enlarged circular previews, plus exact 96px and 28px samples.
Click an enlarged drawing to view its standalone SVG.

No app asset has been changed. The production avatar's unchanged hash is recorded
in the manifest. The earlier studies are preserved separately.

```sh
node docs/animal-avatar-studies/soft/verify.cjs
```

Checks SVG validity/safety, all three rendered images, exact profile/menu sizes,
mobile overflow and axe accessibility in Chromium and WebKit. Refreshes the
preview contact sheet and confirms the production avatar remains unchanged.
