# Cellar entry price

Record what a bottle cost, so the cellar can show what it holds in money as well as in bottles.

## Problem

Cellar entries carry vintage, quantity, notes and date, but no price.
An invoice import therefore loses the one number the invoice is mostly made of.
There is no way to see what the cellar is worth, or what a given wine cost.

## Scope

Price is optional on every cellar entry.
Existing entries stay valid with no price, and every surface degrades to showing nothing rather than zero.

## Data model

Migration `00005_cellar_price` adds a nullable column:

```sql
ALTER TABLE cellar ADD COLUMN price_cents INTEGER;
```

The down migration drops it.
Earlier migrations are not touched.

Price is stored in integer cents, not as a float, so sums are exact.
It means the price of one bottle, not of the whole entry.
The entry's total is `price_cents * quantity`, derived wherever it is shown.

Only purchase rows carry a price.
Drink rows — negative quantity, `parent_id` set — inherit the price of the purchase they draw from, read through a join at query time rather than copied at insert time.
Correcting a purchase price therefore corrects every bottle drunk from it.

`CellarEntry` gains `price_cents: Option(Int)`.
Every cellar `SELECT` appends the new column after `created_at`, so the decoder reads it at index 9 and the existing field indices do not move.

`insert_cellar_entry` and `update_cellar_entry` gain a `price_cents price_cents: Option(Int)` argument.
`insert_cellar_drink` does not.

## Money helpers

Two functions in `db.gleam`, beside `parse_optional_float` and `parse_vintage`:

```gleam
pub fn parse_price_cents(s: String) -> Option(Int)
pub fn format_price(cents: Int) -> String
```

`parse_price_cents` maps `""` to `None`, `"13.70"` to `Some(1370)`, and rounds to the nearest cent.
`format_price` renders `1370` as `€13.70`.

Numbers are formatted en-US with a decimal point and a leading `€`.
The interface is English throughout and ratings already render as `4.2`, so a comma decimal would be inconsistent on the page and would need quoting in the comma-delimited CSV export.

`format_price` writes no thousands separator: `123456` renders as `€1234.56`.
A separator would be a second comma problem in the export for no gain at cellar scale.

## Held value

A wine's held value is the sum of its signed quantities weighted by unit price.
Purchases add, drinks subtract at the price they inherited, so the total describes bottles still in the rack.

`CellarWine` gains `price_breakdown: List(#(Int, Int))` — held bottles and unit price in cents, one pair per distinct price.
It comes from a correlated subquery added to `cellar_wine_cols`:

```sql
(SELECT GROUP_CONCAT(pb.bottles || 'x' || pb.price)
 FROM (SELECT COALESCE(c2.price_cents, p2.price_cents) AS price,
              SUM(c2.quantity) AS bottles
       FROM cellar c2 LEFT JOIN cellar p2 ON c2.parent_id = p2.id
       WHERE c2.username = c.username AND c2.wine_id = w.id
         AND c2.vintage IS c.vintage
         AND COALESCE(c2.price_cents, p2.price_cents) IS NOT NULL
       GROUP BY price HAVING bottles > 0) pb) AS price_breakdown
```

The vintage comparison uses `IS`, not `=`, because entries without a vintage hold `NULL`.
`GROUP_CONCAT` does not guarantee order, so the string `"2x1370,1x1420"` is parsed into pairs and sorted by price in Gleam.

A row's value is a fold over `price_breakdown`, not a second SQL column, so the value shown and the prices behind it cannot disagree.

`cellar_total_value` is a separate query of the same shape without the grouping, returning `Option(Int)` for the whole cellar.

## Interface

The cellar form gains an optional field between Quantity and Date, labelled `Price per bottle (€)`, rendered as `<input type="number" step="0.01" min="0">`.
It appears on both the new and edit forms, prefilled when set, and runs through `parse_price_cents` in `handle_new` and `handle_edit`.
The drink form does not have it.

The cellar entry card shows a Price row reading `€13.70 · €27.40 for 2 bottles`, omitted when no price is set.

The cellar page subtitle becomes `17 bottles · €334.98`, dropping the value when nothing in the cellar is priced.
The page has no stat-card row today and does not gain one for a single number.

The cellar table gains a Value column showing the row's held value, blank when unpriced.
The cell carries a `title` attribute holding the breakdown, `2×€13.70, 1×€14.20`, so hovering answers what the bottles cost without a second request.
Per-entry history stays on the wine page, which already lists every entry with its edit and drink actions.

## Export

`cellar_csv_body` appends one column, giving `Winery,Wine,Vintage,Country,Type,Bottles,Value`.
The field is blank when the row has no priced bottles.
It holds a bare number, `27.40`, without the euro sign, so a spreadsheet reads it as a number.

Value rather than unit price, because an export row is the same wine-and-vintage aggregate as a table row, and a single unit price is undefined once a row spans purchases at different prices.
No line-total column: it is `Value` already, and any per-bottle figure a reader wants is one division away.

## Backfill

The wines from invoice #37140 are already in the live cellar without prices.
A one-off script in the scratchpad updates them by wine and vintage after deploy.
It is not committed.

| Wine | Vintage | € per bottle | `wines.vivino_id` |
| --- | --- | --- | --- |
| Dakishvili Cuvée Amber Dry | 2020 | 23.90 | v165017012 |
| Terra Qisi Khikhvi Amber | 2020 | 16.15 | v171993892 |
| Binekhi Kindzmarauli Red Semi-Sweet | 2022 | 13.70 | v174677626 |
| Chelti Kindzmarauli Family Collection | 2025 | 13.65 | v182784374 |
| Dakishvili Kisi Amber Dry | 2023 | 18.75 | v176759357 |
| Dakishvili Kisi Pétillant Naturel | 2024 | 25.05 | v182085815 |
| BG Wines Mtsvane | 2021 | 21.80 | v173871883 |
| Dakishvili Saperavi Red Dry | 2023 | 18.75 | v179984131 |
| SHNO Saperavi Rosé | 2023 | 11.95 | v178516548 |
| Baia's Wine Tsitska | 2024 | 20.00 | v181698552 |
| Naberauli Tvishi | 2023 | 22.00 | v178098094 |
| Giuaani Tvishi Semi Sweet White | 2024 | 20.00 | v178126535 |
| Binekhi Tsitska Semi Dry | 2022 | 11.30 | v176109896 |
| Ziari Petnat Kisi Sauvignon Blanc | 2025 | 20.00 | — |

The two BG Wines Mtsvane invoice lines were merged into the 2021 entry at import, and both were priced 21.80.
Ziari has no Vivino id because the wine does not exist on Vivino and was created from the invoice alone.

The ids are the unresolved-vintage form the CSV import stores, `v` plus the Vivino vintage id, which pins each row to its exact vintage.
A later Vivino sync rewrites a wine's id to the resolved wine id, so the backfill should match on the id first and fall back to winery, wine name and vintage.

## Testing

`parse_price_cents` round-trips the blank string, `13.70`, `13.7` and `13.705`.

A cellar-value test buys three bottles at €10, drinks one, and asserts a held value of €20.
This is the case that proves drink rows inherit the price of their parent instead of counting as free.

A breakdown test buys two bottles at €13.70 and one at €14.20 of the same wine and vintage, and asserts the parsed pairs sort to `[(2, 1370), (1, 1420)]`.

## Out of scope

Currency: prices are euro, with no code stored and no conversion.

Price on CSV import: the Vivino cellar export has no price column, and rebstock's importer keeps matching that format.

Price history: a corrected price overwrites, nothing is versioned.
