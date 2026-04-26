-- Prevent duplicate vivino ratings per wine+vintage
-- Uses COALESCE so NULL vintages (overall ratings) match each other
CREATE UNIQUE INDEX IF NOT EXISTS ratings_vivino_unique
  ON ratings (username, wine_id, COALESCE(vintage, ''), source)
  WHERE source = 'vivino';
