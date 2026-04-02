ALTER TABLE cellar ADD COLUMN parent_id TEXT REFERENCES cellar(id);
