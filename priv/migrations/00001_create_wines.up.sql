CREATE TABLE wineries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_by TEXT NOT NULL DEFAULT '',
  name TEXT NOT NULL DEFAULT '',
  country TEXT NOT NULL DEFAULT '',
  UNIQUE(created_by, name)
);

CREATE TABLE wines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_by TEXT NOT NULL DEFAULT '',
  winery_id INTEGER NOT NULL REFERENCES wineries(id),
  name TEXT NOT NULL DEFAULT '',
  vintage INTEGER NOT NULL DEFAULT -1,
  region TEXT NOT NULL DEFAULT '',
  country TEXT NOT NULL DEFAULT '',
  style TEXT NOT NULL DEFAULT '',
  avg_rating REAL,
  rating_count INTEGER,
  personal_note TEXT NOT NULL DEFAULT '',
  wine_type TEXT NOT NULL DEFAULT '',
  vivino_link TEXT NOT NULL DEFAULT '',
  in_cellar INTEGER NOT NULL DEFAULT 0,
  wishlisted INTEGER NOT NULL DEFAULT 0,
  UNIQUE(created_by, winery_id, name, vivino_link)
);

CREATE TABLE ratings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  wine_id INTEGER NOT NULL REFERENCES wines(id),
  rating REAL,
  tasting_notes TEXT,
  rated_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);