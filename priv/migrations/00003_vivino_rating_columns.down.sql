-- Restore the source column and unique index; cached Vivino rating rows
-- are not reconstructed (they are re-created on next sync).
ALTER TABLE ratings ADD COLUMN source TEXT NOT NULL DEFAULT 'user';
CREATE UNIQUE INDEX IF NOT EXISTS ratings_vivino_unique
  ON ratings (username, wine_id, COALESCE(vintage, ''), source)
  WHERE source = 'vivino';
ALTER TABLE wines DROP COLUMN vivino_rating;
ALTER TABLE wines DROP COLUMN vivino_rating_count;
ALTER TABLE wines_vintages DROP COLUMN vivino_rating;
ALTER TABLE wines_vintages DROP COLUMN vivino_rating_count;
