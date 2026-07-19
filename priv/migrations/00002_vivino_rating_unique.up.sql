-- Prevent duplicate vivino ratings per wine+vintage
-- Uses COALESCE so NULL vintages (overall ratings) match each other
-- Existing databases may already hold duplicates from repeated imports:
-- keep only the newest row per (username, wine_id, vintage) before indexing.
DELETE FROM ratings
WHERE source = 'vivino'
  AND rowid NOT IN (
    SELECT MAX(rowid) FROM ratings
    WHERE source = 'vivino'
    GROUP BY username, wine_id, COALESCE(vintage, '')
  );

CREATE UNIQUE INDEX IF NOT EXISTS ratings_vivino_unique
  ON ratings (username, wine_id, COALESCE(vintage, ''), source)
  WHERE source = 'vivino';
