-- Country lives on the winery; wines.country duplicated it. Backfill
-- any missing winery country from its wines, then drop the column.
UPDATE wineries SET country = (
  SELECT w.country FROM wines w
  WHERE w.winery_id = wineries.id AND w.country IS NOT NULL
  LIMIT 1
) WHERE country IS NULL;

ALTER TABLE wines DROP COLUMN country;
