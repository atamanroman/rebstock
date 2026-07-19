-- Move cached Vivino community ratings out of the ratings table into
-- dedicated columns on wines (overall) and wines_vintages (per vintage).
-- The ratings table then holds user ratings only.
ALTER TABLE wines ADD COLUMN vivino_rating REAL;
ALTER TABLE wines ADD COLUMN vivino_rating_count INTEGER;
ALTER TABLE wines_vintages ADD COLUMN vivino_rating REAL;
ALTER TABLE wines_vintages ADD COLUMN vivino_rating_count INTEGER;

UPDATE wines SET vivino_rating = (
  SELECT r.rating FROM ratings r
  WHERE r.wine_id = wines.id AND r.source = 'vivino' AND r.vintage IS NULL
  ORDER BY r.created_at DESC LIMIT 1
);

UPDATE wines_vintages SET vivino_rating = (
  SELECT r.rating FROM ratings r
  WHERE r.wine_id = wines_vintages.wine_id
    AND r.vintage = wines_vintages.year
    AND r.source = 'vivino'
  ORDER BY r.created_at DESC LIMIT 1
);

DROP INDEX IF EXISTS ratings_vivino_unique;
DELETE FROM ratings WHERE source = 'vivino';
ALTER TABLE ratings DROP COLUMN source;
