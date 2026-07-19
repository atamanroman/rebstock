ALTER TABLE wines ADD COLUMN country TEXT;
UPDATE wines SET country = (
  SELECT wy.country FROM wineries wy WHERE wy.id = wines.winery_id
);
