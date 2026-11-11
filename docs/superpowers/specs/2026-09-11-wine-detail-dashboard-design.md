# Align the wine detail page with the dashboard

## Summary

The wine detail page will adopt the dashboard's editorial layout and remove its tinted cards and filled section backgrounds.
The redesign will preserve every route, mutation, permission, and htmx interaction.
Wine-related dialogs will share the page's typography, spacing, dividers, and action hierarchy while retaining the white surface needed to separate them from the backdrop.

## Goals

- Make the wine detail page feel like a natural continuation of the dashboard.
- Replace decorative surfaces with whitespace, ruled sections, and typographic hierarchy.
- Give ratings and cellar activity a consistent and scannable structure.
- Align wine-related dialogs with the redesigned page.
- Preserve responsive behavior, accessibility, and native form fallbacks.

## Non-goals

- This work will not change database queries, domain models, routes, or form fields.
- This work will not redesign unrelated detail pages or collection indexes.
- This work will not introduce a second theme or a new styling framework.
- This work will not change the dashboard itself.

## Current problem

The Astra redesign established the dashboard's restrained Journal language, but the wine detail page still relies on pale cards for summary ratings, personal ratings, other users' ratings, and cellar entries.
Those repeated backgrounds fragment the page and compete with the wine's identity.
Filled vintage pills and inconsistent action placement add more visual noise.

## Chosen design

### Wine masthead

The page will place the bottle image beside an unboxed editorial masthead.
The masthead will group the wine name, softened type badge, winery link, origin, region, and style into a clear reading order.
Edit and list-membership actions will use the same understated rose text treatment as dashboard actions.
The layout will use whitespace and one rule below the masthead instead of a surrounding card.

### Vintage navigation and rating summary

Vintage selection will become a compact row of text tabs.
The active vintage will use a rose underline instead of a filled pill.
The Vivino, personal, and community rating summaries will use the dashboard's three-column stat-strip pattern.
The strip will use top, bottom, and internal rules without individual card backgrounds.

### Ratings

Personal and community ratings will appear in ruled activity lists with transparent rows.
Each row will reserve a stable area for the rating and vintage, a flexible area for tasting notes, and a predictable area for metadata and actions.
Empty states will remain plain text beneath the section heading.
Rate and Edit will use consistent rose text actions with accessible target sizes.

### Cellar activity

Cellar purchases and consumption events will use the same ruled-row structure as ratings.
Quantity, vintage, date, price, notes, and actions will retain their existing meaning and visibility.
The section heading will keep the current bottle count and held value without placing them in a tinted badge.
Add to cellar, Drink, and Edit will follow the same action treatment as the rating section.

### Wine-related dialogs

Add to cellar, edit cellar entry, drink, add rating, and edit rating dialogs will adopt the page's spacing and hierarchy.
Each dialog will retain a white panel because the panel must remain distinct from the dimmed page.
Nested tinted panels and decorative field-group backgrounds will be removed.
Headings, labels, field spacing, dividers, validation messages, and primary and secondary actions will remain consistent across these flows.
Focus trapping, Escape dismissal, history behavior, validation responses, and native form submission will remain unchanged.

## Responsive and accessible behavior

The masthead will stack on narrow screens while keeping the wine name and primary actions visible without horizontal scrolling.
Stat strips will preserve readable labels and values at mobile widths.
Rating and cellar rows will collapse into a single-column reading order instead of becoming cards.
Interactive controls will retain their 44-pixel minimum target size and visible focus treatment.
Semantic headings, form labels, dialog names, error focus, and reduced-JavaScript fallbacks will remain intact.

## Implementation boundaries

Shared structural styling belongs in `src/css/ui.css`.
The wine detail markup and wine-specific dialog markup belong in `src/rebstock/web/wines.gleam`.
Existing shared components should be reused when their semantics already match the design.
New shared helpers should be limited to repeated structures that improve consistency without expanding the redesign to unrelated pages.
Tailwind utilities may continue to express isolated positioning and semantic wine colors.

## Verification

Gleam regression tests will assert the new wine-detail structure and the absence of the old tinted panel classes in rating and cellar rows.
Browser tests will exercise the populated wine detail page at desktop and mobile widths.
Browser tests will open each wine-related dialog and retain the existing accessibility, focus, validation, navigation, and no-JavaScript checks.
Visual review will compare the dashboard and wine detail page at the same viewport widths for typography, spacing, rules, and action alignment.
The final verification will run `gleam format .`, `gleam build --warnings-as-errors`, the focused Gleam tests, and the relevant Playwright coverage.

## Alternatives considered

A minimal class cleanup would remove pale fills while preserving the current card composition, but the remaining boxes would still fragment the page.
A two-column editorial layout would create a stronger visual departure, but it would diverge from the dashboard and add unnecessary mobile complexity.
The selected dashboard-aligned layout achieves the requested consistency with the smallest coherent design change.

## Resolved decisions

The dashboard is the visual reference.
The warm application canvas remains.
Tinted content cards on the wine detail page will be removed.
White backgrounds remain only where a distinct surface is necessary, including menus and modal panels.
The wine type badge remains as a softened semantic color marker.
