# Vintage ranges in the wine table

## Problem

The Vintage column of the wine table prints every known vintage as a comma list.
A wine imported from Vivino routinely carries twenty or more, so the cell reads:

```
2000,2001,2002,2003,2005,2007,2009,2010,2011,2012,2013,2014,2015,2016,2017,2018,2019,2020,2021,2022,2023,2024
```

Two separate defects hide in that string.
The list is unreadable at a glance, and most of its entries are empty rows the Vivino import created: no rating, no bottles, no notes.

## Solution

Filter vintages down to those with data attached, then collapse the survivors into year ranges.

The example above renders as `2000–2024`.

## Filtering

A vintage appears in the column when at least one of these holds:

- `wines_vintages.vivino_rating` is not null
- a `cellar` row references the wine and vintage
- a `ratings` row references the wine and vintage
- a `lists_wines` row references the wine and vintage

The cellar match ignores both the owning user and the bottle count.
A vintage drunk down to zero is still a vintage the cellar knows something about.

Filtering happens in the `vintages` subquery shared by `wine_cols` (`db.gleam:200`) and the cellar view query (`db.gleam:877`):

```sql
(SELECT GROUP_CONCAT(v.year) FROM wines_vintages v
   WHERE v.wine_id = w.id
     AND (v.vivino_rating IS NOT NULL
          OR EXISTS (SELECT 1 FROM cellar cx      WHERE cx.wine_id = v.wine_id AND cx.vintage = v.year)
          OR EXISTS (SELECT 1 FROM ratings rx     WHERE rx.wine_id = v.wine_id AND rx.vintage = v.year)
          OR EXISTS (SELECT 1 FROM lists_wines lx WHERE lx.wine_id = v.wine_id AND lx.vintage = v.year))
   ORDER BY v.year) AS vintages
```

The inner aliases are `cx`, `rx` and `lx` because the cellar query already binds `c`.

A wine whose vintages all fail the predicate gets an empty cell.

`vintages_for_wine` keeps returning every vintage.
It populates the vintage dropdowns of the cellar and rating forms, which must offer years that have no data yet — that is how data first gets attached.

## Formatting

A new module `src/rebstock/vintages.gleam` holds the pure formatter:

```gleam
pub fn format(concatenated: Option(String)) -> String
```

Steps:

1. Split on `,`, trim each part, drop empties.
2. Partition into years that parse as integers and everything else.
3. Deduplicate and sort the years ascending.
4. Group them: a year joins the current group while `year - previous <= 2`, otherwise it opens a new group.
5. Render a group of one as the year itself, a longer group as `start–end` with an en dash.
6. Join groups with `", "`, then append the deduplicated non-numeric entries (`NV`) in encounter order.

Step 4 bridges single missing years on purpose.
`2000,2002` renders as `2000–2002` even though 2001 is absent.
Ranges are read as spans, not as inventories, and the exact vintages remain visible on the wine detail page.
Gaps of two years or more split the range.

Years always print in full.
No `'24` abbreviation, no truncated range end.

`components.display_vintages` delegates to `vintages.format`.
The call site at `wines.gleam:891` does not change.

## Testing

`test/vintages_test.gleam` covers the formatter:

- the twenty-two-vintage example collapses to `2000–2024`
- an exact run collapses
- a single year prints alone
- `2010,2012` collapses to `2010–2012`
- a two-year gap splits into two groups
- unsorted input sorts
- duplicates collapse
- `NV` alone, and `NV` mixed with years
- `None` and `""` produce `""`

A database test covers the filter: a wine with one Vivino-rated vintage and one bare vintage exposes only the rated year in `Wine.vintages`.
