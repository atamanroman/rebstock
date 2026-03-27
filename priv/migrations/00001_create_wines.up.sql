CREATE TABLE wineries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_by TEXT NOT NULL,
  name TEXT NOT NULL,
  country TEXT,
  UNIQUE(created_by, name)
);

CREATE TABLE wines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_by TEXT NOT NULL,
  winery_id INTEGER NOT NULL REFERENCES wineries(id),
  name TEXT NOT NULL,
  vintage INTEGER,
  region TEXT,
  country TEXT,
  style TEXT,
  avg_rating REAL,
  rating_count INTEGER,
  personal_note TEXT,
  wine_type TEXT NOT NULL,
  vivino_link TEXT,
  UNIQUE(created_by, winery_id, name, vivino_link)
);

CREATE TABLE wishlist (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  wine_id INTEGER NOT NULL REFERENCES wines(id),
  notes TEXT,
  dated_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(username, wine_id)
);

CREATE TABLE cellar (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  wine_id INTEGER NOT NULL REFERENCES wines(id),
  quantity INTEGER NOT NULL,
  notes TEXT,
  dated_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
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
